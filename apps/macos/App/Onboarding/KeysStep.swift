import DesignSystem
import MailCore
import MailUI
import SwiftUI

/// The main keys, tried on three made-up conversations. While it's on screen every command comes here instead of going
/// to your mail, and ⌘K and ? open the real palette and shortcut sheet.
struct KeysStep: View {
    let bars: StepBars
    let back: (() -> Void)?
    @Environment(AppModel.self) private var model
    @State private var conversations = Self.practice()
    @State private var selected: Conversation.ID?
    @State private var learned: Set<Lesson> = []

    enum Lesson: CaseIterable {
        case move, done, palette, shortcuts

        var keys: [String] {
            switch self {
            case .move: ["J", "K"]
            case .done: ["E"]
            case .palette: ["⌘K"]
            case .shortcuts: ["?"]
            }
        }

        var title: String {
            switch self {
            case .move: "Move down and up"
            case .done: "Mark it done"
            case .palette: "Everything else"
            case .shortcuts: "All the shortcuts"
            }
        }
    }

    var body: some View {
        let next = Lesson.allCases.first { !learned.contains($0) }
        StepPage("Learn the keys", note: "Try them on these. Your real mail isn't touched.", bars: bars, back: back) {
            VStack(spacing: 0) {
                ForEach(conversations) { conversation in
                    ConversationRow(
                        conversation: conversation, accountTag: nil, labels: [], showsSentTime: false,
                        isSelected: conversation.id == selected, isChecked: false, isPicking: false, toggleCheck: {}
                    )
                    .onTapGesture { selected = conversation.id }
                    .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
                }
            }
            .frame(height: 62 * 3, alignment: .top)
            .clipped()
            .overlay(alignment: .top) { Hairline() }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                ForEach(Lesson.allCases, id: \.self) { lesson in
                    GridRow {
                        HStack(spacing: 4) { ForEach(lesson.keys, id: \.self) { KeyCap($0) } }
                            .gridColumnAlignment(.trailing)
                        Text(lesson.title)
                            .strikethrough(learned.contains(lesson))
                            .foregroundStyle(learned.contains(lesson) ? Color.textFaint : lesson == next ? Color.textPrimary : Color.textMuted)
                    }
                }
            }
            .padding(.top, 8)
        } actions: {
            if next == nil {
                Button { model.onboarding.pass(.keys) } label: {
                    HStack(spacing: 8) {
                        Text("Open inbox")
                        KeyCap("↵")
                    }
                }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Skip") { model.onboarding.pass(.keys) }.buttonStyle(.secondary)
            }
        }
        .onAppear {
            selected = conversations.first?.id
            model.practice = handle
        }
        .onDisappear {
            model.practice = nil
            model.isPaletteOpen = false
            model.isShortcutsOpen = false
        }
    }

    private func handle(_ command: Command) -> Bool {
        switch command {
        case .next, .previous:
            let ids = conversations.map(\.id)
            let index = selected.flatMap(ids.firstIndex(of:)) ?? 0
            selected = ids[safe: max(0, min(ids.count - 1, index + (command == .next ? 1 : -1)))]
            learned.insert(.move)
        case .markDone:
            guard let index = conversations.firstIndex(where: { $0.id == selected }) else { return false }
            withAnimation(.snappy(duration: 0.25)) { _ = conversations.remove(at: index) }
            selected = conversations[safe: min(index, conversations.count - 1)]?.id
            learned.insert(.done)
            if conversations.isEmpty {
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    withAnimation { conversations = Self.practice() }
                    selected = conversations.first?.id
                }
            }
        case .palette:
            model.isShortcutsOpen = false
            model.isPaletteOpen.toggle()
            learned.insert(.palette)
        case .shortcuts:
            model.isPaletteOpen = false
            model.isShortcutsOpen.toggle()
            learned.insert(.shortcuts)
        case .back:
            guard model.isPaletteOpen || model.isShortcutsOpen else { return false }
            model.isPaletteOpen = false
            model.isShortcutsOpen = false
        default:
            return false
        }
        return true
    }

    private static func practice() -> [Conversation] {
        [
            ("Lotte Peeters", "Dinner on Friday?", "We found a place in Ghent that does a tasting menu", false, 12),
            ("Vercel", "Your deployment is ready", "bmail is live and serving requests", false, 40),
            ("Tom Verhaegen", "Seed round timeline", "Can we move the call to Thursday morning?", true, 95),
        ].map { name, subject, snippet, isRead, minutes in
            var conversation = Conversation(
                id: UUID(), accountID: UUID(), subject: subject, folder: .inbox, isRead: isRead, isStarred: false,
                snoozedUntil: nil, lastMessageAt: .now.addingTimeInterval(-60 * Double(minutes)), lastOutboundAt: nil
            )
            conversation.participants = name
            conversation.snippet = snippet
            conversation.messageCount = 1
            return conversation
        }
    }
}
