import Foundation
import MailCore

/// Gmail threads to conversations. Gmail has labels, the app has folders: INBOX means inbox, SPAM and TRASH map to
/// themselves and a thread with none of them is done (archived).
struct GmailMapping {
    let accountID: Account.ID

    func conversationID(thread: String) -> Conversation.ID { UUID(stableFrom: "gmail:\(accountID):\(thread)") }
    func messageID(_ id: String) -> Message.ID { UUID(stableFrom: "gmail:\(accountID):message:\(id)") }

    func conversation(_ thread: Gmail.Thread) -> (Conversation, [Message])? {
        let wire = thread.messages ?? []
        guard !wire.isEmpty else { return nil }
        let messages = wire.map(message)
        let labels = wire.map { Set($0.labelIds ?? []) }
        let all = labels.reduce(into: Set<String>()) { $0.formUnion($1) }
        let folder: Folder =
            all.contains("INBOX") ? .inbox : labels.allSatisfy({ $0.contains("TRASH") }) ? .trash : all.contains("SPAM") ? .spam : .done
        let conversation = Conversation(
            id: conversationID(thread: thread.id),
            accountID: accountID,
            subject: messages.first?.subject ?? "",
            folder: folder,
            isRead: !all.contains("UNREAD"),
            isStarred: all.contains("STARRED"),
            snoozedUntil: nil,
            lastMessageAt: messages.map(\.sentAt).max() ?? .now,
            lastOutboundAt: messages.filter { $0.direction == .outbound }.map(\.sentAt).max(),
            remoteID: thread.id
        )
        return (conversation, messages)
    }

    func message(_ wire: Gmail.Message) -> Message {
        let headers = Dictionary((wire.payload?.headers ?? []).map { ($0.name.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        let parts = flatten(wire.payload)
        let html = parts.first { $0.mimeType == "text/html" && ($0.filename ?? "").isEmpty }.flatMap(decodedBody)
        let text = parts.first { $0.mimeType == "text/plain" && ($0.filename ?? "").isEmpty }.flatMap(decodedBody)
        let attachments = parts.compactMap { part -> Attachment? in
            guard let filename = part.filename, !filename.isEmpty, let attachmentID = part.body?.attachmentId else { return nil }
            let contentID = part.headers?.first { $0.name.lowercased() == "content-id" }?.value
            return Attachment(
                id: UUID(stableFrom: "gmail:\(accountID):\(wire.id):\(part.partId ?? filename)"),
                filename: filename,
                contentType: part.mimeType ?? "application/octet-stream",
                size: part.body?.size ?? 0,
                contentID: contentID,
                remoteID: "\(wire.id)/\(attachmentID)"
            )
        }
        let sentAt = wire.internalDate.flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1000) } ?? .now
        return Message(
            id: messageID(wire.id),
            conversationID: conversationID(thread: wire.threadId),
            accountID: accountID,
            direction: (wire.labelIds ?? []).contains("SENT") ? .outbound : .inbound,
            deliveryStatus: nil,
            messageIDHeader: headers["message-id"],
            from: AddressList.parse(headers["from"] ?? "").first ?? Address(email: "unknown"),
            to: AddressList.parse(headers["to"] ?? ""),
            cc: AddressList.parse(headers["cc"] ?? ""),
            bcc: AddressList.parse(headers["bcc"] ?? ""),
            replyTo: AddressList.parse(headers["reply-to"] ?? ""),
            subject: headers["subject"] ?? "",
            html: html,
            text: text,
            snippet: (wire.snippet ?? "").decodingHTMLEntities,
            sentAt: sentAt,
            trackingEnabled: false,
            attachments: attachments,
            links: [],
            remoteID: wire.id
        )
    }

    private func flatten(_ part: Gmail.Part?) -> [Gmail.Part] {
        guard let part else { return [] }
        return [part] + (part.parts ?? []).flatMap(flatten)
    }

    private func decodedBody(_ part: Gmail.Part) -> String? {
        part.body?.data.flatMap { Data(base64URLEncoded: $0) }.map { String(decoding: $0, as: UTF8.self) }
    }
}

extension String {
    /// Gmail snippets arrive html-escaped.
    var decodingHTMLEntities: String {
        replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
