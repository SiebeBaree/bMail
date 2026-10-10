import type { IncomingMessage, ServerResponse } from "node:http";

import swagger from "@fastify/swagger";
import type { Database } from "@repo/db";
import type { Logger } from "@repo/logger";
import * as Sentry from "@sentry/node";
import fastify, { LogController } from "fastify";
import {
    hasZodFastifySchemaValidationErrors,
    jsonSchemaTransform,
    jsonSchemaTransformObject,
    serializerCompiler,
    validatorCompiler,
    type ZodTypeProvider,
} from "fastify-type-provider-zod";

import type { Auth } from "./auth";
import { ConflictError, NotFoundError, UpstreamError } from "./lib/errors";
import type { ResendGateway } from "./lib/resend";
import type { Storage } from "./lib/storage";
import { createTrackingTokens, type TrackingTokens } from "./lib/tracking-token";
import { authModule } from "./modules/auth";
import { conversationsRoutes } from "./modules/conversations";
import { domainsRoutes } from "./modules/domains";
import { healthModule } from "./modules/health";
import { labelsRoutes } from "./modules/labels";
import { mailboxesRoutes } from "./modules/mailboxes";
import { messagesRoutes } from "./modules/messages";
import { syncRoutes } from "./modules/sync";
import { trackedMessagesRoutes, trackingRoutes } from "./modules/tracking";
import { webhooksModule } from "./modules/webhooks";
import { authenticate } from "./plugins/authenticate";
import { observabilityPlugin } from "./plugins/observability";
import { genReqId, requestIdPlugin } from "./plugins/request-id";
import { securityPlugin } from "./plugins/security";

declare module "fastify" {
    interface FastifyInstance {
        db: Database;
        auth: Auth;
        resend: ResendGateway;
        storage: Storage;
        trackingTokens: TrackingTokens;
        /** The api's own origin, e.g. https://mail-api.example.com. */
        publicUrl: string;
    }
}

export type AppOptions = {
    db: Database;
    auth: Auth;
    resend: ResendGateway;
    storage: Storage;
    trackingSecret: string;
    publicUrl: string;
    logger?: Logger;
};

export async function buildApp({ db, auth, resend, storage, trackingSecret, publicUrl, logger }: AppOptions) {
    const app = fastify({
        ...(logger ? { loggerInstance: logger } : { logger: false }),
        // The observability plugin logs one canonical line per request instead.
        logController: new LogController({ disableRequestLogging: true }),
        trustProxy: true,
        genReqId,
    }).withTypeProvider<ZodTypeProvider>();

    // Zod validates every declared input and serializes (and so validates) every declared output.
    app.setValidatorCompiler(validatorCompiler);
    app.setSerializerCompiler(serializerCompiler);

    app.decorate("db", db);
    app.decorate("auth", auth);
    app.decorate("resend", resend);
    app.decorate("storage", storage);
    app.decorate("trackingTokens", createTrackingTokens(trackingSecret));
    app.decorate("publicUrl", publicUrl);
    app.decorateRequest("userId", "");

    // The document the Swift client is generated from. 3.0 rather than 3.1: swift-openapi-generator reads nullable
    // fields best in that dialect. Routes marked `hide` (auth, webhooks, opens and clicks) aren't part of it.
    await app.register(swagger, {
        openapi: {
            openapi: "3.0.3",
            info: { title: "Mail api", version: "1.0.0" },
            components: { securitySchemes: { bearer: { type: "http", scheme: "bearer" } } },
            security: [{ bearer: [] }],
        },
        transform: jsonSchemaTransform,
        // Lifts every contract schema with a `.meta({ id })` into components, so the Swift client gets named types.
        transformObject: jsonSchemaTransformObject,
    });

    await app.register(securityPlugin);
    await app.register(requestIdPlugin);
    await app.register(observabilityPlugin);

    // Must be set before the route modules register: encapsulated scopes resolve their error handler at registration.
    app.setErrorHandler((error, request, reply) => {
        const requestId = request.id;

        if (hasZodFastifySchemaValidationErrors(error)) {
            return reply.status(400).send({
                message: "Invalid input.",
                requestId,
                issues: error.validation.map((issue) => ({
                    path: issue.instancePath.split("/").filter(Boolean).join("."),
                    message: issue.message ?? "Invalid value",
                })),
            });
        }
        if (error instanceof NotFoundError) return reply.status(404).send({ message: error.message, requestId });
        if (error instanceof ConflictError) return reply.status(409).send({ message: error.message, requestId });
        if (error instanceof UpstreamError) {
            request.log.warn({ requestId, err: error }, "request.upstream_failed");
            return reply.status(502).send({ message: error.message, requestId });
        }

        Sentry.captureException(error, { tags: { requestId } });
        request.log.error({ requestId, err: error }, "request.failed");
        return reply.status(500).send({ message: "Something went wrong. Please try again.", requestId });
    });

    // Public: health checks, sign-in, Resend's webhooks and recipients' mail apps.
    await app.register(healthModule);
    await app.register(authModule);
    await app.register(webhooksModule);
    await app.register(trackingRoutes);

    // Private: everything else needs a session.
    await app.register(async (scope) => {
        scope.addHook("onRequest", authenticate);
        await scope.register(syncRoutes);
        await scope.register(domainsRoutes);
        await scope.register(mailboxesRoutes);
        await scope.register(conversationsRoutes);
        await scope.register(messagesRoutes);
        await scope.register(trackedMessagesRoutes);
        await scope.register(labelsRoutes);
    });

    return app;
}

// Vercel's Fastify builder deploys this file as the function entrypoint and calls the default export
// per request. The dynamic import keeps server-only side effects (Sentry, env validation, the real db)
// out of tests, which import buildApp from here.
export default async function handler(req: IncomingMessage, res: ServerResponse) {
    const { getApp } = await import("./server");
    const app = await getApp();
    await app.ready();
    app.server.emit("request", req, res);
}
