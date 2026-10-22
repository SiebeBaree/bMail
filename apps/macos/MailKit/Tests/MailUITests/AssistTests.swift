import Foundation
import MailCore
import SQLiteData
import Testing

@testable import MailUI

@Suite struct SuggestionTests {
    let suggestion = Suggestion(text: "rld peace", offset: 8, hint: "⇥ Tab")
    let body = AttributedString("Hello wo\nBest")

    /// What the editor would write back after `edit` on the shown text.
    private func edited(_ edit: (inout String) -> Void) -> AttributedString {
        var shown = String(suggestion.display(in: body).characters)
        edit(&shown)
        return AttributedString(shown)
    }

    @Test func typingTheNextLettersWalksThroughIt() {
        let edit = suggestion.reconcile(body: body, edited: edited { $0.insert(contentsOf: "rl", at: $0.index($0.startIndex, offsetBy: 8)) })
        #expect(String(edit.body.characters) == "Hello worl\nBest")
        #expect(edit.suggestion?.text == "d peace")
        #expect(edit.suggestion?.offset == 10)
        #expect(edit.cursor == 10)
    }

    @Test func typingSomethingElseDropsIt() {
        let edit = suggestion.reconcile(body: body, edited: edited { $0.insert("n", at: $0.index($0.startIndex, offsetBy: 8)) })
        #expect(String(edit.body.characters) == "Hello won\nBest")
        #expect(edit.suggestion == nil)
        #expect(edit.cursor == 9)
    }

    @Test func deletingOrEditingElsewhereNeverKeepsItsText() {
        let backspace = suggestion.reconcile(body: body, edited: edited { $0.remove(at: $0.index($0.startIndex, offsetBy: 7)) })
        #expect(String(backspace.body.characters) == "Hello w\nBest")
        #expect(backspace.suggestion == nil)

        let below = suggestion.reconcile(body: body, edited: edited { $0 += "!" })
        #expect(String(below.body.characters) == "Hello wo\nBest!")

        let everything = suggestion.reconcile(body: body, edited: AttributedString(""))
        #expect(String(everything.body.characters) == "")
    }
}

@Suite @MainActor struct LabellerTests {
    let store: MailStore
    let account = Account(id: UUID(), kind: .domain, address: "siebe@baree.be", displayName: "Siebe", domainID: nil, position: 0)
    let receipts = MailLabel(id: UUID(), name: "Receipts", description: "Invoices and order confirmations")
    let travel = MailLabel(id: UUID(), name: "Travel")

    init() throws {
        store = MailStore(database: try inMemoryDatabase())
        var changes = ChangeSet()
        changes.accounts = [account]
        changes.labels = [receipts, travel]
        try store.merge(changes, source: "server")
    }

    @Test func looksOnceAtNewInboxMailNobodyLabelled() throws {
        let since = Date().addingTimeInterval(-3_600)
        let fresh = try add("Card payment of €84.20")
        _ = try add("Board deck", direction: .outbound)
        _ = try add("Last month's invoice", minutesAgo: 24 * 60)
        _ = try add("Flight to Lisbon", labels: [travel.id])
        #expect(try Labeller.candidates(since: since, in: store) == [fresh])

        try store.recordLabelDecision([], on: fresh)
        #expect(try Labeller.candidates(since: since, in: store).isEmpty)
    }

    @Test func learnsFromLabelsYouAddAndOnesYouTakeOff() throws {
        _ = try add("Invoice 2026-114", labels: [receipts.id])
        let wrong = try add("Your trial ends in 3 days")
        try store.recordLabelDecision([receipts.id], on: wrong)
        let right = try add("Order confirmed")
        try store.recordLabelDecision([receipts.id], on: right)
        try store.perform([.label(wrong, receipts.id, false)])

        let guides = try Labeller.guides(in: store)
        #expect(guides.map(\.label.name) == ["Receipts"])
        #expect(guides[0].examples.map(\.subject) == ["Invoice 2026-114"])
        #expect(guides[0].corrections.map(\.subject) == ["Your trial ends in 3 days"])
    }

    private func add(_ subject: String, direction: Direction = .inbound, minutesAgo: Double = 1, labels: [MailLabel.ID] = []) throws -> Conversation.ID {
        let date = Date().addingTimeInterval(-minutesAgo * 60)
        let conversation = Conversation(
            id: UUID(), accountID: account.id, subject: subject, folder: .inbox, isRead: false, isStarred: false,
            snoozedUntil: nil, lastMessageAt: date, lastOutboundAt: nil
        )
        let message = Message(
            id: UUID(), conversationID: conversation.id, accountID: account.id, direction: direction, deliveryStatus: nil,
            messageIDHeader: nil, from: Address(email: "billing@example.com"), to: [Address(email: account.address)], cc: [],
            bcc: [], replyTo: [], subject: subject, html: nil, text: subject, snippet: subject, sentAt: date,
            trackingEnabled: false, attachments: [], links: []
        )
        var changes = ChangeSet()
        changes.conversations = [conversation]
        changes.messages = [message]
        changes.conversationLabels = labels.isEmpty ? [:] : [conversation.id: Set(labels)]
        try store.merge(changes, source: "server")
        return conversation.id
    }
}
