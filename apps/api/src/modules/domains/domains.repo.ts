import { domains, mailboxes, type Database, type DomainRow } from "@repo/db";
import { and, asc, eq, isNull } from "drizzle-orm";

const live = (userId: string) => and(eq(domains.userId, userId), isNull(domains.deletedAt));

export function domainsRepo(db: Database) {
    return {
        list(userId: string): Promise<DomainRow[]> {
            return db.select().from(domains).where(live(userId)).orderBy(asc(domains.name));
        },
        async find(userId: string, id: string): Promise<DomainRow | null> {
            const [row] = await db
                .select()
                .from(domains)
                .where(and(live(userId), eq(domains.id, id)));
            return row ?? null;
        },
        async nameTaken(name: string): Promise<boolean> {
            const [row] = await db
                .select({ id: domains.id })
                .from(domains)
                .where(and(eq(domains.name, name), isNull(domains.deletedAt)));
            return row !== undefined;
        },
        async create(values: typeof domains.$inferInsert): Promise<DomainRow> {
            const [row] = await db.insert(domains).values(values).returning();
            if (!row) throw new Error("insert returned no row");
            return row;
        },
        async update(
            userId: string,
            id: string,
            values: Partial<
                Pick<
                    DomainRow,
                    "status" | "records" | "receivingEnabled" | "catchAllMailboxId" | "trackingHostVerifiedAt"
                >
            >,
        ): Promise<DomainRow | null> {
            const [row] = await db
                .update(domains)
                .set(values)
                .where(and(live(userId), eq(domains.id, id)))
                .returning();
            return row ?? null;
        },
        /** Soft, so the app learns about it through sync. Mailboxes go with it. */
        async remove(userId: string, id: string): Promise<void> {
            const now = new Date();
            await db.transaction(async (tx) => {
                await tx
                    .update(mailboxes)
                    .set({ deletedAt: now })
                    .where(and(eq(mailboxes.domainId, id), eq(mailboxes.userId, userId), isNull(mailboxes.deletedAt)));
                await tx
                    .update(domains)
                    .set({ deletedAt: now })
                    .where(and(live(userId), eq(domains.id, id)));
            });
        },
    };
}
