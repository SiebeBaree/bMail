import DesignSystem
import Foundation
import MailCore
import SwiftUI

/// Dates the way a mail list wants them: the time today, the weekday this week, the date before that.
public enum MailDate {
    public static func short(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return date.formatted(date: .omitted, time: .shortened) }
        if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 6 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) { return date.formatted(.dateTime.month(.abbreviated).day()) }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    public static func long(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }
}

extension Folder {
    /// The toast after moving conversations here.
    public var doneMessage: String {
        switch self {
        case .inbox: "Moved to inbox"
        case .done: "Marked as done"
        case .spam: "Reported as spam"
        case .trash: "Moved to trash"
        }
    }
}

extension Account.Kind {
    public var label: String {
        switch self {
        case .domain: "Your domain"
        case .gmail: "Gmail"
        }
    }
}

extension DeliveryStatus {
    /// Where an outbound message is, in a word.
    public var label: String {
        switch self {
        case .sending: "Sending"
        case .sent: "Sent"
        case .delivered: "Delivered"
        case .delayed: "Delayed"
        case .bounced: "Bounced"
        case .complained: "Marked as spam"
        case .failed: "Failed"
        }
    }

    public var color: Color {
        if isFailure { return .danger }
        return switch self {
        case .delivered: .success
        case .delayed: .warning
        default: .textMuted
        }
    }
}

extension MessageEvent.Kind {
    public var title: String {
        switch self {
        case .sent: "Sent"
        case .delivered: "Delivered"
        case .delayed: "Delayed"
        case .bounced: "Bounced"
        case .complained: "Spam report"
        case .failed: "Failed"
        case .opened: "Opened"
        case .clicked: "Clicked"
        }
    }

    public var isFailure: Bool { [.bounced, .complained, .failed].contains(self) }
}

extension MessageEvent {
    /// The rest of an activity row: where, on what, and for machines, which machine.
    public var summary: String {
        switch source {
        case .appleProxy: return "Apple privacy proxy, on delivery"
        case .googleProxy: return "Gmail, location hidden by Google"
        case .scanner:
            if kind == .opened { return "Security scanner, on delivery" }
            return [url.flatMap(URL.init(string:)).map(Self.short), "link scanner"].compactMap(\.self).joined(separator: " · ")
        case .person, nil:
            let place = [city, country].compactMap(\.self).joined(separator: ", ")
            let parts = [url.flatMap(URL.init(string:)).map(Self.short), device, place.isEmpty ? nil : place, detail]
            return parts.compactMap(\.self).joined(separator: " · ")
        }
    }

    private static func short(_ url: URL) -> String {
        (url.host() ?? "") + (url.path() == "/" ? "" : url.path())
    }
}

extension Domain.Status {
    public var label: String {
        switch self {
        case .pending: "Waiting for DNS"
        case .verified: "Verified"
        case .failed: "DNS check failed"
        }
    }

    public var color: Color {
        switch self {
        case .verified: .success
        case .pending: .warning
        case .failed: .danger
        }
    }
}

extension DNSRecord.Status {
    public var label: String {
        switch self {
        case .pending: "Pending"
        case .verified: "Verified"
        case .failed: "Failed"
        case .optional: "Recommended"
        }
    }

    public var color: Color {
        switch self {
        case .verified: .success
        case .pending: .warning
        case .failed: .danger
        case .optional: .textFaint
        }
    }
}

extension Attachment {
    /// The name to save it under. The sender picks `filename`, so only its last component counts and "../" can't put
    /// the file anywhere else.
    public var savedName: String {
        let name = (filename as NSString).lastPathComponent
        return ["", ".", "..", "/"].contains(name) ? "Attachment" : name
    }
}

extension SyncStatus {
    /// The status line under the list's title: trouble first, then a pass the list is waiting on, then how fresh it is.
    public func line(at now: Date) -> String {
        if !failing.isEmpty { return isOffline ? "Offline" : "Sync failed" }
        guard let lastSyncedAt, !isCatchingUp else { return "Checking for mail" }
        let minutes = Int(now.timeIntervalSince(lastSyncedAt) / 60)
        if minutes < 1 { return "Updated just now" }
        if minutes < 60 { return "Updated \(minutes)m ago" }
        return "Updated at \(lastSyncedAt.formatted(date: .omitted, time: .shortened))"
    }
}

extension Toast {
    /// What the sync engine reports, as the toast you see.
    public init(_ notice: SyncStatus.Notice) {
        switch notice {
        case let .sent(subject):
            self.init("Sent", detail: subject.isEmpty ? nil : subject, symbol: "paperplane", tone: .success)
        case let .sendFailed(subject, reason):
            self.init("Couldn't send \(subject.isEmpty ? "your message" : "“\(subject)”").", detail: reason, symbol: "exclamationmark.triangle", tone: .failure, duration: .seconds(10))
        case let .rejected(reason):
            self.init(reason, symbol: "exclamationmark.triangle", tone: .failure)
        case .signedOut:
            self.init("Sign in again to keep syncing.", symbol: "person.crop.circle.badge.exclamationmark", tone: .failure, duration: .seconds(10))
        }
    }
}
