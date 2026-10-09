import Foundation
import MailCore

/// Builds an RFC 5322 message from an outgoing message, for providers that take raw mail (Gmail). Text and html go as
/// alternatives, attachments around them, everything base64 so no line or character needs escaping.
struct MIMEMessage {
    var message: OutgoingMessage
    var inReplyTo: String?
    var references: [String]
    var date = Date()
    /// Our own Message-ID, so replies to it thread back to this conversation.
    var messageID: String

    func render() throws -> Data {
        let mixed = "mixed-\(UUID().uuidString)"
        let alternative = "alt-\(UUID().uuidString)"
        var headers: [(String, String)] = [
            ("From", Self.address(message.from)),
            ("To", message.to.map(Self.address).joined(separator: ", ")),
        ]
        if !message.cc.isEmpty { headers.append(("Cc", message.cc.map(Self.address).joined(separator: ", "))) }
        if !message.bcc.isEmpty { headers.append(("Bcc", message.bcc.map(Self.address).joined(separator: ", "))) }
        headers += [
            ("Subject", Self.encodedWord(message.subject)),
            ("Date", Self.rfc5322Date(date)),
            ("Message-ID", messageID),
            // Comes back on the provider's copy, which then keeps the id the composer gave this message.
            ("X-Bmail-ID", message.id.uuidString.lowercased()),
        ]
        if let inReplyTo { headers.append(("In-Reply-To", inReplyTo)) }
        if !references.isEmpty { headers.append(("References", references.joined(separator: " "))) }
        headers.append(("MIME-Version", "1.0"))

        var body = ""
        let alternatives = """
            --\(alternative)\r
            Content-Type: text/plain; charset=utf-8\r
            Content-Transfer-Encoding: base64\r
            \r
            \(Self.base64Lines(Data(message.text.utf8)))\r
            --\(alternative)\r
            Content-Type: text/html; charset=utf-8\r
            Content-Transfer-Encoding: base64\r
            \r
            \(Self.base64Lines(Data(message.html.utf8)))\r
            --\(alternative)--\r

            """
        if message.attachments.isEmpty {
            headers.append(("Content-Type", "multipart/alternative; boundary=\"\(alternative)\""))
            body = alternatives
        } else {
            headers.append(("Content-Type", "multipart/mixed; boundary=\"\(mixed)\""))
            body = "--\(mixed)\r\nContent-Type: multipart/alternative; boundary=\"\(alternative)\"\r\n\r\n" + alternatives
            for file in message.attachments {
                let data = try Data(contentsOf: file.fileURL)
                let name = Self.encodedWord(file.filename)
                body += """
                    --\(mixed)\r
                    Content-Type: \(file.contentType); name="\(name)"\r
                    Content-Disposition: attachment; filename="\(name)"\r
                    Content-Transfer-Encoding: base64\r
                    \r
                    \(Self.base64Lines(data))\r

                    """
            }
            body += "--\(mixed)--\r\n"
        }
        let head = headers.map { "\($0.0): \($0.1)" }.joined(separator: "\r\n")
        return Data((head + "\r\n\r\n" + body).utf8)
    }

    /// `"Name" <email>`, with the name encoded when it isn't plain ASCII.
    static func address(_ address: Address) -> String {
        guard let name = address.name, !name.isEmpty else { return address.email }
        let isPlain = name.allSatisfy { $0.isASCII && $0 != "\"" && $0 != "\\" }
        return isPlain ? "\"\(name)\" <\(address.email)>" : "\(encodedWord(name)) <\(address.email)>"
    }

    /// RFC 2047 encoded word for headers that aren't ASCII.
    static func encodedWord(_ text: String) -> String {
        text.allSatisfy(\.isASCII) ? text : "=?UTF-8?B?\(Data(text.utf8).base64EncodedString())?="
    }

    static func base64Lines(_ data: Data) -> String {
        data.base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
    }

    static func rfc5322Date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.string(from: date)
    }
}

/// Splits a header like `"Peeters, Lena" <lena@x.be>, tom@y.vc` into addresses, respecting quotes and brackets.
enum AddressList {
    static func parse(_ header: String) -> [Address] {
        var parts: [String] = []
        var current = ""
        var inQuotes = false
        var inBrackets = false
        for character in header {
            switch character {
            case "\"": inQuotes.toggle()
            case "<" where !inQuotes: inBrackets = true
            case ">" where !inQuotes: inBrackets = false
            case "," where !inQuotes && !inBrackets:
                parts.append(current)
                current = ""
                continue
            default: break
            }
            current.append(character)
        }
        parts.append(current)
        return parts.compactMap { part in
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            if let open = trimmed.lastIndex(of: "<"), let close = trimmed.lastIndex(of: ">"), open < close {
                let email = String(trimmed[trimmed.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
                let name = String(trimmed[..<open]).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                return Address(name: name.isEmpty ? nil : name, email: email.lowercased())
            }
            return Address(email: trimmed.lowercased())
        }
    }
}
