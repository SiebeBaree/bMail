import AppKit
import DesignSystem
import Foundation
import MailCore
import Observation
import OSLog
import Providers
import SQLiteData

private let commandLog = Logger(subsystem: "be.baree.mail", category: "Commands")

/// The app's state and the one place commands are carried out, whether they come from a key, the palette or the menu.
@MainActor
@Observable
final class AppModel {
    enum Phase { case signedOut, ready }

    let store: MailStore
    let syncStatus = SyncStatus()
    let toasts = ToastCenter()
    let server: ServerConnection
    @ObservationIgnored private let engine: MailSyncEngine
    @ObservationIgnored private var keyboard: KeyboardRouter?
    /// Each entry is one action, which can have changed many conversations at once.
    @ObservationIgnored private var undoStack: [[Mutation]] = []
    @ObservationIgnored private var markReadTask: Task<Void, Never>?
    /// Set at the end of init: it needs the model itself, for links clicked inside a message.
    @ObservationIgnored private(set) var pages: MailPages!

    var phase: Phase = .signedOut
    var tab: Tab = .inbox {
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
        didSet { runSearch() }
    }
    /// Conversation ids matching `searchText`, best first. Nil when not searching.
    var searchResults: [Conversation.ID]?
    @ObservationIgnored var openSettings: () -> Void = {}

    init() {
        Typography.register()
        // The cache only holds what can be synced again, so one that won't open is deleted and rebuilt.
        let database: any DatabaseWriter
        // The cache and the session belong to one server, so pointing the app at another starts signed out with an
        // empty cache. `--args -resetCache YES` empties it on purpose.
        let defaults = UserDefaults.standard
        let serverChanged = defaults.string(forKey: "cacheServerURL") != Self.serverURL.absoluteString
        if serverChanged { Keychain.delete(ServerConnection.sessionKey) }
        defaults.set(Self.serverURL.absoluteString, forKey: "cacheServerURL")
        let reset = serverChanged || defaults.bool(forKey: "resetCache")
        do {
            database = try appDatabase(reset: reset)
        } catch {
            do {
                database = try appDatabase(reset: true)
            } catch {
                fatalError("The local mail cache couldn't be created: \(error)")
            }
        }
        prepareDependencies { $0.defaultDatabase = database }
        store = MailStore(database: database)
        server = ServerConnection(baseURL: Self.serverURL)
        engine = MailSyncEngine(store: store, status: syncStatus)
        keyboard = KeyboardRouter { [weak self] command in self?.perform(command) ?? false }
        keyboard?.start()
        pages = MailPages(model: self)
        #if DEBUG
            // Scripted runs against a local api: `open … --args -sessionToken <token>` signs in without typing.
            if let token = UserDefaults.standard.string(forKey: "sessionToken") {
                Keychain.write(token, for: ServerConnection.sessionKey)
            }
        #endif
        if server.isSignedIn { start() }
    }

    /// Production unless overridden for development: `open … --args -serverURL http://localhost:4317`. The app is
    /// sandboxed, so `defaults write` from outside can't set it.
    static var serverURL: URL {
        UserDefaults.standard.string(forKey: "serverURL").flatMap(URL.init(string:))
            ?? URL(string: "https://api.mail.baree.be")!
    }

    func start() {
        phase = .ready
        pages.warmUp()
        configureProviders()
        Task { await engine.start() }
    }

    /// One provider for your domains plus one per Gmail account. Called again whenever accounts change.
    func configureProviders() {
        var providers: [any MailProvider] = [ServerProvider(connection: server, store: store)]
        for account in accounts {
            switch account.kind {
            case .domain: continue
            case .gmail:
                if let client = BuildSettings.google {
                    providers.append(GmailProvider(account: account, client: client, store: store, tracking: ServerTracking(connection: server)))
                }
            }
        }
        Task { [engine] in await engine.setProviders(providers) }
    }

    /// Adds a Gmail account after its OAuth sign-in. The id follows from the address, so connecting the same
    /// account again replaces it instead of adding a second one.
    func connectGmail(tokens: OAuthTokens) throws {
        guard let address = tokens.email?.lowercased() else {
            throw ProviderError(.rejected, "The sign-in didn't say which account it was for. Try again.")
        }
        let account = Account(
            id: UUID(stableFrom: "gmail:\(address)"), kind: .gmail, address: address,
            displayName: address, domainID: nil, position: 1_000 + accounts.count
        )
        try TokenStore.save(tokens, for: account.id)
        var changes = ChangeSet()
        changes.accounts = [account]
        try store.merge(changes, source: "settings")
        configureProviders()
        toasts.show(Toast("Connected \(address)", detail: "Your mail is syncing.", symbol: "checkmark", tone: .success))
    }

    func disconnect(_ account: Account) throws {
        Keychain.delete("oauth.\(account.id.uuidString)")
        var changes = ChangeSet()
        changes.removedAccountIDs = [account.id]
        try store.merge(changes, source: "settings")
        try? store.database.write { db in try SyncCursor.find("\(account.kind.rawValue):\(account.id)").delete().execute(db) }
        configureProviders()
    }

    /// Signing out makes this Mac forget the account: the cache and every Gmail token goes with it, so the next
    /// person to sign in starts clean.
    func signOut() async {
        await engine.stop()
        await server.signOut()
        for account in accounts where account.kind != .domain {
            Keychain.delete("oauth.\(account.id.uuidString)")
        }
        try? store.eraseAll()
        selection = nil
        phase = .signedOut
    }

    /// Pulls right away, e.g. when the window comes to the front.
    func syncNow() {
        engine.wake()
    }

    /// Whether any window is on screen. Hidden, the app polls every few minutes instead of every few seconds.
    func setVisible(_ visible: Bool) {
        Task { [engine] in await engine.setVisible(visible) }
    }

    // MARK: - Commands

    /// Runs a command. Returns false when it doesn't apply right now, so the key falls through to the focused view.
    @discardableResult
    func perform(_ command: Command) -> Bool {
        commandLog.debug("perform \(command.title, privacy: .public)")
        guard phase == .ready else { return false }
        if command.needsConversation, selection == nil, checked.isEmpty { return false }

        switch command {
        case .next: return moveSelection(by: 1)
        case .previous: return moveSelection(by: -1)
        case .back: return back()
        case .markDone: move(to: tab == .done ? .inbox : .done)
        case .trash: move(to: .trash)
        case .spam: move(to: .spam)
        case .toggleStar:
            let targets = targets
            // Mixed picks all get the star; only when every one has it does S take it away.
            let star = targets.contains { !$0.isStarred }
            apply(targets.map { .setStarred($0.id, star) }, toast: star ? "Starred" : "Unstarred")
        case .toggleRead:
            let targets = targets
            let read = targets.contains { !$0.isRead }
            markReadTask?.cancel()
            apply(targets.map { .setRead($0.id, read) }, toast: read ? "Marked as read" : "Marked as unread")
        case .label: isLabelPickerOpen = true
        case .unsubscribe: return unsubscribe()
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
        case .undo: return toasts.performLatestAction(key: "Z") || undo()
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
            guard let account = accounts[safe: number - 1] else { return false }
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
        let moving = targets.filter { $0.folder != folder }
        guard !moving.isEmpty else { return }
        let ids = Set(moving.map(\.id))
        let start = selection.flatMap(listOrder.firstIndex(of:)) ?? 0
        let next = (listOrder[start...].dropFirst() + listOrder[..<start].reversed()).first { !ids.contains($0) }
        let toast = moving.count == 1 ? folder.doneMessage : "\(moving.count) conversations: \(folder.doneMessage.lowercased())"
        apply(moving.map { .move($0.id, from: $0.folder, to: folder) }, toast: toast)
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
        let ids = targetIDs
        return (try? store.database.read { db in try Conversation.where { $0.id.in(ids) }.fetchAll(db) }) ?? []
    }

    func apply(_ mutations: [Mutation], toast: String?) {
        guard !mutations.isEmpty else { return }
        do {
            try store.perform(mutations)
            undoStack.append(mutations)
            engine.wake()
            if let toast {
                toasts.show(Toast(toast, action: .init("Undo", key: "Z") { [weak self] in _ = self?.undo() }))
            }
        } catch {
            toasts.show(Toast("Couldn't save that change.", detail: error.localizedDescription, symbol: "exclamationmark.triangle", tone: .failure))
        }
    }

    private func undo() -> Bool {
        guard let mutations = undoStack.popLast() else { return false }
        try? store.perform(mutations.reversed().map(\.inverse))
        engine.wake()
        if case let .move(id, from, _) = mutations.first, from == tabFolder { selection = id }
        toasts.show(Toast("Undone", symbol: "arrow.uturn.backward"))
        return true
    }

    /// Marks a conversation read once it has been on screen for a moment, so skimming with J doesn't mark everything.
    private func scheduleMarkRead() {
        markReadTask?.cancel()
        guard let id = selection else { return }
        markReadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self, self.selection == id, let conversation = self.selectedConversation,
                !conversation.isRead
            else { return }
            try? self.store.perform([.setRead(id, true)])
            self.engine.wake()
        }
    }

    // MARK: - Labels

    /// Puts the label on every target, or takes it off when they all have it already.
    func toggleLabel(_ labelID: MailLabel.ID) {
        let ids = targetIDs
        guard !ids.isEmpty, let label = try? store.database.read({ db in try MailLabel.find(labelID).fetchOne(db) }) else { return }
        let labeled = Set((try? store.database.read { db in
            try ConversationLabel.where { $0.labelID.eq(labelID) && $0.conversationID.in(ids) }.select(\.conversationID).fetchAll(db)
        }) ?? [])
        let isOn = labeled.count < ids.count
        apply(ids.filter { labeled.contains($0) != isOn }.map { .label($0, labelID, isOn) }, toast: isOn ? "Labeled \(label.name)" : "Removed \(label.name)")
    }

    /// Creates a label on the api and puts it on the targets.
    func createLabel(named name: String) {
        let label = MailLabel(id: UUID(), name: name.trimmingCharacters(in: .whitespaces))
        guard !label.name.isEmpty else { return }
        Task {
            do {
                try store.merge(try await ServerAdmin(connection: server).createLabel(label), source: "labels")
                toggleLabel(label.id)
            } catch {
                toasts.show(Toast("Couldn't create \(label.name).", detail: error.localizedDescription, symbol: "exclamationmark.triangle", tone: .failure))
            }
        }
    }

    // MARK: - Unsubscribe

    /// Conversations unsubscribed from since launch, so the button can say it worked.
    var unsubscribed: Set<Conversation.ID> = []

    /// Leaves the mailing list behind the open conversation: one-click where the sender supports it, otherwise a
    /// message to its unsubscribe address, otherwise its page in the browser.
    private func unsubscribe() -> Bool {
        guard let id = selection else { return false }
        let message = try? store.database.read { db in
            try Message.where { $0.conversationID.eq(id) && $0.direction.eq(Direction.inbound) && $0.unsubscribe.isNot(nil) }
                .order { $0.sentAt.desc() }
                .fetchOne(db)
        }
        guard let message, let target = message.unsubscribe else {
            toasts.show(Toast("\(selectedConversation?.participants ?? "This sender") doesn't offer a way to unsubscribe.", symbol: "bell.slash"))
            return true
        }
        let sender = message.from.displayName
        Task {
            if target.isOneClick, let url = target.url, await postOneClick(url) {
                unsubscribed.insert(id)
                toasts.show(Toast("Unsubscribed from \(sender)", symbol: "bell.slash", tone: .success))
            } else if let mailto = target.mailto, let account = accounts.first(where: { $0.id == message.accountID }),
                let request = OutgoingMessage(unsubscribing: mailto, from: account) {
                try? store.enqueue(request, sendAt: .now)
                engine.wake()
                unsubscribed.insert(id)
                toasts.show(Toast("Unsubscribed from \(sender)", detail: "Sent the request to \(request.to.first?.email ?? "them").", symbol: "bell.slash", tone: .success))
            } else if let url = target.url {
                NSWorkspace.shared.open(url)
                toasts.show(Toast("Finish unsubscribing from \(sender) in your browser.", symbol: "bell.slash"))
            }
        }
        return true
    }

    /// RFC 8058: a POST with exactly this body, no cookies and no redirects to follow by hand.
    private func postOneClick(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        request.httpBody = Data("List-Unsubscribe=One-Click".utf8)
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
    }

    // MARK: - Sending

    /// Holds the message for the undo window, then the sync engine sends it.
    func send(_ message: OutgoingMessage) {
        let undoWindow: TimeInterval = 10
        do {
            try store.enqueue(message, sendAt: Date().addingTimeInterval(undoWindow))
            engine.wake()
            let toast = Toast(
                "Sending in \(Int(undoWindow))s",
                symbol: "paperplane",
                action: .init("Undo", key: "Z") { [weak self] in self?.cancelSend(message.id) },
                duration: .seconds(undoWindow)
            )
            toasts.show(toast)
            Task { [toasts] in
                for remaining in stride(from: Int(undoWindow) - 1, through: 1, by: -1) {
                    try? await Task.sleep(for: .seconds(1))
                    toasts.update(toast.id, title: "Sending in \(remaining)s")
                }
            }
        } catch {
            toasts.show(Toast("Couldn't queue the message.", detail: error.localizedDescription, symbol: "exclamationmark.triangle", tone: .failure))
        }
    }

    private func cancelSend(_ id: Message.ID) {
        guard let message = try? store.cancelSend(id) else {
            toasts.show(Toast("Too late, it's already on its way.", symbol: "paperplane"))
            return
        }
        composer = ComposerModel.reopen(message, app: self)
    }

    // MARK: - Attachments

    /// Downloads an attachment into Downloads and opens it. Links and Gmail's ids expire, so each open fetches fresh.
    func open(_ attachment: Attachment, of message: Message) {
        guard let account = accounts.first(where: { $0.id == message.accountID }) else { return }
        toasts.show(Toast("Downloading \(attachment.filename)", symbol: "arrow.down.circle", duration: .seconds(3)))
        Task {
            do {
                let destination = URL.downloadsDirectory.appending(path: attachment.filename)
                let data: Data
                switch account.kind {
                case .domain:
                    let url = try await ServerProvider(connection: server, store: store).downloadURL(for: attachment.id)
                    data = try await URLSession.shared.data(from: url).0
                case .gmail:
                    guard let client = BuildSettings.google else { return }
                    data = try await GmailProvider(account: account, client: client, store: store, tracking: ServerTracking(connection: server))
                        .download(attachment)
                }
                try data.write(to: destination, options: .atomic)
                NSWorkspace.shared.open(destination)
            } catch {
                toasts.show(Toast("Couldn't open \(attachment.filename).", detail: error.localizedDescription, symbol: "exclamationmark.triangle", tone: .failure))
            }
        }
    }

    // MARK: - Search

    private func runSearch() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        searchResults = query.isEmpty ? nil : (try? store.search(query)) ?? []
    }

    // MARK: - Reading

    var accounts: [Account] {
        (try? store.database.read { db in try Account.order(by: \.position).fetchAll(db) }) ?? []
    }

    var selectedConversation: Conversation? {
        guard let selection else { return nil }
        return try? store.database.read { db in try Conversation.find(selection).fetchOne(db) }
    }

    /// The folder the current tab shows, when it is one.
    private var tabFolder: Folder? {
        switch tab {
        case .inbox: .inbox
        case .done: .done
        case .spam: .spam
        case .trash: .trash
        default: nil
        }
    }
}

extension Folder {
    var doneMessage: String {
        switch self {
        case .inbox: "Moved to inbox"
        case .done: "Marked as done"
        case .spam: "Reported as spam"
        case .trash: "Moved to trash"
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
