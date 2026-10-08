import Foundation

/// A message as the composer hands it over. The id is final: the provider uses it as an idempotency key, so a send
/// that is retried after a crash or a timeout goes out once.
public struct OutgoingMessage: Codable, Hashable, Sendable {
    public var id: Message.ID
    /// An existing conversation for a reply or forward, a fresh id for a new conversation.
    public var conversationID: Conversation.ID
    public var accountID: Account.ID
    public var from: Address
    public var to: [Address]
    public var cc: [Address]
    public var bcc: [Address]
    public var subject: String
    public var html: String
    public var text: String
    public var trackingEnabled: Bool
    public var attachments: [OutgoingAttachment]

    public init(
        id: Message.ID = UUID(), conversationID: Conversation.ID, accountID: Account.ID, from: Address, to: [Address],
        cc: [Address] = [], bcc: [Address] = [], subject: String, html: String, text: String,
        trackingEnabled: Bool = false, attachments: [OutgoingAttachment] = []
    ) {
        self.id = id
        self.conversationID = conversationID
        self.accountID = accountID
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.html = html
        self.text = text
        self.trackingEnabled = trackingEnabled
        self.attachments = attachments
    }

    public var recipients: [Address] { to + cc + bcc }
}

/// A file copied into the outbox folder when it was attached, so it survives the undo window and relaunches.
public struct OutgoingAttachment: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var filename: String
    public var contentType: String
    public var size: Int
    public var fileURL: URL

    public init(id: UUID = UUID(), filename: String, contentType: String, size: Int, fileURL: URL) {
        self.id = id
        self.filename = filename
        self.contentType = contentType
        self.size = size
        self.fileURL = fileURL
    }
}
