import AppKit

/// Turns key presses into commands, Superhuman style: single keys, `G` sequences and nothing while you type. Commands
/// with ⌘ go through the menu bar instead, so they show up there.
@MainActor
final class KeyboardRouter {
    private var monitor: Any?
    private var pendingG: Date?
    private let perform: @MainActor (Command) -> Bool

    /// `perform` returns whether the command applied; an unhandled key falls through to the focused view.
    init(perform: @escaping @MainActor (Command) -> Bool) {
        self.perform = perform
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
        // Down and up arrows move through the list like J and K.
        if modifiers.isEmpty, !isTyping, let arrow = [125: Command.next, 126: .previous][event.keyCode] { return perform(arrow) }
        // `characters` includes Shift, so ? and # arrive as themselves.
        guard modifiers.isEmpty, !isTyping, let typed = event.characters?.lowercased().first else { return false }

        if let started = pendingG, Date().timeIntervalSince(started) < 1.2 {
            pendingG = nil
            guard let tab = Tab.allCases.first(where: { $0.key == typed }) else { return false }
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
