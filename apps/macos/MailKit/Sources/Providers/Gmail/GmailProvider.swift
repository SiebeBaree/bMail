import Foundation
import MailCore
import SQLiteData

/// One Gmail account, straight from the Mac. First sync takes the newest threads; after that Gmail's history api says
/// which threads changed since the stored history id, and only those are fetched again.
public struct GmailProvider: MailProvider {
    /// How many threads the first sync pulls. Older mail is still found through search.
    static let initialThreads = 300

    public let source: String
    private let accountID: Account.ID
    private let api: GmailAPI
    private let store: MailStore
    private let mapping: GmailMapping
    private let tracking: ServerTracking

    public init(account: Account, client: OAuthClient, store: MailStore, tracking: ServerTracking) {
        self.source = "gmail:\(account.id)"
        self.accountID = account.id
        self.api = GmailAPI(tokens: TokenStore(accountID: account.id, client: client))
        self.store = store
        self.mapping = GmailMapping(accountID: account.id)
        self.tracking = tracking
    }

    public func owns(_ account: Account) -> Bool {
        account.id == accountID
    }

    public func pull(after cursor: String?) async throws -> ChangeSet {
        switch cursor.map(SyncPosition.init) {
        case nil:
            // Taken before the first page, so whatever changes while the first sync pages through is caught after.
            let profile: Gmail.Profile = try await api.get("profile")
            return try await initialPage(.init(historyID: profile.historyId))
        case let .initial(page): return try await initialPage(page)
        case let .history(historyID):
            do {
                return try await changes(since: historyID)
            } catch is GmailNotFound {
                // History ids expire after about a week offline; start over from the newest threads.
                return try await pull(after: nil)
            }
        }
    }

    /// One page of the newest threads. The cursor remembers how far the first sync got, so a failure halfway resumes
    /// instead of starting over, and the inbox fills in while the rest loads.
    private func initialPage(_ position: SyncPosition.InitialPage) async throws -> ChangeSet {
        var query = ["maxResults": "50", "q": "-in:chats"]
        if let pageToken = position.pageToken { query["pageToken"] = pageToken }
        let page: Gmail.ThreadList = try await api.get("threads", query: query)
        let ids = (page.threads ?? []).map(\.id)
        var changes = try await fetch(threads: ids)
        let fetched = position.fetched + ids.count
        if let next = page.nextPageToken, fetched < Self.initialThreads {
            changes.cursor = SyncPosition.initial(.init(historyID: position.historyID, pageToken: next, fetched: fetched)).cursor
            changes.hasMore = true
        } else {
            changes.cursor = position.historyID
        }
        return changes
    }

    /// The stored cursor: a plain history id once the first sync is done, `initial:<json>` while it pages through.
    enum SyncPosition {
        struct InitialPage: Codable {
            var historyID: String
            var pageToken: String? = nil
            var fetched = 0
        }

        case initial(InitialPage)
        case history(String)

        private static let prefix = "initial:"

        init(_ cursor: String) {
            if cursor.hasPrefix(Self.prefix),
               let page = try? JSONDecoder().decode(InitialPage.self, from: Data(cursor.dropFirst(Self.prefix.count).utf8)) {
                self = .initial(page)
            } else {
                self = .history(cursor)
            }
        }

        var cursor: String {
            switch self {
            case let .initial(page): Self.prefix + String(decoding: (try? JSONEncoder().encode(page)) ?? Data(), as: UTF8.self)
            case let .history(historyID): historyID
            }
        }
    }

    private func changes(since historyID: String) async throws -> ChangeSet {
        var touched = Set<String>()
        var latest = historyID
        var pageToken: String?
        repeat {
            var query = ["startHistoryId": historyID]
            if let pageToken { query["pageToken"] = pageToken }
            let page: Gmail.HistoryList = try await api.get("history", query: query)
            for entry in page.history ?? [] {
                for change in (entry.messagesAdded ?? []) + (entry.messagesDeleted ?? []) + (entry.labelsAdded ?? []) + (entry.labelsRemoved ?? []) {
                    touched.insert(change.message.threadId)
                }
            }
            latest = page.historyId
            pageToken = page.nextPageToken
        } while pageToken != nil
        var changes = try await fetch(threads: Array(touched))
        changes.cursor = latest
        return changes
    }

    /// Fetches full threads, eight at a time. A thread that's gone was deleted and leaves the cache too, and so does a
    /// cached message its thread no longer has (deleted in Gmail).
    private func fetch(threads ids: [String]) async throws -> ChangeSet {
        var changes = ChangeSet()
        try await withThrowingTaskGroup(of: (String, Gmail.Thread?).self) { group in
            var pending = ids[...]
            func next() {
                guard let id = pending.popFirst() else { return }
                group.addTask {
                    do {
                        return (id, try await api.get("threads/\(id)", query: ["format": "full"]))
                    } catch is GmailNotFound {
                        return (id, nil)
                    }
                }
            }
            for _ in 0..<8 { next() }
            for try await (id, thread) in group {
                if let thread, let (conversation, messages) = mapping.conversation(thread) {
                    changes.conversations.append(conversation)
                    changes.messages += messages
                } else {
                    changes.removedConversationIDs.append(mapping.conversationID(thread: id))
                }
                next()
            }
        }
        let fetched = Set(changes.messages.map(\.id))
        let conversationIDs = changes.conversations.map(\.id)
        // Only rows Gmail knows about: an optimistic reply that hasn't gone out yet has no remote id.
        let cached = try await store.database.read { db in
            try Message.where { conversationIDs.contains($0.conversationID) && $0.remoteID.isNot(nil) }.select(\.id).fetchAll(db)
        }
        changes.removedMessageIDs = cached.filter { !fetched.contains($0) }
        return changes
    }

    public func push(_ mutation: Mutation) async throws {
        guard let threadID = try remoteID(of: mutation.conversationID) else { return }
        switch mutation {
        case let .setRead(_, isRead): try await modify(threadID, add: isRead ? [] : ["UNREAD"], remove: isRead ? ["UNREAD"] : [])
        case let .setStarred(_, isStarred): try await modify(threadID, add: isStarred ? ["STARRED"] : [], remove: isStarred ? [] : ["STARRED"])
        case let .move(_, from, to):
            if from == .trash { let _: Gmail.Thread = try await api.post("threads/\(threadID)/untrash", body: GmailAPI.Empty()) }
            switch to {
            case .inbox: try await modify(threadID, add: ["INBOX"], remove: ["SPAM"])
            case .done: try await modify(threadID, add: [], remove: ["INBOX", "SPAM"])
            case .spam: try await modify(threadID, add: ["SPAM"], remove: ["INBOX"])
            case .trash: let _: Gmail.Thread = try await api.post("threads/\(threadID)/trash", body: GmailAPI.Empty())
            }
        case .label: return
        }
    }

    private func modify(_ threadID: String, add: [String], remove: [String]) async throws {
        struct Body: Encodable {
            var addLabelIds: [String]
            var removeLabelIds: [String]
        }
        let _: Gmail.Thread = try await api.post("threads/\(threadID)/modify", body: Body(addLabelIds: add, removeLabelIds: remove))
    }

    public func send(_ message: OutgoingMessage) async throws -> ChangeSet {
        var message = message
        // Gmail's copy keeps this id (see X-Bmail-ID), so it's the one the opens are recorded under.
        if message.trackingEnabled { message.html = try await tracking.instrument(message.html, id: message.id) }
        let (threadID, parent) = try await store.database.read { [message] db in
            let conversation = try Conversation.find(message.conversationID).fetchOne(db)
            let parent = try Message.where { $0.conversationID.eq(message.conversationID) && $0.id.neq(message.id) }
                .order { $0.sentAt.desc() }
                .fetchOne(db)
            return (conversation?.remoteID, parent)
        }
        let mime = MIMEMessage(
            message: message,
            inReplyTo: parent?.messageIDHeader,
            references: parent?.messageIDHeader.map { [$0] } ?? [],
            messageID: "<\(message.id.uuidString.lowercased())@baree.mail>"
        )
        struct Body: Encodable {
            var raw: String
            var threadId: String?
        }
        let sent: Gmail.Sent = try await api.post("messages/send", body: Body(raw: try mime.render().base64URLEncoded, threadId: threadID))
        // The mail is out, so a failed read-back mustn't fail the send: the next pull brings Gmail's copy.
        var changes = (try? await fetch(threads: [sent.threadId])) ?? ChangeSet()
        // Gmail's copy has the message's id but not the conversation's: a new thread replaces the optimistic one.
        if !changes.messages.contains(where: { $0.id == message.id }) { changes.removedMessageIDs.append(message.id) }
        changes.removedConversationIDs = threadID == nil ? [message.conversationID] : []
        // Shows as tracked right away; its links follow with the api's next sync.
        if message.trackingEnabled { changes.trackedSends = [TrackedSend(id: message.id, links: [])] }
        return changes
    }

    /// The bytes of an attachment, fetched on demand: Gmail's attachment ids don't survive between syncs.
    public func download(_ attachment: Attachment) async throws -> Data {
        guard let remote = attachment.remoteID?.split(separator: "/"), remote.count == 2 else {
            throw ProviderError(.rejected, "That attachment can't be downloaded.")
        }
        let body: Gmail.AttachmentBody = try await api.get("messages/\(remote[0])/attachments/\(remote[1])")
        guard let data = Data(base64URLEncoded: body.data) else { throw ProviderError(.unavailable, "Gmail sent a broken attachment.") }
        return data
    }

    private func remoteID(of conversationID: Conversation.ID) throws -> String? {
        try store.database.read { db in try Conversation.find(conversationID).fetchOne(db)?.remoteID }
    }
}
