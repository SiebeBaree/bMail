import type { FastifyPluginAsync } from "fastify";
import type { WebhookEventPayload } from "resend";

import { toFetchHeaders } from "../../lib/headers";
import { inboundService } from "../messages";
import { deliveryService, isDeliveryEvent } from "../tracking/delivery.service";

/** One endpoint for every Resend webhook. The server creates the webhook itself when bMail saves the Resend key. */
export const webhooksModule: FastifyPluginAsync = async (app) => {
    const inbound = inboundService({ db: app.db, resend: app.resend, storage: app.storage, log: app.log });
    const delivery = deliveryService(app.db);

    // The signature covers the exact bytes Resend sent, so the body stays a string until it's verified.
    app.addContentTypeParser("application/json", { parseAs: "string" }, (_request, body, done) => done(null, body));

    app.post("/webhooks/resend", { schema: { hide: true } }, async (request, reply) => {
        let event: WebhookEventPayload;
        try {
            event = await app.resend.verifyWebhook(String(request.body), toFetchHeaders(request.headers));
        } catch {
            return reply.status(400).send({ message: "Invalid signature.", requestId: request.id });
        }

        if (event.type === "email.received") await inbound.receive(event.data.email_id);
        else if (isDeliveryEvent(event)) await delivery.record(String(request.headers["svix-id"]), event);

        return reply.status(204).send();
    });
};
