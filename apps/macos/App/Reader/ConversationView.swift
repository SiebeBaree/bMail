import DesignSystem
import MailCore
import MailUI
import SQLiteData
import SwiftUI

struct ConversationView: View {
    @Environment(AppModel.self) private var model
    @Fetch private var thread: ThreadRequest.Value
    /// Messages the reader shows in full. The newest and every unread one start open.
    @State private var expanded: Set<Message.ID> = []

    init(conversationID: Conversation.ID) {
        _thread = Fetch(wrappedValue: .init(), ThreadRequest(id: conversationID))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let conversation = thread.conversation {
                        Text(conversation.subject.isEmpty ? "(no subject)" : conversation.subject)
                            .font(.pageTitle)
                            .tracking(-0.3)
                            .textSelection(.enabled)
                        Text(summary)
                            .font(.geist(12))
                            .foregroundStyle(Color.textMuted)
                            .padding(.top, 4)
                            .padding(.bottom, 18)
                    }
                    ForEach(thread.messages) { message in
                        Hairline()
                        if expanded.contains(message.id) {
                            MessageView(message: message, events: thread.events.filter { $0.messageID == message.id }) {
                                toggle(message.id)
                            }
                        } else {
                            CollapsedMessage(message: message) { toggle(message.id) }
                        }
                    }
                    if let composer = model.composer, !composer.replacesReader, composer.conversationID == thread.conversation?.id {
                        ComposerView(model: composer)
                            .padding(.top, 16)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 26)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.composer == nil, let last = thread.messages.last {
                ReplyBar(to: last)
            }
        }
        .background(Color.canvas)
        .onChange(of: thread.messages.map(\.id), initial: true) { _, _ in openDefaultMessages() }
    }

    private var header: some View {
        HStack(spacing: 4) {
            if let account = thread.account {
                Image(systemName: "envelope").font(.system(size: 11)).foregroundStyle(Color.textMuted)
                Text(account.address).font(.meta).foregroundStyle(Color.textMuted)
            }
            ForEach(thread.labels, id: \.self) { label in
                Text(label).font(.geist(12)).foregroundStyle(Color.textSecondary).padding(.leading, 10)
            }
            Spacer()
            if let conversation = thread.conversation, thread.messages.contains(where: { $0.direction == .inbound && $0.unsubscribe != nil }) {
                if model.session.unsubscribed.contains(conversation.id) {
                    Text("Unsubscribed").font(.geist(12)).foregroundStyle(Color.textMuted).padding(.trailing, 8)
                } else {
                    Button("Unsubscribe") { model.perform(.unsubscribe) }
                        .buttonStyle(.ghost)
                        .help("Leave this mailing list")
                }
            }
            ActionButton(symbol: "tag", key: "L", help: "Label") { model.perform(.label) }
            ActionButton(symbol: "checkmark", key: "E", help: model.tab == .done ? "Move to inbox" : "Mark as done") {
                model.perform(.markDone)
            }
            ActionButton(symbol: thread.conversation?.isStarred == true ? "star.fill" : "star", key: "S", help: "Star") {
                model.perform(.toggleStar)
            }
            ActionButton(symbol: "trash", key: "⌘⌫", help: "Move to trash") { model.perform(.trash) }
        }
        .padding(.leading, 32)
        .padding(.trailing, 16)
        .frame(height: 48)
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

    private func openDefaultMessages() {
        guard expanded.isEmpty, let last = thread.messages.last else { return }
        expanded = [last.id]
        if thread.conversation?.isRead == false {
            expanded.formUnion(thread.messages.suffix(3).map(\.id))
        }
    }

    private func toggle(_ id: Message.ID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }
}

private struct ActionButton: View {
    let symbol: String
    let key: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12))
                KeyCap(key)
            }
        }
        .buttonStyle(.ghost)
        .help(help)
    }
}

private struct CollapsedMessage: View {
    let message: Message
    let open: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Avatar(message.from.displayName, size: 22)
            Text(message.direction == .outbound ? "You" : message.from.displayName)
                .font(.uiMedium)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 120, alignment: .leading)
                .lineLimit(1)
            Text(message.snippet)
                .foregroundStyle(Color.textMuted)
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(MailDate.short(message.sentAt)).font(.meta).foregroundStyle(Color.textMuted)
        }
        .padding(.vertical, 11)
        .background(isHovered ? Color.hover.opacity(0.6) : .clear)
        .contentShape(.rect)
        .onTapGesture(perform: open)
        .onHover { isHovered = $0 }
    }
}

private struct ReplyBar: View {
    let to: Message
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.perform(.reply)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrowshape.turn.up.left").font(.system(size: 12))
                Text("Reply to \(to.direction == .outbound ? to.to.first?.displayName ?? "everyone" : to.from.displayName)")
                Spacer()
                KeyCap("R")
                Text("all").font(.geist(12))
                KeyCap("A")
            }
            .foregroundStyle(Color.textMuted)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .overlay(RoundedRectangle(cornerRadius: Metrics.popoverRadius).strokeBorder(Color.lineStrong))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 32)
        .padding(.vertical, 14)
    }
}
