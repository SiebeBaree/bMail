import {
    conversationSchema,
    errorSchema,
    idParamSchema,
    updateConversationSchema,
    type UpdateConversationInput,
} from "@repo/contracts";
import { conversations, type Database } from "@repo/db";
import { and, eq } from "drizzle-orm";
import type { FastifyPluginAsyncZod } from "fastify-type-provider-zod";

import { toConversation } from "../../lib/dto";
import { NotFoundError } from "../../lib/errors";

// The whole module is one update, so it skips the service and repo layers: they would only pass it through.
export const conversationsRoutes: FastifyPluginAsyncZod = async (app) => {
    app.patch(
        "/conversations/:id",
        {
            schema: {
                operationId: "updateConversation",
                params: idParamSchema,
                body: updateConversationSchema,
                response: { 200: conversationSchema, 400: errorSchema, 404: errorSchema },
            },
        },
        (request) => updateConversation(app.db, request.userId, request.params.id, request.body),
    );
};

async function updateConversation(db: Database, userId: string, id: string, input: UpdateConversationInput) {
    const { snoozedUntil, ...flags } = input;
    const [row] = await db
        .update(conversations)
        .set({
            ...flags,
            ...(snoozedUntil === undefined ? {} : { snoozedUntil: snoozedUntil ? new Date(snoozedUntil) : null }),
        })
        .where(and(eq(conversations.userId, userId), eq(conversations.id, id)))
        .returning();
    if (!row) throw new NotFoundError("That conversation doesn't exist anymore.");
    return toConversation(row);
}
