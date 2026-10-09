import Foundation
import SQLiteData

/// Every write to the local cache goes through here. Views only read, through `@FetchAll` and friends, so the rules
/// that keep derived columns, search and pending mutations consistent live in one place.
public struct MailStore: Sendable {
    public let database: any DatabaseWriter

    public init(database: any DatabaseWriter) {
        self.database = database
    }

    // MARK: - Provider changes

    /// Writes what a provider reported, in one transaction. Mutations that haven't reached the provider yet are
    /// replayed on top, so a sync that raced an archive doesn't bring the conversation back.
    public func merge(_ changes: ChangeSet, source: String) throws {
        try database.write { db in
            for id in changes.removedAccountIDs {
                try Account.find(id).delete().execute(db)
            }
            for id in changes.removedDomainIDs {
                try Domain.find(id).delete().execute(db)
            }
            for id in changes.removedMessageIDs {
                try Message.find(id).delete().execute(db)
            }
            for id in changes.removedConversationIDs {
                try Conversation.find(id).delete().execute(db)
            }
            for domain in changes.domains {
                try Domain.upsert { domain }.execute(db)
            }
            for account in changes.accounts {
                try Account.upsert { account }.execute(db)
            }
            for conversation in changes.conversations {
                try Conversation.upsert { conversation }.execute(db)
            }
            for message in changes.messages {
                try Message.upsert { message }.execute(db)
                try index(message, in: db)
                try remember(message, in: db)
            }
            for event in changes.events {
                try MessageEvent.upsert { event }.execute(db)
            }
            for id in changes.removedLabelIDs {
                try MailLabel.find(id).delete().execute(db)
            }
            for label in changes.labels {
                try MailLabel.upsert { label }.execute(db)
            }
            let known = Set(try MailLabel.select(\.id).fetchAll(db))
            for (conversationID, labelIDs) in changes.conversationLabels {
                try ConversationLabel.where { $0.conversationID.eq(conversationID) }.delete().execute(db)
                // A label deleted on another Mac can still be in a set that was saved before.
                for labelID in labelIDs where known.contains(labelID) {
                    try ConversationLabel.insert { ConversationLabel(conversationID: conversationID, labelID: labelID) }.execute(db)
                }
            }
            for tracked in changes.trackedSends {
                try TrackedSend.upsert { tracked }.execute(db)
            }
            let retracked = try overlayTrackedSends(on: changes.trackedSends.map(\.id) + changes.messages.map(\.id), in: db)

            let touched = Set(changes.conversations.map(\.id) + changes.messages.map(\.conversationID) + retracked)
                .subtracting(changes.removedConversationIDs)
            for id in touched {
                try refreshDerivedColumns(of: id, in: db)
            }
            for pending in try PendingMutation.order(by: \.id).fetchAll(db) {
                try apply(pending.mutation, in: db)
            }
            if let cursor = changes.cursor {
                try SyncCursor.upsert { SyncCursor(source: source, cursor: cursor) }.execute(db)
            }
        }
    }

    public func cursor(for source: String) throws -> String? {
        try database.read { db in try SyncCursor.find(source).fetchOne(db)?.cursor }
    }

    /// Empties the cache, for signing out: everything in it belongs to whoever was signed in.
    public func eraseAll() throws {
        try database.write { db in
            // Deleting accounts and domains cascades to their conversations and messages.
            for table in [
                "accounts", "domains", "pendingMutations", "outboxItems", "syncCursors", "contacts", "messageTexts", "labels",
                "conversationLabels", "trackedSends", "messageEvents",
            ] {
                try db.execute(sql: #"DELETE FROM "\#(table)""#)
            }
        }
    }

    // MARK: - Your changes

    /// Applies mutations locally and queues them for their providers, all or none.
    public func perform(_ mutations: [Mutation]) throws {
        try database.write { db in
            for mutation in mutations {
                try apply(mutation, in: db)
                try PendingMutation.insert {
                    PendingMutation.Draft(mutation: mutation, attempts: 0, createdAt: Date())
                }
                .execute(db)
            }
        }
    }

    /// Every queued mutation, oldest first.
    public func pendingMutations() throws -> [PendingMutation] {
        try database.read { db in try PendingMutation.order(by: \.id).fetchAll(db) }
    }

    public func completeMutation(_ id: PendingMutation.ID) throws {
        try database.write { db in try PendingMutation.find(id).delete().execute(db) }
    }

    /// Gives up on a mutation the provider refused, and puts the conversation back the way the provider has it.
    public func abandonMutation(_ pending: PendingMutation) throws {
        try database.write { db in
            try PendingMutation.find(pending.id).delete().execute(db)
            try apply(pending.mutation.inverse, in: db)
        }
    }

    public func recordFailedAttempt(_ id: PendingMutation.ID) throws {
        try database.write { db in
            try PendingMutation.find(id).update { $0.attempts += 1 }.execute(db)
        }
    }

    private func apply(_ mutation: Mutation, in db: Database) throws {
        let conversation = Conversation.find(mutation.conversationID)
        switch mutation {
        case let .setRead(_, isRead):
            try conversation.update { $0.isRead = #bind(isRead) }.execute(db)
        case let .setStarred(_, isStarred):
            try conversation.update { $0.isStarred = #bind(isStarred) }.execute(db)
        case let .move(_, _, to):
            try conversation.update { $0.folder = #bind(to) }.execute(db)
        case let .label(id, labelID, isOn):
            try ConversationLabel.where { $0.conversationID.eq(id) && $0.labelID.eq(labelID) }.delete().execute(db)
            if isOn, try MailLabel.find(labelID).fetchCount(db) > 0 {
                try ConversationLabel.insert { ConversationLabel(conversationID: id, labelID: labelID) }.execute(db)
            }
        }
    }

    /// Marks messages sent from Gmail with tracking as tracked, with their links. Their providers' copies
    /// don't carry that, so it's laid over them each time either side arrives. Returns the conversations it changed.
    private func overlayTrackedSends(on ids: [Message.ID], in db: Database) throws -> [Conversation.ID] {
        guard !ids.isEmpty else { return [] }
        var conversations: [Conversation.ID] = []
        for tracked in try TrackedSend.where({ $0.id.in(ids) }).fetchAll(db) {
            guard let message = try Message.find(tracked.id).fetchOne(db) else { continue }
            try Message.find(tracked.id).update {
                $0.trackingEnabled = true
                $0.links = #bind(tracked.links)
            }
            .execute(db)
            conversations.append(message.conversationID)
        }
        return conversations
    }

    // MARK: - Outbox

    /// Shows the message in its conversation right away and holds it until `sendAt`, which is the undo window.
    public func enqueue(_ message: OutgoingMessage, sendAt: Date) throws {
        try database.write { db in
            let now = Date()
            if var conversation = try Conversation.find(message.conversationID).fetchOne(db) {
                conversation.lastMessageAt = now
                conversation.lastOutboundAt = now
                conversation.isRead = true
                try Conversation.upsert { conversation }.execute(db)
            } else {
                try Conversation.insert {
                    Conversation(
                        id: message.conversationID, accountID: message.accountID, subject: message.subject,
                        folder: .done, isRead: true, isStarred: false, snoozedUntil: nil, lastMessageAt: now,
                        lastOutboundAt: now
                    )
                }
                .execute(db)
            }
            let local = Message(
                id: message.id, conversationID: message.conversationID, accountID: message.accountID,
                direction: .outbound, deliveryStatus: .sending, messageIDHeader: nil, from: message.from,
                to: message.to, cc: message.cc, bcc: message.bcc, replyTo: [], subject: message.subject,
                html: message.html, text: message.text, snippet: snippet(of: message.text), sentAt: now,
                trackingEnabled: message.trackingEnabled,
                attachments: message.attachments.map {
                    Attachment(id: $0.id, filename: $0.filename, contentType: $0.contentType, size: $0.size, contentID: nil)
                },
                links: []
            )
            try Message.insert { local }.execute(db)
            try index(local, in: db)
            try remember(local, in: db)
            try refreshDerivedColumns(of: message.conversationID, in: db)
            try OutboxItem.insert { OutboxItem(id: message.id, message: message, sendAt: sendAt, attempts: 0) }.execute(db)
        }
    }

    /// Undo send: the message disappears as if it was never written. Returns it so the composer can reopen.
    public func cancelSend(_ id: Message.ID) throws -> OutgoingMessage? {
        try database.write { db in
            guard let item = try OutboxItem.find(id).fetchOne(db) else { return nil }
            try OutboxItem.find(id).delete().execute(db)
            try Message.find(id).delete().execute(db)
            let conversationID = item.message.conversationID
            if try Message.where({ $0.conversationID.eq(conversationID) }).fetchCount(db) == 0 {
                try Conversation.find(conversationID).delete().execute(db)
            } else {
                try refreshDerivedColumns(of: conversationID, in: db)
            }
            return item.message
        }
    }

    public func dueOutboxItems(at date: Date = Date()) throws -> [OutboxItem] {
        try database.read { db in
            try OutboxItem.where { $0.sendAt <= date }.order(by: \.sendAt).fetchAll(db)
        }
    }

    public func nextOutboxDate() throws -> Date? {
        try database.read { db in try OutboxItem.select { $0.sendAt.min() }.fetchOne(db) ?? nil }
    }

    /// The provider took the message; its own version replaces the optimistic one.
    public func completeSend(_ id: Message.ID, with changes: ChangeSet, source: String) throws {
        try database.write { db in try OutboxItem.find(id).delete().execute(db) }
        try merge(changes, source: source)
    }

    /// Keeps the message in the outbox for another try, or marks it failed when retrying won't help.
    public func failSend(_ id: Message.ID, error: String, permanently: Bool, retryAt: Date) throws {
        try database.write { db in
            if permanently {
                try OutboxItem.find(id).delete().execute(db)
                try Message.find(id).update { $0.deliveryStatus = #bind(DeliveryStatus.failed) }.execute(db)
            } else {
                try OutboxItem.find(id).update {
                    $0.attempts += 1
                    $0.lastError = #bind(error)
                    $0.sendAt = #bind(retryAt)
                }
                .execute(db)
            }
        }
    }

    // MARK: - Search

    /// Conversations whose subject, people or body match, best match first. Every word matches as a prefix, so
    /// results appear while you type.
    public func search(_ query: String, limit: Int = 100) throws -> [Conversation.ID] {
        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"*" }
        guard !terms.isEmpty else { return [] }
        return try database.read { db in
            try UUID.fetchAll(
                db,
                sql: """
                    SELECT "messages"."conversationID" FROM "messageTexts"
                    JOIN "messages" ON "messages"."rowid" = "messageTexts"."rowid"
                    WHERE "messageTexts" MATCH ?
                    GROUP BY "messages"."conversationID"
                    ORDER BY min("messageTexts"."rank")
                    LIMIT ?
                    """,
                arguments: [terms.joined(separator: " "), limit]
            )
        }
    }

    // MARK: - Contacts

    /// People to suggest for `prefix`, the ones you write to most and most recently first.
    public func contacts(matching prefix: String, limit: Int = 8) throws -> [Contact] {
        let pattern = "\(prefix.lowercased())%"
        return try database.read { db in
            try Contact
                .where {
                    #sql("\($0.email) LIKE \(pattern) OR \($0.name) LIKE \(pattern) OR \($0.name) LIKE \("% " + pattern)")
                }
                .order { ($0.timesContacted.desc(), $0.lastContactedAt.desc()) }
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Derived data

    private func refreshDerivedColumns(of conversationID: Conversation.ID, in db: Database) throws {
        let messages = try Message
            .where { $0.conversationID.eq(conversationID) }
            .order(by: \.sentAt)
            .fetchAll(db)
        guard let latest = messages.last else { return }
        try Conversation.find(conversationID).update {
            $0.snippet = #bind(latest.snippet)
            $0.participants = #bind(participants(of: messages))
            $0.messageCount = #bind(messages.count)
            $0.hasAttachments = #bind(messages.contains { !$0.listedAttachments.isEmpty })
            $0.isTracked = #bind(messages.contains(where: \.trackingEnabled))
        }
        .execute(db)
    }

    private func index(_ message: Message, in db: Database) throws {
        // Raw SQL binds a UUID as a blob, but the tables store ids as lowercase text, the way StructuredQueries does.
        guard let rowid = try Int.fetchOne(db, sql: #"SELECT "rowid" FROM "messages" WHERE "id" = ?"#, arguments: [message.id.uuidString.lowercased()])
        else { return }
        let people = ([message.from] + message.to + message.cc).map { "\($0.name ?? "") \($0.email)" }.joined(separator: " ")
        try db.execute(sql: #"DELETE FROM "messageTexts" WHERE "rowid" = ?"#, arguments: [rowid])
        try db.execute(
            sql: #"INSERT INTO "messageTexts" ("rowid", "subject", "people", "body") VALUES (?, ?, ?, ?)"#,
            arguments: [rowid, message.subject, people, message.text ?? message.html.map(plainText) ?? ""]
        )
    }

    /// Ranks autocomplete: people you write to rank above people who only write to you.
    private func remember(_ message: Message, in db: Database) throws {
        let people = message.direction == .outbound ? message.to + message.cc + message.bcc : [message.from]
        let weight = message.direction == .outbound ? 1 : 0
        for person in people {
            try Contact.insert {
                Contact(email: person.email.lowercased(), name: person.name, lastContactedAt: message.sentAt, timesContacted: weight)
            } onConflictDoUpdate: {
                $0.timesContacted += weight
                $0.lastContactedAt = #bind(message.sentAt)
                if let name = person.name, !name.isEmpty { $0.name = #bind(name) }
            }
            .execute(db)
        }
    }
}

/// Who the conversation is with, latest first: `Lena Peeters` for one person, `Tom, Pieter, me` for a thread you
/// replied in, and the recipients for one you started, since "me" alone says nothing.
func participants(of messages: [Message]) -> String {
    var names: [String] = []
    for message in messages.reversed() {
        let people = message.direction == .outbound ? message.to + message.cc : [message.from]
        for name in people.map(\.displayName) where !names.contains(name) {
            names.append(name)
        }
    }
    let replied = messages.contains { $0.direction == .outbound } && messages.contains { $0.direction == .inbound }
    if names.count == 1 && !replied { return names[0] }
    let short = names.map { String($0.prefix { $0 != " " }) }
    return (short + (replied ? ["me"] : [])).joined(separator: ", ")
}

func snippet(of text: String) -> String {
    String(text.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(200))
}

/// Good enough for a search index: tags out, entities for spaces and the common characters decoded.
func plainText(_ html: String) -> String {
    html
        .replacingOccurrences(of: #"<(style|script)[^>]*>[\s\S]*?</\1>"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        .replacingOccurrences(of: "&nbsp;", with: " ")
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
}

extension MailStore {
    /// The original url behind one of our tracked links (`…/c/<link id>.<signature>`), if it's in the cache.
    public func trackedLinkDestination(for url: URL) -> URL? {
        guard url.pathComponents.count == 3, url.pathComponents[1] == "c",
            let id = url.lastPathComponent.split(separator: ".").first.flatMap({ UUID(uuidString: String($0)) })
        else { return nil }
        let pattern = "%\(id.uuidString.lowercased())%"
        return try? database.read { db in
            let candidates = try Message.where { #sql("\($0.links) LIKE \(pattern)") }.select(\.links).fetchAll(db)
            return candidates.lazy.flatMap { $0 }.first { $0.id == id }?.url
        }
    }
}
