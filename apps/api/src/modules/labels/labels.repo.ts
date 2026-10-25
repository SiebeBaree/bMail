import { conversationLabels, labels, type ConversationLabelsRow, type Database, type LabelRow } from "@repo/db";
import { and, eq, inArray, isNull, ne, sql } from "drizzle-orm";

const live = (userId: string) => and(eq(labels.userId, userId), isNull(labels.deletedAt));

export function labelsRepo(db: Database) {
    return {
        async find(userId: string, id: string): Promise<LabelRow | null> {
            const [row] = await db
                .select()
                .from(labels)
                .where(and(live(userId), eq(labels.id, id)));
            return row ?? null;
        },
        /** Case-insensitive, like the unique index. A label may take another casing of its own name. */
        async nameTaken(userId: string, name: string, exceptId?: string): Promise<boolean> {
            const [row] = await db
                .select({ id: labels.id })
                .from(labels)
                .where(
                    and(
                        live(userId),
                        sql`lower(${labels.name}) = lower(${name})`,
                        exceptId ? ne(labels.id, exceptId) : undefined,
                    ),
                );
            return row !== undefined;
        },
        /** Whether every id is one of the user's labels that isn't removed. Expects unique ids. */
        async allLive(userId: string, ids: string[]): Promise<boolean> {
            if (ids.length === 0) return true;
            const rows = await db
                .select({ id: labels.id })
                .from(labels)
                .where(and(live(userId), inArray(labels.id, ids)));
            return rows.length === ids.length;
        },
        async create(values: typeof labels.$inferInsert): Promise<LabelRow> {
            const [row] = await db.insert(labels).values(values).returning();
            if (!row) throw new Error("insert returned no row");
            return row;
        },
        async rename(userId: string, id: string, name: string): Promise<LabelRow | null> {
            const [row] = await db
                .update(labels)
                .set({ name })
                .where(and(live(userId), eq(labels.id, id)))
                .returning();
            return row ?? null;
        },
        /** Soft, so the app learns about it through sync. The label comes off every conversation in the same go. */
        async remove(userId: string, id: string): Promise<void> {
            await db.transaction(async (tx) => {
                await tx
                    .update(labels)
                    .set({ deletedAt: new Date() })
                    .where(and(live(userId), eq(labels.id, id)));
                await tx
                    .update(conversationLabels)
                    .set({ labelIds: sql`${conversationLabels.labelIds} - ${id}::text` })
                    .where(and(eq(conversationLabels.userId, userId), sql`${conversationLabels.labelIds} ? ${id}`));
            });
        },
        async setConversationLabels(
            userId: string,
            conversationId: string,
            labelIds: string[],
        ): Promise<ConversationLabelsRow> {
            const [row] = await db
                .insert(conversationLabels)
                .values({ userId, conversationId, labelIds })
                .onConflictDoUpdate({
                    target: [conversationLabels.userId, conversationLabels.conversationId],
                    set: { labelIds },
                })
                .returning();
            if (!row) throw new Error("upsert returned no row");
            return row;
        },
    };
}
