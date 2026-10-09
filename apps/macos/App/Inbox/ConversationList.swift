import DesignSystem
import MailCore
import SQLiteData
import SwiftUI

struct ConversationList: View {
    @Environment(AppModel.self) private var model
    @State private var query = ConversationQuery()

    var body: some View {
        let request = ConversationsRequest(tab: model.tab, accountID: model.accountFilter, searchIDs: model.searchResults)
        let tags = model.accountFilter == nil ? query.tags : [:]
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(query.conversations) { conversation in
                        ConversationRow(
                            conversation: conversation,
                            accountTag: tags[conversation.accountID],
                            showsSentTime: model.tab == .sent || model.tab == .tracked,
                            isSelected: model.selection == conversation.id
                        )
                        .id(conversation.id)
                        .onTapGesture { model.selection = conversation.id }
                    }
                }
            }
            .scrollIndicators(.automatic)
            .overlay {
                if query.conversations.isEmpty, !query.isLoading { EmptyList(tab: model.tab, isSearching: model.searchResults != nil) }
            }
            .onChange(of: model.selection) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
        .background(Color.canvas)
        .task(id: request) { await query.load(request) }
        .onChange(of: query.conversations.map(\.id), initial: true) { _, ids in model.listOrder = ids }
    }
}

@MainActor
@Observable
final class ConversationQuery {
    @ObservationIgnored @Fetch(wrappedValue: [], ConversationsRequest(tab: .inbox)) var conversations: [Conversation]
    @ObservationIgnored @FetchAll(Account.all) var accounts
    var isLoading = true

    var tags: [Account.ID: String] {
        Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.tag) })
    }

    func load(_ request: ConversationsRequest) async {
        isLoading = true
        try? await $conversations.load(request)
        isLoading = false
    }
}

private struct EmptyList: View {
    let tab: Tab
    let isSearching: Bool

    var body: some View {
        Text(message)
            .font(.ui)
            .foregroundStyle(Color.textMuted)
    }

    private var message: String {
        if isSearching { return "No mail matches that." }
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
