import type { SyncResponse } from "@repo/contracts";
import { conversations, domains, events, links, mailboxes, messages, syncState, type Database } from "@repo/db";
import { and, asc, eq, gt, inArray, lte } from "drizzle-orm";
import type { AnyPgColumn } from "drizzle-orm/pg-core";

import { toConversation, toDomain, toEvent, toMailbox } from "../../lib/dto";
import { messagesRepo } from "../messages/messages.repo";

type Synced = { userId: AnyPgColumn; seq: AnyPgColumn };

/** Vercel caps responses at 4.5 MB; a page of message bodies stops short of that. */
const MESSAGE_BYTES_PER_PAGE = 3_000_000;

/** Ids referenced by `ids` that aren't among the rows the page already has. */
function missing<T>(ids: (string | null)[], have: T[], idOf: (row: T) => string) {
    const present = new Set(have.map(idOf));
    return [...new Set(ids.filter((id): id is string => id !== null && !present.has(id)))];
}

type Page = {
    domains: (typeof domains.$inferSelect)[];
    mailboxes: { mailbox: typeof mailboxes.$inferSelect; domainName: string }[];
    conversations: (typeof conversations.$inferSelect)[];
    messages: (typeof messages.$inferSelect)[];
    events: { event: typeof events.$inferSelect; url: string | null }[];
};

export function syncService(db: Database) {
    /**
     * Every change moves a row to a new seq, so a message can come up pages before its conversation, which was starred
     * since. The app's cache won't hold a row whose parent it hasn't seen, so parents past the ceiling ride along in
     * their current state. Parents at or below it are already in the app or on this page. The ones that ride along
     * come again on their own page later, which is harmless: the app upserts.
     */
    async function withParents(page: Page, ceiling: number) {
        const messageIds = missing(
            page.events.map((row) => row.event.messageId),
            page.messages,
            (row) => row.id,
        );
        if (messageIds.length > 0)
            page.messages.push(
                ...(await db
                    .select()
                    .from(messages)
                    .where(and(inArray(messages.id, messageIds), gt(messages.seq, ceiling)))),
            );
        const conversationIds = missing(
            page.messages.map((row) => row.conversationId),
            page.conversations,
            (row) => row.id,
        );
        if (conversationIds.length > 0) {
            page.conversations.push(
                ...(await db
                    .select()
                    .from(conversations)
                    .where(and(inArray(conversations.id, conversationIds), gt(conversations.seq, ceiling)))),
            );
        }
        const mailboxIds = missing(
            page.conversations.map((row) => row.mailboxId),
            page.mailboxes,
            (row) => row.mailbox.id,
        );
        if (mailboxIds.length > 0) {
            page.mailboxes.push(
                ...(await db
                    .select({ mailbox: mailboxes, domainName: domains.name })
                    .from(mailboxes)
                    .innerJoin(domains, eq(domains.id, mailboxes.domainId))
                    .where(and(inArray(mailboxes.id, mailboxIds), gt(mailboxes.seq, ceiling)))),
            );
        }
        const domainIds = missing(
            page.mailboxes.map((row) => row.mailbox.domainId),
            page.domains,
            (row) => row.id,
        );
        if (domainIds.length > 0)
            page.domains.push(
                ...(await db
                    .select()
                    .from(domains)
                    .where(and(inArray(domains.id, domainIds), gt(domains.seq, ceiling)))),
            );
    }

    return {
        /**
         * Rows changed after `cursor`, oldest first, up to `limit` per kind.
         *
         * `head` is read first: writers bump the user's counter under a row lock held until commit, so every row at or
         * below head is committed and nothing later can land below it. Reading up to head gives one consistent cut
         * across five queries. When a kind fills its limit the cut moves down to the lowest of those last rows, so a
         * page never skips past rows another kind hasn't returned yet.
         */
        async changes(userId: string, cursor: number, limit: number): Promise<SyncResponse> {
            const [state] = await db.select({ seq: syncState.seq }).from(syncState).where(eq(syncState.userId, userId));
            const head = state?.seq ?? 0;
            const window = (table: Synced) =>
                and(eq(table.userId, userId), gt(table.seq, cursor), lte(table.seq, head));

            const [domainRows, mailboxRows, conversationRows, messageRows, eventRows] = await Promise.all([
                db.select().from(domains).where(window(domains)).orderBy(asc(domains.seq)).limit(limit),
                db
                    .select({ mailbox: mailboxes, domainName: domains.name })
                    .from(mailboxes)
                    .innerJoin(domains, eq(domains.id, mailboxes.domainId))
                    .where(window(mailboxes))
                    .orderBy(asc(mailboxes.seq))
                    .limit(limit),
                db
                    .select()
                    .from(conversations)
                    .where(window(conversations))
                    .orderBy(asc(conversations.seq))
                    .limit(limit),
                db.select().from(messages).where(window(messages)).orderBy(asc(messages.seq)).limit(limit),
                db
                    .select({ event: events, url: links.url })
                    .from(events)
                    .leftJoin(links, eq(links.id, events.linkId))
                    .where(window(events))
                    .orderBy(asc(events.seq))
                    .limit(limit),
            ]);

            const pages = [
                domainRows.map((row) => row.seq),
                mailboxRows.map((row) => row.mailbox.seq),
                conversationRows.map((row) => row.seq),
                messageRows.map((row) => row.seq),
                eventRows.map((row) => row.event.seq),
            ];
            const fullPages = pages.filter((seqs) => seqs.length === limit);
            let ceiling = fullPages.length > 0 ? Math.min(...fullPages.map((seqs) => seqs.at(-1) ?? head)) : head;
            // Bodies are the only big rows, so they also end a page early. At least one always fits.
            let bytes = 0;
            for (const [index, row] of messageRows.entries()) {
                if (row.seq > ceiling) break;
                bytes += (row.html?.length ?? 0) + (row.text?.length ?? 0);
                if (bytes > MESSAGE_BYTES_PER_PAGE && index > 0) {
                    ceiling = messageRows[index - 1]?.seq ?? ceiling;
                    break;
                }
            }
            const upToCeiling = <T>(rows: T[], seqOf: (row: T) => number) =>
                rows.filter((row) => seqOf(row) <= ceiling);

            const page = {
                domains: upToCeiling(domainRows, (row) => row.seq),
                mailboxes: upToCeiling(mailboxRows, (row) => row.mailbox.seq),
                conversations: upToCeiling(conversationRows, (row) => row.seq),
                messages: upToCeiling(messageRows, (row) => row.seq),
                events: upToCeiling(eventRows, (row) => row.event.seq),
            };
            await withParents(page, ceiling);

            return {
                cursor: ceiling,
                hasMore: ceiling < head,
                domains: page.domains.map(toDomain),
                mailboxes: page.mailboxes.map((row) => toMailbox(row.mailbox, row.domainName)),
                conversations: page.conversations.map(toConversation),
                messages: await messagesRepo(db).wireMessages(page.messages),
                events: page.events.map((row) => toEvent(row.event, row.url)),
            };
        },
    };
}
