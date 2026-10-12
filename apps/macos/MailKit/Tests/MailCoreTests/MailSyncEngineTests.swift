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
