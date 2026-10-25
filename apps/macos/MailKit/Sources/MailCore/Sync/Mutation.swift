import Foundation

/// Every change you make to a conversation. It's applied to the local database in the same frame, queued, and replayed
/// against the provider. Undo enqueues the inverse, which is why a move remembers where it came from.
public enum Mutation: Codable, Hashable, Sendable {
    case setRead(Conversation.ID, Bool)
    case setStarred(Conversation.ID, Bool)
    case move(Conversation.ID, from: Folder, to: Folder)
    /// Adds or removes one label. It goes to whoever owns the label: the Gmail account, or your server.
    case label(Conversation.ID, MailLabel.ID, Bool)

    public var conversationID: Conversation.ID {
        switch self {
        case let .setRead(id, _), let .setStarred(id, _), let .move(id, _, _), let .label(id, _, _): id
        }
    }

    public var inverse: Mutation {
        switch self {
        case let .setRead(id, isRead): .setRead(id, !isRead)
        case let .setStarred(id, isStarred): .setStarred(id, !isStarred)
        case let .move(id, from, to): .move(id, from: to, to: from)
        case let .label(id, label, isOn): .label(id, label, !isOn)
        }
    }
}
