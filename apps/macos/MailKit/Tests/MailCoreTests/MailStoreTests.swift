import Foundation
import SQLiteData
import Testing

@testable import MailCore

@Suite struct MailStoreTests {
    let store: MailStore
    let account = Account(id: UUID(), kind: .domain, address: "siebe@baree.be", displayName: "Siebe Baree", domainID: nil, position: 0)

    init() throws {
        store = MailStore(database: try inMemoryDatabase())
        var changes = ChangeSet()
        changes.accounts = [account]
        try store.merge(changes, source: "server")
    }

    @Test func mergeDerivesListColumnsFromMessages() throws {
        let conversation = conversation()
        try store.merge(changes([conversation], [
            message(in: conversation, from: Address(name: "Tom Verhaegen", email: "tom@northfund.vc"), minutesAgo: 30),
            message(in: conversation, direction: .outbound, to: [Address(name: "Tom Verhaegen", email: "tom@northfund.vc")], minutesAgo: 20, snippet: "Sounds good"),
            message(in: conversation, from: Address(name: "Pieter Claes", email: "pieter@northfund.vc"), minutesAgo: 10, snippet: "Adding myself"),
        ]), source: "server")

        let stored = try fetch(conversation.id)
        #expect(stored.messageCount == 3)
        #expect(stored.snippet == "Adding myself")
        #expect(stored.participants == "Pieter, Tom, me")
    }

    @Test func aConversationYouStartedShowsItsRecipients() throws {
        let conversation = conversation()
        try store.merge(changes([conversation], [
            message(in: conversation, direction: .outbound, to: [Address(name: "Jan Wouters", email: "jan@wouters.be")], minutesAgo: 5),
        ]), source: "server")
        #expect(try fetch(conversation.id).participants == "Jan Wouters")
    }

    @Test func pendingMutationsSurviveASyncThatRacedThem() throws {
        let conversation = conversation()
        try store.merge(changes([conversation], [message(in: conversation, minutesAgo: 1)]), source: "server")

        try store.perform(.move(conversation.id, from: .inbox, to: .done))
        // The server hasn't seen the archive yet and still reports the conversation in the inbox.
        try store.merge(changes([conversation], []), source: "server")
        #expect(try fetch(conversation.id).folder == .done)

        let pending = try #require(try store.pendingMutations().first)
        try store.completeMutation(pending.id)
        try store.merge(changes([conversation], []), source: "server")
        #expect(try fetch(conversation.id).folder == .inbox)
    }

    @Test func aRefusedMutationIsRolledBack() throws {
        let conversation = conversation()
        try store.merge(changes([conversation], [message(in: conversation, minutesAgo: 1)]), source: "server")
        try store.perform(.setStarred(conversation.id, true))
        try store.abandonMutation(try #require(try store.pendingMutations().first))

        #expect(try fetch(conversation.id).isStarred == false)
        #expect(try store.pendingMutations().isEmpty)
    }

    @Test func undoSendRemovesTheMessageAndTheConversationItStarted() throws {
        let outgoing = OutgoingMessage(
            conversationID: UUID(), accountID: account.id, from: Address(email: account.address),
            to: [Address(email: "jan@wouters.be")], subject: "Hi", html: "<p>Hi</p>", text: "Hi"
        )
        try store.enqueue(outgoing, sendAt: Date().addingTimeInterval(10))
        #expect(try fetch(outgoing.conversationID).lastOutboundAt != nil)
        #expect(try store.dueOutboxItems().isEmpty)

        #expect(try store.cancelSend(outgoing.id) == outgoing)
        let remaining = try store.database.read { db in try Conversation.find(outgoing.conversationID).fetchOne(db) }
        #expect(remaining == nil)
    }

    @Test func searchMatchesWordPrefixesAcrossSubjectPeopleAndBody() throws {
        let contract = conversation(subject: "Contract draft v3")
        let dinner = conversation(subject: "Dinner Friday?")
        try store.merge(changes([contract, dinner], [
            message(in: contract, from: Address(name: "Lena Peeters", email: "lena@peeters.be"), minutesAgo: 2, text: "Page 4 has the termination terms"),
            message(in: dinner, from: Address(name: "Arne Janssens", email: "arne@janssens.be"), minutesAgo: 1, text: "A six course thing"),
        ]), source: "server")

        #expect(try store.search("contr") == [contract.id])
        #expect(try store.search("termin") == [contract.id])
        #expect(try store.search("arne") == [dinner.id])
        #expect(try store.search("nothing here").isEmpty)
    }

    @Test func signingOutLeavesNothingBehind() throws {
        let conversation = conversation(subject: "Contract draft v3")
        try store.merge(changes([conversation], [message(in: conversation, minutesAgo: 1, text: "Page 4")]), source: "server")
        try store.perform(.setRead(conversation.id, true))

        try store.eraseAll()

        let left = try store.database.read { db in
            try Account.fetchCount(db) + Conversation.fetchCount(db) + PendingMutation.fetchCount(db) + SyncCursor.fetchCount(db)
        }
        #expect(left == 0)
        #expect(try store.search("contract").isEmpty)
    }

    @Test func trackedLinksResolveToTheirOriginalDestination() throws {
        let conversation = conversation()
        let link = TrackedLink(id: UUID(), url: URL(string: "https://baree.be/proposal")!)
        var sent = message(in: conversation, direction: .outbound, minutesAgo: 1)
        sent.trackingEnabled = true
        sent.links = [link]
        try store.merge(changes([conversation], [sent]), source: "server")

        let tracked = URL(string: "https://t.baree.be/c/\(link.id.uuidString.lowercased()).AbCdEfGhIjKlMnOpQrStUv")!
        #expect(store.trackedLinkDestination(for: tracked) == link.url)
        #expect(store.trackedLinkDestination(for: URL(string: "https://baree.be/c/nope")!) == nil)
    }

    @Test func everyMutationHasAnInverseThatUndoesIt() {
        let id = UUID()
        #expect(Mutation.move(id, from: .inbox, to: .done).inverse == .move(id, from: .done, to: .inbox))
        #expect(Mutation.setRead(id, true).inverse == .setRead(id, false))
        #expect(Mutation.setStarred(id, false).inverse.inverse == .setStarred(id, false))
    }

    // MARK: - Helpers

    private func conversation(subject: String = "Seed round timeline") -> Conversation {
        Conversation(
            id: UUID(), accountID: account.id, subject: subject, folder: .inbox, isRead: false, isStarred: false,
            snoozedUntil: nil, lastMessageAt: Date(), lastOutboundAt: nil
        )
    }

    private func message(
        in conversation: Conversation, direction: Direction = .inbound, from: Address = Address(email: "someone@example.com"),
        to: [Address] = [], minutesAgo: Double, snippet: String = "Hello", text: String = "Hello"
    ) -> Message {
        Message(
            id: UUID(), conversationID: conversation.id, accountID: account.id, direction: direction, deliveryStatus: nil,
            messageIDHeader: nil, from: direction == .outbound ? Address(name: account.displayName, email: account.address) : from,
            to: to.isEmpty ? [Address(email: account.address)] : to, cc: [], bcc: [], replyTo: [], subject: conversation.subject,
            html: nil, text: text, snippet: snippet, sentAt: Date().addingTimeInterval(-minutesAgo * 60), trackingEnabled: false,
            attachments: [], links: []
        )
    }

    private func changes(_ conversations: [Conversation], _ messages: [Message]) -> ChangeSet {
        var changes = ChangeSet()
        changes.conversations = conversations
        changes.messages = messages
        return changes
    }

    private func fetch(_ id: Conversation.ID) throws -> Conversation {
        try #require(try store.database.read { db in try Conversation.find(id).fetchOne(db) })
    }
}
