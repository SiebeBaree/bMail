import helmet from "@fastify/helmet";
import fp from "fastify-plugin";

// No CORS: the only clients are the native app and recipients' mail apps, neither of which runs in a browser origin
// that needs our permission.
export const securityPlugin = fp(async (app) => {
    await app.register(helmet, {
        // A JSON api serves no documents, so the CSP allows nothing at all.
        contentSecurityPolicy: {
            useDefaults: false,
            directives: { "default-src": ["'none'"], "frame-ancestors": ["'none'"] },
        },
        // The tracking pixel is loaded as a cross-origin image by webmail clients; same-origin would block it.
        crossOriginResourcePolicy: { policy: "cross-origin" },
    });
});
