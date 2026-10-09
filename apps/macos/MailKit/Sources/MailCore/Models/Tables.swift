import Foundation
import SQLiteData

/// One address you read and send from: a mailbox on your own domain, a Gmail account or an Outlook account.
@Table
public struct Account: Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable, QueryBindable {
        /// A mailbox on one of your own domains, served by the api.
        case domain
        case gmail
        case outlook
    }

    public let id: UUID
    public var kind: Kind
    public var address: String
    public var displayName: String
    public var domainID: Domain.ID?
    public var position: Int

    public init(id: UUID, kind: Kind, address: String, displayName: String, domainID: Domain.ID?, position: Int) {
        self.id = id
        self.kind = kind
        self.address = address
        self.displayName = displayName
        self.domainID = domainID
        self.position = position
    }

    /// The short label the unified inbox shows next to each conversation.
    public var tag: String {
        switch kind {
        case .domain: String(address.prefix { $0 != "@" })
        case .gmail: "gmail"
        case .outlook: "outlook"
        }
    }
}

@Table
public struct Domain: Hashable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable, QueryBindable { case pending, verified, failed }

    public let id: UUID
    public var name: String
    public var status: Status
    @Column(as: [DNSRecord].JSONRepresentation.self)
    public var records: [DNSRecord]
    public var receivingEnabled: Bool
    public var catchAllMailboxID: Account.ID?
    public var trackingHost: String
    public var trackingHostVerified: Bool

    public init(
        id: UUID, name: String, status: Status, records: [DNSRecord], receivingEnabled: Bool,
        catchAllMailboxID: Account.ID?, trackingHost: String, trackingHostVerified: Bool
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.records = records
        self.receivingEnabled = receivingEnabled
        self.catchAllMailboxID = catchAllMailboxID
        self.trackingHost = trackingHost
        self.trackingHostVerified = trackingHostVerified
    }
}

@Table
public struct Conversation: Hashable, Identifiable, Sendable {
    public let id: UUID
    public var accountID: Account.ID
    public var subject: String
    public var folder: Folder
    public var isRead: Bool
    public var isStarred: Bool
    public var snoozedUntil: Date?
    public var lastMessageAt: Date
    public var lastOutboundAt: Date?
    /// The provider's own id (a Gmail thread id, an Outlook conversation id). Nil for your own domains, whose ids are ours.
    public var remoteID: String?

    // Derived from the messages whenever they change, so a list row never has to look at a message.
    public var snippet: String = ""
    public var participants: String = ""
    public var messageCount: Int = 0
    public var hasAttachments: Bool = false
    public var isTracked: Bool = false

    public init(
        id: UUID, accountID: Account.ID, subject: String, folder: Folder, isRead: Bool, isStarred: Bool,
        snoozedUntil: Date?, lastMessageAt: Date, lastOutboundAt: Date?, remoteID: String? = nil
    ) {
        self.id = id
        self.accountID = accountID
        self.subject = subject
        self.folder = folder
        self.isRead = isRead
        self.isStarred = isStarred
        self.snoozedUntil = snoozedUntil
        self.lastMessageAt = lastMessageAt
        self.lastOutboundAt = lastOutboundAt
        self.remoteID = remoteID
    }
}

@Table
public struct Message: Hashable, Identifiable, Sendable {
    public let id: UUID
    public var conversationID: Conversation.ID
    public var accountID: Account.ID
    public var direction: Direction
    public var deliveryStatus: DeliveryStatus?
    public var messageIDHeader: String?
    @Column(as: Address.JSONRepresentation.self)
    public var from: Address
    @Column(as: [Address].JSONRepresentation.self)
    public var to: [Address]
    @Column(as: [Address].JSONRepresentation.self)
    public var cc: [Address]
    @Column(as: [Address].JSONRepresentation.self)
    public var bcc: [Address]
    @Column(as: [Address].JSONRepresentation.self)
    public var replyTo: [Address]
    public var subject: String
    public var html: String?
    public var text: String?
    public var snippet: String
    public var sentAt: Date
    public var trackingEnabled: Bool
    @Column(as: [Attachment].JSONRepresentation.self)
    public var attachments: [Attachment]
    @Column(as: [TrackedLink].JSONRepresentation.self)
    public var links: [TrackedLink]
    /// The provider's own id for this message, when it has one.
    public var remoteID: String?

    public init(
        id: UUID, conversationID: Conversation.ID, accountID: Account.ID, direction: Direction,
        deliveryStatus: DeliveryStatus?, messageIDHeader: String?, from: Address, to: [Address], cc: [Address],
        bcc: [Address], replyTo: [Address], subject: String, html: String?, text: String?, snippet: String,
        sentAt: Date, trackingEnabled: Bool, attachments: [Attachment], links: [TrackedLink], remoteID: String? = nil
    ) {
        self.id = id
        self.conversationID = conversationID
        self.accountID = accountID
        self.direction = direction
        self.deliveryStatus = deliveryStatus
        self.messageIDHeader = messageIDHeader
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.replyTo = replyTo
        self.subject = subject
        self.html = html
        self.text = text
        self.snippet = snippet
        self.sentAt = sentAt
        self.trackingEnabled = trackingEnabled
        self.attachments = attachments
        self.links = links
        self.remoteID = remoteID
    }

    /// Attachments to list under the body. Inline images are part of the body already.
    public var listedAttachments: [Attachment] {
        attachments.filter { $0.contentID == nil || $0.contentType.hasPrefix("image/") == false }
    }
}

/// A delivery update, open or click on a message you sent.
@Table
public struct MessageEvent: Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable, QueryBindable {
        case sent, delivered, delayed, bounced, complained, failed, opened, clicked
    }

    public enum Source: String, Codable, Sendable, QueryBindable {
        case person
        case appleProxy = "apple_proxy"
        case googleProxy = "google_proxy"
        case scanner
    }

    public let id: UUID
    public var messageID: Message.ID
    public var kind: Kind
    public var source: Source?
    public var url: String?
    public var device: String?
    public var city: String?
    public var country: String?
    public var detail: String?
    public var occurredAt: Date

    public init(
        id: UUID, messageID: Message.ID, kind: Kind, source: Source?, url: String?, device: String?,
        city: String?, country: String?, detail: String?, occurredAt: Date
    ) {
        self.id = id
        self.messageID = messageID
        self.kind = kind
        self.source = source
        self.url = url
        self.device = device
        self.city = city
        self.country = country
        self.detail = detail
        self.occurredAt = occurredAt
    }

    /// Whether a person did this. Gmail's proxy only loads images when someone opens the mail, so it counts; Apple's
    /// proxy and security scanners fetch on delivery and are shown but never counted.
    public var isReader: Bool { source == nil || source == .person || source == .googleProxy }
}

/// A mutation waiting for its provider, in the order they were made.
@Table
public struct PendingMutation: Hashable, Identifiable, Sendable {
    public let id: Int
    @Column(as: Mutation.JSONRepresentation.self)
    public var mutation: Mutation
    public var attempts: Int
    public var createdAt: Date
}

/// A message waiting out its undo window, or waiting for the network.
@Table
public struct OutboxItem: Hashable, Identifiable, Sendable {
    public let id: Message.ID
    @Column(as: OutgoingMessage.JSONRepresentation.self)
    public var message: OutgoingMessage
    public var sendAt: Date
    public var attempts: Int
    public var lastError: String?
}

/// How far each source has synced. The value is opaque: a seq for the api, a history id for Gmail.
@Table
public struct SyncCursor: Hashable, Identifiable, Sendable {
    @Column(primaryKey: true)
    public var source: String
    public var cursor: String
    public var id: String { source }
}

/// Everyone you've exchanged mail with, ranked for autocomplete.
@Table
public struct Contact: Hashable, Identifiable, Sendable {
    @Column(primaryKey: true)
    public var email: String
    public var name: String?
    public var lastContactedAt: Date
    public var timesContacted: Int
    public var id: String { email }
}
