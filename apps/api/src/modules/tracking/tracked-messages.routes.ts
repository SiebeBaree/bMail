import { errorSchema, trackedHtmlSchema, trackMessageSchema } from "@repo/contracts";
import type { FastifyPluginAsyncZod } from "fastify-type-provider-zod";

import { trackedMessagesService } from "./tracked-messages.service";

export const trackedMessagesRoutes: FastifyPluginAsyncZod = async (app) => {
    const service = trackedMessagesService({
        db: app.db,
        trackingTokens: app.trackingTokens,
        publicUrl: app.publicUrl,
    });

    app.post(
        "/tracking/messages",
        {
            // Same allowance as POST /messages: the html of a forwarded newsletter can be large.
            bodyLimit: 4 * 1024 * 1024,
            schema: {
                operationId: "trackMessage",
                body: trackMessageSchema,
                response: { 200: trackedHtmlSchema, 400: errorSchema, 409: errorSchema },
            },
        },
        (request) => service.track(request.userId, request.body),
    );
};
