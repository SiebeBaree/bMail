import AuthenticationServices
import DesignSystem
import MailCore
import MailUI
import Observation
import SQLiteData
import SwiftUI
import UIKit

/// What the list shows: one of the views, or a label's conversations, by name.
enum Mailbox: Hashable {
    case tab(MailTab)
    case label(String)
}

/// The app's state and the actions views call. What changes mail lives in the session, which the Mac app shares; this
/// adds where you are on the phone and what's on screen.
@MainActor
@Observable
final class AppModel {
    /// What's in the one sheet the app shows at a time. One slot rather than one per sheet: changing it swaps the sheet,
    /// where two separate sheets would refuse to show over each other.
    enum Sheet: Identifiable {
        case composer(ComposerModel)
        case labels([Conversation.ID])
        case settings
        /// Asks before connecting to a server, from a `bmail://connect` link or a typed address.
        case connectServer(URL)

        var id: String {
            switch self {
            case let .composer(composer): "composer.\(composer.id)"
            case let .labels(ids): "labels.\(ids)"
            case .settings: "settings"
            case let .connectServer(url): "server.\(url)"
            }
        }
    }

    let session = MailSession(google: BuildSettings.google)

    var mailbox: Mailbox = .tab(.inbox)
    /// Nil shows every account together.
    var accountFilter: Account.ID?
    var searchText = "" {
        didSet { searchResults = session.search(searchText) }
    }
    /// Conversation ids matching `searchText`, best first. Nil when not searching.
    private(set) var searchResults: [Conversation.ID]?
    /// The navigation stack. Only the reader is ever pushed.
    var path: [Conversation.ID] = []
    /// The list as shown, written by the list, so the reader can step through it.
    var listOrder: [Conversation.ID] = []
    var sheet: Sheet?
    /// A message Undo send brought back while you were writing another one. It opens when that one closes.
    @ObservationIgnored private var waitingToReopen: ComposerModel?
    /// The window's width in points. Message bodies are laid out to fit it.
    var width = 0

    init() {
        Typography.register()
        Theme.apply()
        session.openLink = { [weak self] url in self?.open(url) }
    }

    /// A link from a message: mail opens the composer, everything else the app that handles it.
    private func open(_ url: URL) {
        if url.scheme?.lowercased() == "mailto" {
            compose(mailto: url)
        } else {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Accounts

    /// Google's sign-in in a browser sheet, then the account. Cancelling isn't an error.
    func connectGmail(using webAuthenticationSession: WebAuthenticationSession) async throws {
        guard let client = session.google else { return }
        let attempt = client.start()
        do {
            let callback = try await webAuthenticationSession.authenticate(
                using: attempt.url,
                callback: .customScheme(attempt.callbackScheme),
                preferredBrowserSession: .ephemeral,
                additionalHeaderFields: [:]
            )
            try session.connectGmail(tokens: try await client.finish(attempt, callback: callback))
            Haptics.success()
        } catch let failure as ASWebAuthenticationSessionError where failure.code == .canceledLogin {
            return
        }
    }

    /// Asks before connecting to the server at `url`, unless it's the one already connected.
    func connect(to url: URL) {
        if session.server?.baseURL == url {
            session.toasts.show(Toast("Already connected to \(url.host() ?? url.absoluteString)", symbol: "checkmark"))
        } else {
            sheet = .connectServer(url)
        }
    }

    /// Links bMail opens: `bmail://connect?server=…`, which Vercel's deploy flow sends you back with.
    func handle(_ link: URL) {
        guard let server = ServerSetup.server(in: link) else { return }
        connect(to: server)
    }

    // MARK: - Triage

    /// Moves conversations to a folder, with a toast that takes it back.
    func move(_ ids: [Conversation.ID], to folder: Folder) {
        session.move(session.conversations(ids), to: folder)
    }

    func toggleStar(_ ids: [Conversation.ID]) {
        session.toggleStar(session.conversations(ids))
    }

    func toggleRead(_ ids: [Conversation.ID]) {
        session.toggleRead(session.conversations(ids))
    }

    func label(_ ids: [Conversation.ID]) {
        sheet = .labels(ids)
    }

    // MARK: - Writing

    func compose(mailto: URL? = nil) {
        sheet = .composer(ComposerModel.new(app: self, mailto: mailto))
    }

    func respond(to id: Conversation.ID, _ mode: Response.Mode) {
        guard let composer = ComposerModel.respond(to: id, mode: mode, app: self) else { return }
        sheet = .composer(composer)
    }

    /// Holds the message for the undo window. Undo brings back the composer it came from, exactly as it was, unless
    /// you're writing something else by then: it waits until that one closes.
    func send(_ message: OutgoingMessage, from composer: ComposerModel) {
        Haptics.success()
        session.send(message) { [weak self] in
            guard let self else { return }
            Haptics.tap()
            if case let .composer(current) = self.sheet, current.hasContent {
                self.waitingToReopen = composer
            } else {
                self.sheet = .composer(composer)
            }
        }
    }

    /// The sheet went away, by a button or a swipe.
    func sheetDismissed() {
        guard let reopened = waitingToReopen else { return }
        waitingToReopen = nil
        sheet = .composer(reopened)
    }

    // MARK: - Reading

    var title: String {
        if searchResults != nil { return "Search" }
        switch mailbox {
        case let .tab(tab): return tab.title
        case let .label(name): return name
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
