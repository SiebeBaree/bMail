import { boolean, index, pgTable, text, timestamp } from "drizzle-orm/pg-core";

// Better Auth's core tables. Field names follow its schema exactly; the adapter maps models by these keys.
const timestamps = {
    createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp({ withTimezone: true })
        .notNull()
        .defaultNow()
        .$onUpdate(() => new Date()),
};

export const users = pgTable("user", {
    id: text().primaryKey(),
    name: text().notNull(),
    email: text().notNull().unique(),
    emailVerified: boolean().notNull().default(false),
    image: text(),
    ...timestamps,
});

export const sessions = pgTable(
    "session",
    {
        id: text().primaryKey(),
        token: text().notNull().unique(),
        expiresAt: timestamp({ withTimezone: true }).notNull(),
        ipAddress: text(),
        userAgent: text(),
        userId: text()
            .notNull()
            .references(() => users.id, { onDelete: "cascade" }),
        ...timestamps,
    },
    (table) => [index().on(table.userId)],
);

export const accounts = pgTable(
    "account",
    {
        id: text().primaryKey(),
        accountId: text().notNull(),
        providerId: text().notNull(),
        userId: text()
            .notNull()
            .references(() => users.id, { onDelete: "cascade" }),
        accessToken: text(),
        refreshToken: text(),
        idToken: text(),
        accessTokenExpiresAt: timestamp({ withTimezone: true }),
        refreshTokenExpiresAt: timestamp({ withTimezone: true }),
        scope: text(),
        password: text(),
        ...timestamps,
    },
    (table) => [index().on(table.userId)],
);

export const verifications = pgTable(
    "verification",
    {
        id: text().primaryKey(),
        identifier: text().notNull(),
        value: text().notNull(),
        expiresAt: timestamp({ withTimezone: true }).notNull(),
        ...timestamps,
    },
    (table) => [index().on(table.identifier)],
);
