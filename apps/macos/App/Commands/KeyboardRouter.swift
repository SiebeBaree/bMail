import AppKit
import MailUI

/// Turns key presses into commands, Superhuman style: single keys, `G` sequences and nothing while you type. Commands
/// with ⌘ go through the menu bar instead, so they show up there.
@MainActor
final class KeyboardRouter {
    private var monitor: Any?
    private var pendingG: Date?
    private let perform: @MainActor (Command) -> Bool
    private let acceptSuggestion: @MainActor () -> Bool

    /// `perform` returns whether the command applied; an unhandled key falls through to the focused view. So does Tab
    /// when there's no suggestion to accept.
    init(perform: @escaping @MainActor (Command) -> Bool, acceptSuggestion: @escaping @MainActor () -> Bool) {
        self.perform = perform
        self.acceptSuggestion = acceptSuggestion
    }

    func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        if event.keyCode == 53 { return perform(.back) }
        // Caught here because the text view would insert a tab before SwiftUI saw the key.
        if event.keyCode == 48, modifiers.isEmpty, !event.modifierFlags.contains(.shift), isTyping, acceptSuggestion() { return true }
        // ⌘A and ⌘⌫ act on conversations, except in a text field, where they select and delete text.
        if modifiers == .command, !isTyping, event.charactersIgnoringModifiers == "a" { return perform(.checkAll) }
        if modifiers == .command, !isTyping, event.keyCode == 51 { return perform(.trash) }
        // Down and up arrows move through the list like J and K; with Shift, any of them extends the selection.
        let shifted = event.modifierFlags.contains(.shift)
        if modifiers.isEmpty, !isTyping, let arrow = [125: Command.next, 126: .previous][event.keyCode] {
            return perform(shifted ? (arrow == .next ? .extendNext : .extendPrevious) : arrow)
        }
        if modifiers.isEmpty, !isTyping, shifted, let extend = ["j": Command.extendNext, "k": .extendPrevious][event.charactersIgnoringModifiers?.lowercased() ?? ""] {
            return perform(extend)
        }
        // `characters` includes Shift, so ? and # arrive as themselves.
        guard modifiers.isEmpty, !isTyping, let typed = event.characters?.lowercased().first else { return false }

        if let started = pendingG, Date().timeIntervalSince(started) < 1.2 {
            pendingG = nil
            guard let tab = MailTab.allCases.first(where: { $0.key == typed }) else { return false }
            return perform(.go(tab))
        }
        if typed == "g" {
            pendingG = Date()
            return true
        }
        guard let command = Command.allCases.first(where: { $0.plainKey == typed }) else { return false }
        return perform(command)
    }

    /// True while a text field or the composer has focus: then keys are text, not commands.
    private var isTyping: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSText || responder is NSTextView
    }
}
