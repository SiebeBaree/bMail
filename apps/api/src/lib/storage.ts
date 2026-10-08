import { AwsClient } from "aws4fetch";

import { UpstreamError } from "./errors";

/**
 * Object storage for attachments and raw .eml files. Written against the S3 api, so R2 today and any S3-compatible
 * store tomorrow is a change of endpoint, not of code.
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
