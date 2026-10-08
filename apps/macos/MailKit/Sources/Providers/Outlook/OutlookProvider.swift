import Foundation
import MailCore
import SQLiteData

/// One Outlook or Microsoft 365 account through Microsoft Graph. Outlook keeps state per message in folders; the app
/// keeps it per conversation, so every changed conversation is fetched whole and folded into one row.
public struct OutlookProvider: MailProvider {
    static let initialMessages = 300

    public let source: String
    private let accountID: Account.ID
    private let address: String
    private let api: GraphAPI
    private let store: MailStore
    private let folderIDs = FolderCache()

    public init(account: Account, client: OAuthClient, store: MailStore) {
        self.source = "outlook:\(account.id)"
        self.accountID = account.id
        self.address = account.address.lowercased()
        self.api = GraphAPI(tokens: TokenStore(accountID: account.id, client: client))
        self.store = store
    }

    public func owns(_ account: Account) -> Bool {
        account.id == accountID
    }

    // MARK: - Sync

    /// The cursor is the newest `lastModifiedDateTime` seen: moves, reads and flags all bump it, so one query finds every
    /// conversation that changed.
    public func pull(after cursor: String?) async throws -> ChangeSet {
        let folders = try await wellKnownFolders()
        var query = ["$select": Graph.messageFields, "$top": "100"]
        if let cursor {
            query["$filter"] = "lastModifiedDateTime gt \(cursor)"
            query["$orderby"] = "lastModifiedDateTime asc"
        } else {
            query["$orderby"] = "receivedDateTime desc"
        }
        var page: Graph.Page<Graph.Message> = try await api.get("messages", query: query)
        var changed = page.value
        while let next = page.nextLink, cursor != nil || changed.count < Self.initialMessages {
            page = try await api.get(absolute: next)
            changed += page.value
        }
        changed.removeAll { $0.isDraft == true }

        var changes = ChangeSet()
        let conversationIDs = Set(changed.compactMap(\.conversationId))
        for conversationID in conversationIDs {
            // On first sync the page already holds whole recent conversations; later, refetch each one in full.
            let messages = cursor == nil ? changed.filter { $0.conversationId == conversationID } : try await conversation(conversationID)
            guard let (conversation, mapped) = fold(conversationID, messages, folders: folders) else {
                changes.removedConversationIDs.append(stableID(conversation: conversationID))
                continue
            }
            changes.conversations.append(conversation)
            changes.messages += mapped
        }
        let newest = changed.compactMap(\.lastModifiedDateTime).max()
        changes.cursor = newest.map { $0.formatted(.iso8601) } ?? cursor ?? Date().formatted(.iso8601)
        return changes
    }

    private func conversation(_ id: String) async throws -> [Graph.Message] {
        let escaped = id.replacingOccurrences(of: "'", with: "''")
        let page: Graph.Page<Graph.Message> = try await api.get(
            "messages",
            query: ["$filter": "conversationId eq '\(escaped)'", "$select": Graph.messageFields, "$top": "100"]
        )
        return page.value.filter { $0.isDraft != true }
    }

    fileprivate struct Folders: Sendable {
        var inbox: String
        var junk: String
        var deleted: String
        var sent: String
    }

    /// The ids behind Outlook's well-known folders. They never change, so they're fetched once per launch.
    private func wellKnownFolders() async throws -> Folders {
        try await folderIDs.value {
            async let inbox: Graph.Folder = api.get("mailFolders/inbox")
            async let junk: Graph.Folder = api.get("mailFolders/junkemail")
            async let deleted: Graph.Folder = api.get("mailFolders/deleteditems")
            async let sent: Graph.Folder = api.get("mailFolders/sentitems")
            return try await Folders(inbox: inbox.id, junk: junk.id, deleted: deleted.id, sent: sent.id)
        }
    }

    private func fold(_ conversationID: String, _ wire: [Graph.Message], folders: Folders) -> (Conversation, [Message])? {
        guard !wire.isEmpty else { return nil }
        let id = stableID(conversation: conversationID)
        let messages = wire.map { message($0, conversation: id, folders: folders) }.sorted { $0.sentAt < $1.sentAt }
        let places = Set(wire.compactMap(\.parentFolderId))
        let folder: Folder =
            places.contains(folders.inbox) ? .inbox
            : places == [folders.deleted] ? .trash
            : places.contains(folders.junk) ? .spam
            : .done
        let conversation = Conversation(
            id: id,
            accountID: accountID,
            subject: messages.first?.subject ?? "",
            folder: folder,
            isRead: wire.allSatisfy { $0.isRead ?? true },
            isStarred: wire.contains { $0.flag?.flagStatus == "flagged" },
            snoozedUntil: nil,
            lastMessageAt: messages.last?.sentAt ?? .now,
            lastOutboundAt: messages.filter { $0.direction == .outbound }.map(\.sentAt).max(),
            remoteID: conversationID
        )
        return (conversation, messages)
    }

    private func message(_ wire: Graph.Message, conversation: Conversation.ID, folders: Folders) -> Message {
        let from = Address(wire.from) ?? Address(email: "unknown")
        let outbound = wire.parentFolderId == folders.sent || from.email == address
        return Message(
            id: UUID(stableFrom: "outlook:\(accountID):message:\(wire.id)"),
            conversationID: conversation,
            accountID: accountID,
            direction: outbound ? .outbound : .inbound,
            deliveryStatus: nil,
            messageIDHeader: wire.internetMessageId,
            from: from,
            to: (wire.toRecipients ?? []).compactMap(Address.init),
            cc: (wire.ccRecipients ?? []).compactMap(Address.init),
            bcc: (wire.bccRecipients ?? []).compactMap(Address.init),
            replyTo: (wire.replyTo ?? []).compactMap(Address.init),
            subject: wire.subject ?? "",
            html: wire.body?.contentType.lowercased() == "html" ? wire.body?.content : nil,
            text: wire.body?.contentType.lowercased() == "text" ? wire.body?.content : nil,
            snippet: wire.bodyPreview ?? "",
            sentAt: (outbound ? wire.sentDateTime : wire.receivedDateTime) ?? wire.receivedDateTime ?? .now,
            trackingEnabled: false,
            attachments: [],
            links: [],
            remoteID: wire.id
        )
    }

    private func stableID(conversation: String) -> Conversation.ID {
        UUID(stableFrom: "outlook:\(accountID):\(conversation)")
    }

    // MARK: - Changes

    public func push(_ mutation: Mutation) async throws {
        let messages = try await store.database.read { db in
            try Message.where { $0.conversationID.eq(mutation.conversationID) }.order(by: \.sentAt).fetchAll(db)
        }
        let remote = messages.compactMap(\.remoteID)
        switch mutation {
        case let .setRead(_, isRead):
            for id in remote { try await api.patch("messages/\(id)", body: ["isRead": isRead]) }
        case let .setStarred(_, isStarred):
            guard let latest = remote.last else { return }
            try await api.patch("messages/\(latest)", body: ["flag": ["flagStatus": isStarred ? "flagged" : "notFlagged"]])
        case let .move(_, _, to):
            let destination = switch to {
            case .inbox: "inbox"
            case .done: "archive"
            case .spam: "junkemail"
            case .trash: "deleteditems"
            }
            // Your own sent copies stay in Sent; everything else moves.
            for message in messages where message.direction == .inbound {
                guard let id = message.remoteID else { continue }
                let _: Graph.Folder = try await api.post("messages/\(id)/move", body: ["destinationId": destination])
            }
        }
    }

    /// Creates a draft (a reply draft when answering, so Outlook threads it), fills it, sends it and reads back the sent
    /// copy, which keeps its id thanks to immutable ids.
    public func send(_ message: OutgoingMessage) async throws -> ChangeSet {
        let parent = try await store.database.read { db in
            try Message.where { $0.conversationID.eq(message.conversationID) && $0.id.neq(message.id) && $0.remoteID.isNot(nil) }
                .order { $0.sentAt.desc() }
                .fetchOne(db)
        }
        struct Draft: Encodable {
            var subject: String
            var body: Graph.Body
            var toRecipients: [Graph.Recipient]
            var ccRecipients: [Graph.Recipient]
            var bccRecipients: [Graph.Recipient]
        }
        let draft = Draft(
            subject: message.subject,
            body: Graph.Body(contentType: "HTML", content: message.html),
            toRecipients: message.to.map(Graph.Recipient.init),
            ccRecipients: message.cc.map(Graph.Recipient.init),
            bccRecipients: message.bcc.map(Graph.Recipient.init)
        )
        let created: Graph.Message
        if let parentID = parent?.remoteID {
            created = try await api.post("messages/\(parentID)/createReply", body: [String: String]())
            try await api.patch("messages/\(created.id)", body: draft)
        } else {
            created = try await api.post("messages", body: draft)
        }
        for file in message.attachments {
            struct FileAttachment: Encodable {
                var odataType = "#microsoft.graph.fileAttachment"
                var name: String
                var contentType: String
                var contentBytes: String
                enum CodingKeys: String, CodingKey {
                    case odataType = "@odata.type"
                    case name, contentType, contentBytes
                }
            }
            guard file.size <= 3 * 1024 * 1024 else {
                throw ProviderError(.rejected, "\(file.filename) is over 3 MB, the most Outlook takes this way.")
            }
            let attachment = FileAttachment(name: file.filename, contentType: file.contentType, contentBytes: try Data(contentsOf: file.fileURL).base64EncodedString())
            let _: Graph.Attachment = try await api.post("messages/\(created.id)/attachments", body: attachment)
        }
        try await api.post("messages/\(created.id)/send")

        var changes = try await pull(conversationOf: created.id)
        changes.removedMessageIDs = [message.id]
        if parent == nil { changes.removedConversationIDs = [message.conversationID] }
        return changes
    }

    private func pull(conversationOf messageID: String) async throws -> ChangeSet {
        let sent: Graph.Message = try await api.get("messages/\(messageID)", query: ["$select": Graph.messageFields])
        var changes = ChangeSet()
        guard let conversationID = sent.conversationId,
            let (conversation, messages) = fold(conversationID, try await conversation(conversationID), folders: try await wellKnownFolders())
        else { return changes }
        changes.conversations = [conversation]
        changes.messages = messages
        return changes
    }
}

extension Address {
    init?(_ recipient: Graph.Recipient?) {
        guard let recipient else { return nil }
        self.init(name: recipient.emailAddress.name, email: recipient.emailAddress.address.lowercased())
    }
}

extension Graph.Recipient {
    init(_ address: Address) {
        self.init(emailAddress: Email(name: address.name, address: address.email))
    }
}

private actor FolderCache {
    private var folders: OutlookProvider.Folders?

    func value(_ load: @Sendable () async throws -> OutlookProvider.Folders) async throws -> OutlookProvider.Folders {
        if let folders { return folders }
        let loaded = try await load()
        folders = loaded
        return loaded
    }
}
