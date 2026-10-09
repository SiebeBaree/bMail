import type { Conversation, ConversationLabels, Domain, Label, Mailbox, Message, MessageEvent } from "@repo/contracts";
import type {
    AttachmentRow,
    ConversationLabelsRow,
    ConversationRow,
    DomainRow,
    EventRow,
    LabelRow,
    MailboxRow,
    MessageRow,
} from "@repo/db";

// Row to wire format, in one place, because sync returns every kind of row and each module returns its own.
// Dates become ISO strings here and nowhere else.

const iso = (date: Date) => date.toISOString();
const isoOrNull = (date: Date | null) => (date ? date.toISOString() : null);

export function toDomain(row: DomainRow): Domain {
    return {
        id: row.id,
        name: row.name,
        status: row.status,
        records: row.records,
        receivingEnabled: row.receivingEnabled,
        catchAllMailboxId: row.catchAllMailboxId,
        trackingHost: trackingHostOf(row.name),
        trackingHostVerified: row.trackingHostVerifiedAt !== null,
        createdAt: iso(row.createdAt),
        deletedAt: isoOrNull(row.deletedAt),
    };
}

export function toMailbox(row: MailboxRow, domainName: string): Mailbox {
    return {
        id: row.id,
        domainId: row.domainId,
        localPart: row.localPart,
        address: `${row.localPart}@${domainName}`,
        displayName: row.displayName,
        signatureHtml: row.signatureHtml,
        createdAt: iso(row.createdAt),
        deletedAt: isoOrNull(row.deletedAt),
    };
}

export function toConversation(row: ConversationRow): Conversation {
    return {
        id: row.id,
        mailboxId: row.mailboxId,
        subject: row.subject,
        folder: row.folder,
        isRead: row.isRead,
        isStarred: row.isStarred,
        snoozedUntil: isoOrNull(row.snoozedUntil),
        lastMessageAt: iso(row.lastMessageAt),
        lastOutboundAt: isoOrNull(row.lastOutboundAt),
    };
}

export function toMessage(
    row: MessageRow,
    attachments: AttachmentRow[],
    links: { id: string; url: string }[],
): Message {
    return {
        id: row.id,
        conversationId: row.conversationId,
        mailboxId: row.mailboxId,
        direction: row.direction,
        deliveryStatus: row.deliveryStatus,
        messageIdHeader: row.messageIdHeader,
        from: row.from,
        to: row.to,
        cc: row.cc,
        bcc: row.bcc,
        replyTo: row.replyTo,
        subject: row.subject,
        html: row.html,
        text: row.text,
        snippet: row.snippet,
        sentAt: iso(row.sentAt),
        trackingEnabled: row.trackingEnabled,
        attachments: attachments.map((file) => ({
            id: file.id,
            filename: file.filename,
            contentType: file.contentType,
            size: file.size,
            contentId: file.contentId,
        })),
        links,
        listUnsubscribe: row.listUnsubscribe,
        listUnsubscribeOneClick: row.listUnsubscribePost?.toLowerCase() === "list-unsubscribe=one-click",
    };
}

export function toEvent(row: EventRow, url: string | null): MessageEvent {
    return {
        id: row.id,
        messageId: row.messageId,
        type: row.type,
        source: row.source,
        url,
        device: row.device,
        city: row.city,
        country: row.country,
        detail: row.detail,
        occurredAt: iso(row.occurredAt),
    };
}

export function toLabel(row: LabelRow): Label {
    return {
        id: row.id,
        name: row.name,
        createdAt: iso(row.createdAt),
        deletedAt: isoOrNull(row.deletedAt),
    };
}

export function toConversationLabels(row: ConversationLabelsRow): ConversationLabels {
    return { conversationId: row.conversationId, labelIds: row.labelIds };
}

/** Every domain gets `t.<domain>` for tracking, a CNAME to the api, so links match the sender's domain. */
export function trackingHostOf(domainName: string): string {
    return `t.${domainName}`;
}
