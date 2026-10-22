import Assist
import Foundation
import MailCore
import SQLiteData

/// Tab completion for one composer: asks the model for what comes next, with your sent mail and the thread as context.
@MainActor
public final class Completion {
    /// What the composer holds right now, read on every request.
    public struct Draft {
        public var accountID: Account.ID?
        public var to: [Address]
        public var subject: String
        /// The conversation being answered. Nil for new mail and forwards, which start their own.
        public var replyingTo: Conversation.ID?

        public init(accountID: Account.ID?, to: [Address], subject: String, replyingTo: Conversation.ID?) {
            self.accountID = accountID
            self.to = to
            self.subject = subject
            self.replyingTo = replyingTo
        }
    }

    private weak var session: MailSession?
    private let client: AIClient
    private let choice: ModelChoice
    private let draft: @MainActor () -> Draft
    /// The system prompt for the current account and recipients. Kept byte for byte between requests so it caches.
    private var system: (key: String, text: String)?

    init(session: MailSession, client: AIClient, choice: ModelChoice, draft: @escaping @MainActor () -> Draft) {
        self.session = session
        self.client = client
        self.choice = choice
        self.draft = draft
        Task { await client.warmUp() }
    }

    /// The gray text to show, or nil when there's nothing worth suggesting.
    public func suggest(before: String, after: String) async -> String? {
        guard let session else { return nil }
        let draft = draft()
        guard let account = session.accounts.first(where: { $0.id == draft.accountID }) else { return nil }
        let thread = draft.replyingTo.map { thread(of: $0, in: session) } ?? []
        // A new message with nothing in it yet gives the model nothing to go on.
        guard !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !thread.isEmpty else { return nil }
        let prompt = CompletionPrompt.prompt(
            from: Address(name: account.displayName, email: account.address), to: draft.to, subject: draft.subject,
            thread: thread, before: before, after: after, today: .now
        )
        let request = AIRequest(
            model: choice.model, reasoning: choice.reasoning, system: system(for: account, to: draft.to, in: session),
            prompt: prompt, maxTokens: 100, timeout: choice.reasoning == .off ? 10 : 60
        )
        do {
            let answer = try await client.complete(request)
            session.aiProblem = nil
            return CompletionPrompt.suggestion(from: answer, before: before, after: after)
        } catch is CancellationError {
            return nil
        } catch let error as URLError where error.code == .cancelled {
            return nil
        } catch {
            session.aiProblem = "Tab completion: \(error.localizedDescription)"
            return nil
        }
    }

    private func system(for account: Account, to: [Address], in session: MailSession) -> String {
        let key = ([account.id.uuidString] + to.map { $0.email.lowercased() }.sorted()).joined(separator: ",")
        if let system, system.key == key { return system.text }
        // From this address when it has enough, otherwise from all of them: a new address still sounds like you.
        let sent: [Message] = (try? session.store.database.read { db in
            let own = try Message.where { $0.accountID.eq(account.id) && $0.direction.eq(Direction.outbound) }
                .order { $0.sentAt.desc() }
                .limit(200)
                .fetchAll(db)
            guard own.count < 20 else { return own }
            return try Message.where { $0.direction.eq(Direction.outbound) }.order { $0.sentAt.desc() }.limit(200).fetchAll(db)
        }) ?? []
        let text = CompletionPrompt.system(examples: CompletionPrompt.examples(from: sent, to: to))
        system = (key, text)
        return text
    }

    /// The last few messages, oldest first.
    private func thread(of id: Conversation.ID, in session: MailSession) -> [Message] {
        let messages = (try? session.store.database.read { db in
            try Message.where { $0.conversationID.eq(id) }.order { $0.sentAt.desc() }.limit(4).fetchAll(db)
        }) ?? []
        return messages.reversed()
    }
}
