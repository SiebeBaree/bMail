import { createEnv } from "@t3-oss/env-core";
import { z } from "zod";

const isProd = process.env.NODE_ENV === "production";

/**
 * Api environment. Only DATABASE_URL is required, which is what lets the Vercel deploy button run without anyone typing
 * a variable.
 *
 * - PUBLIC_URL falls back to the project's production domain on Vercel.
 * - The tracking secret and Resend's key and webhook secret normally live in Postgres: the server generates the first
 *   and bMail sends the key when you add your first domain. Set here, they win, which keeps servers deployed before
 *   that working unchanged.
 * - Attachments go to R2 when its four variables are set, otherwise to the project's Vercel Blob store.
 */
export const env = createEnv({
    server: {
        DATABASE_URL: z.url(),
        PORT: z.coerce.number().int().positive().default(3001),
        // Tracking pixels and links are built from it, and Gmail's image proxy never loads an http pixel.
        PUBLIC_URL: isProd ? z.url({ protocol: /^https$/ }) : z.url().default("http://localhost:3001"),
        // Lets the owner take the server back after losing every device. Unset, a claimed server can't be claimed again.
        CLAIM_CODE: z.string().min(1).optional(),

        TRACKING_SECRET: z.string().min(32).optional(),
        RESEND_API_KEY: z.string().startsWith("re_").optional(),
        RESEND_WEBHOOK_SECRET: z.string().startsWith("whsec_").optional(),

        R2_ACCOUNT_ID: z.string().min(1).optional(),
        R2_ACCESS_KEY_ID: z.string().min(1).optional(),
        R2_SECRET_ACCESS_KEY: z.string().min(1).optional(),
        R2_BUCKET: z.string().min(1).optional(),
        // A Blob store connected to the project sets one of these. On Vercel the SDK signs in with OIDC.
        BLOB_READ_WRITE_TOKEN: z.string().min(1).optional(),
        BLOB_STORE_ID: z.string().min(1).optional(),

        SENTRY_DSN: z.url().optional(),
    },
    runtimeEnv: {
        ...process.env,
        PUBLIC_URL:
            process.env.PUBLIC_URL ||
            (process.env.VERCEL_PROJECT_PRODUCTION_URL && `https://${process.env.VERCEL_PROJECT_PRODUCTION_URL}`),
    },
    emptyStringAsUndefined: true,
    // For processes that have no environment, e.g. CI: SKIP_ENV_VALIDATION=1 pnpm openapi
    skipValidation: Boolean(process.env.SKIP_ENV_VALIDATION),
});
