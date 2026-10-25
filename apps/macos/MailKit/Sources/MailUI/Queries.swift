import MailCore
import SQLiteData

/// The views of your mail. Each one is a query over conversations, not a folder on its own.
public enum MailTab: String, CaseIterable, Identifiable, Sendable {
    case inbox, starred, sent, done, tracked, spam, trash

    public var id: Self { self }

    public var title: String {
        switch self {
        case .inbox: "Inbox"
        case .starred: "Starred"
        case .sent: "Sent"
        case .done: "Done"
        case .tracked: "Tracked"
        case .spam: "Spam"
        case .trash: "Trash"
        }
    }

    public var symbol: String {
        switch self {
        case .inbox: "tray"
        case .starred: "star"
        case .sent: "paperplane"
        case .done: "checkmark"
        case .tracked: "waveform.path.ecg"
        case .spam: "exclamationmark.octagon"
        case .trash: "trash"
        }
    }

    /// The folder behind a folder tab. Starred, sent and tracked span folders.
    public var folder: Folder? {
        switch self {
        case .inbox: .inbox
        case .done: .done
        case .spam: .spam
        case .trash: .trash
        case .starred, .sent, .tracked: nil
        }
    }

    /// The tabs you live in. Spam and trash are reached on purpose, not shown all the time.
    public static let visible: [MailTab] = [.inbox, .starred, .sent, .done, .tracked]
}

/// The conversations a tab shows, for one account or all of them. Observed: the list redraws whenever the rows behind
/// it change, whether from sync or from your own actions.
public struct ConversationsRequest: FetchKeyRequest {
    public var tab: MailTab
    public var accountID: Account.ID?
    /// When set, the conversations with a label by this name instead of the tab, outside spam and trash.
    public var label: String?
    /// When set, the search results in rank order instead of the tab.
    public var searchIDs: [Conversation.ID]?
    public var limit = 500

    public init(tab: MailTab, accountID: Account.ID? = nil, label: String? = nil, searchIDs: [Conversation.ID]? = nil) {
        self.tab = tab
        self.accountID = accountID
        self.label = label
        self.searchIDs = searchIDs
    }

    public func fetch(_ db: Database) throws -> [Conversation] {
        if let searchIDs {
            let found = try scoped(Conversation.where { $0.id.in(searchIDs) }).fetchAll(db)
            let byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return searchIDs.compactMap { byID[$0] }
        }
        if let label {
            let ids = try ConversationLabel.where { $0.labelID.in(MailLabel.where { $0.name.eq(label) }.select(\.id)) }
                .select(\.conversationID).fetchAll(db)
            return try scoped(Conversation.where { $0.id.in(ids) && $0.folder.neq(Folder.spam) && $0.folder.neq(Folder.trash) })
                .order { $0.lastMessageAt.desc() }
                .limit(limit)
                .fetchAll(db)
        }
        switch tab {
        case .inbox: return try conversations(in: .inbox, db)
        case .done: return try conversations(in: .done, db)
        case .spam: return try conversations(in: .spam, db)
        case .trash: return try conversations(in: .trash, db)
        case .starred:
            return try scoped(Conversation.where { $0.isStarred && $0.folder.neq(Folder.trash) })
                .order { $0.lastMessageAt.desc() }
                .limit(limit)
                .fetchAll(db)
        case .sent:
            return try scoped(Conversation.where { $0.lastOutboundAt.isNot(nil) })
                .order { $0.lastOutboundAt.desc() }
                .limit(limit)
                .fetchAll(db)
        case .tracked:
            return try scoped(Conversation.where { $0.isTracked })
                .order { $0.lastOutboundAt.desc() }
                .limit(limit)
                .fetchAll(db)
        }
    }

    private func conversations(in folder: Folder, _ db: Database) throws -> [Conversation] {
        try scoped(Conversation.where { $0.folder.eq(folder) })
            .order { $0.lastMessageAt.desc() }
            .limit(limit)
            .fetchAll(db)
    }

    private func scoped(_ query: Where<Conversation>) -> Where<Conversation> {
        guard let accountID else { return query }
        return query.where { $0.accountID.eq(accountID) }
    }
}

extension Array where Element == MailLabel {
    /// Each name once, in order. Gmail accounts and your server can each have a label by the same name, and to you
    /// that's one label.
    public var names: [String] {
        var seen = Set<String>()
        return map(\.name).filter { seen.insert($0).inserted }
    }
}

/// Everything the reader shows for one conversation, observed as a whole.
public struct ThreadRequest: FetchKeyRequest {
    public struct Value: Equatable, Sendable {
        public var conversation: Conversation?
        public var account: Account?
        public var messages: [Message] = []
        public var events: [MessageEvent] = []
        /// Label names, once each: Gmail and your server can both have one by the same name.
        public var labels: [String] = []

        public init() {}

        init(conversation: Conversation?, account: Account?, messages: [Message], events: [MessageEvent], labels: [String]) {
            self.conversation = conversation
            self.account = account
            self.messages = messages
            self.events = events
            self.labels = labels
        }
    }

    public let id: Conversation.ID

    public init(id: Conversation.ID) {
        self.id = id
    }

    public func fetch(_ db: Database) throws -> Value {
        guard let conversation = try Conversation.find(id).fetchOne(db) else { return Value() }
        let messages = try Message.where { $0.conversationID.eq(id) }.order(by: \.sentAt).fetchAll(db)
        let messageIDs = messages.filter(\.trackingEnabled).map(\.id) + messages.filter { $0.direction == .outbound }.map(\.id)
        let events = try MessageEvent.where { $0.messageID.in(messageIDs) }.order(by: \.occurredAt).fetchAll(db)
        let labelIDs = try ConversationLabel.where { $0.conversationID.eq(id) }.select(\.labelID).fetchAll(db)
        return Value(
            conversation: conversation,
            account: try Account.find(conversation.accountID).fetchOne(db),
            messages: messages,
            events: events,
            labels: try MailLabel.where { $0.id.in(labelIDs) }.select(\.name).distinct().order(by: \.name).fetchAll(db)
        )
    }
}
