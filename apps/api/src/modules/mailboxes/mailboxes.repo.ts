import { domains, mailboxes, type Database, type MailboxRow } from "@repo/db";
import { and, eq, isNull } from "drizzle-orm";

export type MailboxWithDomain = { mailbox: MailboxRow; domainName: string };

const live = (userId: string) => and(eq(mailboxes.userId, userId), isNull(mailboxes.deletedAt));

export function mailboxesRepo(db: Database) {
    return {
        async find(userId: string, id: string): Promise<MailboxRow | null> {
            const [row] = await db
                .select()
                .from(mailboxes)
                .where(and(live(userId), eq(mailboxes.id, id)));
            return row ?? null;
        },
        async findWithDomain(userId: string, id: string) {
            const [row] = await db
                .select({ mailbox: mailboxes, domain: domains })
                .from(mailboxes)
                .innerJoin(domains, eq(domains.id, mailboxes.domainId))
                .where(and(live(userId), eq(mailboxes.id, id)));
            return row ?? null;
        },
        async exists(domainId: string, localPart: string): Promise<boolean> {
            const [row] = await db
                .select({ id: mailboxes.id })
                .from(mailboxes)
                .where(
                    and(
                        eq(mailboxes.domainId, domainId),
                        eq(mailboxes.localPart, localPart),
                        isNull(mailboxes.deletedAt),
                    ),
                );
            return row !== undefined;
        },
        /** Creates the mailbox and, when the domain has no catch-all yet, makes it the catch-all. */
        async create(values: typeof mailboxes.$inferInsert): Promise<MailboxRow> {
            return db.transaction(async (tx) => {
                const [row] = await tx.insert(mailboxes).values(values).returning();
                if (!row) throw new Error("insert returned no row");
                await tx
                    .update(domains)
                    .set({ catchAllMailboxId: row.id })
                    .where(and(eq(domains.id, row.domainId), isNull(domains.catchAllMailboxId)));
                return row;
            });
        },
        async update(
            userId: string,
            id: string,
            values: Partial<Pick<MailboxRow, "displayName" | "signatureHtml">>,
        ): Promise<MailboxRow | null> {
            const [row] = await db
                .update(mailboxes)
                .set(values)
                .where(and(live(userId), eq(mailboxes.id, id)))
                .returning();
            return row ?? null;
        },
        async remove(userId: string, id: string): Promise<void> {
            await db.transaction(async (tx) => {
                await tx
                    .update(domains)
                    .set({ catchAllMailboxId: null })
                    .where(and(eq(domains.userId, userId), eq(domains.catchAllMailboxId, id)));
                await tx
                    .update(mailboxes)
                    .set({ deletedAt: new Date() })
                    .where(and(live(userId), eq(mailboxes.id, id)));
            });
        },
    };
}
