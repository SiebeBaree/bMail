import fp from "fastify-plugin";

// One canonical log line per request (fastify's own per-request logging is disabled in app.ts). /health is skipped
// because platform health checks would drown everything else.
export const observabilityPlugin = fp(async (app) => {
    app.addHook("onResponse", async (request, reply) => {
        if (request.routeOptions.url === "/health") return;
        request.log.info(
            {
                requestId: request.id,
                method: request.method,
                path: request.routeOptions.url ?? request.url,
                statusCode: reply.statusCode,
                durationMs: Math.round(reply.elapsedTime),
            },
            "request.completed",
        );
    });
});
