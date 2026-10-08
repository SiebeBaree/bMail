import AppKit
import Foundation
import MailCore
import Observation
import SQLiteData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class ComposerModel {
    enum Mode: Equatable {
        case new, reply, replyAll, forward

        init(_ command: Command) {
            switch command {
            case .replyAll: self = .replyAll
            case .forward: self = .forward
            default: self = .reply
            }
        }
    }

    let mode: Mode
    /// The existing conversation for a reply, a fresh one for anything else.
    let conversationID: Conversation.ID
    let messageID: Message.ID
    var accountID: Account.ID?
    var to: [Address] = []
    var cc: [Address] = []
    var bcc: [Address] = []
    var showsCopies = false
    var subject = ""
    var body = AttributedString()
    var selection = AttributedTextSelection()
    /// The message being answered or forwarded, sent below the body and collapsed while writing.
    var quoted: Quote?
    var showsQuote = false
    var trackingEnabled = false
    var attachments: [OutgoingAttachment] = []
    var error: String?

    @ObservationIgnored private weak var app: AppModel?

    struct Quote: Equatable {
        var header: String
        var html: String
        var text: String
    }

    private init(app: AppModel, mode: Mode, conversationID: Conversation.ID, messageID: Message.ID = UUID()) {
        self.app = app
        self.mode = mode
        self.conversationID = conversationID
        self.messageID = messageID
    }

    /// New mail and forwards take the reader's place; replies open under the conversation they answer.
    var replacesReader: Bool { mode == .new || mode == .forward }

    var accounts: [Account] { app?.accounts ?? [] }
    var account: Account? { accounts.first { $0.id == accountID } }

    /// Tracking runs through the api, so it exists for your own domains only.
    var canTrack: Bool { account?.kind == .domain }

    var title: String {
        switch mode {
        case .new: "New message"
        case .reply, .replyAll: "Reply"
        case .forward: "Forward"
        }
    }

    // MARK: - Opening

    static func new(app: AppModel, mailto: URL? = nil) -> ComposerModel {
        let model = ComposerModel(app: app, mode: .new, conversationID: UUID())
        model.accountID = app.accountFilter ?? app.accounts.first?.id
        if let mailto, let components = URLComponents(url: mailto, resolvingAgainstBaseURL: false) {
            model.to = components.path.split(separator: ",").map { Address(email: String($0)) }
            model.subject = components.queryItems?.first { $0.name.lowercased() == "subject" }?.value ?? ""
        }
        return model
    }

    static func respond(to conversationID: Conversation.ID, mode: Mode, app: AppModel) -> ComposerModel? {
        let thread = try? app.store.database.read { db in
            try Message.where { $0.conversationID.eq(conversationID) }.order(by: \.sentAt).fetchAll(db)
        }
        guard let thread, let last = thread.last else { return nil }
        let model = ComposerModel(app: app, mode: mode, conversationID: mode == .forward ? UUID() : conversationID)
        model.accountID = last.accountID
        let own = Set(app.accounts.map { $0.address.lowercased() })
        let isOwn = { (address: Address) in own.contains(address.email.lowercased()) }

        switch mode {
        case .reply:
            model.to = last.direction == .outbound ? last.to : (last.replyTo.isEmpty ? [last.from] : last.replyTo)
        case .replyAll:
            let sender = last.direction == .outbound ? [] : (last.replyTo.isEmpty ? [last.from] : last.replyTo)
            model.to = unique(sender + last.to.filter { !isOwn($0) })
            model.cc = unique(last.cc.filter { !isOwn($0) && !model.to.contains($0) })
            model.showsCopies = !model.cc.isEmpty
        case .forward, .new:
            break
        }
        let base = last.subject.replacing(/^((re|fwd?):\s*)+/.ignoresCase(), with: "")
        model.subject = mode == .forward ? "Fwd: \(base)" : "Re: \(base)"
        let when = last.sentAt.formatted(date: .abbreviated, time: .shortened)
        let author = last.from.name.map { "\($0) <\(last.from.email)>" } ?? last.from.email
        model.quoted = Quote(
            header: mode == .forward ? "Forwarded message from \(author), \(when):" : "On \(when), \(author) wrote:",
            html: last.html ?? EmailDocument.textAsHTML(last.text ?? ""),
            text: last.text ?? ""
        )
        model.showsQuote = mode == .forward
        return model
    }

    /// Brings a message back after Undo send, exactly as it was.
    static func reopen(_ message: OutgoingMessage, app: AppModel) -> ComposerModel {
        let isReply = (try? app.store.database.read { db in try Conversation.find(message.conversationID).fetchOne(db) }) != nil
        let model = ComposerModel(app: app, mode: isReply ? .reply : .new, conversationID: message.conversationID, messageID: message.id)
        model.accountID = message.accountID
        model.to = message.to
        model.cc = message.cc
        model.bcc = message.bcc
        model.showsCopies = !message.cc.isEmpty || !message.bcc.isEmpty
        model.subject = message.subject
        model.body = AttributedString(message.text)
        model.trackingEnabled = message.trackingEnabled
        model.attachments = message.attachments
        return model
    }

    private static func unique(_ addresses: [Address]) -> [Address] {
        var seen = Set<String>()
        return addresses.filter { seen.insert($0.email.lowercased()).inserted }
    }

    // MARK: - Editing

    func toggleTracking() {
        guard canTrack else { return }
        trackingEnabled.toggle()
    }

    func attach(_ urls: [URL]) {
        for url in urls {
            do {
                attachments.append(try OutboxFiles.copy(url, for: messageID))
            } catch {
                self.error = "Couldn't attach \(url.lastPathComponent)."
            }
        }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { attach(panel.urls) }
    }

    func close() {
        app?.composer = nil
    }

    // MARK: - Sending

    func send(fontContext: Font.Context) {
        guard let account else {
            error = "Pick an account to send from."
            return
        }
        guard !(to + cc + bcc).isEmpty else {
            error = "Add a recipient."
            return
        }
        if let invalid = (to + cc + bcc).first(where: { !$0.email.isPlausibleEmail }) {
            error = "\(invalid.email) isn't an email address."
            return
        }
        let rendered = BodySerializer(context: fontContext).render(body)
        let quote = quoted.map { quote in
            (
                html: #"<br><div>\#(quote.header)</div><blockquote style="margin:0 0 0 .8ex;border-left:1px solid #ccc;padding-left:1ex">\#(quote.html)</blockquote>"#,
                text: "\n\n\(quote.header)\n" + quote.text.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n")
            )
        }
        let message = OutgoingMessage(
            id: messageID,
            conversationID: conversationID,
            accountID: account.id,
            from: Address(name: account.displayName, email: account.address),
            to: to,
            cc: cc,
            bcc: bcc,
            subject: subject.trimmingCharacters(in: .whitespaces),
            html: rendered.html + (quote?.html ?? ""),
            text: rendered.text + (quote?.text ?? ""),
            trackingEnabled: trackingEnabled && canTrack,
            attachments: attachments
        )
        app?.composer = nil
        app?.send(message)
    }
}

/// Attachments are copied into the app's container when attached, so the send still works after the undo window, a
/// relaunch or the original file moving.
enum OutboxFiles {
    static func copy(_ url: URL, for messageID: Message.ID) throws -> OutgoingAttachment {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let folder = URL.applicationSupportDirectory.appending(path: "Outbox/\(messageID.uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.copyItem(at: url, to: destination)
        let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return OutgoingAttachment(filename: url.lastPathComponent, contentType: type, size: size, fileURL: destination)
    }
}

extension String {
    /// A sanity check, not validation: catches typos like a missing @ before the server bounces them.
    var isPlausibleEmail: Bool {
        wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s]+/) != nil
    }
}
