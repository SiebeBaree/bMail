import Agents
import AppKit
import Foundation
import MailCore
import MailUI
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

        /// How the shared rules start this one. New mail answers nothing, so it never asks.
        var response: Response.Mode {
            switch self {
            case .replyAll: .replyAll
            case .forward: .forward
            case .new, .reply: .reply
            }
        }
    }

    let mode: Mode
    /// The existing conversation for a reply, a fresh one for anything else.
    let conversationID: Conversation.ID
    let messageID: Message.ID
    /// The message an agent wrote, when this is one waiting for you at Ask to send.
    private(set) var draft: AgentDraft?
    /// Switching accounts swaps the signature under the body, as long as it's still the one that was put there.
    var accountID: Account.ID? {
        didSet {
            guard accountID != oldValue, let swapped = Signatures.swapped(in: String(body.characters), from: oldValue, to: accountID) else { return }
            body = AttributedString(swapped)
        }
    }
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

    private init(app: AppModel, mode: Mode, conversationID: Conversation.ID, messageID: Message.ID = UUID()) {
        self.app = app
        self.accounts = app.session.accounts
        self.mode = mode
        self.conversationID = conversationID
        self.messageID = messageID
    }

    /// New mail and forwards take the reader's place; replies open under the conversation they answer. An agent's
    /// message takes it too, so it's on screen whatever conversation is open.
    var replacesReader: Bool { mode == .new || mode == .forward || draft != nil }

    /// Read once when the composer opens: the app's list is a database read on every access.
    let accounts: [Account]
    var account: Account? { accounts.first { $0.id == accountID } }

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
        model.accountID = app.accountFilter ?? model.accounts.first?.id
        model.selection = AttributedTextSelection(range: model.body.startIndex..<model.body.startIndex)
        if let mailto, let components = URLComponents(url: mailto, resolvingAgainstBaseURL: false) {
            model.to = components.path.split(separator: ",").map { Address(email: String($0)) }
            model.subject = components.queryItems?.first { $0.name.lowercased() == "subject" }?.value ?? ""
        }
        return model
    }

    static func respond(to conversationID: Conversation.ID, mode: Mode, app: AppModel) -> ComposerModel? {
        let thread = (try? app.session.store.database.read { db in
            try Message.where { $0.conversationID.eq(conversationID) }.order(by: \.sentAt).fetchAll(db)
        }) ?? []
        let model = ComposerModel(app: app, mode: mode, conversationID: mode == .forward ? UUID() : conversationID)
        let own = Set(model.accounts.map { $0.address.lowercased() })
        guard let response = Response(to: thread, mode: mode.response, ownAddresses: own) else {
            return nil
        }
        model.accountID = response.accountID
        model.to = response.to
        model.cc = response.cc
        model.showsCopies = !response.cc.isEmpty
        model.subject = response.subject
        model.quoted = response.quote
        model.selection = AttributedTextSelection(range: model.body.startIndex..<model.body.startIndex)
        model.showsQuote = mode == .forward
        return model
    }

    /// A message an agent wrote at Ask to send, to read, change and send yourself.
    static func drafted(_ draft: AgentDraft, app: AppModel) -> ComposerModel {
        let mode: Mode = switch draft.mode {
        case .reply: .reply
        case .replyAll: .replyAll
        case .forward: .forward
        case nil: .new
        }
        let model = ComposerModel(app: app, mode: mode, conversationID: draft.conversationID, messageID: draft.id)
        model.draft = draft
        model.accountID = draft.account.id
        model.to = draft.to
        model.cc = draft.cc
        model.bcc = draft.bcc
        model.showsCopies = !draft.cc.isEmpty || !draft.bcc.isEmpty
        model.subject = draft.subject
        model.body = AttributedString(draft.text)
        model.selection = AttributedTextSelection(range: model.body.startIndex..<model.body.startIndex)
        model.quoted = draft.quote
        model.showsQuote = mode == .forward
        return model
    }

    // MARK: - Editing

    func toggleTracking() {
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
        let quote = quoted?.appendix
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
            trackingEnabled: trackingEnabled,
            attachments: attachments
        )
        app?.composer = nil
        app?.send(message, from: self)
    }
}
