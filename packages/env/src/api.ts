import { createEnv } from "@t3-oss/env-core";
import { z } from "zod";

const isProd = process.env.NODE_ENV === "production";

const commaList = z.string().transform((value) =>
    value
        .split(",")
        .map((entry) => entry.trim().toLowerCase())
        .filter(Boolean),
);

/**
 * Api environment.
 *
 * - DATABASE_URL and ALLOWED_EMAILS are always required. Only allowlisted emails can have an account, which is what
 *   keeps strangers away from your Resend account.
 * - Secrets, Resend and R2 are required in production and optional in dev, where tests and the seeded local database
 *   run without them (storage falls back to memory, sending is disabled).
 * - Social sign-in is optional everywhere: a provider without its id is simply not offered.
 */
export const env = createEnv({
    server: {
        DATABASE_URL: z.url(),
        PORT: z.coerce.number().int().positive().default(3001),
        // Tracking pixels and links are built from it, and Gmail's image proxy never loads an http pixel.
        PUBLIC_URL: isProd ? z.url({ protocol: /^https$/ }) : z.url().default("http://localhost:3001"),
        ALLOWED_EMAILS: commaList,

        BETTER_AUTH_SECRET: isProd
            ? z.string().min(32)
            : z.string().min(32).default("dev-only-secret-dev-only-secret-dev"),
        GOOGLE_CLIENT_ID: z.string().min(1).optional(),
        APPLE_BUNDLE_ID: z.string().min(1).optional(),

        RESEND_API_KEY: isProd ? z.string().startsWith("re_") : z.string().startsWith("re_").optional(),
        RESEND_WEBHOOK_SECRET: isProd ? z.string().startsWith("whsec_") : z.string().startsWith("whsec_").optional(),
        TRACKING_SECRET: isProd ? z.string().min(32) : z.string().min(32).default("dev-only-tracking-secret-dev-only"),

        R2_ACCOUNT_ID: isProd ? z.string().min(1) : z.string().min(1).optional(),
        R2_ACCESS_KEY_ID: isProd ? z.string().min(1) : z.string().min(1).optional(),
        R2_SECRET_ACCESS_KEY: isProd ? z.string().min(1) : z.string().min(1).optional(),
        R2_BUCKET: isProd ? z.string().min(1) : z.string().min(1).optional(),

        SENTRY_DSN: z.url().optional(),
    },
    runtimeEnv: process.env,
    emptyStringAsUndefined: true,
    // For processes that have no environment, e.g. CI: SKIP_ENV_VALIDATION=1 pnpm openapi
    skipValidation: Boolean(process.env.SKIP_ENV_VALIDATION),
});
