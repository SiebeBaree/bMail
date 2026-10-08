import { pino } from "pino";

/**
 * Logging philosophy: one canonical log line per unit of work (a request, a failed job), with a stable event name and
 * a small set of searchable fields: requestId, durationMs, statusCode. No debug spam, no payload dumps. When Sentry
 * reports an error or a customer quotes a requestId, filter Axiom by it to reconstruct what happened.
 *
 * In production this writes JSON to stdout and Vercel's Axiom log drain ships it, so flushing is never a concern.
 * Local dev gets pretty-printed output.
 */
export function createLogger({ pretty = false }: { pretty?: boolean } = {}) {
    return pino({
        redact: ["req.headers.authorization", "req.headers.cookie"],
        ...(pretty && { transport: { target: "pino-pretty", options: { colorize: true } } }),
    });
}

export type Logger = ReturnType<typeof createLogger>;
