import SwiftUI

/// The menu bar. Every command is here so it can be found by browsing; single-key shortcuts are shown in the palette
/// and the shortcut sheet because AppKit menus can't show a key without a modifier.
struct MenuCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Message") { model.perform(.compose) }
                .keyboardShortcut("n")
        }
        CommandGroup(after: .sidebar) {
            Button("Command Palette") { model.perform(.palette) }
                .keyboardShortcut("k")
            Button("Search") { model.perform(.search) }
                .keyboardShortcut("f")
            Divider()
            Button("All Accounts") { model.perform(.allAccounts) }
                .keyboardShortcut("0")
            ForEach(Array(model.accounts.prefix(9).enumerated()), id: \.element.id) { index, account in
                Button(account.address) { model.perform(.account(index + 1)) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
            }
        }
        CommandMenu("Conversation") {
            ForEach(Command.allCases.filter { $0.group == .triage || $0.group == .write }) { command in
                Button(command.title) { model.perform(command) }
            }
        }
        CommandMenu("Go") {
            ForEach(Tab.allCases) { tab in
                Button(tab.title) { model.perform(.go(tab)) }
            }
        }
        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") { model.perform(.shortcuts) }
                .keyboardShortcut("/")
        }
    }
}
