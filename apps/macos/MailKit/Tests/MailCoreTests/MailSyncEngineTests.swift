import Foundation
import Testing

@testable import MailCore

@Suite struct MailSyncEngineTests {
    @Test func refreshWaitsForAPassThatStartedAfterIt() async throws {
        let store = MailStore(database: try inMemoryDatabase())
        let engine = MailSyncEngine(store: store, status: await SyncStatus())
        let provider = CountingProvider()
        await engine.setProviders([provider])
        await engine.start()

        await engine.refresh()
        let first = await provider.pulls
        await engine.refresh()
        #expect(first >= 1)
        #expect(await provider.pulls > first)
        await engine.stop()
    }

    @Test func refreshOnAStoppedEngineReturnsRightAway() async throws {
        let engine = MailSyncEngine(store: MailStore(database: try inMemoryDatabase()), status: await SyncStatus())
        await engine.refresh()
    }

    @Test func aLabelChangeGoesToWhoeverOwnsTheLabel() async throws {
        let store = MailStore(database: try inMemoryDatabase())
        let domain = Account(id: UUID(), kind: .domain, address: "siebe@baree.be", displayName: "Siebe", domainID: nil, position: 0)
        let gmail = Account(id: UUID(), kind: .gmail, address: "siebe@gmail.com", displayName: "Siebe", domainID: nil, position: 1)
        let domainMail = conversation(on: domain)
        let gmailMail = conversation(on: gmail)
        let serverLabel = MailLabel(id: UUID(), name: "Clients")
        let gmailLabel = MailLabel(id: UUID(), name: "Clients", accountID: gmail.id, remoteID: "Label_1")
        var changes = ChangeSet()
        changes.accounts = [domain, gmail]
        changes.conversations = [domainMail, gmailMail]
        changes.labels = [serverLabel, gmailLabel]
        try store.merge(changes, source: "test")
        try store.perform([.label(domainMail.id, serverLabel.id, true), .label(gmailMail.id, gmailLabel.id, true)])

        let server = RecordingProvider(source: "server", owner: domain.id, keepsLabels: true)
        let google = RecordingProvider(source: "gmail", owner: gmail.id, keepsLabels: false)
        let engine = MailSyncEngine(store: store, status: await SyncStatus())
        await engine.setProviders([server, google])
        await engine.start()
        await engine.refresh()
        await engine.stop()

        #expect(await server.pushed == [.label(domainMail.id, serverLabel.id, true)])
        #expect(await google.pushed == [.label(gmailMail.id, gmailLabel.id, true)])
    }

    private func conversation(on account: Account) -> Conversation {
        Conversation(
            id: UUID(), accountID: account.id, subject: "Proposal", folder: .inbox, isRead: true, isStarred: false,
            snoozedUntil: nil, lastMessageAt: Date(), lastOutboundAt: nil
        )
    }

    @MainActor @Test func onlyAPassOnAStaleListCountsAsCatchingUp() {
        let status = SyncStatus()
        status.passStarted()
        #expect(status.isCatchingUp)
        status.succeeded("test")
        status.passFinished()
        #expect(!status.isCatchingUp)

        status.passStarted()
        #expect(!status.isCatchingUp)
    }
}

private actor CountingProvider: MailProvider {
    nonisolated let source = "test"
    private(set) var pulls = 0

    nonisolated func owns(_ account: Account) -> Bool { false }

    func pull(after cursor: String?) async throws -> ChangeSet {
        pulls += 1
        return ChangeSet()
    }

    func push(_ mutation: Mutation) async throws {}

    func send(_ message: OutgoingMessage) async throws -> ChangeSet { ChangeSet() }
}

private actor RecordingProvider: MailProvider {
    nonisolated let source: String
    nonisolated let owner: Account.ID
    nonisolated let keepsLabels: Bool
    private(set) var pushed: [Mutation] = []

    init(source: String, owner: Account.ID, keepsLabels: Bool) {
        self.source = source
        self.owner = owner
        self.keepsLabels = keepsLabels
    }

    nonisolated func owns(_ account: Account) -> Bool { account.id == owner }

    func pull(after cursor: String?) async throws -> ChangeSet { ChangeSet() }

    func push(_ mutation: Mutation) async throws { pushed.append(mutation) }

    func send(_ message: OutgoingMessage) async throws -> ChangeSet { ChangeSet() }
}
