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
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let conversation = thread.conversation {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(conversation.subject.isEmpty ? "(no subject)" : conversation.subject)
                                    .font(.pageTitle)
                                    .tracking(-0.3)
                                    .textSelection(.enabled)
                                // One message names its sender right below, so only a thread gets the line.
                                if thread.messages.count > 1 {
                                    Text(summary)
                                        .font(.geist(12))
                                        .foregroundStyle(Color.textMuted)
                                }
                            }
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
                                .id("composer")
                                // A reply opens under the last message, which can be far below; you type where you can see.
                                .task { withAnimation(.enter) { proxy.scrollTo("composer", anchor: .bottom) } }
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 26)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
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
                Image(systemName: "envelope").font(.smallIcon).foregroundStyle(Color.textMuted)
                Text(account.address).font(.meta).foregroundStyle(Color.textMuted)
            }
            if !thread.labels.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "tag").font(.smallIcon).foregroundStyle(Color.textMuted)
                    ForEach(thread.labels, id: \.self) { label in
                        LabelLink(name: label) { model.labelFilter = label }
                    }
                }
                .padding(.leading, 14)
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
            ActionButton(
                symbol: model.tab == .done ? "tray.and.arrow.down" : Command.markDone.symbol, key: "E",
                help: model.tab == .done ? "Move to inbox" : "Mark as done"
            ) {
                model.perform(.markDone)
            }
            let isStarred = thread.conversation?.isStarred == true
            ActionButton(symbol: isStarred ? "star.fill" : "star", key: "S", help: isStarred ? "Unstar" : "Star") {
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
                Image(systemName: symbol).font(.icon)
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
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 2) {
            Button {
                model.perform(.reply)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrowshape.turn.up.left").font(.icon)
                    Text("Reply to \(to.direction == .outbound ? to.to.first?.displayName ?? "everyone" : to.from.displayName)")
                    Spacer()
                    KeyCap("R")
                }
                .foregroundStyle(isHovered ? Color.textPrimary : Color.textMuted)
                .padding(.leading, 14)
                .padding(.trailing, 6)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            ForEach([Command.replyAll, .forward], id: \.self) { command in
                Button { model.perform(command) } label: {
                    HStack(spacing: 8) {
                        Text(command.title)
                        ForEach(command.keys, id: \.self) { KeyCap($0) }
                    }
                }
                .buttonStyle(.ghost)
            }
        }
        .padding(.trailing, 6)
        .frame(height: 44)
        .overlay(RoundedRectangle(cornerRadius: Metrics.popoverRadius).strokeBorder(Color.lineStrong))
        .padding(.horizontal, 32)
        .padding(.vertical, 14)
    }
}

/// A label on the open conversation. Clicking it shows everything with that label.
private struct LabelLink: View {
    let name: String
    let open: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(name, action: open)
            .buttonStyle(.plain)
            .font(.geist(12))
            .foregroundStyle(isHovered ? Color.textPrimary : Color.textSecondary)
            .onHover { isHovered = $0 }
            .help("Show everything labelled \(name)")
    }
}
