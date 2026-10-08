import type { SyncResponse } from "@repo/contracts";
import { conversations, domains, events, links, mailboxes, messages, syncState, type Database } from "@repo/db";
import { and, asc, eq, gt, lte } from "drizzle-orm";
import type { AnyPgColumn } from "drizzle-orm/pg-core";

import { toConversation, toDomain, toEvent, toMailbox } from "../../lib/dto";
import { messagesRepo } from "../messages/messages.repo";

type Synced = { userId: AnyPgColumn; seq: AnyPgColumn };

export function syncService(db: Database) {
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
            const ceiling = fullPages.length > 0 ? Math.min(...fullPages.map((seqs) => seqs.at(-1) ?? head)) : head;
            const upToCeiling = <T>(rows: T[], seqOf: (row: T) => number) =>
                rows.filter((row) => seqOf(row) <= ceiling);

            return {
                cursor: ceiling,
                hasMore: fullPages.length > 0,
                domains: upToCeiling(domainRows, (row) => row.seq).map(toDomain),
                mailboxes: upToCeiling(mailboxRows, (row) => row.mailbox.seq).map((row) =>
                    toMailbox(row.mailbox, row.domainName),
                ),
                conversations: upToCeiling(conversationRows, (row) => row.seq).map(toConversation),
                messages: await messagesRepo(db).wireMessages(upToCeiling(messageRows, (row) => row.seq)),
                events: upToCeiling(eventRows, (row) => row.event.seq).map((row) => toEvent(row.event, row.url)),
            };
        },
    };
}
