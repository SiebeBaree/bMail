import Foundation
import MailCore

/// How far agents may go with one account. Each level allows everything the ones before it do. Kept per account on
/// this Mac and checked on every call, so a change in Settings applies to the next thing an agent does.
public enum AgentAccess: String, CaseIterable, Comparable, Sendable {
    case off
    case read
    case organize
    case askToSend = "ask-to-send"
    case send

    public var title: String {
        switch self {
        case .off: "Off"
        case .read: "Read"
        case .organize: "Organize"
        case .askToSend: "Ask to send"
        case .send: "Send"
        }
    }

    public var detail: String {
        switch self {
        case .off: "Agents can't see it"
        case .read: "Search and read"
        case .organize: "Also mark done, star and label"
        case .askToSend: "Also write mail you approve"
        case .send: "Also send without asking"
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// An account's level. Every account starts at Off.
    public static func of(_ account: Account.ID) -> AgentAccess {
        UserDefaults.standard.string(forKey: key(for: account)).flatMap(AgentAccess.init(rawValue:)) ?? .off
    }

    /// Where an account's level is kept, for `@AppStorage`.
    public static func key(for account: Account.ID) -> String {
        "agents.access.\(account.uuidString)"
    }
}
