import Assist
import DesignSystem
import Foundation
import MailCore
import Observation
import Providers
import SQLiteData

/// Your mail on this device: the cache, your server, the sync engine and every action that changes mail. Each app's
/// model owns one and puts its own navigation on top, so sending, undo and connecting accounts work the same on the
/// Mac and the iPhone.
///
/// There's no account to sign in to. The app is ready as soon as it has a mail account or your server, and both live
/// in iCloud Keychain, so what you add on one device shows up on the others.
@MainActor
@Observable
public final class MailSession {
    /// `welcome` until there's a mail account or a server to read from.
    public enum Phase: Sendable { case welcome, ready }

    public let store: MailStore
    public let syncStatus = SyncStatus()
    public let toasts = ToastCenter()
    /// Your AI provider, key and features on this device.
    public let ai = AISettings()
    /// The last thing that went wrong talking to the AI provider, for Settings. Cleared by the next request that works.
    public internal(set) var aiProblem: String?
    /// Gmail access, from the build's OAuth client. Without one Gmail isn't offered.
    public let google: OAuthClient?
    /// The api you host for your own domains and tracking. Nil until you connect one.
    public private(set) var server: ServerConnection?
    public private(set) var phase: Phase = .welcome
    /// Conversations unsubscribed from since launch, so the button can say it worked.
    public private(set) var unsubscribed: Set<Conversation.ID> = []
    /// Message bodies, loaded ahead of time. Set at the end of init: links tapped inside them need the session.
    @ObservationIgnored public private(set) var pages: MailPages!
    /// Where a link tapped in a message goes, already past our own tracking: the browser, or a composer for `mailto:`.
    @ObservationIgnored public var openLink: @MainActor (URL) -> Void = { _ in }
    /// Runs after every undo, from a key or a toast, with what it took back.
    @ObservationIgnored public var didUndo: @MainActor ([Mutation]) -> Void = { _ in }
    @ObservationIgnored private let engine: MailSyncEngine
    @ObservationIgnored private var labeller: Labeller!
    @ObservationIgnored private var isStarted = false
    /// Each entry is one action, which can have changed many conversations at once. Its toast undoes that action and
    /// no other, even after newer ones.
    @ObservationIgnored private var undoStack: [(id: UUID, mutations: [Mutation])] = []

    public init(google: OAuthClient?) {
        self.google = google
        // The cache only holds what can be synced again, so one that won't open is deleted and rebuilt.
        // `--args -resetCache YES` empties it on purpose.
        let database: any DatabaseWriter
        do {
            database = try appDatabase(reset: UserDefaults.standard.bool(forKey: "resetCache"))
        } catch {
            do {
                database = try appDatabase(reset: true)
            } catch {
                fatalError("The local mail cache couldn't be created: \(error)")
            }
        }
        prepareDependencies { $0.defaultDatabase = database }
        store = MailStore(database: database)
        engine = MailSyncEngine(store: store, status: syncStatus)
        #if DEBUG
            // Scripted runs against a local api: `--args -serverURL <url> -sessionToken <token>` connects without claiming.
            let defaults = UserDefaults.standard
            if let url = defaults.string(forKey: "serverURL").flatMap(URL.init(string:)), let token = defaults.string(forKey: "sessionToken") {
                ServerLink(url: url, token: token).save()
            }
        #endif
        server = ServerLink.load().map(ServerConnection.init)
        pages = MailPages(store: store, apiHost: { [weak self] in self?.server?.baseURL.host() }, open: { [weak self] in self?.openLink($0) })
        labeller = Labeller(session: self)
        adoptAccountsFromKeychain()
        updatePhase()
    }

    // MARK: - Accounts and your server

    /// Whether mail can go out tracked: tracking runs on your server.
    public var canTrack: Bool { server != nil }

    /// Domain, mailbox, label and Resend changes, which go straight to your server.
    public var admin: ServerAdmin {
        get throws {
            guard let server else { throw ProviderError(.rejected, "Connect your server first.") }
            return ServerAdmin(connection: server)
        }
    }

    /// Ready once there's something to read from. The engine starts the first time it is.
    private func updatePhase() {
        phase = accounts.isEmpty && server == nil ? .welcome : .ready
        guard phase == .ready, !isStarted else { return }
        isStarted = true
        pages.warmUp()
        configureProviders()
        let afterPass: @Sendable () -> Void = { [weak self] in Task { @MainActor in self?.labeller.run() } }
        Task {
            await engine.setAfterPass(afterPass)
            await engine.start()
            await moveServerLabelsToGmail()
        }
    }

    /// One provider for your server plus one per Gmail account. Called again whenever accounts change.
    public func configureProviders() {
        let tracking = server.map(ServerTracking.init(connection:))
        var providers: [any MailProvider] = server.map { [ServerProvider(connection: $0, store: store)] } ?? []
        if let google {
            for account in accounts where account.kind == .gmail {
                providers.append(GmailProvider(account: account, client: google, store: store, tracking: tracking))
            }
        }
        Task { [engine] in await engine.setProviders(providers) }
    }

    /// Adds a Gmail account after its OAuth sign-in. The id follows from the address, so connecting the same account
    /// again, here or on another device, replaces it instead of adding a second one.
    public func connectGmail(tokens: OAuthTokens) throws {
        guard let address = tokens.email?.lowercased() else {
            throw ProviderError(.rejected, "The sign-in didn't say which account it was for. Try again.")
        }
        let account = gmailAccount(address)
        try TokenStore.save(tokens, for: account.id)
        var changes = ChangeSet()
        changes.accounts = [account]
        try store.merge(changes, source: "settings")
        configureProviders()
        updatePhase()
        toasts.show(Toast("Connected \(address)", detail: "Your mail is syncing.", symbol: "checkmark", tone: .success))
    }

    private func gmailAccount(_ address: String) -> Account {
        Account(
            id: UUID(stableFrom: "gmail:\(address)"), kind: .gmail, address: address,
            displayName: address, domainID: nil, position: 1_000 + accounts.count
        )
    }

    /// Removes a Gmail account from every device, since its tokens leave iCloud Keychain with it.
    public func disconnect(_ account: Account) throws {
        TokenStore.forget(account.id)
        var changes = ChangeSet()
        changes.removedAccountIDs = [account.id]
        try store.merge(changes, source: "settings")
        try? store.database.write { db in try SyncCursor.find("\(account.kind.rawValue):\(account.id)").delete().execute(db) }
        configureProviders()
        updatePhase()
    }

    /// Gmail accounts added or removed on another device, which only says so through iCloud Keychain. Runs at launch
    /// and whenever the app comes back to the front.
    private func adoptAccountsFromKeychain() {
        guard google != nil, let keys = Keychain.keys(withPrefix: TokenStore.keyPrefix) else { return }
        let stored = Set(accounts.filter { $0.kind == .gmail }.map(\.id))
        let synced = Set(keys.compactMap { UUID(uuidString: String($0.dropFirst(TokenStore.keyPrefix.count))) })
        let added = synced.subtracting(stored).compactMap { id in
            TokenStore.load(for: id)?.email.map { gmailAccount($0.lowercased()) }.flatMap { $0.id == id ? $0 : nil }
        }
        let removed = stored.subtracting(synced)
        guard !added.isEmpty || !removed.isEmpty else { return }
        var changes = ChangeSet()
        changes.accounts = added
        changes.removedAccountIDs = Array(removed)
        try? store.merge(changes, source: "settings")
        configureProviders()
        updatePhase()
    }

    /// Whether a bMail server answers at `url`, and whether it has an owner yet.
    public func ownership(of url: URL) async throws -> ServerConnection.Ownership {
        try await ServerConnection(baseURL: url).ownership()
    }

    /// Becomes the owner of the server at `url` and connects to it. A server that has an owner takes its claim code.
    public func claimServer(at url: URL, code: String? = nil) async throws {
        let link = try await ServerConnection(baseURL: url).claim(code: code)
        link.save()
        adopt(link)
        toasts.show(Toast("Connected to \(server?.host ?? url.absoluteString)", symbol: "checkmark", tone: .success))
    }

    /// Switches to `link`. What came from another server, its domains, labels and tracking, goes; Gmail stays.
    private func adopt(_ link: ServerLink) {
        if let server, server.baseURL != link.url { try? store.eraseServerData() }
        server = ServerConnection(link)
        configureProviders()
        updatePhase()
        engine.wake()
    }

    /// Forgets your server on every device, with your domains' mail and all tracking. Gmail stays.
    public func disconnectServer() {
        ServerLink.forget()
        try? store.eraseServerData()
        server = nil
        configureProviders()
        updatePhase()
    }

    // MARK: - Syncing

    /// Pulls right away, e.g. when the app comes to the front. Also picks up accounts and a server added on another
    /// device.
    public func syncNow() {
        adoptAccountsFromKeychain()
        if server == nil, let link = ServerLink.load() { adopt(link) }
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

    /// Whether `undo()` has an earlier change to take back.
    public var canUndo: Bool { !undoStack.isEmpty }

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

    /// Puts the label called `name` on every conversation, or takes it off when they all have it already. Gmail mail
    /// gets its account's Gmail label and the rest gets your server's, each made first where it doesn't exist yet.
    /// `toast` replaces the usual "Labeled …", for agents that say who did it.
    public func toggleLabel(named name: String, on ids: [Conversation.ID], toast: String? = nil) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !ids.isEmpty, let owners = try? store.labelOwners(of: ids) else { return }
        let labels = (try? self.labels(named: name)) ?? []
        let assigned = (try? store.database.read { db in
            try ConversationLabel.where { $0.labelID.in(labels.map(\.id)) && $0.conversationID.in(ids) }.fetchAll(db)
        }) ?? []
        let labeled = Set(assigned.map(\.conversationID))
        let isOn = labeled.count < ids.count
        guard isOn else {
            apply(assigned.map { .label($0.conversationID, $0.labelID, false) }, toast: toast ?? "Removed \(name)")
            return
        }
        let unlabeled = ids.filter { !labeled.contains($0) && owners[$0] != nil }
        let missing = Set(unlabeled.map { owners[$0] ?? nil }).filter { owner in !labels.contains { $0.accountID == owner } }
        Task {
            var labels = labels
            for owner in missing {
                do {
                    labels.append(try await createLabel(named: name, for: owner))
                } catch {
                    toasts.show(Toast("Couldn't create \(name).", detail: error.localizedDescription, symbol: "exclamationmark.triangle", tone: .failure))
                    return
                }
            }
            let mutations = unlabeled.compactMap { id -> Mutation? in
                labels.first { $0.accountID == owners[id] ?? nil }.map { .label(id, $0.id, true) }
            }
            apply(mutations, toast: toast ?? "Labeled \(name)")
        }
    }

    /// Makes the label in Gmail for a Gmail account's mail, or on your server (`owner` nil) for the rest.
    private func createLabel(named name: String, for owner: Account.ID?) async throws -> MailLabel {
        let label: MailLabel
        if let owner, let account = accounts.first(where: { $0.id == owner }) {
            label = try await gmail(account).createLabel(named: name)
        } else {
            // The id is the app's, so a retry after a lost response returns the same label instead of a duplicate.
            label = MailLabel(id: UUID(), name: name)
            try store.merge(try await admin.createLabel(label), source: "labels")
            return label
        }
        var changes = ChangeSet()
        changes.labels = [label]
        try store.merge(changes, source: "labels")
        return label
    }

    /// Renames every label called `name`, in Gmail and on your server.
    public func renameLabel(named name: String, to newName: String) async throws {
        let newName = newName.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, newName != name else { return }
        for label in try labels(named: name) {
            var changes = ChangeSet()
            if let account = gmailAccount(of: label) {
                changes.labels = [try await gmail(account).renameLabel(label, to: newName)]
            } else {
                changes = try await admin.renameLabel(label.id, to: newName)
            }
            try store.merge(changes, source: "labels")
        }
        if let description = ai.labelDescriptions.removeValue(forKey: name) { ai.labelDescriptions[newName] = description }
    }

    /// Deletes every label called `name` and takes it off every conversation, in Gmail and on your server.
    public func deleteLabel(named name: String) async throws {
        for label in try labels(named: name) {
            var changes = ChangeSet()
            if let account = gmailAccount(of: label) {
                try await gmail(account).deleteLabel(label)
                changes.removedLabelIDs = [label.id]
            } else {
                changes = try await admin.deleteLabel(label.id)
            }
            try store.merge(changes, source: "labels")
        }
        ai.labelDescriptions[name] = nil
    }

    /// The label called `name` that `owner`'s mail carries, made first if it doesn't exist yet.
    func label(named name: String, for owner: Account.ID?) async throws -> MailLabel {
        if let label = try labels(named: name).first(where: { $0.accountID == owner }) { return label }
        return try await createLabel(named: name, for: owner)
    }

    private func labels(named name: String) throws -> [MailLabel] {
        try store.database.read { db in try MailLabel.where { $0.name.eq(name) }.fetchAll(db) }
    }

    private func gmailAccount(of label: MailLabel) -> Account? {
        label.accountID.flatMap { id in accounts.first { $0.id == id } }
    }

    /// Before Gmail labels, your server kept the labels on Gmail mail too. Once, on a device that still has those, they
    /// become Gmail labels and leave the server.
    private func moveServerLabelsToGmail() async {
        let done = "movedServerLabelsToGmail"
        guard server != nil, google != nil, !UserDefaults.standard.bool(forKey: done) else { return }
        let moves: [(conversation: Conversation.ID, account: Account.ID, label: MailLabel)] = (try? await store.database.read { db in
            let serverLabels = try MailLabel.where { $0.accountID.is(nil) }.fetchAll(db)
            let gmail = try Conversation.where { $0.accountID.in(Account.where { $0.kind.eq(Account.Kind.gmail) }.select(\.id)) }
                .select { ($0.id, $0.accountID) }.fetchAll(db)
            let accountOf = Dictionary(gmail, uniquingKeysWith: { first, _ in first })
            return try ConversationLabel.where { $0.labelID.in(serverLabels.map(\.id)) && $0.conversationID.in(gmail.map(\.0)) }.fetchAll(db)
                .compactMap { pair in
                    guard let account = accountOf[pair.conversationID], let label = serverLabels.first(where: { $0.id == pair.labelID }) else { return nil }
                    return (pair.conversationID, account, label)
                }
        }) ?? []
        var created: [String: MailLabel] = [:]
        var mutations: [Mutation] = []
        for move in moves {
            let key = "\(move.account):\(move.label.name)"
            do {
                if created[key] == nil { created[key] = try await createLabel(named: move.label.name, for: move.account) }
            } catch {
                return
            }
            guard let gmailLabel = created[key] else { continue }
            mutations += [.label(move.conversation, gmailLabel.id, true), .label(move.conversation, move.label.id, false)]
        }
        if !mutations.isEmpty {
            try? store.perform(mutations)
            engine.wake()
        }
        UserDefaults.standard.set(true, forKey: done)
    }

    /// Saves what belongs under the labels called `name`, on this device with the rest of the AI setup. Auto labelling
    /// only applies labels that have this. Empty clears it.
    public func describeLabel(named name: String, as description: String) {
        let description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        ai.labelDescriptions[name] = description.isEmpty ? nil : description
        labeller.run()
    }

    // MARK: - AI

    /// Emails you've sent, which tab completion learns your voice from. Below `CompletionPrompt.minimumSentMails` it
    /// stays in learning mode and suggests nothing.
    public var sentMailCount: Int {
        (try? store.database.read { db in try Message.where { $0.direction.eq(Direction.outbound) }.fetchCount(db) }) ?? 0
    }

    /// Tab completion for a composer, or nil while it's off, has no key or is still learning.
    public func completion(for draft: @escaping @MainActor () -> Completion.Draft) -> Completion? {
        guard ai.isCompletionOn, let client = ai.client, sentMailCount >= CompletionPrompt.minimumSentMails else { return nil }
        return Completion(session: self, client: client, draft: draft)
    }

    /// Labels new mail now, for when auto labelling is turned on or a description changes.
    public func labelNewMail() {
        labeller.run()
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
    /// `reopen`, which brings back the composer it came from. `detail` goes under the countdown, to say who wrote it.
    public func send(_ message: OutgoingMessage, detail: String? = nil, reopen: @escaping @MainActor () -> Void) {
        var message = message
        // Tracking runs on your server. Without one, say an agent asked for it, the mail still goes, untracked.
        if !canTrack { message.trackingEnabled = false }
        do {
            try store.enqueue(message, sendAt: Date().addingTimeInterval(TimeInterval(Self.undoWindow)))
            engine.wake()
            let toast = Toast(
                "Sending in \(Self.undoWindow)s",
                detail: detail,
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
        guard let account = accounts.first(where: { $0.id == message.accountID }) else {
            throw ProviderError(.rejected, "That account is gone.")
        }
        switch account.kind {
        case .domain:
            guard let server else { throw ProviderError(.rejected, "Connect your server to open this.") }
            let url = try await ServerProvider(connection: server, store: store).downloadURL(for: attachment.id)
            return try await URLSession.shared.data(from: url).0
        case .gmail:
            return try await gmail(account).download(attachment)
        }
    }

    private func gmail(_ account: Account) throws -> GmailProvider {
        guard let google else { throw ProviderError(.rejected, "This build can't reach Gmail.") }
        return GmailProvider(account: account, client: google, store: store, tracking: server.map(ServerTracking.init(connection:)))
    }
}
