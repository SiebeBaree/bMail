import { issueSignedToken, presignUrl, put } from "@vercel/blob";
import { AwsClient } from "aws4fetch";

import { UpstreamError } from "./errors";

/**
 * Object storage for attachments and raw .eml files: R2 (or anything S3-compatible) or a private Vercel Blob store.
 * Both hand out signed urls, so file bytes never pass through the api.
 */
export type Storage = {
    put(key: string, body: Uint8Array, contentType: string): Promise<void>;
    /** A short-lived url the app downloads from directly. */
    downloadUrl(key: string, filename: string, expiresInSeconds: number): Promise<string>;
    /** A short-lived url the app uploads an attachment to directly, so file bytes never pass through the api. */
    uploadUrl(key: string, contentType: string, expiresInSeconds: number): Promise<string>;
};

export type R2Config = { accountId: string; accessKeyId: string; secretAccessKey: string; bucket: string };

export function createR2Storage({ accountId, accessKeyId, secretAccessKey, bucket }: R2Config): Storage {
    const client = new AwsClient({ accessKeyId, secretAccessKey, service: "s3", region: "auto" });
    const objectUrl = (key: string) =>
        new URL(
            `https://${accountId}.r2.cloudflarestorage.com/${bucket}/${key.split("/").map(encodeURIComponent).join("/")}`,
        );

    const presign = async (
        url: URL,
        method: "GET" | "PUT",
        expiresInSeconds: number,
        headers?: Record<string, string>,
    ) => {
        url.searchParams.set("X-Amz-Expires", String(expiresInSeconds));
        const signed = await client.sign(new Request(url, { method, headers }), { aws: { signQuery: true } });
        return signed.url;
    };

    return {
        async put(key, body, contentType) {
            const response = await client.fetch(objectUrl(key), {
                method: "PUT",
                body,
                headers: { "content-type": contentType },
            });
            if (!response.ok) throw new UpstreamError(`Couldn't store ${key} (R2 answered ${response.status}).`);
        },
        downloadUrl(key, filename, expiresInSeconds) {
            const url = objectUrl(key);
            url.searchParams.set(
                "response-content-disposition",
                `attachment; filename*=UTF-8''${encodeURIComponent(filename)}`,
            );
            return presign(url, "GET", expiresInSeconds);
        },
        uploadUrl(key, contentType, expiresInSeconds) {
            return presign(objectUrl(key), "PUT", expiresInSeconds, { "content-type": contentType });
        },
    };
}

/**
 * A private Vercel Blob store. The SDK finds its credentials itself: BLOB_READ_WRITE_TOKEN, or OIDC on Vercel. Each url
 * comes from a token scoped to its one pathname and operation.
 */
export function createBlobStorage(): Storage {
    return {
        async put(key, body, contentType) {
            try {
                await put(key, Buffer.from(body), {
                    access: "private",
                    contentType,
                    addRandomSuffix: false,
                    allowOverwrite: true,
                });
            } catch (error) {
                throw new UpstreamError(`Couldn't store ${key} (${blobMessage(error)}).`);
            }
        },
        // Blob has no content-disposition to sign. Nothing needs it: the app names the file it saves and Resend gets
        // the filename next to the url.
        downloadUrl: (key, _filename, expiresInSeconds) => signBlobUrl(key, "get", expiresInSeconds),
        uploadUrl: (key, contentType, expiresInSeconds) => signBlobUrl(key, "put", expiresInSeconds, contentType),
    };
}

async function signBlobUrl(pathname: string, operation: "get" | "put", expiresInSeconds: number, contentType?: string) {
    const validUntil = Date.now() + expiresInSeconds * 1000;
    const allowedContentTypes = contentType ? [contentType] : undefined;
    try {
        const token = await issueSignedToken({ pathname, operations: [operation], validUntil, allowedContentTypes });
        const { presignedUrl } = await presignUrl(
            token,
            operation === "put"
                ? {
                      operation,
                      pathname,
                      access: "private",
                      validUntil,
                      allowedContentTypes,
                      addRandomSuffix: false,
                      allowOverwrite: true,
                  }
                : { operation, pathname, access: "private", validUntil },
        );
        return presignedUrl;
    } catch (error) {
        throw new UpstreamError(`Couldn't sign a url for ${pathname} (${blobMessage(error)}).`);
    }
}

const blobMessage = (error: unknown) => (error instanceof Error ? error.message : "Vercel Blob failed");

/** Production without a Blob store or R2. Tracking still works; anything that touches a file says what's missing. */
export function createMissingStorage(): Storage {
    return { put: storageMissing, downloadUrl: storageMissing, uploadUrl: storageMissing };
}

async function storageMissing(): Promise<never> {
    throw new UpstreamError(
        "Attachments need storage. Add a Blob store to the project on Vercel, or set the R2 variables.",
    );
}

/** Local dev and tests. Urls point nowhere; the bytes are only there for assertions. */
export function createMemoryStorage(): Storage & { objects: Map<string, Uint8Array> } {
    const objects = new Map<string, Uint8Array>();
    return {
        objects,
        async put(key, body) {
            objects.set(key, body);
        },
        async downloadUrl(key) {
            return `https://storage.invalid/${encodeURI(key)}`;
        },
        async uploadUrl(key) {
            return `https://storage.invalid/${encodeURI(key)}?upload`;
        },
    };
}
