import MailCore
import SQLiteData

/// Everything the reader shows for one conversation, observed as a whole.
struct ThreadRequest: FetchKeyRequest {
    struct Value: Equatable, Sendable {
        var conversation: Conversation?
        var account: Account?
        var messages: [Message] = []
        var events: [MessageEvent] = []
        var labels: [MailLabel] = []
    }

    let id: Conversation.ID

    func fetch(_ db: Database) throws -> Value {
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
            labels: try MailLabel.where { $0.id.in(labelIDs) }.order(by: \.name).fetchAll(db)
        )
    }
}
