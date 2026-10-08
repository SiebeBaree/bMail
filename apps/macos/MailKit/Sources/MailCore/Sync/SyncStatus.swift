import Foundation
import Observation

/// What the sync engine wants you to know, for the status line and toasts.
@MainActor
@Observable
public final class SyncStatus {
    public enum Notice: Equatable, Sendable {
        case sent(subject: String)
        case sendFailed(subject: String, reason: String)
        case rejected(String)
        case signedOut(source: String)
    }

    public private(set) var lastSyncedAt: Date?
    /// Sources whose last pass failed for network reasons, mapped to the error.
    public private(set) var failing: [String: String] = [:]
    /// The latest notice, consumed by the toast layer.
    public var notice: Notice?

    public init() {}

    public var isOffline: Bool { !failing.isEmpty }

    func succeeded(_ source: String) {
        lastSyncedAt = Date()
        failing[source] = nil
    }

    func failed(_ source: String, _ error: any Error) {
        if let error = error as? ProviderError, error.kind == .unauthorized {
            notice = .signedOut(source: source)
        }
        failing[source] = error.localizedDescription
    }

    func sent(_ message: OutgoingMessage) {
        notice = .sent(subject: message.subject)
    }

    func sendFailed(_ message: OutgoingMessage, _ reason: String) {
        notice = .sendFailed(subject: message.subject, reason: reason)
    }

    func report(_ message: String) {
        notice = .rejected(message)
    }
}
