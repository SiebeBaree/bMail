import { env } from "@repo/env/api";
import * as Sentry from "@sentry/node";

// Imported first by server.ts so Sentry instruments before anything else loads. Errors only and lean on purpose:
// Axiom owns logs, so traces are sampled low, breadcrumbs are capped and PII stays out.
Sentry.init({
    dsn: env.SENTRY_DSN,
    enabled: Boolean(env.SENTRY_DSN),
    environment: process.env.VERCEL_ENV ?? process.env.NODE_ENV,
    tracesSampleRate: 0.1,
    maxBreadcrumbs: 30,
    sendDefaultPii: false,
    normalizeDepth: 5,
});
