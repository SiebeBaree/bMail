import APIClient
import Foundation
import MailCore

// Wire to model. The wire format is generated from the api's contracts, so a renamed field breaks this file at
// compile time, which is the point.

typealias Wire = Components.Schemas

extension UUID {
    /// The api only ever sends valid uuids (its schemas say so), so a failure here means a broken contract.
    init(wire: String) {
        guard let id = UUID(uuidString: wire) else { preconditionFailure("api sent an invalid uuid: \(wire)") }
        self = id
    }
}

extension Address {
    init(_ wire: Wire.Address) {
        self.init(name: wire.name, email: wire.email)
    }
}

extension Domain {
    init(_ wire: Wire.Domain) {
        self.init(
            id: UUID(wire: wire.id),
            name: wire.name,
            status: Status(rawValue: wire.status.rawValue) ?? .pending,
            records: wire.records.map {
                DNSRecord(
                    purpose: DNSRecord.Purpose(rawValue: $0.purpose.rawValue) ?? .dkim,
                    type: $0._type.rawValue,
                    name: $0.name,
                    value: $0.value,
                    priority: $0.priority,
                    status: DNSRecord.Status(rawValue: $0.status.rawValue) ?? .pending
                )
            },
            receivingEnabled: wire.receivingEnabled,
            catchAllMailboxID: wire.catchAllMailboxId.map(UUID.init(wire:)),
            trackingHost: wire.trackingHost,
            trackingHostVerified: wire.trackingHostVerified
        )
    }
}

extension Account {
    /// A mailbox on your own domain is an account like any other.
    init(_ wire: Wire.Mailbox, position: Int) {
        self.init(
            id: UUID(wire: wire.id),
            kind: .domain,
            address: wire.address,
            displayName: wire.displayName,
            domainID: UUID(wire: wire.domainId),
            position: position
        )
    }
}

extension Conversation {
    init(_ wire: Wire.Conversation) {
        self.init(
            id: UUID(wire: wire.id),
            accountID: UUID(wire: wire.mailboxId),
            subject: wire.subject,
            folder: Folder(rawValue: wire.folder.rawValue) ?? .inbox,
            isRead: wire.isRead,
            isStarred: wire.isStarred,
            snoozedUntil: wire.snoozedUntil,
            lastMessageAt: wire.lastMessageAt,
            lastOutboundAt: wire.lastOutboundAt
        )
    }
}

extension Message {
    init(_ wire: Wire.Message) {
        self.init(
            id: UUID(wire: wire.id),
            conversationID: UUID(wire: wire.conversationId),
            accountID: UUID(wire: wire.mailboxId),
            direction: Direction(rawValue: wire.direction.rawValue) ?? .inbound,
            deliveryStatus: wire.deliveryStatus.flatMap { DeliveryStatus(rawValue: $0.rawValue) },
            messageIDHeader: wire.messageIdHeader,
            from: Address(wire.from),
            to: wire.to.map(Address.init),
            cc: wire.cc.map(Address.init),
            bcc: wire.bcc.map(Address.init),
            replyTo: wire.replyTo.map(Address.init),
            subject: wire.subject,
            html: wire.html,
            text: wire.text,
            snippet: wire.snippet,
            sentAt: wire.sentAt,
            trackingEnabled: wire.trackingEnabled,
            attachments: wire.attachments.map {
                Attachment(id: UUID(wire: $0.id), filename: $0.filename, contentType: $0.contentType, size: $0.size, contentID: $0.contentId)
            },
            links: wire.links.compactMap(TrackedLink.init),
            unsubscribe: Unsubscribe(header: wire.listUnsubscribe, oneClick: wire.listUnsubscribeOneClick)
        )
    }
}

extension TrackedLink {
    init?(_ wire: Wire.TrackedLink) {
        guard let url = URL(string: wire.url) else { return nil }
        self.init(id: UUID(wire: wire.id), url: url)
    }
}

extension MailLabel {
    init(_ wire: Wire.Label) {
        self.init(id: UUID(wire: wire.id), name: wire.name)
    }
}

extension TrackedSend {
    init(_ wire: Wire.TrackedMessage) {
        self.init(id: UUID(wire: wire.id), links: wire.links.compactMap(TrackedLink.init))
    }
}

extension MessageEvent {
    init(_ wire: Wire.MessageEvent) {
        self.init(
            id: UUID(wire: wire.id),
            messageID: UUID(wire: wire.messageId),
            kind: Kind(rawValue: wire._type.rawValue) ?? .sent,
            source: wire.source.flatMap { Source(rawValue: $0.rawValue) },
            url: wire.url,
            device: wire.device,
            city: wire.city,
            country: wire.country,
            detail: wire.detail,
            occurredAt: wire.occurredAt
        )
    }
}

extension Wire.RecipientInput {
    init(_ address: Address) {
        self.init(name: address.name, email: address.email)
    }
}
