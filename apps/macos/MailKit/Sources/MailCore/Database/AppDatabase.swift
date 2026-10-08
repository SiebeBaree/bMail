import Foundation
import OSLog
import SQLiteData

private let logger = Logger(subsystem: "be.baree.mail", category: "Database")

/// Opens the local cache at Application Support/Mail/Mail.sqlite, creating and migrating it as needed. Tests and
/// previews get a fresh temporary database. Everything in it can be synced again, so `reset` simply deletes it.
public func appDatabase(reset: Bool = false) throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    #if DEBUG
        configuration.prepareDatabase { db in
            db.trace(options: .profile) { event in
                if case let .profile(statement, duration) = event, duration > 0.02 {
                    logger.debug("slow query \(duration, format: .fixed(precision: 3))s: \(statement.sql)")
                }
            }
        }
    #endif
    let folder = URL.applicationSupportDirectory.appending(path: "Mail", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appending(path: "Mail.sqlite")
    if reset {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: file.path(percentEncoded: false) + suffix)
        }
    }
    let database = try defaultDatabase(path: file.path(percentEncoded: false), configuration: configuration)
    try migrator.migrate(database)
    return database
}

/// An empty in-memory database with the same schema, for tests and previews.
public func inMemoryDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let database = try DatabaseQueue(configuration: configuration)
    try migrator.migrate(database)
    return database
}

private var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()
    #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
    #endif

    migrator.registerMigration("Create tables") { db in
        try db.execute(
            sql: """
                CREATE TABLE "domains" (
                    "id" TEXT PRIMARY KEY NOT NULL,
                    "name" TEXT NOT NULL,
                    "status" TEXT NOT NULL,
                    "records" TEXT NOT NULL,
                    "receivingEnabled" INTEGER NOT NULL,
                    "catchAllMailboxID" TEXT,
                    "trackingHost" TEXT NOT NULL,
                    "trackingHostVerified" INTEGER NOT NULL
                ) STRICT;

                CREATE TABLE "accounts" (
                    "id" TEXT PRIMARY KEY NOT NULL,
                    "kind" TEXT NOT NULL,
                    "address" TEXT NOT NULL,
                    "displayName" TEXT NOT NULL,
                    "domainID" TEXT REFERENCES "domains"("id") ON DELETE CASCADE,
                    "position" INTEGER NOT NULL DEFAULT 0
                ) STRICT;

                CREATE TABLE "conversations" (
                    "id" TEXT PRIMARY KEY NOT NULL,
                    "accountID" TEXT NOT NULL REFERENCES "accounts"("id") ON DELETE CASCADE,
                    "subject" TEXT NOT NULL,
                    "folder" TEXT NOT NULL,
                    "isRead" INTEGER NOT NULL,
                    "isStarred" INTEGER NOT NULL,
                    "snoozedUntil" TEXT,
                    "lastMessageAt" TEXT NOT NULL,
                    "lastOutboundAt" TEXT,
                    "snippet" TEXT NOT NULL DEFAULT '',
                    "participants" TEXT NOT NULL DEFAULT '',
                    "messageCount" INTEGER NOT NULL DEFAULT 0,
                    "hasAttachments" INTEGER NOT NULL DEFAULT 0,
                    "isTracked" INTEGER NOT NULL DEFAULT 0,
                    "remoteID" TEXT
                ) STRICT;
                CREATE INDEX "conversations_by_folder" ON "conversations"("folder", "lastMessageAt" DESC);
                CREATE INDEX "conversations_by_account" ON "conversations"("accountID", "folder", "lastMessageAt" DESC);
                CREATE INDEX "conversations_sent" ON "conversations"("lastOutboundAt" DESC) WHERE "lastOutboundAt" IS NOT NULL;

                CREATE TABLE "messages" (
                    "id" TEXT PRIMARY KEY NOT NULL,
                    "conversationID" TEXT NOT NULL REFERENCES "conversations"("id") ON DELETE CASCADE,
                    "accountID" TEXT NOT NULL,
                    "direction" TEXT NOT NULL,
                    "deliveryStatus" TEXT,
                    "messageIDHeader" TEXT,
                    "from" TEXT NOT NULL,
                    "to" TEXT NOT NULL,
                    "cc" TEXT NOT NULL,
                    "bcc" TEXT NOT NULL,
                    "replyTo" TEXT NOT NULL,
                    "subject" TEXT NOT NULL,
                    "html" TEXT,
                    "text" TEXT,
                    "snippet" TEXT NOT NULL,
                    "sentAt" TEXT NOT NULL,
                    "trackingEnabled" INTEGER NOT NULL,
                    "attachments" TEXT NOT NULL,
                    "links" TEXT NOT NULL,
                    "remoteID" TEXT
                ) STRICT;
                CREATE INDEX "messages_by_conversation" ON "messages"("conversationID", "sentAt");

                CREATE TABLE "messageEvents" (
                    "id" TEXT PRIMARY KEY NOT NULL,
                    "messageID" TEXT NOT NULL REFERENCES "messages"("id") ON DELETE CASCADE,
                    "kind" TEXT NOT NULL,
                    "source" TEXT,
                    "url" TEXT,
                    "device" TEXT,
                    "city" TEXT,
                    "country" TEXT,
                    "detail" TEXT,
                    "occurredAt" TEXT NOT NULL
                ) STRICT;
                CREATE INDEX "messageEvents_by_message" ON "messageEvents"("messageID", "occurredAt");

                CREATE TABLE "pendingMutations" (
                    "id" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "mutation" TEXT NOT NULL,
                    "attempts" INTEGER NOT NULL DEFAULT 0,
                    "createdAt" TEXT NOT NULL
                ) STRICT;

                CREATE TABLE "outboxItems" (
                    "id" TEXT PRIMARY KEY NOT NULL,
                    "message" TEXT NOT NULL,
                    "sendAt" TEXT NOT NULL,
                    "attempts" INTEGER NOT NULL DEFAULT 0,
                    "lastError" TEXT
                ) STRICT;

                CREATE TABLE "syncCursors" (
                    "source" TEXT PRIMARY KEY NOT NULL,
                    "cursor" TEXT NOT NULL
                ) STRICT;

                CREATE TABLE "contacts" (
                    "email" TEXT PRIMARY KEY NOT NULL COLLATE NOCASE,
                    "name" TEXT,
                    "lastContactedAt" TEXT NOT NULL,
                    "timesContacted" INTEGER NOT NULL DEFAULT 0
                ) STRICT;

                -- One row per message, keyed by the message's rowid. Kept in step by MailStore, not triggers, because
                -- the body text is derived in Swift.
                CREATE VIRTUAL TABLE "messageTexts" USING fts5(
                    "subject", "people", "body",
                    tokenize = 'unicode61 remove_diacritics 2'
                );
                """
        )
    }
    return migrator
}
