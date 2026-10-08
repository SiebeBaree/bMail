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

    public init(account: Account, client: OAuthClient, store: MailStore) {
        self.source = "gmail:\(account.id)"
        self.accountID = account.id
        self.api = GmailAPI(tokens: TokenStore(accountID: account.id, client: client))
        self.store = store
        self.mapping = GmailMapping(accountID: account.id)
    }

    public func owns(_ account: Account) -> Bool {
        account.id == accountID
    }

    public func pull(after cursor: String?) async throws -> ChangeSet {
        if let cursor {
            do {
                return try await changes(since: cursor)
            } catch is GmailNotFound {
                // History ids expire after about a week offline; start over from the newest threads.
                return try await initialSync()
            }
        }
        return try await initialSync()
    }

    private func initialSync() async throws -> ChangeSet {
        let profile: Gmail.Profile = try await api.get("profile")
        var threadIDs: [String] = []
        var pageToken: String?
        repeat {
            var query = ["maxResults": "100", "q": "-in:chats"]
            if let pageToken { query["pageToken"] = pageToken }
            let page: Gmail.ThreadList = try await api.get("threads", query: query)
            threadIDs += (page.threads ?? []).map(\.id)
            pageToken = page.nextPageToken
        } while pageToken != nil && threadIDs.count < Self.initialThreads
        var changes = try await fetch(threads: Array(threadIDs.prefix(Self.initialThreads)))
        changes.cursor = profile.historyId
        return changes
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

    /// Fetches full threads, eight at a time. A thread that's gone was deleted and leaves the cache too.
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
        let (threadID, parent) = try await store.database.read { db in
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
        var changes = try await fetch(threads: [sent.threadId])
        // Gmail's copy replaces the optimistic one, which had the ids the composer gave it.
        changes.removedMessageIDs = [message.id]
        changes.removedConversationIDs = threadID == nil ? [message.conversationID] : []
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
