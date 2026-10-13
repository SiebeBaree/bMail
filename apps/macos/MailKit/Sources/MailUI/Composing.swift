import Foundation
import MailCore
import SwiftUI
import UniformTypeIdentifiers

/// How a reply or forward starts: from the account the last message reached, to the people it should go to, with the
/// last message quoted under what you write.
public struct Response: Sendable {
    public enum Mode: Sendable { case reply, replyAll, forward }

    public var accountID: Account.ID
    public var to: [Address] = []
    public var cc: [Address] = []
    public var subject: String
    public var quote: Quote

    /// Nil for an empty thread. `ownAddresses` are your accounts' addresses, lowercased, so reply all leaves you out.
    public init?(to thread: [Message], mode: Mode, ownAddresses: Set<String>) {
        guard let last = thread.last else { return nil }
        let isOwn = { (address: Address) in ownAddresses.contains(address.email.lowercased()) }
        accountID = last.accountID
        switch mode {
        case .reply:
            to = last.direction == .outbound ? last.to : (last.replyTo.isEmpty ? [last.from] : last.replyTo)
        case .replyAll:
            let sender = last.direction == .outbound ? [] : (last.replyTo.isEmpty ? [last.from] : last.replyTo)
            let to = Self.unique(sender + last.to.filter { !isOwn($0) })
            self.to = to
            cc = Self.unique(last.cc.filter { !isOwn($0) && !to.contains($0) })
        case .forward:
            break
        }
        let base = last.subject.replacing(/^((re|fwd?):\s*)+/.ignoresCase(), with: "")
        subject = mode == .forward ? "Fwd: \(base)" : "Re: \(base)"
        let when = last.sentAt.formatted(date: .abbreviated, time: .shortened)
        let author = last.from.name.map { "\($0) <\(last.from.email)>" } ?? last.from.email
        quote = Quote(
            header: mode == .forward ? "Forwarded message from \(author), \(when):" : "On \(when), \(author) wrote:",
            html: Self.withoutOpenPixels(last.html ?? EmailDocument.textAsHTML(last.text ?? "")),
            text: last.text ?? ""
        )
    }

    /// Gmail keeps the copy of a tracked message that went out, pixel included. Quoting it would send that
    /// pixel along again and count the next reader of this reply as an open of the old message.
    public static func withoutOpenPixels(_ html: String) -> String {
        html.replacing(/<img[^>]+\/o\/[0-9a-f-]{36}\.[^>]*>/.ignoresCase(), with: "")
    }

    private static func unique(_ addresses: [Address]) -> [Address] {
        var seen = Set<String>()
        return addresses.filter { seen.insert($0.email.lowercased()).inserted }
    }
}

/// The message being answered or forwarded, sent below the body.
public struct Quote: Equatable, Sendable {
    public var header: String
    public var html: String
    public var text: String

    /// What goes after your own words in each part of the message.
    public var appendix: (html: String, text: String) {
        (
            #"<br><div>\#(BodySerializer.escape(header))</div><blockquote style="margin:0 0 0 .8ex;border-left:1px solid #ccc;padding-left:1ex">\#(html)</blockquote>"#,
            "\n\n\(header)\n" + text.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n")
        )
    }
}

/// Turns what you typed into the html and text parts of an email. Only what people actually use survives: paragraphs,
/// line breaks, bold, italic, underline and links. Pasted fonts and colors are dropped, so mail looks written, not
/// assembled.
public struct BodySerializer {
    let context: Font.Context

    public init(context: Font.Context) {
        self.context = context
    }

    public func render(_ body: AttributedString) -> (html: String, text: String) {
        var html = ""
        for run in body.runs {
            var fragment = Self.escape(String(body[run.range].characters))
            let resolved = run.font?.resolve(in: context)
            if resolved?.isBold == true { fragment = "<strong>\(fragment)</strong>" }
            if resolved?.isItalic == true { fragment = "<em>\(fragment)</em>" }
            if run.underlineStyle != nil, run.link == nil { fragment = "<u>\(fragment)</u>" }
            if let link = run.link { fragment = #"<a href="\#(Self.escape(link.absoluteString))">\#(fragment)</a>"# }
            html += fragment
        }
        let paragraphs = html
            .components(separatedBy: "\n\n")
            .map { "<p style=\"margin:0 0 12px\">\($0.replacingOccurrences(of: "\n", with: "<br>"))</p>" }
            .joined()
        return (#"<div style="font-family:-apple-system,Helvetica,Arial,sans-serif;font-size:14px;line-height:1.6">\#(paragraphs)</div>"#, String(body.characters))
    }

    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// One signature per account, kept on this device. Plain text: the composer puts it under what you write, where it can
/// still be edited like the rest of the message.
public enum Signatures {
    public static func text(for account: Account.ID) -> String {
        UserDefaults.standard.string(forKey: key(account)) ?? ""
    }

    public static func set(_ text: String, for account: Account.ID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: key(account))
        } else {
            UserDefaults.standard.set(trimmed, forKey: key(account))
        }
    }

    /// The body with the old account's signature swapped for the new one's, as long as it's still the one that was put
    /// there. Nil when nothing should change.
    public static func swapped(in body: String, from old: Account.ID?, to new: Account.ID?) -> String? {
        let old = old.map(text(for:)) ?? ""
        let new = new.map(text(for:)) ?? ""
        if !old.isEmpty, body.hasSuffix(old) { return String(body.dropLast(old.count)) + new }
        if old.isEmpty, !new.isEmpty, body.isEmpty { return "\n\n" + new }
        return nil
    }

    private static func key(_ account: Account.ID) -> String { "signature.\(account.uuidString)" }
}

/// Attachments are copied into the app's container when attached, so the send still works after the undo window, a
/// relaunch or the original file moving.
public enum OutboxFiles {
    public static func copy(_ url: URL, for messageID: Message.ID) throws -> OutgoingAttachment {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let destination = try destination(named: url.lastPathComponent, for: messageID)
        try FileManager.default.copyItem(at: url, to: destination)
        return attachment(at: destination)
    }

    /// For files that only exist in memory, like a photo from the library.
    public static func write(_ data: Data, named filename: String, for messageID: Message.ID) throws -> OutgoingAttachment {
        let destination = try destination(named: filename, for: messageID)
        try data.write(to: destination)
        return attachment(at: destination)
    }

    /// A file name of its own in the message's folder: two files called `scan.pdf` both go out, as `scan.pdf` and
    /// `scan 2.pdf`.
    private static func destination(named filename: String, for messageID: Message.ID) throws -> URL {
        let folder = URL.applicationSupportDirectory.appending(path: "Outbox/\(messageID.uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var destination = folder.appending(path: filename)
        var number = 2
        while FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            destination = folder.appending(path: ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)")
            number += 1
        }
        return destination
    }

    private static func attachment(at url: URL) -> OutgoingAttachment {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return OutgoingAttachment(filename: url.lastPathComponent, contentType: type, size: size, fileURL: url)
    }
}

extension String {
    /// A sanity check, not validation: catches typos like a missing @ before the server bounces them.
    public var isPlausibleEmail: Bool {
        wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s]+/) != nil
    }
}

extension OutgoingMessage {
    /// The message a `mailto:` unsubscribe link asks for, from the account the list mails. Nil unless the link names
    /// exactly one address. It goes out without a composer, so the sender only picks that address and the subject;
    /// a body of theirs would be mail you never saw sent in your name.
    public init?(unsubscribing mailto: URL, from account: Account) {
        guard let components = URLComponents(url: mailto, resolvingAgainstBaseURL: false), components.path.isPlausibleEmail else {
            return nil
        }
        let subject = components.queryItems?.first { $0.name.lowercased() == "subject" }?.value
        self.init(
            conversationID: UUID(),
            accountID: account.id,
            from: Address(name: account.displayName, email: account.address),
            to: [Address(email: components.path)],
            subject: subject ?? "unsubscribe",
            html: EmailDocument.textAsHTML("unsubscribe"),
            text: "unsubscribe"
        )
    }
}
