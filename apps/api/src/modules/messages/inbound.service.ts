import { randomUUID } from "node:crypto";

import { attachments, conversations, domains, mailboxes, messages, type Database, type MailboxRow } from "@repo/db";
import { and, eq, inArray, isNull, sql } from "drizzle-orm";
import type { FastifyBaseLogger } from "fastify";

import { domainOf, parseAddress } from "../../lib/addresses";
import { normalizeMessageId } from "../../lib/headers";
import { snippetOf, textOf } from "../../lib/html";
import type { ReceivedEmail, ResendGateway } from "../../lib/resend";
import type { Storage } from "../../lib/storage";

type Dependencies = { db: Database; resend: ResendGateway; storage: Storage; log: FastifyBaseLogger };

type StoredFile = { filename: string; contentType: string; size: number; contentId: string | null; storageKey: string };

export function inboundService({ db, resend, storage, log }: Dependencies) {
    /**
     * The mailboxes an email belongs in: every exact address match, plus the domain's catch-all for recipients on our
     * domains that have no mailbox. One email to siebe@ and hello@ lands in both.
     */
    async function targetsFor(email: ReceivedEmail): Promise<MailboxRow[]> {
        const recipients = [
            ...new Set(
                [...email.to, ...email.cc, ...email.bcc, ...email.receivedFor].map((raw) => parseAddress(raw).email),
            ),
        ];
        const owned = await db
            .select()
            .from(domains)
            .where(
                and(
                    inArray(domains.name, [...new Set(recipients.map(domainOf))]),
                    eq(domains.receivingEnabled, true),
                    isNull(domains.deletedAt),
                ),
            );
        if (owned.length === 0) return [];

        const candidates = await db
            .select()
            .from(mailboxes)
            .where(
                and(
                    inArray(
                        mailboxes.domainId,
                        owned.map((domain) => domain.id),
                    ),
                    isNull(mailboxes.deletedAt),
                ),
            );

        const targets = new Map<string, MailboxRow>();
        for (const domain of owned) {
            const onDomain = candidates.filter((mailbox) => mailbox.domainId === domain.id);
            const localParts = recipients
                .filter((address) => domainOf(address) === domain.name)
                .map((address) => address.split("@")[0]);
            for (const localPart of localParts) {
                const mailbox =
                    onDomain.find((candidate) => candidate.localPart === localPart) ??
                    onDomain.find((candidate) => candidate.id === domain.catchAllMailboxId);
                if (mailbox) targets.set(mailbox.id, mailbox);
            }
        }
        return [...targets.values()];
    }

    /** Copies the raw file and attachments out of Resend before its download links expire. */
    async function storeFiles(email: ReceivedEmail): Promise<{ rawKey: string | null; files: StoredFile[] }> {
        const prefix = `inbound/${email.id}`;
        let rawKey: string | null = null;
        if (email.rawUrl) {
            rawKey = `${prefix}/raw.eml`;
            await storage.put(rawKey, await download(email.rawUrl), "message/rfc822");
        }
        const files = await Promise.all(
            (await resend.listReceivedAttachments(email.id)).map(async (file): Promise<StoredFile> => {
                const storageKey = `${prefix}/${file.id}/${file.filename}`;
                await storage.put(storageKey, await download(file.downloadUrl), file.contentType);
                return {
                    filename: file.filename,
                    contentType: file.contentType,
                    size: file.size,
                    contentId: file.contentId,
                    storageKey,
                };
            }),
        );
        return { rawKey, files };
    }

    return {
        /**
         * Handles `email.received`. Safe to run twice for the same email: a mailbox that already has it is skipped,
         * which is what makes Resend's retries harmless.
         */
        async receive(emailId: string): Promise<void> {
            const email = await resend.getReceivedEmail(emailId);
            const targets = await targetsFor(email);
            if (targets.length === 0) {
                log.info({ emailId, to: email.to }, "inbound.unrouted");
                return;
            }

            const { rawKey, files } = await storeFiles(email);
            const header = (name: string) =>
                Object.entries(email.headers)
                    .find(([key]) => key.toLowerCase() === name)?.[1]
                    ?.trim() ?? null;
            const inReplyToHeader = header("in-reply-to");
            const inReplyTo = inReplyToHeader ? normalizeMessageId(inReplyToHeader) : null;
            const references = header("references")?.split(/\s+/).filter(Boolean).map(normalizeMessageId) ?? [];
            const threadIds = [...new Set([...references, ...(inReplyTo ? [inReplyTo] : [])])];
            const receivedAt = new Date(email.createdAt);
            const body = textOf(email.html, email.text);

            for (const mailbox of targets) {
                // One transaction per mailbox, in order: they all bump the same user's sync counter anyway.
                // oxlint-disable-next-line no-await-in-loop
                await db.transaction(async (tx) => {
                    const [duplicate] = await tx
                        .select({ id: messages.id })
                        .from(messages)
                        .where(and(eq(messages.mailboxId, mailbox.id), eq(messages.resendEmailId, email.id)));
                    if (duplicate) return;

                    const [parent] = threadIds.length
                        ? await tx
                              .select({ conversationId: messages.conversationId })
                              .from(messages)
                              .where(
                                  and(eq(messages.mailboxId, mailbox.id), inArray(messages.messageIdHeader, threadIds)),
                              )
                              .limit(1)
                        : [];

                    const conversationId = parent?.conversationId ?? randomUUID();
                    if (parent) {
                        // A reply brings a conversation back from Done and ends a snooze. Spam and trash stay put.
                        await tx
                            .update(conversations)
                            .set({
                                isRead: false,
                                snoozedUntil: null,
                                folder: sql`case when ${conversations.folder} = 'done' then 'inbox'::folder else ${conversations.folder} end`,
                                lastMessageAt: sql`greatest(${conversations.lastMessageAt}, ${receivedAt})`,
                            })
                            .where(eq(conversations.id, conversationId));
                    } else {
                        await tx.insert(conversations).values({
                            id: conversationId,
                            userId: mailbox.userId,
                            mailboxId: mailbox.id,
                            subject: email.subject,
                            lastMessageAt: receivedAt,
                        });
                    }

                    const messageId = randomUUID();
                    await tx.insert(messages).values({
                        id: messageId,
                        userId: mailbox.userId,
                        conversationId,
                        mailboxId: mailbox.id,
                        direction: "inbound",
                        messageIdHeader: normalizeMessageId(email.messageId),
                        inReplyTo,
                        references,
                        from: parseAddress(email.from),
                        to: email.to.map(parseAddress),
                        cc: email.cc.map(parseAddress),
                        bcc: email.bcc.map(parseAddress),
                        replyTo: email.replyTo.map(parseAddress),
                        subject: email.subject,
                        html: email.html,
                        text: email.text,
                        snippet: snippetOf(body),
                        sentAt: receivedAt,
                        resendEmailId: email.id,
                        rawStorageKey: rawKey,
                        listUnsubscribe: header("list-unsubscribe"),
                        listUnsubscribePost: header("list-unsubscribe-post"),
                    });
                    if (files.length > 0) {
                        await tx
                            .insert(attachments)
                            .values(files.map((file) => ({ ...file, userId: mailbox.userId, messageId })));
                    }
                });
            }
            log.info({ emailId, mailboxes: targets.length, attachments: files.length }, "inbound.stored");
        },
    };
}

async function download(url: string): Promise<Uint8Array> {
    const response = await fetch(url);
    if (!response.ok) throw new Error(`download failed with ${response.status}`);
    return new Uint8Array(await response.arrayBuffer());
}
