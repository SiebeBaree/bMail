import "./instrument";
import { pathToFileURL } from "node:url";

import { createDb } from "@repo/db";
import { env } from "@repo/env/api";
import { createLogger } from "@repo/logger";

import { buildApp } from "./app";
import { createAuth } from "./auth";
import { UpstreamError } from "./lib/errors";
import { createResendGateway, type ResendGateway } from "./lib/resend";
import { createMemoryStorage, createR2Storage } from "./lib/storage";

// Built once per process and reused, so serverless invocations after a cold start skip the setup.
let appPromise: ReturnType<typeof buildApp> | undefined;

export function getApp() {
    if (appPromise) return appPromise;
    const db = createDb(env.DATABASE_URL);
    const logger = createLogger({ pretty: process.env.NODE_ENV === "development" });

    appPromise = buildApp({
        db,
        logger,
        publicUrl: env.PUBLIC_URL,
        trackingSecret: env.TRACKING_SECRET,
        auth: createAuth({
            db,
            baseURL: env.PUBLIC_URL,
            secret: env.BETTER_AUTH_SECRET,
            allowedEmails: env.ALLOWED_EMAILS,
            appleBundleId: env.APPLE_BUNDLE_ID,
        }),
        resend:
            env.RESEND_API_KEY && env.RESEND_WEBHOOK_SECRET
                ? createResendGateway(env.RESEND_API_KEY, env.RESEND_WEBHOOK_SECRET)
                : resendUnavailable,
        storage:
            env.R2_ACCOUNT_ID && env.R2_ACCESS_KEY_ID && env.R2_SECRET_ACCESS_KEY && env.R2_BUCKET
                ? createR2Storage({
                      accountId: env.R2_ACCOUNT_ID,
                      accessKeyId: env.R2_ACCESS_KEY_ID,
                      secretAccessKey: env.R2_SECRET_ACCESS_KEY,
                      bucket: env.R2_BUCKET,
                  })
                : createMemoryStorage(),
    });
    return appPromise;
}

// Local dev without Resend keys: everything that reads works, everything that would reach Resend says why it can't.
const notConfigured = () => {
    throw new UpstreamError("Resend isn't configured. Set RESEND_API_KEY and RESEND_WEBHOOK_SECRET in apps/api/.env.");
};
const resendUnavailable: ResendGateway = {
    createDomain: notConfigured,
    getDomain: notConfigured,
    verifyDomain: notConfigured,
    removeDomain: notConfigured,
    send: notConfigured,
    getReceivedEmail: notConfigured,
    listReceivedAttachments: notConfigured,
    verifyWebhook: notConfigured,
};

// Run as a plain node process (pnpm dev, pnpm start): bind a port. On Vercel this file is loaded
// lazily by the handler in app.ts and the guard is false, so no port is ever bound there.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
    const app = await getApp();
    await app.listen({ port: env.PORT, host: "0.0.0.0" });
}
