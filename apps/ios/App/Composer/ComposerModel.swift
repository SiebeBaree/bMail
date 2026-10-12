import Foundation
import MailCore
import MailUI
import Observation
import SwiftUI

/// One message being written, in the composer sheet.
@MainActor
@Observable
final class ComposerModel: Identifiable {
    enum Mode: Equatable {
        case new
        case response(Response.Mode)
    }

    let id = UUID()
    let mode: Mode
    /// The existing conversation for a reply, a fresh one for anything else.
    let conversationID: Conversation.ID
    let messageID: Message.ID
    /// Read once when the composer opens: the session's list is a database read on every access.
    let accounts: [Account]
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
    /// What's typed in each recipient field and not yet a token. Send turns it into one.
    var pending: [RecipientKind: String] = [:]
    /// Cc, Bcc and From folded into one line until you need them.
    var showsCopies = false
    var subject = ""
    var body = AttributedString()
    var selection = AttributedTextSelection()
    /// The message being answered or forwarded, sent below the body and folded away while writing.
    var quoted: Quote?
    var showsQuote = false
    var trackingEnabled = false
    var attachments: [OutgoingAttachment] = []
    var error: String?

    @ObservationIgnored private weak var app: AppModel?

    enum RecipientKind: Hashable { case to, cc, bcc }

    private init(app: AppModel, mode: Mode, conversationID: Conversation.ID, messageID: Message.ID = UUID()) {
        self.app = app
        self.accounts = app.session.accounts
        self.mode = mode
        self.conversationID = conversationID
        self.messageID = messageID
    }

    var account: Account? { accounts.first { $0.id == accountID } }

    var title: String {
        switch mode {
        case .new: "New Message"
        case .response(.forward): "Forward"
        case .response: "Reply"
        }
    }

    /// Whether closing would lose something you did, so it asks first.
    var hasContent: Bool {
        let signature = accountID.map(Signatures.text(for:)) ?? ""
        let written = String(body.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        let typed = !written.isEmpty && written != signature
        if case .new = mode {
            return typed || !to.isEmpty || !cc.isEmpty || !bcc.isEmpty || !subject.isEmpty || !attachments.isEmpty
        }
        return typed || !attachments.isEmpty
    }

    // MARK: - Opening

    static func new(app: AppModel, mailto: URL? = nil) -> ComposerModel {
        let model = ComposerModel(app: app, mode: .new, conversationID: UUID())
        model.accountID = app.accountFilter ?? model.accounts.first?.id
        if let mailto, let components = URLComponents(url: mailto, resolvingAgainstBaseURL: false) {
            model.to = components.path.split(separator: ",").map { Address(email: String($0)) }
            model.subject = components.queryItems?.first { $0.name.lowercased() == "subject" }?.value ?? ""
            if let text = components.queryItems?.first(where: { $0.name.lowercased() == "body" })?.value {
                model.body = AttributedString(text + String(model.body.characters))
            }
        }
        model.selection = AttributedTextSelection(range: model.body.startIndex..<model.body.startIndex)
        return model
    }

    static func respond(to conversationID: Conversation.ID, mode: Response.Mode, app: AppModel) -> ComposerModel? {
        let thread = (try? app.session.store.database.read { db in
            try Message.where { $0.conversationID.eq(conversationID) }.order(by: \.sentAt).fetchAll(db)
        }) ?? []
        let model = ComposerModel(app: app, mode: .response(mode), conversationID: mode == .forward ? UUID() : conversationID)
        let own = Set(model.accounts.map { $0.address.lowercased() })
        guard let response = Response(to: thread, mode: mode, ownAddresses: own) else { return nil }
        model.accountID = response.accountID
        model.to = response.to
        model.cc = response.cc
        model.showsCopies = !response.cc.isEmpty
        model.subject = response.subject
        model.quoted = response.quote
        model.showsQuote = mode == .forward
        model.selection = AttributedTextSelection(range: model.body.startIndex..<model.body.startIndex)
        return model
    }

    /// Brings a message back after Undo send, exactly as it was.
    static func reopen(_ message: OutgoingMessage, app: AppModel) -> ComposerModel {
        let isReply = !app.session.conversations([message.conversationID]).isEmpty
        let model = ComposerModel(app: app, mode: isReply ? .response(.reply) : .new, conversationID: message.conversationID, messageID: message.id)
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

    // MARK: - Editing

    func addresses(_ kind: RecipientKind) -> [Address] {
        switch kind {
        case .to: to
        case .cc: cc
        case .bcc: bcc
        }
    }

    func setAddresses(_ addresses: [Address], for kind: RecipientKind) {
        switch kind {
        case .to: to = addresses
        case .cc: cc = addresses
        case .bcc: bcc = addresses
        }
        error = nil
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

    func attach(_ data: Data, named filename: String) {
        do {
            attachments.append(try OutboxFiles.write(data, named: filename, for: messageID))
        } catch {
            self.error = "Couldn't attach \(filename)."
        }
    }

    func close() {
        app?.sheet = nil
    }

    // MARK: - Sending

    /// Checks the message and hands it to the outbox. False, with `error` set, when it can't go yet.
    @discardableResult
    func send(fontContext: Font.Context) -> Bool {
        for (kind, text) in pending {
            let address = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !address.isEmpty else { continue }
            if !addresses(kind).contains(where: { $0.email.caseInsensitiveCompare(address) == .orderedSame }) {
                setAddresses(addresses(kind) + [Address(email: address)], for: kind)
            }
        }
        pending = [:]
        guard let account else {
            error = "Pick an account to send from."
            return false
        }
        guard !(to + cc + bcc).isEmpty else {
            error = "Add someone to send this to."
            return false
        }
        if let invalid = (to + cc + bcc).first(where: { !$0.email.isPlausibleEmail }) {
            error = "\(invalid.email) isn't an email address."
            return false
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
        app?.sheet = nil
        app?.send(message)
        return true
    }
}
