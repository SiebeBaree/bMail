import MailCore
import SQLiteData

/// The conversations a tab shows, for one account or all of them. Observed: the list redraws whenever the rows behind
/// it change, whether from sync or from your own keystrokes.
struct ConversationsRequest: FetchKeyRequest {
    var tab: Tab
    var accountID: Account.ID?
    /// When set, the label's conversations instead of the tab, outside spam and trash.
    var labelID: MailLabel.ID?
    /// When set, the search results in rank order instead of the tab.
    var searchIDs: [Conversation.ID]?
    var limit = 500

    func fetch(_ db: Database) throws -> [Conversation] {
        if let searchIDs {
            let found = try scoped(Conversation.where { $0.id.in(searchIDs) }).fetchAll(db)
            let byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return searchIDs.compactMap { byID[$0] }
        }
        if let labelID {
            let ids = try ConversationLabel.where { $0.labelID.eq(labelID) }.select(\.conversationID).fetchAll(db)
            return try scoped(Conversation.where { $0.id.in(ids) && $0.folder.neq(Folder.spam) && $0.folder.neq(Folder.trash) })
                .order { $0.lastMessageAt.desc() }
                .limit(limit)
                .fetchAll(db)
        }
        switch tab {
        case .inbox, .done, .spam, .trash:
            let folder = tab.folder
            return try scoped(Conversation.where { $0.folder.eq(folder) })
                .order { $0.lastMessageAt.desc() }
                .limit(limit)
                .fetchAll(db)
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

    private func scoped(_ query: Where<Conversation>) -> Where<Conversation> {
        guard let accountID else { return query }
        return query.where { $0.accountID.eq(accountID) }
    }
}

extension Tab {
    /// The folder behind a folder tab. Only called for those.
    var folder: Folder {
        switch self {
        case .done: .done
        case .spam: .spam
        case .trash: .trash
        default: .inbox
        }
    }
}
