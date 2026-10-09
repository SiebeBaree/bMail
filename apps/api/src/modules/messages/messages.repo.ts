import type { Message, TrackedMessage } from "@repo/contracts";
import {
    attachments,
    conversations,
    events,
    links,
    messages,
    type AttachmentRow,
    type ConversationRow,
    type Database,
    type MessageRow,
    type TrackedMessageRow,
    type Transaction,
} from "@repo/db";
import { and, asc, desc, eq, inArray, isNull } from "drizzle-orm";

import { toMessage } from "../../lib/dto";

export function messagesRepo(db: Database | Transaction) {
    return {
        async findMessage(userId: string, id: string): Promise<MessageRow | null> {
            const [row] = await db
                .select()
                .from(messages)
                .where(and(eq(messages.userId, userId), eq(messages.id, id)));
            return row ?? null;
        },
        async findConversation(userId: string, id: string): Promise<ConversationRow | null> {
            const [row] = await db
                .select()
                .from(conversations)
                .where(and(eq(conversations.userId, userId), eq(conversations.id, id)));
            return row ?? null;
        },
        /** The message a reply answers: the newest one in the conversation. */
        async latestMessage(conversationId: string): Promise<MessageRow | null> {
            const [row] = await db
                .select()
                .from(messages)
                .where(eq(messages.conversationId, conversationId))
                .orderBy(desc(messages.sentAt))
                .limit(1);
            return row ?? null;
        },
        /** Uploads that belong to this user and aren't attached to a sent message yet. */
        pendingUploads(userId: string, ids: string[]): Promise<AttachmentRow[]> {
            if (ids.length === 0) return Promise.resolve([]);
            return db
                .select()
                .from(attachments)
                .where(
                    and(eq(attachments.userId, userId), inArray(attachments.id, ids), isNull(attachments.messageId)),
                );
        },
        linksOf(messageId: string) {
            return db
                .select({ id: links.id, url: links.url })
                .from(links)
                .where(eq(links.messageId, messageId))
                .orderBy(asc(links.position));
        },
        /** Messages in wire format, with their attachments and tracked links. */
        async wireMessages(rows: MessageRow[]): Promise<Message[]> {
            if (rows.length === 0) return [];
            const ids = rows.map((row) => row.id);
            const [files, trackedLinks] = await Promise.all([
                db.select().from(attachments).where(inArray(attachments.messageId, ids)),
                db.select().from(links).where(inArray(links.messageId, ids)).orderBy(asc(links.position)),
            ]);
            return rows.map((row) =>
                toMessage(
                    row,
                    files.filter((file) => file.messageId === row.id),
                    trackedLinks.filter((link) => link.messageId === row.id).map(({ id, url }) => ({ id, url })),
                ),
            );
        },
        /** Gmail and Outlook messages the api tracks, in wire format with their links. */
        async wireTrackedMessages(rows: TrackedMessageRow[]): Promise<TrackedMessage[]> {
            if (rows.length === 0) return [];
            const trackedLinks = await db
                .select()
                .from(links)
                .where(
                    inArray(
                        links.messageId,
                        rows.map((row) => row.id),
                    ),
                )
                .orderBy(asc(links.position));
            return rows.map((row) => ({
                id: row.id,
                links: trackedLinks.filter((link) => link.messageId === row.id).map(({ id, url }) => ({ id, url })),
            }));
        },
        async recordEvent(values: typeof events.$inferInsert): Promise<void> {
            await db.insert(events).values(values);
        },
    };
}
