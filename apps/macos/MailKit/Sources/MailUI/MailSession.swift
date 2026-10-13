import DesignSystem
import Foundation
import MailCore
import Observation
import Providers
import SQLiteData

/// Your mail on this device: the cache, your server, the sync engine and every action that changes mail. Each app's
/// model owns one and puts its own navigation on top, so sending, undo and signing out work the same on the Mac and the
/// iPhone.
@MainActor
@Observable
public final class MailSession {
    public enum Phase: Sendable { case signedOut, ready }

    public let store: MailStore
    public let syncStatus = SyncStatus()
    public let toasts = ToastCenter()
    /// Gmail access, from the build's OAuth client. Without one Gmail isn't offered.
    public let google: OAuthClient?
    /// The api for your domains. Nil until you first sign in, which is where you say which server is yours.
    public private(set) var server: ServerConnection?
    public private(set) var phase: Phase = .signedOut
    /// Conversations unsubscribed from since launch, so the button can say it worked.
    public private(set) var unsubscribed: Set<Conversation.ID> = []
    /// Message bodies, loaded ahead of time. Set at the end of init: links tapped inside them need the session.
    @ObservationIgnored public private(set) var pages: MailPages!
    /// Where a link tapped in a message goes, already past our own tracking: the browser, or a composer for `mailto:`.
    @ObservationIgnored public var openLink: @MainActor (URL) -> Void = { _ in }
    /// Runs after every undo, from a key or a toast, with what it took back.
    @ObservationIgnored public var didUndo: @MainActor ([Mutation]) -> Void = { _ in }
    @ObservationIgnored private let engine: MailSyncEngine
    /// Each entry is one action, which can have changed many conversations at once. Its toast undoes that action and
    /// no other, even after newer ones.
    @ObservationIgnored private var undoStack: [(id: UUID, mutations: [Mutation])] = []

    public init(google: OAuthClient?) {
        self.google = google
        // The cache and the session belong to one server, so pointing the app at another starts signed out with an
        // empty cache. `--args -resetCache YES` empties it on purpose.
        let defaults = UserDefaults.standard
        // Builds from before the server step only recorded the server as the cache's, so that one carries over.
        let serverURL = (defaults.string(forKey: "serverURL") ?? defaults.string(forKey: "cacheServerURL")).flatMap(URL.init(string:))
        let serverChanged = defaults.string(forKey: "cacheServerURL") != serverURL?.absoluteString
        if serverChanged { Keychain.delete(ServerConnection.sessionKey) }
        defaults.set(serverURL?.absoluteString, forKey: "cacheServerURL")
        let reset = serverChanged || defaults.bool(forKey: "resetCache")
        // The cache only holds what can be synced again, so one that won't open is deleted and rebuilt.
        let database: any DatabaseWriter
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
        server = serverURL.map(ServerConnection.init(baseURL:))
        engine = MailSyncEngine(store: store, status: syncStatus)
        pages = MailPages(store: store, apiHost: { [weak self] in self?.server?.baseURL.host() }, open: { [weak self] in self?.openLink($0) })
        #if DEBUG
            // Scripted runs against a local api: `--args -sessionToken <token>` signs in without typing.
            if let token = defaults.string(forKey: "sessionToken") {
                Keychain.write(token, for: ServerConnection.sessionKey)
            }
        #endif
        if server?.isSignedIn == true { start() }
    }

    // MARK: - Signing in and out

    /// Points the app at the server typed on the sign-in screen and remembers it. The cache and the session belong to one
    /// server, so another one starts both over. Development can skip the typing: `--args -serverURL <url>`.
    @discardableResult
    public func connect(to url: URL) throws -> ServerConnection {
        if let server, server.baseURL == url { return server }
        try store.eraseAll()
        Keychain.delete(ServerConnection.sessionKey)
        UserDefaults.standard.set(url.absoluteString, forKey: "serverURL")
        UserDefaults.standard.set(url.absoluteString, forKey: "cacheServerURL")
        let server = ServerConnection(baseURL: url)
        self.server = server
        return server
    }

    /// Domain, mailbox and label changes, which go straight to your server.
    public var admin: ServerAdmin {
        get throws {
            guard let server else { throw ProviderError(.rejected, "Sign in to your server first.") }
            return ServerAdmin(connection: server)
        }
    }

    public func start() {
        phase = .ready
        pages.warmUp()
        configureProviders()
        Task { await engine.start() }
    }

    /// One provider for your domains plus one per Gmail account. Called again whenever accounts change.
    public func configureProviders() {
        guard let server else { return }
        var providers: [any MailProvider] = [ServerProvider(connection: server, store: store)]
        for account in accounts {
            switch account.kind {
            case .domain: continue
            case .gmail:
                if let google {
                    providers.append(GmailProvider(account: account, client: google, store: store, tracking: ServerTracking(connection: server)))
                }
            }
        }
        Task { [engine] in await engine.setProviders(providers) }
    }

    /// Adds a Gmail account after its OAuth sign-in. The id follows from the address, so connecting the same
    /// account again replaces it instead of adding a second one.
    public func connectGmail(tokens: OAuthTokens) throws {
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

    public func disconnect(_ account: Account) throws {
        Keychain.delete("oauth.\(account.id.uuidString)")
        var changes = ChangeSet()
        changes.removedAccountIDs = [account.id]
        try store.merge(changes, source: "settings")
        try? store.database.write { db in try SyncCursor.find("\(account.kind.rawValue):\(account.id)").delete().execute(db) }
        configureProviders()
    }

    /// Signing out makes this device forget the account: the cache and every Gmail token goes with it, so the next
    /// person to sign in starts clean.
    public func signOut() async {
        await engine.stop()
        await server?.signOut()
        for account in accounts where account.kind != .domain {
            Keychain.delete("oauth.\(account.id.uuidString)")
        }
        try? store.eraseAll()
        undoStack = []
        pages.removeAll()
        phase = .signedOut
    }

    // MARK: - Syncing

    /// Pulls right away, e.g. when the app comes to the front.
    public func syncNow() {
        engine.wake()
    }

    /// Pulls and returns once the pass is done, for pull to refresh.
    public func refresh() async {
        await engine.refresh()
    }

    /// Whether the app is on screen. Hidden, it polls every few minutes instead of every few seconds.
    public func setVisible(_ visible: Bool) {
        Task { [engine] in await engine.setVisible(visible) }
    }

    /// Sends what's waiting, for the moments after you leave the app with a message still in its undo window. Returns
    /// once the outbox and the queue are empty, or once a pass gets nothing more out and the next retry is too far off
    /// to wait for.
    public func finishPendingWork() async {
        var remaining = pendingWork
        while remaining > 0, !Task.isCancelled {
            if let next = try? store.nextOutboxDate(), next > .now {
                try? await Task.sleep(for: .seconds(next.timeIntervalSinceNow))
            }
            await engine.refresh()
            let left = pendingWork
            let retry = (try? store.nextOutboxDate()) ?? .distantFuture
            if left >= remaining, retry > .now.addingTimeInterval(20) { return }
            remaining = left
        }
    }

    private var pendingWork: Int {
        ((try? store.dueOutboxItems(at: .distantFuture).count) ?? 0) + ((try? store.pendingMutations().count) ?? 0)
    }

    // MARK: - Changing conversations

    /// Applies mutations here first and queues them for their providers, with a toast that undoes them.
    public func apply(_ mutations: [Mutation], toast: String?) {
        guard !mutations.isEmpty else { return }
        do {
            try store.perform(mutations)
            let id = UUID()
            undoStack.append((id, mutations))
            engine.wake()
            if let toast {
                toasts.show(Toast(toast, action: .init("Undo", key: "Z") { [weak self] in _ = self?.undo(id) }))
            }
        } catch {
            toasts.show(Toast("Couldn't save that change.", detail: error.localizedDescription, symbol: "exclamationmark.triangle", tone: .failure))
        }
    }

    /// Takes back the last action. False when there's nothing left to undo.
    @discardableResult
    public func undo() -> Bool {
        guard let last = undoStack.last else { return false }
        return undo(last.id)
    }

    private func undo(_ id: UUID) -> Bool {
        guard let index = undoStack.firstIndex(where: { $0.id == id }) else { return false }
        let mutations = undoStack.remove(at: index).mutations
        try? store.perform(mutations.reversed().map(\.inverse))
        engine.wake()
        toasts.show(Toast("Undone", symbol: "arrow.uturn.backward"))
        didUndo(mutations)
        return true
    }

    /// Moves conversations that aren't in `folder` yet. Returns the ones it moved.
    @discardableResult
    public func move(_ conversations: [Conversation], to folder: Folder) -> [Conversation] {
        let moving = conversations.filter { $0.folder != folder }
        guard !moving.isEmpty else { return [] }
        let toast = moving.count == 1 ? folder.doneMessage : "\(moving.count) conversations: \(folder.doneMessage.lowercased())"
        apply(moving.map { .move($0.id, from: $0.folder, to: folder) }, toast: toast)
        return moving
    }

    /// Mixed picks all get the star; only when every one has it does it come off.
    public func toggleStar(_ conversations: [Conversation]) {
        let star = conversations.contains { !$0.isStarred }
        apply(conversations.map { .setStarred($0.id, star) }, toast: star ? "Starred" : "Unstarred")
    }

    public func toggleRead(_ conversations: [Conversation]) {
        let read = conversations.contains { !$0.isRead }
        apply(conversations.map { .setRead($0.id, read) }, toast: read ? "Marked as read" : "Marked as unread")
    }

    /// Opening a conversation reads it. No toast and nothing to undo: it's not something you did on purpose.
    public func markRead(_ id: Conversation.ID) {
        guard let conversation = conversations([id]).first, !conversation.isRead else { return }
        try? store.perform([.setRead(id, true)])
        engine.wake()
    }

    /// The conversations behind `ids`, as they are now.
    public func conversations(_ ids: [Conversation.ID]) -> [Conversation] {
        (try? store.database.read { db in try Conversation.where { $0.id.in(ids) }.fetchAll(db) }) ?? []
    }

    // MARK: - Labels

    /// Puts the label on every conversation, or takes it off when they all have it already.
    public func toggleLabel(_ labelID: MailLabel.ID, on ids: [Conversation.ID]) {
        guard !ids.isEmpty, let label = try? store.database.read({ db in try MailLabel.find(labelID).fetchOne(db) }) else { return }
        let labeled = Set((try? store.database.read { db in
            try ConversationLabel.where { $0.labelID.eq(labelID) && $0.conversationID.in(ids) }.select(\.conversationID).fetchAll(db)
        }) ?? [])
        let isOn = labeled.count < ids.count
        apply(ids.filter { labeled.contains($0) != isOn }.map { .label($0, labelID, isOn) }, toast: isOn ? "Labeled \(label.name)" : "Removed \(label.name)")
    }

    /// Creates a label on the api and puts it on the conversations.
    public func createLabel(named name: String, on ids: [Conversation.ID]) {
        let label = MailLabel(id: UUID(), name: name.trimmingCharacters(in: .whitespaces))
        guard !label.name.isEmpty else { return }
        Task {
            do {
                try store.merge(try await admin.createLabel(label), source: "labels")
                toggleLabel(label.id, on: ids)
            } catch {
                toasts.show(Toast("Couldn't create \(label.name).", detail: error.localizedDescription, symbol: "exclamationmark.triangle", tone: .failure))
            }
        }
    }

    // MARK: - Unsubscribe

    /// Whether the conversation came from a mailing list that says how to leave it.
    public func canUnsubscribe(from id: Conversation.ID) -> Bool {
        unsubscribeTarget(of: id) != nil
    }

    /// Leaves the mailing list behind a conversation: one-click where the sender supports it, otherwise a message to its
    /// unsubscribe address, otherwise its page in the browser.
    public func unsubscribe(from id: Conversation.ID) {
        guard let message = unsubscribeTarget(of: id), let target = message.unsubscribe else {
            let sender = conversations([id]).first?.participants ?? "This sender"
            toasts.show(Toast("\(sender) doesn't offer a way to unsubscribe.", symbol: "bell.slash"))
            return
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
                openLink(url)
                toasts.show(Toast("Finish unsubscribing from \(sender) in your browser.", symbol: "bell.slash"))
            }
        }
    }

    private func unsubscribeTarget(of id: Conversation.ID) -> Message? {
        try? store.database.read { db in
            try Message.where { $0.conversationID.eq(id) && $0.direction.eq(Direction.inbound) && $0.unsubscribe.isNot(nil) }
                .order { $0.sentAt.desc() }
                .fetchOne(db)
        }
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

    /// How long a message waits before it goes, so Undo can still take it back.
    public static let undoWindow = 10

    /// Holds the message for the undo window, then the sync engine sends it. Undo takes it out of the outbox and calls
    /// `reopen`, which brings back the composer it came from.
    public func send(_ message: OutgoingMessage, reopen: @escaping @MainActor () -> Void) {
        do {
            try store.enqueue(message, sendAt: Date().addingTimeInterval(TimeInterval(Self.undoWindow)))
            engine.wake()
            let toast = Toast(
                "Sending in \(Self.undoWindow)s",
                symbol: "paperplane",
                action: .init("Undo", key: "Z") { [weak self] in self?.cancelSend(message.id, reopen: reopen) },
                duration: .seconds(Self.undoWindow)
            )
            toasts.show(toast)
            Task { [toasts] in
                for remaining in stride(from: Self.undoWindow - 1, through: 1, by: -1) {
                    try? await Task.sleep(for: .seconds(1))
                    toasts.update(toast.id, title: "Sending in \(remaining)s")
                }
            }
        } catch {
            toasts.show(Toast("Couldn't queue the message.", detail: error.localizedDescription, symbol: "exclamationmark.triangle", tone: .failure))
        }
    }

    private func cancelSend(_ id: Message.ID, reopen: @MainActor () -> Void) {
        guard (try? store.cancelSend(id)) != nil else {
            toasts.show(Toast("Too late, it's already on its way.", symbol: "paperplane"))
            return
        }
        reopen()
    }

    // MARK: - Reading

    public var accounts: [Account] {
        (try? store.database.read { db in try Account.order(by: \.position).fetchAll(db) }) ?? []
    }

    /// Conversation ids matching `query`, best first. Nil when there's nothing to search for.
    public func search(_ query: String) -> [Conversation.ID]? {
        let query = query.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? nil : (try? store.search(query)) ?? []
    }

    /// An attachment's bytes. Links and Gmail's ids expire, so every open fetches fresh.
    public func download(_ attachment: Attachment, of message: Message) async throws -> Data {
        guard let server, let account = accounts.first(where: { $0.id == message.accountID }) else {
            throw ProviderError(.rejected, "That account is gone.")
        }
        switch account.kind {
        case .domain:
            let url = try await ServerProvider(connection: server, store: store).downloadURL(for: attachment.id)
            return try await URLSession.shared.data(from: url).0
        case .gmail:
            guard let google else { throw ProviderError(.rejected, "This build can't reach Gmail.") }
            return try await GmailProvider(account: account, client: google, store: store, tracking: ServerTracking(connection: server))
                .download(attachment)
        }
    }
}
