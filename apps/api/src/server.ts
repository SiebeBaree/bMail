import "./instrument";
import { pathToFileURL } from "node:url";

import { createDb } from "@repo/db";
import { env } from "@repo/env/api";
import { createLogger } from "@repo/logger";

import { buildApp } from "./app";
import { createResendGateway } from "./lib/resend";
import { createServerSettings } from "./lib/server-settings";
import { createBlobStorage, createMemoryStorage, createMissingStorage, createR2Storage } from "./lib/storage";

// Built once per process and reused, so serverless invocations after a cold start skip the setup.
let appPromise: ReturnType<typeof buildApp> | undefined;

export function getApp() {
    // A failed start (the database unreachable for a moment) is retried by the next request instead of kept.
    appPromise ??= start().catch((error: unknown) => {
        appPromise = undefined;
        throw error;
    });
    return appPromise;
}

async function start() {
    const db = createDb(env.DATABASE_URL);
    const settings = createServerSettings(db, {
        ...(env.RESEND_API_KEY &&
            env.RESEND_WEBHOOK_SECRET && {
                resend: { apiKey: env.RESEND_API_KEY, webhookSecret: env.RESEND_WEBHOOK_SECRET },
            }),
    });
    return buildApp({
        db,
        settings,
        logger: createLogger({ pretty: process.env.NODE_ENV === "development" }),
        publicUrl: env.PUBLIC_URL,
        claimCode: env.CLAIM_CODE,
        // A server deployed before the generated one keeps its own, or the links in mail it already sent break.
        trackingSecret: env.TRACKING_SECRET ?? (await settings.trackingSecret()),
        resend: createResendGateway(settings.resend),
        storage: storage(),
    });
}

function storage() {
    if (env.R2_ACCOUNT_ID && env.R2_ACCESS_KEY_ID && env.R2_SECRET_ACCESS_KEY && env.R2_BUCKET) {
        return createR2Storage({
            accountId: env.R2_ACCOUNT_ID,
            accessKeyId: env.R2_ACCESS_KEY_ID,
            secretAccessKey: env.R2_SECRET_ACCESS_KEY,
            bucket: env.R2_BUCKET,
        });
    }
    if (env.BLOB_READ_WRITE_TOKEN || env.BLOB_STORE_ID) return createBlobStorage();
    return process.env.NODE_ENV === "production" ? createMissingStorage() : createMemoryStorage();
}

// Run as a plain node process (pnpm dev, pnpm start): bind a port. On Vercel this file is loaded
// lazily by the handler in app.ts and the guard is false, so no port is ever bound there.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
    const app = await getApp();
    await app.listen({ port: env.PORT, host: "0.0.0.0" });
}
