import Foundation

/// One per account kind. A provider only translates between its wire format and these models; the sync engine decides
/// what gets written to the store and when.
public protocol MailProvider: Sendable {
    /// Names this provider's cursor in the store: `server`, or `gmail:<account id>`.
    var source: String { get }

    /// Whether mutations and sends for this account go through this provider.
    func owns(_ account: Account) -> Bool

    /// Whether label changes go through this provider, whichever account the conversation is on.
    var keepsLabels: Bool { get }

    /// Everything that changed after `cursor`, which is nil on first sync. The engine calls again with the returned
    /// cursor while `hasMore` is true.
    func pull(after cursor: String?) async throws -> ChangeSet

    func push(_ mutation: Mutation) async throws

    /// Sends and returns the provider's own view of the sent message, which replaces the optimistic one.
    func send(_ message: OutgoingMessage) async throws -> ChangeSet
}

extension MailProvider {
    public var keepsLabels: Bool { false }
}

/// What a provider reports back. Rows are complete: an upserted conversation replaces the stored one.
public struct ChangeSet: Sendable {
    public var accounts: [Account] = []
    public var removedAccountIDs: [Account.ID] = []
    public var domains: [Domain] = []
    public var removedDomainIDs: [Domain.ID] = []
    public var conversations: [Conversation] = []
    public var removedConversationIDs: [Conversation.ID] = []
    public var messages: [Message] = []
    /// Optimistic messages the provider's own copy replaces, for providers that pick their own ids.
    public var removedMessageIDs: [Message.ID] = []
    public var events: [MessageEvent] = []
    public var labels: [MailLabel] = []
    public var removedLabelIDs: [MailLabel.ID] = []
    /// The whole set per conversation; an empty set clears it.
    public var conversationLabels: [Conversation.ID: Set<MailLabel.ID>] = [:]
    public var trackedSends: [TrackedSend] = []
    public var cursor: String?
    public var hasMore = false

    public init() {}

    public var isEmpty: Bool {
        accounts.isEmpty && removedAccountIDs.isEmpty && domains.isEmpty && removedDomainIDs.isEmpty
            && conversations.isEmpty && removedConversationIDs.isEmpty && messages.isEmpty && removedMessageIDs.isEmpty
            && events.isEmpty && labels.isEmpty && removedLabelIDs.isEmpty && conversationLabels.isEmpty && trackedSends.isEmpty
    }
}

/// Errors a provider throws on purpose, worded for the person reading the toast.
public struct ProviderError: LocalizedError, Sendable {
    public enum Kind: Sendable {
        /// Sign in again. Retrying won't help.
        case unauthorized
        /// The server refused this change for a reason retrying won't fix.
        case rejected
        /// Network or server trouble. Retry later.
        case unavailable
    }

    public var kind: Kind
    public var message: String

    public init(_ kind: Kind, _ message: String) {
        self.kind = kind
        self.message = message
    }

    public var errorDescription: String? { message }
}
