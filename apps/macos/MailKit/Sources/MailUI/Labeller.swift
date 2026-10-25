import Assist
import Foundation
import MailCore
import SQLiteData

/// Auto labelling: after each sync, every new conversation in the inbox gets the labels whose description fits it.
///
/// It learns from what you do with labels, with nothing to set up. A label you put on yourself makes that conversation
/// an example of it; a label it applied that you took off makes one a correction. Both go in the next request.
@MainActor
final class Labeller {
    /// Per run, so a burst of new mail is labelled over a few syncs instead of all at once.
    static let batchSize = 20

    private weak var session: MailSession?
    private var isRunning = false

    init(session: MailSession) {
        self.session = session
    }

    func run() {
        guard !isRunning, let session, session.ai.isLabellingOn, let since = session.ai.labellingSince, let client = session.ai.client else { return }
        isRunning = true
        Task {
            defer { isRunning = false }
            do {
                try await label(since: since, with: client, choice: session.ai.labelling, in: session)
            } catch {
                session.aiProblem = "Auto labelling: \(error.localizedDescription)"
            }
        }
    }

    private func label(since: Date, with client: AIClient, choice: ModelChoice, in session: MailSession) async throws {
        let store = session.store
        let candidates = try Self.candidates(since: since, in: store)
        guard !candidates.isEmpty else { return }
        let guides = try Self.guides(describedAs: session.ai.labelDescriptions, in: store)
        guard !guides.isEmpty else { return }
        let system = LabelPrompt.system(guides)
        for id in candidates {
            guard session.ai.isLabellingOn, let message = try Self.newestInbound(in: id, store: store) else { continue }
            let answer = try await client.complete(AIRequest(
                model: choice.model, reasoning: choice.reasoning, system: system, prompt: LabelPrompt.prompt(for: message),
                maxTokens: 100, timeout: 180
            ))
            session.aiProblem = nil
            // You may have labelled it yourself while the model was thinking. Then it keeps yours.
            let names = try Self.isLabelled(id, in: store) ? [] : LabelPrompt.labels(in: answer, from: guides)
            var labelIDs: [MailLabel.ID] = []
            if !names.isEmpty, let owner = try store.labelOwners(of: [id])[id] {
                for name in names { labelIDs.append(try await session.label(named: name, for: owner).id) }
            }
            try store.recordLabelDecision(labelIDs, on: id)
            session.syncNow()
        }
    }

    /// New inbox conversations it hasn't looked at, that you haven't labelled and that someone else wrote to. Newest first.
    static func candidates(since: Date, in store: MailStore) throws -> [Conversation.ID] {
        try store.database.read { db in
            let recent = try Conversation.where { $0.folder.eq(Folder.inbox) && $0.lastMessageAt >= since }
                .order { $0.lastMessageAt.desc() }
                .limit(200)
                .select(\.id)
                .fetchAll(db)
            let decided = Set(try LabelDecision.where { $0.conversationID.in(recent) }.select(\.conversationID).fetchAll(db))
            let labelled = Set(try ConversationLabel.where { $0.conversationID.in(recent) }.select(\.conversationID).fetchAll(db))
            let received = Set(try Message.where { $0.conversationID.in(recent) && $0.direction.eq(Direction.inbound) }.select(\.conversationID).fetchAll(db))
            return Array(recent.filter { !decided.contains($0) && !labelled.contains($0) && received.contains($0) }.prefix(batchSize))
        }
    }

    /// Every label with a description, by name, with up to three examples and three corrections each, newest first. A
    /// name covers that label in every Gmail account and on your server.
    static func guides(describedAs descriptions: [String: String], in store: MailStore) throws -> [LabelGuide] {
        try store.database.read { db in
            let labels = try MailLabel.where { $0.name.in(Array(descriptions.keys)) }.fetchAll(db)
            guard !labels.isEmpty else { return [] }
            let decisions = try LabelDecision.order { $0.decidedAt.desc() }.limit(1_000).fetchAll(db)
            let applied = Dictionary(grouping: try ConversationLabel.fetchAll(db), by: \.labelID).mapValues { Set($0.map(\.conversationID)) }
            return try Set(labels.map(\.name)).sorted().map { name in
                let ids = Set(labels.filter { $0.name == name }.map(\.id))
                let on = ids.reduce(into: Set<Conversation.ID>()) { on, id in on.formUnion(applied[id] ?? []) }
                let mine = decisions.filter { !ids.isDisjoint(with: $0.labelIDs) }
                let byAI = Set(mine.map(\.conversationID))
                let corrections = mine.filter { !on.contains($0.conversationID) }.prefix(3).map(\.conversationID)
                let examples = try Conversation.where { $0.id.in(Array(on.subtracting(byAI))) }
                    .order { $0.lastMessageAt.desc() }
                    .limit(3)
                    .fetchAll(db)
                let corrected = try Conversation.where { $0.id.in(Array(corrections)) }.fetchAll(db)
                return LabelGuide(name: name, description: descriptions[name] ?? "", examples: examples.map(example), corrections: corrected.map(example))
            }
        }
    }

    private static func example(_ conversation: Conversation) -> LabelGuide.Example {
        LabelGuide.Example(from: conversation.participants, subject: conversation.subject, snippet: conversation.snippet)
    }

    private static func isLabelled(_ id: Conversation.ID, in store: MailStore) throws -> Bool {
        try store.database.read { db in try ConversationLabel.where { $0.conversationID.eq(id) }.fetchCount(db) } > 0
    }

    private static func newestInbound(in id: Conversation.ID, store: MailStore) throws -> Message? {
        try store.database.read { db in
            try Message.where { $0.conversationID.eq(id) && $0.direction.eq(Direction.inbound) }.order { $0.sentAt.desc() }.fetchOne(db)
        }
    }
}
