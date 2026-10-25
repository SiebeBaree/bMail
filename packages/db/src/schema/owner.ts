import { sql } from "drizzle-orm";
import { check, index, pgTable, smallint, text, timestamp } from "drizzle-orm/pg-core";

/**
 * Whoever owns this server. One row: the first device to claim a fresh server creates it, and every synced row
 * points at it. Servers from before the claim may hold more than one.
 */
export const users = pgTable("user", {
    id: text().primaryKey(),
    createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
});

/** The owner's devices share one token through iCloud Keychain. Only its sha256 is stored. */
export const ownerTokens = pgTable(
    "owner_tokens",
    {
        tokenHash: text().primaryKey(),
        userId: text()
            .notNull()
            .references(() => users.id, { onDelete: "cascade" }),
        createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
    },
    (table) => [index().on(table.userId)],
);

/**
 * What the server generated or was given after it was deployed, so nobody has to type it into the host's environment.
 * Always one row, id 1.
 */
export const serverSettings = pgTable(
    "server_settings",
    {
        id: smallint().primaryKey().default(1),
        trackingSecret: text(),
        resendApiKey: text(),
        resendWebhookId: text(),
        resendWebhookSecret: text(),
        updatedAt: timestamp({ withTimezone: true })
            .notNull()
            .defaultNow()
            .$onUpdate(() => new Date()),
    },
    () => [check("server_settings_single_row", sql`id = 1`)],
);
