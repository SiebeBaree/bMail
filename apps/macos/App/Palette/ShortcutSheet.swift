import DesignSystem
import MailUI
import SwiftUI

/// `?`. Every shortcut, grouped, read from the same keymap the keys use.
struct ShortcutSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { model.isShortcutsOpen = false }
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Keyboard shortcuts").font(.geist(16, .semibold))
                    Spacer()
                    KeyCap("Esc")
                }
                HStack(alignment: .top, spacing: 36) {
                    ForEach(Command.Group.allCases, id: \.self) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.rawValue).font(.uiSemibold).padding(.bottom, 4)
                            ForEach(commands(in: group)) { command in
                                HStack(spacing: 10) {
                                    Text(command.title).foregroundStyle(Color.textSecondary)
                                    Spacer(minLength: 16)
                                    HStack(spacing: 4) { ForEach(command.keys, id: \.self) { KeyCap($0) } }
                                }
                            }
                        }
                        .frame(width: 230)
                    }
                }
            }
            .padding(28)
            // As wide as its columns. The title row's Spacer would otherwise stretch it across the window.
            .fixedSize()
            .background(Color.raised, in: .rect(cornerRadius: Metrics.windowRadius))
            .overlay(RoundedRectangle(cornerRadius: Metrics.windowRadius).strokeBorder(Color.lineStrong))
            .shadow(color: .black.opacity(0.45), radius: 30, y: 16)
        }
    }

    private func commands(in group: Command.Group) -> [Command] {
        Command.allCases.filter { command in
            guard command.group == group else { return false }
            if case let .account(number) = command { return number == 1 }
            if case let .go(tab) = command { return MailTab.visible.contains(tab) }
            return true
        }
    }
}
