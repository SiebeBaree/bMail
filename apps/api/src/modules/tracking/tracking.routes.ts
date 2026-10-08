import { trackingTokenParamSchema } from "@repo/contracts";
import { events, links, messages } from "@repo/db";
import { eq } from "drizzle-orm";
import type { FastifyPluginAsyncZod } from "fastify-type-provider-zod";

import { NotFoundError } from "../../lib/errors";
import { classifyClient } from "./classify-client";

const PIXEL = Buffer.from("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7", "base64");

// Public on purpose: recipients' mail apps call these, through t.<domain> or the api's own host. Tokens are signed, so
// a forged or guessed token is rejected before it reaches the database.
export const trackingRoutes: FastifyPluginAsyncZod = async (app) => {
    app.get("/o/:token", { schema: { hide: true, params: trackingTokenParamSchema } }, async (request, reply) => {
        const messageId = app.trackingTokens.verify("open", request.params.token);
        const [message] = messageId ? await app.db.select().from(messages).where(eq(messages.id, messageId)) : [];
        if (message?.trackingEnabled) {
            const client = classifyClient(request, "open", message.sentAt);
            await app.db.insert(events).values({
                userId: message.userId,
                messageId: message.id,
                type: "opened",
                ...client,
                occurredAt: new Date(),
            });
        }
        // Always the pixel, even for a bad token: a broken image tells the recipient they are tracked.
        return reply
            .header("cache-control", "no-store, no-cache, must-revalidate, max-age=0")
            .type("image/gif")
            .send(PIXEL);
    });

    app.get("/c/:token", { schema: { hide: true, params: trackingTokenParamSchema } }, async (request, reply) => {
        const linkId = app.trackingTokens.verify("click", request.params.token);
        const [row] = linkId
            ? await app.db
                  .select({ link: links, message: messages })
                  .from(links)
                  .innerJoin(messages, eq(messages.id, links.messageId))
                  .where(eq(links.id, linkId))
            : [];
        if (!row) throw new NotFoundError("This link doesn't exist.");

        const client = classifyClient(request, "click", row.message.sentAt);
        await app.db.insert(events).values({
            userId: row.message.userId,
            messageId: row.message.id,
            type: "clicked",
            linkId: row.link.id,
            ...client,
            occurredAt: new Date(),
        });
        return reply.header("cache-control", "no-store").redirect(row.link.url, 302);
    });
};
