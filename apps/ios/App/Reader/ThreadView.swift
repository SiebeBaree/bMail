import DesignSystem
import MailCore
import MailUI
import SQLiteData
import SwiftUI

/// A conversation as one scrolling page: the subject, then every message. The newest and the unread ones start open;
/// the rest are a line each until tapped.
struct ThreadView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Fetch private var thread: ThreadRequest.Value
    @State private var expanded: Set<Message.ID> = []

    init(conversationID: Conversation.ID) {
        _thread = Fetch(wrappedValue: .init(), ThreadRequest(id: conversationID))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let conversation = thread.conversation {
                    header(conversation)
                }
                ForEach(thread.messages) { message in
                    Hairline()
                    if expanded.contains(message.id) {
                        MessageView(
                            message: message,
                            events: thread.events.filter { $0.messageID == message.id },
                            collapse: thread.messages.count > 1 ? { toggle(message.id) } : nil
                        )
                    } else {
                        CollapsedMessage(message: message) { toggle(message.id) }
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .scrollIndicators(.automatic)
        .background(Color.canvas)
        .onChange(of: thread.messages.map(\.id), initial: true) { _, _ in openDefaultMessages() }
    }

    private func header(_ conversation: Conversation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(conversation.subject.isEmpty ? "(no subject)" : conversation.subject)
                .font(.phone(24, .semibold, relativeTo: .title2))
                .tracking(-0.4)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if !thread.labels.isEmpty {
                HStack(spacing: 6) {
                    ForEach(thread.labels) { label in
                        Text(label.name)
                            .font(.phone(12, .medium, relativeTo: .caption))
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .overlay(Capsule().strokeBorder(Color.lineStrong))
                    }
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(summary).font(.phone(14)).foregroundStyle(Color.textMuted).lineLimit(2)
                Spacer(minLength: 12)
                unsubscribe(conversation.id)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    @ViewBuilder private func unsubscribe(_ id: Conversation.ID) -> some View {
        if thread.messages.contains(where: { $0.direction == .inbound && $0.unsubscribe != nil }) {
            if model.session.unsubscribed.contains(id) {
                Text("Unsubscribed").font(.phone(14)).foregroundStyle(Color.textMuted)
            } else {
                Button("Unsubscribe") { model.session.unsubscribe(from: id) }
                    .font(.phone(14, .medium))
                    .foregroundStyle(Color.link)
            }
        }
    }

    private var summary: String {
        let count = thread.messages.count
        let others = Set(thread.messages.filter { $0.direction == .inbound }.map(\.from.displayName)).sorted()
        let people = others.isEmpty
            ? (thread.messages.first?.to.map(\.displayName) ?? []).joined(separator: ", ")
            : ListFormatter.localizedString(byJoining: others)
        if count == 1 { return thread.messages.first?.direction == .outbound ? "To \(people)" : "From \(people)" }
        return "\(count) messages with \(people)"
    }

    /// Opens the newest message, and the last three when the conversation was unread. Then it counts as read: it's on
    /// screen.
    private func openDefaultMessages() {
        guard expanded.isEmpty, let last = thread.messages.last, let conversation = thread.conversation else { return }
        expanded = [last.id]
        if !conversation.isRead {
            expanded.formUnion(thread.messages.suffix(3).map(\.id))
            model.session.markRead(conversation.id)
        }
        model.session.pages.prefetch(around: conversation.id, in: model.listOrder, dark: colorScheme == .dark, width: model.width)
    }

    private func toggle(_ id: Message.ID) {
        withAnimation(.snappy(duration: 0.25)) {
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        }
    }
}

/// An older message as one line: who and how it starts.
private struct CollapsedMessage: View {
    let message: Message
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Avatar(message.from.displayName, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(message.direction == .outbound ? "You" : message.from.displayName)
                            .font(.phone(15, .medium))
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(MailDate.short(message.sentAt)).font(.phoneMono(12)).foregroundStyle(Color.textMuted)
                    }
                    Text(message.snippet)
                        .font(.phone(14))
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(RowPressStyle())
    }
}

/// A row that dims while pressed, without the system's tint.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.hover : Color.clear)
    }
}
