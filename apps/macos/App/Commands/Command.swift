import SwiftUI

/// The one keymap. Key handling, the ⌘K palette, the shortcut sheet and the menu bar all read from it, so a shortcut
/// can't exist in one place and be missing in another.
enum Command: Hashable, CaseIterable, Identifiable {
    case next, previous, back
    case markDone, trash, spam, toggleStar, toggleRead, undo
    case compose, reply, replyAll, forward
    case search, palette, shortcuts, settings
    case go(Tab)
    case allAccounts, account(Int)

    static let allCases: [Command] =
        [.next, .previous, .back, .markDone, .trash, .spam, .toggleStar, .toggleRead, .undo, .compose, .reply, .replyAll,
         .forward, .search, .palette, .shortcuts, .settings]
        + Tab.allCases.map(Command.go)
        + [.allAccounts] + (1...9).map(Command.account)

    var id: Self { self }

    enum Group: String, CaseIterable {
        case move = "Move"
        case triage = "Triage"
        case write = "Write"
        case app = "App"
    }

    var group: Group {
        switch self {
        case .next, .previous, .back, .go, .allAccounts, .account, .search: .move
        case .markDone, .trash, .spam, .toggleStar, .toggleRead, .undo: .triage
        case .compose, .reply, .replyAll, .forward: .write
        case .palette, .shortcuts, .settings: .app
        }
    }

    var title: String {
        switch self {
        case .next: "Next conversation"
        case .previous: "Previous conversation"
        case .back: "Back"
        case .markDone: "Mark as done"
        case .trash: "Move to trash"
        case .spam: "Report spam"
        case .toggleStar: "Star"
        case .toggleRead: "Mark read or unread"
        case .undo: "Undo"
        case .compose: "New message"
        case .reply: "Reply"
        case .replyAll: "Reply all"
        case .forward: "Forward"
        case .search: "Search"
        case .palette: "Command palette"
        case .shortcuts: "Keyboard shortcuts"
        case .settings: "Settings"
        case let .go(tab): "Go to \(tab.title)"
        case .allAccounts: "All accounts"
        case let .account(number): "Account \(number)"
        }
    }

    var symbol: String {
        switch self {
        case .next: "arrow.down"
        case .previous: "arrow.up"
        case .back: "arrow.left"
        case .markDone: "checkmark"
        case .trash: "trash"
        case .spam: "exclamationmark.octagon"
        case .toggleStar: "star"
        case .toggleRead: "circle.fill"
        case .undo: "arrow.uturn.backward"
        case .compose: "square.and.pencil"
        case .reply: "arrowshape.turn.up.left"
        case .replyAll: "arrowshape.turn.up.left.2"
        case .forward: "arrowshape.turn.up.right"
        case .search: "magnifyingglass"
        case .palette: "command"
        case .shortcuts: "keyboard"
        case .settings: "gearshape"
        case let .go(tab): tab.symbol
        case .allAccounts, .account: "person.crop.circle"
        }
    }

    /// The keys as they're shown, e.g. `E`, `G I`, `⌘K`.
    var keys: [String] {
        switch self {
        case .next: ["J"]
        case .previous: ["K"]
        case .back: ["Esc"]
        case .markDone: ["E"]
        case .trash: ["#"]
        case .spam: ["!"]
        case .toggleStar: ["S"]
        case .toggleRead: ["U"]
        case .undo: ["Z"]
        case .compose: ["C"]
        case .reply: ["R"]
        case .replyAll: ["A"]
        case .forward: ["F"]
        case .search: ["/"]
        case .palette: ["⌘K"]
        case .shortcuts: ["?"]
        case .settings: ["⌘,"]
        case let .go(tab): ["G", tab.key.uppercased()]
        case .allAccounts: ["⌘0"]
        case let .account(number): ["⌘\(number)"]
        }
    }

    /// The single key that triggers it, for commands without modifiers.
    var plainKey: Character? {
        switch self {
        case .next: "j"
        case .previous: "k"
        case .markDone: "e"
        case .trash: "#"
        case .spam: "!"
        case .toggleStar: "s"
        case .toggleRead: "u"
        case .undo: "z"
        case .compose: "c"
        case .reply: "r"
        case .replyAll: "a"
        case .forward: "f"
        case .search: "/"
        case .shortcuts: "?"
        default: nil
        }
    }

    /// Commands that act on the open conversation and do nothing without one.
    var needsConversation: Bool {
        switch self {
        case .markDone, .trash, .spam, .toggleStar, .toggleRead, .reply, .replyAll, .forward: true
        default: false
        }
    }

    /// Shown in the palette. Account switching is reached through its own entries.
    var isInPalette: Bool {
        if case .account = self { return false }
        return self != .palette && self != .back
    }
}

/// The views across the top. Each one is a query over conversations, not a folder on its own.
enum Tab: String, CaseIterable, Identifiable {
    case inbox, starred, sent, done, tracked, spam, trash

    var id: Self { self }

    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .starred: "Starred"
        case .sent: "Sent"
        case .done: "Done"
        case .tracked: "Tracked"
        case .spam: "Spam"
        case .trash: "Trash"
        }
    }

    var symbol: String {
        switch self {
        case .inbox: "tray"
        case .starred: "star"
        case .sent: "paperplane"
        case .done: "checkmark"
        case .tracked: "waveform.path.ecg"
        case .spam: "exclamationmark.octagon"
        case .trash: "trash"
        }
    }

    /// The second key of `G` then this.
    var key: Character {
        switch self {
        case .inbox: "i"
        case .starred: "s"
        case .sent: "t"
        case .done: "e"
        case .tracked: "r"
        case .spam: "!"
        case .trash: "#"
        }
    }

    /// Spam and trash stay out of the tab bar; you reach them with G ! and G #.
    static let visible: [Tab] = [.inbox, .starred, .sent, .done, .tracked]
}
