import {
    deliveryStatuses,
    directions,
    domainStatuses,
    eventSources,
    eventTypes,
    folders,
    type Address,
    type DnsRecord,
} from "@repo/contracts";
import { sql } from "drizzle-orm";
import {
    bigint,
    boolean,
    index,
    integer,
    jsonb,
    pgEnum,
    pgTable,
    text,
    timestamp,
    unique,
    uniqueIndex,
    uuid,
    type AnyPgColumn,
} from "drizzle-orm/pg-core";

import { users } from "./auth";

export const domainStatus = pgEnum("domain_status", domainStatuses);
export const folder = pgEnum("folder", folders);
export const direction = pgEnum("direction", directions);
export const deliveryStatus = pgEnum("delivery_status", deliveryStatuses);
export const eventType = pgEnum("event_type", eventTypes);
export const eventSource = pgEnum("event_source", eventSources);

/**
 * Every synced table carries `seq`. A trigger sets it from `next_change(user_id)` on each insert and update (see the
 * sync migration), so no write can forget it. The function takes a row lock on the user's counter, which serializes
 * writers per user: commit order equals seq order and the app's cursor never skips a row that commits late.
 */
const synced = {
    userId: text()
        .notNull()
        .references(() => users.id, { onDelete: "cascade" }),
    seq: bigint({ mode: "number" }).notNull().default(0),
    createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
};

export const syncState = pgTable("sync_state", {
    userId: text()
        .primaryKey()
        .references(() => users.id, { onDelete: "cascade" }),
    seq: bigint({ mode: "number" }).notNull().default(0),
});

export const domains = pgTable(
    "domains",
    {
        id: uuid().primaryKey().defaultRandom(),
        ...synced,
        name: text().notNull(),
        resendDomainId: text().notNull(),
        status: domainStatus().notNull().default("pending"),
        records: jsonb().$type<DnsRecord[]>().notNull(),
        receivingEnabled: boolean().notNull().default(true),
        catchAllMailboxId: uuid().references((): AnyPgColumn => mailboxes.id, { onDelete: "set null" }),
        trackingHostVerifiedAt: timestamp({ withTimezone: true }),
        deletedAt: timestamp({ withTimezone: true }),
    },
    // Partial, so a removed domain can be added again.
    (table) => [
        uniqueIndex()
            .on(table.name)
            .where(sql`${table.deletedAt} is null`),
        index().on(table.userId, table.seq),
    ],
);

export const mailboxes = pgTable(
    "mailboxes",
    {
        id: uuid().primaryKey().defaultRandom(),
        ...synced,
        domainId: uuid()
            .notNull()
            .references(() => domains.id, { onDelete: "cascade" }),
        localPart: text().notNull(),
        displayName: text().notNull(),
        signatureHtml: text(),
        deletedAt: timestamp({ withTimezone: true }),
    },
    (table) => [
        uniqueIndex()
            .on(table.domainId, table.localPart)
            .where(sql`${table.deletedAt} is null`),
        index().on(table.userId, table.seq),
    ],
);

export const conversations = pgTable(
    "conversations",
    {
        id: uuid().primaryKey().defaultRandom(),
        ...synced,
        mailboxId: uuid()
            .notNull()
            .references(() => mailboxes.id, { onDelete: "cascade" }),
        subject: text().notNull(),
        folder: folder().notNull().default("inbox"),
        isRead: boolean().notNull().default(false),
        isStarred: boolean().notNull().default(false),
        snoozedUntil: timestamp({ withTimezone: true }),
        lastMessageAt: timestamp({ withTimezone: true }).notNull(),
        /** Set when we send into the conversation. The Sent view is every conversation where this is not null. */
        lastOutboundAt: timestamp({ withTimezone: true }),
    },
    (table) => [index().on(table.userId, table.seq), index().on(table.mailboxId, table.lastMessageAt)],
);

export const messages = pgTable(
    "messages",
    {
        id: uuid().primaryKey().defaultRandom(),
        ...synced,
        conversationId: uuid()
            .notNull()
            .references(() => conversations.id, { onDelete: "cascade" }),
        mailboxId: uuid()
            .notNull()
            .references(() => mailboxes.id, { onDelete: "cascade" }),
        direction: direction().notNull(),
        /** Null for inbound mail. Outbound starts at `sending` and follows Resend's webhooks. */
        deliveryStatus: deliveryStatus(),
        /** The RFC 5322 Message-ID. Outbound mail learns it from Resend's `email.sent` webhook. */
        messageIdHeader: text(),
        inReplyTo: text(),
        references: jsonb().$type<string[]>().notNull().default([]),
        from: jsonb().$type<Address>().notNull(),
        to: jsonb().$type<Address[]>().notNull(),
        cc: jsonb().$type<Address[]>().notNull().default([]),
        bcc: jsonb().$type<Address[]>().notNull().default([]),
        replyTo: jsonb().$type<Address[]>().notNull().default([]),
        subject: text().notNull(),
        /** Exactly as written or received. Tracked mail is instrumented on the way out and never stored that way. */
        html: text(),
        text: text(),
        snippet: text().notNull(),
        sentAt: timestamp({ withTimezone: true }).notNull(),
        resendEmailId: text(),
        trackingEnabled: boolean().notNull().default(false),
        rawStorageKey: text(),
    },
    (table) => [
        unique().on(table.mailboxId, table.resendEmailId),
        index().on(table.userId, table.seq),
        index().on(table.userId, table.messageIdHeader),
        index().on(table.conversationId, table.sentAt),
    ],
);

/** An attachment starts as an upload (no message yet) when the app sends one, and is linked when the mail goes out. */
export const attachments = pgTable(
    "attachments",
    {
        id: uuid().primaryKey().defaultRandom(),
        userId: text()
            .notNull()
            .references(() => users.id, { onDelete: "cascade" }),
        messageId: uuid().references(() => messages.id, { onDelete: "cascade" }),
        filename: text().notNull(),
        contentType: text().notNull(),
        size: integer().notNull(),
        /** Set for inline images referenced as `cid:` from the html. */
        contentId: text(),
        storageKey: text().notNull(),
    },
    (table) => [index().on(table.messageId)],
);

/** The original destination of every link in a tracked message. A click token points at a row here. */
export const links = pgTable(
    "links",
    {
        id: uuid().primaryKey().defaultRandom(),
        messageId: uuid()
            .notNull()
            .references(() => messages.id, { onDelete: "cascade" }),
        /** Order in the html, so re-instrumenting a retried send produces the same links. */
        position: integer().notNull(),
        url: text().notNull(),
    },
    (table) => [index().on(table.messageId)],
);

/** Delivery webhooks, opens and clicks. A message's timeline is one query on this table. */
export const events = pgTable(
    "events",
    {
        id: uuid().primaryKey().defaultRandom(),
        ...synced,
        messageId: uuid()
            .notNull()
            .references(() => messages.id, { onDelete: "cascade" }),
        type: eventType().notNull(),
        linkId: uuid().references(() => links.id, { onDelete: "set null" }),
        /** Opens and clicks only. Location and device are derived on arrival; the raw IP is never stored. */
        source: eventSource(),
        device: text(),
        city: text(),
        country: text(),
        detail: text(),
        occurredAt: timestamp({ withTimezone: true }).notNull(),
    },
    (table) => [index().on(table.userId, table.seq), index().on(table.messageId, table.occurredAt)],
);

/** Resend retries webhooks with the same svix-id. Inserting here first makes a retry a no-op. */
export const webhookReceipts = pgTable("webhook_receipts", {
    svixId: text().primaryKey(),
    receivedAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
});

export type DomainRow = typeof domains.$inferSelect;
export type MailboxRow = typeof mailboxes.$inferSelect;
export type ConversationRow = typeof conversations.$inferSelect;
export type MessageRow = typeof messages.$inferSelect;
export type AttachmentRow = typeof attachments.$inferSelect;
export type EventRow = typeof events.$inferSelect;
