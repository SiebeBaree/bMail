import AppKit
import DesignSystem
import MailCore
import MailUI
import SQLiteData
import SwiftUI

struct ConversationList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ConversationQuery()
    @State private var showsFetching = false

    var body: some View {
        let request = ConversationsRequest(tab: model.tab, accountID: model.accountFilter, label: model.labelFilter, searchIDs: model.searchResults)
        let labelNames = query.labelNames
        let tags = model.accountFilter == nil ? query.tags : [:]
        let isFetching = model.session.syncStatus.isCatchingUp && model.tab == .inbox && model.labelFilter == nil && model.searchResults == nil
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if showsFetching, !query.conversations.isEmpty { FetchingRow() }
                    ForEach(query.conversations) { conversation in
                        ConversationRow(
                            conversation: conversation,
                            accountTag: tags[conversation.accountID],
                            labels: labelNames[conversation.id] ?? [],
                            showsSentTime: model.tab == .sent || model.tab == .tracked,
                            isSelected: model.selection == conversation.id,
                            isChecked: model.checked.contains(conversation.id),
                            isPicking: !model.checked.isEmpty,
                            toggleCheck: { model.toggleCheck(conversation.id) }
                        )
                        .id(conversation.id)
                        .onTapGesture { click(conversation.id) }
                    }
                }
            }
            .scrollIndicators(.automatic)
            .overlay {
                if query.conversations.isEmpty, !query.isLoading {
                    if showsFetching {
                        FetchingMail()
                    } else if !isFetching {
                        EmptyList(tab: model.tab, isSearching: model.searchResults != nil, isLabel: model.labelFilter != nil)
                    }
                }
            }
            .onChange(of: model.selection) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
        .background(Color.canvas)
        .loaderVisibility(while: isFetching, isShown: $showsFetching)
        .task(id: request) { await query.load(request) }
        .onChange(of: query.conversations.map(\.id), initial: true) { _, ids in model.listOrder = ids }
        .onChange(of: [model.selection], initial: true) { _, _ in
            model.session.pages.prefetch(around: model.selection, in: model.listOrder, dark: colorScheme == .dark)
        }
    }
}

extension ConversationList {
    /// A click opens a conversation, ⌘-click picks it and Shift-click picks everything from the open one to it.
    private func click(_ id: Conversation.ID) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) {
            model.toggleCheck(id)
        } else if modifiers.contains(.shift), let anchor = model.selection,
            let from = model.listOrder.firstIndex(of: anchor), let to = model.listOrder.firstIndex(of: id) {
            model.checked.formUnion(model.listOrder[min(from, to)...max(from, to)])
            model.selection = id
        } else {
            model.selection = id
        }
    }
}

@MainActor
@Observable
final class ConversationQuery {
    @ObservationIgnored @Fetch(wrappedValue: [], ConversationsRequest(tab: .inbox)) var conversations: [Conversation]
    @ObservationIgnored @FetchAll(Account.all) var accounts
    @ObservationIgnored @FetchAll(MailLabel.order(by: \.name)) var labels
    @ObservationIgnored @FetchAll(ConversationLabel.all) var assignments
    var isLoading = true

    var tags: [Account.ID: String] {
        Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.tag) })
    }

    /// Each conversation's label names, alphabetical.
    var labelNames: [Conversation.ID: [String]] {
        let names = Dictionary(uniqueKeysWithValues: labels.map { ($0.id, $0.name) })
        return Dictionary(grouping: assignments, by: \.conversationID).mapValues { rows in
            Set(rows.compactMap { names[$0.labelID] }).sorted()
        }
    }

    func load(_ request: ConversationsRequest) async {
        isLoading = true
        try? await $conversations.load(request)
        isLoading = false
    }
}

/// The first row while new mail is on its way.
private struct FetchingRow: View {
    var body: some View {
        VStack(spacing: 6) {
            EnvelopeLoader(size: 52)
            Text("Fetching new mail").font(.uiMedium).foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) { Hairline().opacity(0.6) }
    }
}

/// An empty inbox while the first sync brings mail in.
private struct FetchingMail: View {
    var body: some View {
        VStack(spacing: 10) {
            EnvelopeLoader(size: 150)
            Text("Fetching your mail").font(.ui).foregroundStyle(Color.textMuted)
        }
    }
}

private struct EmptyList: View {
    let tab: MailTab
    let isSearching: Bool
    let isLabel: Bool

    var body: some View {
        Text(message)
            .font(.ui)
            .foregroundStyle(Color.textMuted)
    }

    private var message: String {
        if isSearching { return "No mail matches that." }
        if isLabel { return "Nothing has this label. Add it to a conversation with L." }
        switch tab {
        case .inbox: return "Nothing left."
        case .starred: return "Star a conversation with S to keep it here."
        case .sent: return "Mail you send shows up here."
        case .done: return "Conversations you mark done with E land here."
        case .tracked: return "Turn on tracking in the composer with ⌘⇧T."
        case .spam: return "No spam."
        case .trash: return "Trash is empty."
        }
    }
}
