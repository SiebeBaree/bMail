import { randomUUID } from "node:crypto";

import type { Address, CreateUploadInput, SendMessageInput, SentMessage, Upload } from "@repo/contracts";
import { attachments, conversations, links, messages, type Database, type MessageRow } from "@repo/db";
import { and, eq, inArray } from "drizzle-orm";

import { formatAddress } from "../../lib/addresses";
import { toConversation, trackingHostOf } from "../../lib/dto";
import { ConflictError, NotFoundError } from "../../lib/errors";
import { instrumentHtml, snippetOf } from "../../lib/html";
import type { ResendGateway } from "../../lib/resend";
import type { Storage } from "../../lib/storage";
import type { TrackingTokens } from "../../lib/tracking-token";
import { mailboxesRepo } from "../mailboxes/mailboxes.repo";
import { messagesRepo } from "./messages.repo";

type Dependencies = {
    db: Database;
    resend: ResendGateway;
    storage: Storage;
    trackingTokens: TrackingTokens;
    publicUrl: string;
};

const UPLOAD_URL_TTL_SECONDS = 15 * 60;
// Resend fetches attachments by url while it builds the email, which can lag behind the send call.
const ATTACHMENT_FETCH_TTL_SECONDS = 60 * 60;

export function sendService({ db, resend, storage, trackingTokens, publicUrl }: Dependencies) {
    const repo = messagesRepo(db);

    async function sentMessage(userId: string, message: MessageRow): Promise<SentMessage> {
        const conversation = await repo.findConversation(userId, message.conversationId);
        if (!conversation) throw new NotFoundError("That conversation doesn't exist anymore.");
        const [wire] = await repo.wireMessages([message]);
        if (!wire) throw new Error("message vanished while reading it back");
        return { conversation: toConversation(conversation), message: wire };
    }

    async function setOutcome(userId: string, id: string, outcome: { resendEmailId: string } | { error: string }) {
        const now = new Date();
        const message = await db.transaction(async (tx) => {
            const [row] = await tx
                .update(messages)
                .set(
                    "error" in outcome
                        ? { deliveryStatus: "failed" }
                        : { deliveryStatus: "sent", resendEmailId: outcome.resendEmailId },
                )
                .where(and(eq(messages.userId, userId), eq(messages.id, id)))
                .returning();
            if (!row) throw new Error("message vanished while sending it");
            await messagesRepo(tx).recordEvent({
                userId,
                messageId: id,
                type: "error" in outcome ? "failed" : "sent",
                detail: "error" in outcome ? outcome.error : null,
                occurredAt: now,
            });
            return row;
        });
        return message;
    }

    return {
        /**
         * Stores the message, then sends it through Resend with the message id as idempotency key. A send that failed
         * or was cut off halfway can be retried with the same id: it rebuilds the exact same email, so Resend either
         * sends it once or recognizes the retry.
         */
        async send(userId: string, input: SendMessageInput): Promise<SentMessage> {
            const existing = await repo.findMessage(userId, input.id);
            if (existing && existing.deliveryStatus !== "sending" && existing.deliveryStatus !== "failed") {
                return sentMessage(userId, existing);
            }

            const target = await mailboxesRepo(db).findWithDomain(userId, input.mailboxId);
            if (!target) throw new NotFoundError("That mailbox doesn't exist anymore.");
            const { mailbox, domain } = target;
            if (domain.status !== "verified") {
                throw new ConflictError(`${domain.name} isn't verified yet, so mail from it would bounce.`);
            }
            const from: Address = { name: mailbox.displayName, email: `${mailbox.localPart}@${domain.name}` };

            const conversation = await repo.findConversation(userId, input.conversationId);
            const parent = conversation ? await repo.latestMessage(conversation.id) : null;
            const references = parent?.messageIdHeader ? [...parent.references, parent.messageIdHeader].slice(-20) : [];
            const inReplyTo = parent?.messageIdHeader ?? null;

            const uploads = existing
                ? await db.select().from(attachments).where(eq(attachments.messageId, existing.id))
                : await repo.pendingUploads(userId, input.attachmentIds);
            if (uploads.length !== input.attachmentIds.length) {
                throw new NotFoundError("An attachment didn't finish uploading. Attach it again.");
            }

            // Reuses the stored links on a retry, in order, so the retried email is byte-for-byte the first one.
            const knownLinks = existing ? await repo.linksOf(existing.id) : [];
            const trackedLinks: { id: string; url: string }[] = [];
            const trackingOrigin = domain.trackingHostVerifiedAt ? `https://${trackingHostOf(domain.name)}` : publicUrl;
            const html = input.trackingEnabled
                ? instrumentHtml(input.html, {
                      pixelUrl: `${trackingOrigin}/o/${trackingTokens.create("open", input.id)}`,
                      rewriteLink: (url) => {
                          const link = knownLinks[trackedLinks.length] ?? { id: randomUUID(), url };
                          trackedLinks.push(link);
                          return `${trackingOrigin}/c/${trackingTokens.create("click", link.id)}`;
                      },
                  })
                : input.html;

            if (!existing) {
                const now = new Date();
                await db.transaction(async (tx) => {
                    if (conversation) {
                        await tx
                            .update(conversations)
                            .set({ lastMessageAt: now, lastOutboundAt: now, isRead: true })
                            .where(eq(conversations.id, conversation.id));
                    } else {
                        // A conversation you start isn't something to triage, so it lives in Done until someone replies.
                        await tx.insert(conversations).values({
                            id: input.conversationId,
                            userId,
                            mailboxId: mailbox.id,
                            subject: input.subject,
                            folder: "done",
                            isRead: true,
                            lastMessageAt: now,
                            lastOutboundAt: now,
                        });
                    }
                    await tx.insert(messages).values({
                        id: input.id,
                        userId,
                        conversationId: input.conversationId,
                        mailboxId: mailbox.id,
                        direction: "outbound",
                        deliveryStatus: "sending",
                        inReplyTo,
                        references,
                        from,
                        to: input.to,
                        cc: input.cc,
                        bcc: input.bcc,
                        subject: input.subject,
                        html: input.html,
                        text: input.text,
                        snippet: snippetOf(input.text),
                        sentAt: now,
                        trackingEnabled: input.trackingEnabled,
                    });
                    if (trackedLinks.length > 0) {
                        await tx.insert(links).values(
                            trackedLinks.map((link, position) => ({
                                id: link.id,
                                url: link.url,
                                position,
                                messageId: input.id,
                            })),
                        );
                    }
                    if (uploads.length > 0) {
                        await tx
                            .update(attachments)
                            .set({ messageId: input.id })
                            .where(
                                inArray(
                                    attachments.id,
                                    uploads.map((upload) => upload.id),
                                ),
                            );
                    }
                });
            }

            try {
                const { id: resendEmailId } = await resend.send(
                    {
                        from: formatAddress(from),
                        to: input.to.map(formatAddress),
                        cc: input.cc.map(formatAddress),
                        bcc: input.bcc.map(formatAddress),
                        subject: input.subject,
                        html,
                        text: input.text,
                        // Webhooks find the message by this tag. Resend's own id isn't stored yet when the first one lands.
                        tags: { message: input.id },
                        headers: {
                            ...(inReplyTo && { "In-Reply-To": inReplyTo }),
                            ...(references.length > 0 && { References: references.join(" ") }),
                        },
                        attachments: await Promise.all(
                            uploads.map(async (file) => ({
                                filename: file.filename,
                                contentType: file.contentType,
                                url: await storage.downloadUrl(
                                    file.storageKey,
                                    file.filename,
                                    ATTACHMENT_FETCH_TTL_SECONDS,
                                ),
                            })),
                        ),
                    },
                    input.id,
                );
                return sentMessage(userId, await setOutcome(userId, input.id, { resendEmailId }));
            } catch (error) {
                await setOutcome(userId, input.id, { error: error instanceof Error ? error.message : "Unknown error" });
                throw error;
            }
        },

        /** Reserves an attachment and returns where the app uploads its bytes, straight to storage. */
        async createUpload(userId: string, input: CreateUploadInput): Promise<Upload> {
            const id = randomUUID();
            const storageKey = `uploads/${userId}/${id}/${input.filename}`;
            const uploadUrl = await storage.uploadUrl(storageKey, input.contentType, UPLOAD_URL_TTL_SECONDS);
            await db.insert(attachments).values({
                id,
                userId,
                filename: input.filename,
                contentType: input.contentType,
                size: input.size,
                storageKey,
            });
            return { id, uploadUrl, expiresAt: new Date(Date.now() + UPLOAD_URL_TTL_SECONDS * 1000).toISOString() };
        },

        async attachmentUrl(userId: string, id: string) {
            const [file] = await db
                .select()
                .from(attachments)
                .where(and(eq(attachments.userId, userId), eq(attachments.id, id)));
            if (!file) throw new NotFoundError("That attachment doesn't exist anymore.");
            const ttl = 15 * 60;
            return {
                url: await storage.downloadUrl(file.storageKey, file.filename, ttl),
                expiresAt: new Date(Date.now() + ttl * 1000).toISOString(),
            };
        },
    };
}
