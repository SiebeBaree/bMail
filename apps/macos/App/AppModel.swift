import Agents
import AppKit
import AuthenticationServices
import DesignSystem
import Foundation
import MailCore
import MailUI
import Observation
import OSLog
import SwiftUI

private let commandLog = Logger(subsystem: "be.baree.mail", category: "Commands")

/// The app's state and the one place commands are carried out, whether they come from a key, the palette or the menu.
/// What changes mail lives in the session, which the iPhone app shares; this adds the Mac's selection and keys.
@MainActor
@Observable
final class AppModel {
    let session = MailSession(google: BuildSettings.google)
    let onboarding: Onboarding
    let agents: AgentServer
    @ObservationIgnored private let notifications = AgentNotifications()
    /// Messages agents wrote at Ask to send, oldest first. The first opens in the composer as soon as it's free.
    @ObservationIgnored private var agentDrafts: [AgentDraft] = []
    @ObservationIgnored private var keyboard: KeyboardRouter?
    @ObservationIgnored private var markReadTask: Task<Void, Never>?

    var tab: MailTab = .inbox {
        didSet {
            labelFilter = nil
            if tab != oldValue { selection = nil; checked = [] }
        }
    }
    /// A label's conversations instead of the tab's, by name. Picking a tab leaves it.
    var labelFilter: String? {
        didSet { if labelFilter != oldValue { selection = nil; checked = [] } }
    }
    /// Nil shows every account together.
    var accountFilter: Account.ID? {
        didSet { if accountFilter != oldValue { selection = nil; checked = [] } }
    }
    /// Conversations picked with X, Shift or ⌘A. While any are, triage keys act on all of them instead of the open one.
    var checked: Set<Conversation.ID> = []
    var selection: Conversation.ID? {
        didSet { if selection != oldValue { scheduleMarkRead() } }
    }
    /// The visible list in order, written by the list so J and K know where to go.
    var listOrder: [Conversation.ID] = [] {
        didSet {
            if !checked.isEmpty { checked.formIntersection(listOrder) }
            if let selection, listOrder.contains(selection) { return }
            selection = listOrder.first
        }
    }
    var composer: ComposerModel? {
        didSet {
            if let old = oldValue, old !== composer, let draft = old.draft {
                // Sent or discarded, an agent's message is done. Pushed aside by another composer, it waits its turn again.
                if composer == nil { notifications.remove(draft.id) } else { agentDrafts.insert(draft, at: 0) }
            }
            if composer == nil, !agentDrafts.isEmpty {
                Task { self.openNextDraft() }
            }
        }
    }
    /// The server the connect sheet is asking about, from a `bmail://connect` link or a typed address.
    var connectingServer: URL?
    var isPaletteOpen = false
    var isShortcutsOpen = false
    var isLabelPickerOpen = false
    var isSearchFocused = false
    var searchText = "" {
        didSet { searchResults = session.search(searchText) }
    }
    /// Conversation ids matching `searchText`, best first. Nil when not searching.
    var searchResults: [Conversation.ID]?
    @ObservationIgnored var openSettings: () -> Void = {}
    /// The keys step, while it's on screen. During setup every command goes here instead, so practice never touches mail.
    @ObservationIgnored var practice: (@MainActor (Command) -> Bool)?

    init() {
        Typography.register()
        onboarding = Onboarding(isReturning: session.hasSyncedBefore, hasMail: session.phase == .ready, offersAgents: true)
        agents = AgentServer(session: session)
        agents.review = { [weak self] draft in self?.review(draft) }
        notifications.send = { [weak self] id in self?.sendDraft(id) }
        keyboard = KeyboardRouter(
            perform: { [weak self] command in self?.perform(command) ?? false },
            acceptSuggestion: { [weak self] in self?.composer?.text.accept() ?? false }
        )
        keyboard?.start()
        session.openLink = { [weak self] url in self?.open(url) }
        // Undoing a move out of this tab shows the conversation again.
        session.didUndo = { [weak self] mutations in
            guard let self, case let .move(id, from, _) = mutations.first, from == self.tab.folder else { return }
            self.selection = id
        }
    }

    /// A link from a message: mail opens the composer, the web opens in the browser.
    private func open(_ url: URL) {
        switch url.scheme {
        case "mailto": composer = ComposerModel.new(app: self, mailto: url)
        case "http", "https": NSWorkspace.shared.open(url)
        default: break
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
        } catch let failure as ASWebAuthenticationSessionError where failure.code == .canceledLogin {
            return
        }
    }

    /// Asks before connecting to the server at `url`, unless it's the one already connected.
    func connect(to url: URL) {
        if session.server?.baseURL == url {
            session.toasts.show(Toast("Already connected to \(url.host() ?? url.absoluteString)", symbol: "checkmark"))
        } else {
            connectingServer = url
        }
    }

    /// Links bMail opens: `bmail://connect?server=…`, which Vercel's deploy flow sends you back with.
    func handle(_ link: URL) {
        guard let server = ServerSetup.server(in: link) else { return }
        NSApp.activate()
        connect(to: server)
    }

    // MARK: - Commands

    /// Runs a command. Returns false when it doesn't apply right now, so the key falls through to the focused view.
    @discardableResult
    func perform(_ command: Command) -> Bool {
        commandLog.debug("perform \(command.title, privacy: .public)")
        guard onboarding.isFinished else { return practice?(command) ?? false }
        guard session.phase == .ready else { return false }
        if command.needsConversation, selection == nil, checked.isEmpty { return false }

        switch command {
        case .next: return moveSelection(by: 1)
        case .previous: return moveSelection(by: -1)
        case .back: return back()
        case .markDone: move(to: tab == .done ? .inbox : .done)
        case .trash: move(to: .trash)
        case .spam: move(to: .spam)
        case .toggleStar: session.toggleStar(targets)
        case .toggleRead:
            markReadTask?.cancel()
            session.toggleRead(targets)
        case .label: isLabelPickerOpen = true
        case .unsubscribe:
            guard let id = selection else { return false }
            session.unsubscribe(from: id)
        case .toggleCheck:
            guard let id = selection else { return false }
            toggleCheck(id)
        case .extendNext, .extendPrevious:
            if let id = selection { checked.insert(id) }
            guard moveSelection(by: command == .extendNext ? 1 : -1), let id = selection else { return false }
            checked.insert(id)
        case .checkAll:
            guard !listOrder.isEmpty else { return false }
            checked = checked.count == listOrder.count ? [] : Set(listOrder)
        // Z answers the newest toast first (Undo send, Undo archive), then walks back through earlier changes.
        case .undo: return session.toasts.performLatestAction(key: "Z") || session.undo()
        case .compose: composer = ComposerModel.new(app: self)
        case .reply, .replyAll, .forward:
            guard let id = selection else { return false }
            composer = ComposerModel.respond(to: id, mode: .init(command), app: self)
        case .search: isSearchFocused = true
        case .palette: isPaletteOpen.toggle()
        case .shortcuts: isShortcutsOpen.toggle()
        case .settings: openSettings()
        case let .go(destination): tab = destination
        case .allAccounts: accountFilter = nil
        case let .account(number):
            guard let account = session.accounts[safe: number - 1] else { return false }
            accountFilter = account.id
        }
        return true
    }

    private func back() -> Bool {
        if isPaletteOpen { isPaletteOpen = false } else if isShortcutsOpen { isShortcutsOpen = false } else if isLabelPickerOpen {
            isLabelPickerOpen = false
        } else if composer?.isSuggestingRecipients == true {
            composer?.isSuggestingRecipients = false
        } else if composer?.text.dismissSuggestion() == true {
            // Esc takes the suggestions away first, and only then the composer.
        } else if composer != nil {
            composer?.close()
        } else if !checked.isEmpty {
            checked = []
        } else if searchResults != nil || isSearchFocused {
            searchText = ""
            isSearchFocused = false
        } else { return false }
        return true
    }

    private func moveSelection(by offset: Int) -> Bool {
        guard !listOrder.isEmpty else { return false }
        let index = selection.flatMap(listOrder.firstIndex(of:)) ?? (offset > 0 ? -1 : listOrder.count)
        selection = listOrder[max(0, min(listOrder.count - 1, index + offset))]
        return true
    }

    /// Moves the picked conversations, or the open one, and opens the next one left, so triage is one key per
    /// conversation.
    private func move(to folder: Folder) {
        let ids = Set(session.move(targets, to: folder).map(\.id))
        guard !ids.isEmpty else { return }
        let start = selection.flatMap(listOrder.firstIndex(of:)) ?? 0
        let next = (listOrder[start...].dropFirst() + listOrder[..<start].reversed()).first { !ids.contains($0) }
        checked = []
        if let selection, ids.contains(selection) { self.selection = next }
    }

    func toggleCheck(_ id: Conversation.ID) {
        if checked.contains(id) { checked.remove(id) } else { checked.insert(id) }
    }

    /// What triage keys act on: the picked conversations when there are any, otherwise the open one.
    var targetIDs: [Conversation.ID] {
        checked.isEmpty ? selection.map { [$0] } ?? [] : Array(checked)
    }

    private var targets: [Conversation] {
        session.conversations(targetIDs)
    }

    /// Marks a conversation read once it has been on screen for a moment, so skimming with J doesn't mark everything.
    private func scheduleMarkRead() {
        markReadTask?.cancel()
        guard let id = selection else { return }
        markReadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self, self.selection == id else { return }
            self.session.markRead(id)
        }
    }

    // MARK: - Labels

    /// Puts the label on the targets or takes it off, creating it where it doesn't exist yet.
    func toggleLabel(_ name: String) {
        session.toggleLabel(named: name, on: targetIDs)
    }

    // MARK: - Sending

    /// Closes the composer. One with something in it comes back with Undo, exactly as it was.
    func discard(_ discarded: ComposerModel) {
        if composer === discarded { composer = nil }
        guard discarded.hasContent else { return }
        session.toasts.show(Toast("Discarded", symbol: "trash", action: .init("Undo", key: "Z") { [weak self] in
            self?.composer = discarded
        }))
    }

    /// Undo brings back the composer the message came from, exactly as it was.
    func send(_ message: OutgoingMessage, from composer: ComposerModel) {
        session.send(message) { [weak self] in self?.composer = composer }
    }

    // MARK: - Agents

    /// A message an agent wrote at Ask to send. It opens in the composer once that's free, and its notification can send
    /// it from anywhere.
    private func review(_ draft: AgentDraft) {
        agentDrafts.append(draft)
        notifications.post(draft)
        if composer != nil {
            session.toasts.show(Toast("\(draft.agent) wrote a message", detail: "It opens when you're done with this one.", symbol: "envelope"))
        }
        openNextDraft()
    }

    private func openNextDraft() {
        guard composer == nil, !agentDrafts.isEmpty else { return }
        composer = ComposerModel.drafted(agentDrafts.removeFirst(), app: self)
    }

    /// Send from the notification: what's in the composer if the message is open there, otherwise what the agent wrote.
    private func sendDraft(_ id: Message.ID) {
        if let composer, composer.draft?.id == id {
            composer.send(fontContext: EnvironmentValues().fontResolutionContext)
        } else if let index = agentDrafts.firstIndex(where: { $0.id == id }) {
            let draft = agentDrafts.remove(at: index)
            session.send(draft.message, detail: "Written by \(draft.agent)") { [weak self] in self?.review(draft) }
        }
    }

    // MARK: - Attachments

    /// Downloads an attachment into Downloads and opens it.
    func open(_ attachment: Attachment, of message: Message) {
        session.toasts.show(Toast("Downloading \(attachment.filename)", symbol: "arrow.down.circle", duration: .seconds(3)))
        Task {
            do {
                let destination = attachment.freeURL(in: .downloadsDirectory)
                try await session.download(attachment, of: message).write(to: destination, options: .atomic)
                NSWorkspace.shared.open(destination)
            } catch {
                session.toasts.show(Toast("Couldn't open \(attachment.filename).", detail: error.localizedDescription, symbol: "exclamationmark.triangle", tone: .failure))
            }
        }
    }

    /// Whether Z has anything to take back: a toast's Undo or an earlier change.
    var canUndo: Bool {
        session.toasts.toasts.contains { $0.action?.key == "Z" } || session.canUndo
    }

    // MARK: - Reading

    var selectedConversation: Conversation? {
        guard let selection else { return nil }
        return session.conversations([selection]).first
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
