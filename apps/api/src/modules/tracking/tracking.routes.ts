import { trackingTokenParamSchema } from "@repo/contracts";
import { events, links, messages, trackedMessages, type Database } from "@repo/db";
import { and, eq } from "drizzle-orm";
import type { FastifyPluginAsyncZod } from "fastify-type-provider-zod";

import { NotFoundError } from "../../lib/errors";
import { classifyClient } from "./classify-client";

const PIXEL = Buffer.from("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7", "base64");

// Public on purpose: recipients' mail apps call these, through t.<domain> or the api's own host. Tokens are signed, so
// a forged or guessed token is rejected before it reaches the database.
export const trackingRoutes: FastifyPluginAsyncZod = async (app) => {
    app.get("/o/:token", { schema: { hide: true, params: trackingTokenParamSchema } }, async (request, reply) => {
        const messageId = app.trackingTokens.verify("open", request.params.token);
        const message = messageId ? await trackedMessage(app.db, messageId) : null;
        if (message) {
            const client = classifyClient(request, message.sentAt);
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
        const [link] = linkId ? await app.db.select().from(links).where(eq(links.id, linkId)) : [];
        const message = link ? await trackedMessage(app.db, link.messageId) : null;
        if (!link || !message) throw new NotFoundError("This link doesn't exist.");

        const client = classifyClient(request, message.sentAt);
        await app.db.insert(events).values({
            userId: message.userId,
            messageId: message.id,
            type: "clicked",
            linkId: link.id,
            ...client,
            occurredAt: new Date(),
        });
        return reply.header("cache-control", "no-store").redirect(link.url, 302);
    });
};

/** Mail sent through the api with tracking on, or Gmail and Outlook mail the app had instrumented. */
async function trackedMessage(db: Database, id: string) {
    const [row] = await db
        .select({ id: messages.id, userId: messages.userId, sentAt: messages.sentAt })
        .from(messages)
        .where(and(eq(messages.id, id), eq(messages.trackingEnabled, true)))
        .unionAll(
            db
                .select({ id: trackedMessages.id, userId: trackedMessages.userId, sentAt: trackedMessages.sentAt })
                .from(trackedMessages)
                .where(eq(trackedMessages.id, id)),
        );
    return row ?? null;
}
