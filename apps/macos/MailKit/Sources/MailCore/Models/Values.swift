import Foundation
import SQLiteData

/// A person on a message. `name` is whatever the sender's mail app put there, so it can be missing or odd.
public struct Address: Codable, Hashable, Sendable {
    public var name: String?
    public var email: String

    public init(name: String? = nil, email: String) {
        self.name = name
        self.email = email
    }

    /// The name if there is one, otherwise the part before the @.
    public var displayName: String {
        if let name, !name.isEmpty { return name }
        return String(email.prefix { $0 != "@" })
    }
}

public struct Attachment: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var filename: String
    public var contentType: String
    public var size: Int
    /// Set for inline images, which the reader shows in the body instead of the attachment list.
    public var contentID: String?
    /// What the provider needs to download it, for providers that don't use our ids.
    public var remoteID: String?

    public init(id: UUID, filename: String, contentType: String, size: Int, contentID: String?, remoteID: String? = nil) {
        self.id = id
        self.filename = filename
        self.contentType = contentType
        self.size = size
        self.contentID = contentID
        self.remoteID = remoteID
    }
}

/// The original destination of a link in a tracked message, keyed by the id inside its tracking url.
public struct TrackedLink: Codable, Hashable, Sendable {
    public var id: UUID
    public var url: URL

    public init(id: UUID, url: URL) {
        self.id = id
        self.url = url
    }
}

/// How to leave a mailing list, from its List-Unsubscribe headers. One-click (RFC 8058) is a POST to `url` that needs
/// nothing else; without it the mailto address gets a message, or the url opens in the browser.
public struct Unsubscribe: Codable, Hashable, Sendable {
    public var url: URL?
    public var mailto: URL?
    public var isOneClick: Bool

    /// Nil when the header names neither an https url nor a mailto address.
    public init?(header: String?, oneClick: Bool) {
        let targets = (header ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " <>\t\r\n")) }
            .compactMap(URL.init(string:))
        url = targets.first { $0.scheme?.lowercased() == "https" }
        mailto = targets.first { $0.scheme?.lowercased() == "mailto" }
        isOneClick = oneClick && url != nil
        if url == nil, mailto == nil { return nil }
    }

    public init(url: URL?, mailto: URL?, isOneClick: Bool) {
        self.url = url
        self.mailto = mailto
        self.isOneClick = isOneClick
    }
}

public struct DNSRecord: Codable, Hashable, Sendable {
    public enum Purpose: String, Codable, Sendable { case dkim, spf, receiving, tracking, dmarc }
    public enum Status: String, Codable, Sendable { case pending, verified, failed, optional }

    public var purpose: Purpose
    public var type: String
    public var name: String
    public var value: String
    public var priority: Int?
    public var status: Status

    public init(purpose: Purpose, type: String, name: String, value: String, priority: Int?, status: Status) {
        self.purpose = purpose
        self.type = type
        self.name = name
        self.value = value
        self.priority = priority
        self.status = status
    }
}

/// Where a conversation lives. Sent, starred and tracked are views over these, not folders.
public enum Folder: String, Codable, Sendable, CaseIterable, QueryBindable {
    case inbox, done, spam, trash
}

public enum Direction: String, Codable, Sendable, QueryBindable {
    case inbound, outbound
}

public enum DeliveryStatus: String, Codable, Sendable, QueryBindable {
    case sending, sent, delivered, delayed, bounced, complained, failed

    /// The mail didn't reach the recipient and won't.
    public var isFailure: Bool { [.bounced, .complained, .failed].contains(self) }
}
