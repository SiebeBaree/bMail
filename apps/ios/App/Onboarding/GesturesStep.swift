import DesignSystem
import MailCore
import MailUI
import SwiftUI

/// The inbox's swipes and long press, tried on three made-up conversations with the same actions and colors as the
/// real list. Your real mail isn't touched.
struct GesturesStep: View {
    let bars: StepBars
    let back: (() -> Void)?
    @Environment(AppModel.self) private var model
    @State private var conversations = Self.practice()
    @State private var learned: Set<Lesson> = []

    enum Lesson: CaseIterable {
        case done, trash, menu

        var gesture: String {
            switch self {
            case .done: "Swipe right"
            case .trash: "Swipe left"
            case .menu: "Long press"
            }
        }

        var title: String {
            switch self {
            case .done: "Done"
            case .trash: "Trash"
            case .menu: "Everything else"
            }
        }
    }

    var body: some View {
        let next = Lesson.allCases.first { !learned.contains($0) }
        StepPage("Swipe to sort", note: "Try it on these. Your real mail isn't touched.", bars: bars, back: back) {
            List {
                ForEach(conversations) { conversation in
                    ConversationRow(conversation: conversation, accountTag: nil, labels: [], showsSentTime: false)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 16))
                        .listRowBackground(Color.canvas)
                        .listRowSeparatorTint(Color.line)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button(role: .destructive) { remove(conversation, learning: .done) } label: {
                                Label("Done", systemImage: "checkmark")
                            }
                            .tint(Color.success)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { remove(conversation, learning: .trash) } label: {
                                Label("Trash", systemImage: "trash")
                            }
                            .tint(Color.danger)
                        }
                        .contextMenu {
                            Button("Star", systemImage: "star") { learned.insert(.menu) }
                            Button("Label", systemImage: "tag") { learned.insert(.menu) }
                            Button("Mark as read", systemImage: "envelope.open") { learned.insert(.menu) }
                        }
                }
            }
            .listStyle(.plain)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .frame(height: 3 * 96)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                ForEach(Lesson.allCases, id: \.self) { lesson in
                    let color = learned.contains(lesson) ? Color.textFaint : lesson == next ? Color.textPrimary : Color.textMuted
                    GridRow {
                        Text(lesson.gesture).foregroundStyle(color).gridColumnAlignment(.trailing)
                        Text(lesson.title).foregroundStyle(color)
                    }
                    .strikethrough(learned.contains(lesson))
                }
            }
            .font(.phone(16))
            .padding(.top, 8)
        } actions: {
            Button(next == nil ? "Open inbox" : "Skip") { model.onboarding.pass(.keys) }
                .buttonStyle(PhoneButtonStyle(next == nil ? .primary : .secondary))
        }
    }

    private func remove(_ conversation: Conversation, learning lesson: Lesson) {
        Haptics.tap()
        learned.insert(lesson)
        withAnimation { conversations.removeAll { $0.id == conversation.id } }
        guard conversations.isEmpty else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation { conversations = Self.practice() }
        }
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
