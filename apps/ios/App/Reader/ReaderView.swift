import DesignSystem
import MailCore
import MailUI
import SQLiteData
import SwiftUI

/// One conversation, pushed over the list. Done, trash and spam move on to the next conversation, like E on the Mac, and
/// the arrows step through the list without going back to it.
struct ReaderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var current: Conversation.ID
    /// Where the next conversation comes in from: below for the next one down the list, above for the one before.
    @State private var arrival: Edge = .bottom
    @State private var shown = ShownConversation()

    init(conversationID: Conversation.ID) {
        _current = State(initialValue: conversationID)
    }

    private var conversation: Conversation? { shown.conversation }

    var body: some View {
        ZStack {
            ThreadView(conversationID: current)
                .id(current)
                .transition(.asymmetric(insertion: .move(edge: arrival), removal: .move(edge: arrival == .bottom ? .top : .bottom)).combined(with: .opacity))
        }
        .clipped()
        .background(Color.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .task(id: current) { await shown.load(current) }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { step(to: previous, from: .top) } label: { Image(systemName: "chevron.up") }
                .disabled(previous == nil)
                .accessibilityLabel("Previous conversation")
            Button { step(to: next, from: .bottom) } label: { Image(systemName: "chevron.down") }
                .disabled(next == nil)
                .accessibilityLabel("Next conversation")
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if let conversation { ReaderMenu(conversation: conversation, triage: triage) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("More")
        }
        ToolbarItemGroup(placement: .bottomBar) {
            let restores = conversation.map { $0.folder != .inbox } ?? false
            Button { triage(restores ? .inbox : .done) } label: {
                Image(systemName: restores ? "tray.and.arrow.down" : MailTab.done.symbol)
            }
            .accessibilityLabel(restores ? "Move to inbox" : "Mark as done")
            if conversation?.folder != .trash {
                Button { triage(.trash) } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Move to trash")
            }
            Button { model.toggleStar([current]) } label: {
                Image(systemName: conversation?.isStarred == true ? "star.fill" : "star")
                    .foregroundStyle(conversation?.isStarred == true ? Color.warning : Color.textPrimary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(conversation?.isStarred == true ? "Unstar" : "Star")
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItemGroup(placement: .bottomBar) {
            Menu {
                Button("Reply", systemImage: "arrowshape.turn.up.left") { model.respond(to: current, .reply) }
                Button("Reply all", systemImage: "arrowshape.turn.up.left.2") { model.respond(to: current, .replyAll) }
                Button("Forward", systemImage: "arrowshape.turn.up.right") { model.respond(to: current, .forward) }
            } label: {
                Image(systemName: "arrowshape.turn.up.left")
            }
            .accessibilityLabel("Reply")
            Button { model.compose() } label: { Image(systemName: "square.and.pencil") }
                .accessibilityLabel("New message")
        }
    }

    private var previous: Conversation.ID? {
        model.listOrder.firstIndex(of: current).flatMap { model.listOrder[safe: $0 - 1] }
    }

    private var next: Conversation.ID? {
        model.listOrder.firstIndex(of: current).flatMap { model.listOrder[safe: $0 + 1] }
    }

    /// Moves the conversation and shows the next one down the list, or the one above when it was the last. Back to the
    /// list when there's neither.
    private func triage(_ folder: Folder) {
        let (next, previous) = (next, previous)
        model.move([current], to: folder)
        if let next {
            step(to: next, from: .bottom)
        } else if let previous {
            step(to: previous, from: .top)
        } else {
            dismiss()
        }
    }

    private func step(to id: Conversation.ID?, from edge: Edge) {
        guard let id else { return }
        arrival = edge
        withAnimation(.spring(duration: 0.4, bounce: 0.1)) { current = id }
    }
}

/// The ··· menu in the reader.
private struct ReaderMenu: View {
    let conversation: Conversation
    let triage: (Folder) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let id = conversation.id
        Button(conversation.isRead ? "Mark as unread" : "Mark as read", systemImage: conversation.isRead ? "envelope.badge" : "envelope.open") {
            model.toggleRead([id])
        }
        Button("Label", systemImage: "tag") { model.label([id]) }
        if model.session.canUnsubscribe(from: id), !model.session.unsubscribed.contains(id) {
            Button("Unsubscribe", systemImage: "bell.slash") { model.session.unsubscribe(from: id) }
        }
        Divider()
        if conversation.folder == .spam {
            Button("Not spam", systemImage: "tray.and.arrow.down") { triage(.inbox) }
        } else {
            Button("Report spam", systemImage: "exclamationmark.octagon") { triage(.spam) }
        }
    }
}

/// The conversation the reader shows, observed for its toolbar: the star and the folder change under it.
@MainActor
@Observable
private final class ShownConversation {
    @ObservationIgnored @Fetch(wrappedValue: nil, ConversationRequest(id: nil)) var conversation: Conversation?

    func load(_ id: Conversation.ID) async {
        _ = try? await $conversation.load(ConversationRequest(id: id))
    }
}

private struct ConversationRequest: FetchKeyRequest {
    let id: Conversation.ID?

    func fetch(_ db: Database) throws -> Conversation? {
        guard let id else { return nil }
        return try Conversation.find(id).fetchOne(db)
    }
}
