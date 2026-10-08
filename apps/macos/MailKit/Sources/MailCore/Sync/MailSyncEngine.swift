import Foundation
import OSLog
import SQLiteData

private let logger = Logger(subsystem: "be.baree.mail", category: "Sync")

/// Moves data between the store and the providers: pulls changes, pushes queued mutations and sends the outbox. Views
/// never talk to it for data; they read the store and redraw when it changes.
public actor MailSyncEngine {
    /// How often providers are asked for changes while the app is in front. Focus, wake and every local change also
    /// trigger a pass right away.
    public static let pullInterval: Duration = .seconds(10)

    private let store: MailStore
    private let status: SyncStatus
    private var providers: [any MailProvider] = []
    private var loop: Task<Void, Never>?
    private var outboxTimer: Task<Void, Never>?
    private var wakeUp: AsyncStream<Void>.Continuation?

    public init(store: MailStore, status: SyncStatus) {
        self.store = store
        self.status = status
    }

    public func setProviders(_ providers: [any MailProvider]) {
        self.providers = providers
        wake()
    }

    public func start() {
        guard loop == nil else { return }
        let (signals, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        wakeUp = continuation
        loop = Task { [weak self] in
            await self?.pass()
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: Self.pullInterval)
                        continuation.yield()
                    }
                }
                for await _ in signals {
                    guard let self else { break }
                    await self.pass()
                }
                group.cancelAll()
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
        wakeUp?.finish()
        wakeUp = nil
    }

    /// Runs a pass as soon as the current one finishes.
    public nonisolated func wake() {
        Task { await self.signal() }
    }

    private func signal() {
        wakeUp?.yield()
    }

    // MARK: - One pass

    private func pass() async {
        await pushMutations()
        await sendDueMessages()
        await pull()
        scheduleOutboxTimer()
    }

    private func pull() async {
        for provider in providers {
            do {
                var cursor = try store.cursor(for: provider.source)
                repeat {
                    let changes = try await provider.pull(after: cursor)
                    try store.merge(changes, source: provider.source)
                    cursor = changes.cursor
                    if !changes.hasMore { break }
                } while !Task.isCancelled
                await status.succeeded(provider.source)
            } catch {
                logger.error("pull \(provider.source, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                await status.failed(provider.source, error)
            }
        }
    }

    private func pushMutations() async {
        while let pending = try? store.nextPendingMutation() {
            guard let provider = try? provider(for: pending.mutation.conversationID) else {
                // The account is gone, so there's nobody left to tell.
                try? store.completeMutation(pending.id)
                continue
            }
            do {
                try await provider.push(pending.mutation)
                try store.completeMutation(pending.id)
            } catch let error as ProviderError where error.kind == .rejected {
                try? store.abandonMutation(pending)
                await status.report(error.message)
            } catch {
                // Offline or the server is down: keep the order, try the whole queue again next pass.
                try? store.recordFailedAttempt(pending.id)
                await status.failed(provider.source, error)
                return
            }
        }
    }

    private func sendDueMessages() async {
        guard let due = try? store.dueOutboxItems() else { return }
        for item in due {
            guard let provider = try? provider(forAccount: item.message.accountID) else { continue }
            do {
                let changes = try await provider.send(item.message)
                try store.completeSend(item.id, with: changes, source: provider.source)
                await status.sent(item.message)
            } catch {
                let permanent = (error as? ProviderError)?.kind == .rejected || item.attempts >= 5
                let retryAt = Date().addingTimeInterval(min(300, 5 * pow(2, Double(item.attempts))))
                try? store.failSend(item.id, error: error.localizedDescription, permanently: permanent, retryAt: retryAt)
                if permanent { await status.sendFailed(item.message, error.localizedDescription) }
            }
        }
    }

    /// Wakes the engine when the next message's undo window closes, instead of waiting for the next pull.
    private func scheduleOutboxTimer() {
        outboxTimer?.cancel()
        guard let next = try? store.nextOutboxDate() else { return }
        outboxTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.wake()
        }
    }

    // MARK: - Routing

    private func provider(for conversationID: Conversation.ID) throws -> (any MailProvider)? {
        let accountID = try store.database.read { db in
            try Conversation.find(conversationID).select(\.accountID).fetchOne(db)
        }
        guard let accountID else { return nil }
        return try provider(forAccount: accountID)
    }

    private func provider(forAccount id: Account.ID) throws -> (any MailProvider)? {
        guard let account = try store.database.read({ db in try Account.find(id).fetchOne(db) }) else { return nil }
        return providers.first { $0.owns(account) }
    }
}
