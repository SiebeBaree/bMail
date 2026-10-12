import AppKit
import DesignSystem
import Foundation
import MailCore
import MailUI
import Observation
import OSLog

private let commandLog = Logger(subsystem: "be.baree.mail", category: "Commands")

/// The app's state and the one place commands are carried out, whether they come from a key, the palette or the menu.
/// What changes mail lives in the session, which the iPhone app shares; this adds the Mac's selection and keys.
@MainActor
@Observable
final class AppModel {
    let session = MailSession(google: BuildSettings.google)
    @ObservationIgnored private var keyboard: KeyboardRouter?
    @ObservationIgnored private var markReadTask: Task<Void, Never>?

    var tab: MailTab = .inbox {
        didSet {
            labelFilter = nil
            if tab != oldValue { selection = nil; checked = [] }
        }
    }
    /// A label's conversations instead of the tab's. Picking a tab leaves it.
    var labelFilter: MailLabel.ID? {
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
    var composer: ComposerModel?
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

    init() {
        Typography.register()
        keyboard = KeyboardRouter { [weak self] command in self?.perform(command) ?? false }
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

    func signOut() async {
        await session.signOut()
        selection = nil
    }

    // MARK: - Commands

    /// Runs a command. Returns false when it doesn't apply right now, so the key falls through to the focused view.
    @discardableResult
    func perform(_ command: Command) -> Bool {
        commandLog.debug("perform \(command.title, privacy: .public)")
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
        } else if composer != nil {
            composer?.close()
        } else if !checked.isEmpty {
            checked = []
        } else if searchResults != nil {
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

    func toggleLabel(_ labelID: MailLabel.ID) {
        session.toggleLabel(labelID, on: targetIDs)
    }

    func createLabel(named name: String) {
        session.createLabel(named: name, on: targetIDs)
    }

    // MARK: - Sending

    func send(_ message: OutgoingMessage) {
        session.send(message) { [weak self] message in
            guard let self else { return }
            self.composer = ComposerModel.reopen(message, app: self)
        }
    }

    // MARK: - Attachments

    /// Downloads an attachment into Downloads and opens it.
    func open(_ attachment: Attachment, of message: Message) {
        session.toasts.show(Toast("Downloading \(attachment.filename)", symbol: "arrow.down.circle", duration: .seconds(3)))
        Task {
            do {
                let destination = URL.downloadsDirectory.appending(path: attachment.filename)
                try await session.download(attachment, of: message).write(to: destination, options: .atomic)
                NSWorkspace.shared.open(destination)
            } catch {
                session.toasts.show(Toast("Couldn't open \(attachment.filename).", detail: error.localizedDescription, symbol: "exclamationmark.triangle", tone: .failure))
            }
        }
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
