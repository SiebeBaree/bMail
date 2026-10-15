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
    /// A pass is running on a list that may be missing mail: the last good sync was a while ago, or there never was
    /// one. The routine pass every few seconds doesn't count, so the status line doesn't flicker.
    public private(set) var isCatchingUp = false
    /// Sources whose last pass failed, mapped to why.
    public private(set) var failing: [String: Failure] = [:]
    /// The latest notice, consumed by the toast layer.
    public var notice: Notice?

    public init() {}

    public struct Failure: Equatable, Sendable {
        public var message: String
        /// Network or server trouble that clears on its own, as opposed to a provider refusing us.
        public var isOffline: Bool
    }

    public var isOffline: Bool { failing.values.contains(where: \.isOffline) }

    func passStarted() {
        isCatchingUp = lastSyncedAt.map { $0.timeIntervalSinceNow < -30 } ?? true
    }

    func passFinished() {
        isCatchingUp = false
    }

    func succeeded(_ source: String) {
        lastSyncedAt = Date()
        failing[source] = nil
    }

    func failed(_ source: String, _ error: any Error) {
        // Once per streak: a pass every few seconds would otherwise repeat the toast forever.
        if let error = error as? ProviderError, error.kind == .unauthorized, failing[source] == nil {
            notice = .signedOut(source: source)
        }
        let isOffline = (error as? ProviderError).map { $0.kind == .unavailable } ?? (error is URLError)
        failing[source] = Failure(message: error.localizedDescription, isOffline: isOffline)
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
