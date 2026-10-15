import DesignSystem
import MailCore
import MailUI
import SQLiteData
import SwiftUI

/// The app once you're signed in: the list, the reader pushed over it, and the sheets for writing, labels and settings.
struct InboxScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.path) {
            ConversationList()
                .navigationDestination(for: Conversation.ID.self) { ReaderView(conversationID: $0) }
        }
        .sheet(item: $model.sheet, onDismiss: model.sheetDismissed) { sheet in
            switch sheet {
            case let .composer(composer): ComposerView(model: composer)
            case let .labels(ids): LabelPicker(conversations: ids)
            case .settings: SettingsView()
            }
        }
    }
}

/// The conversations of the current view. Tap to read, swipe to triage, long press for everything else, Select to act
/// on many at once.
private struct ConversationList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ConversationQuery()
    @State private var editMode: EditMode = .inactive
    @State private var picked: Set<Conversation.ID> = []
    /// Whether the large title has scrolled away, which is when the bar shows the small one.
    @State private var isTitleCollapsed = false

    var body: some View {
        @Bindable var model = model
        let request = request
        let labelNames = query.labelNames
        let tags = model.accountFilter == nil && query.accounts.count > 1 ? query.tags : [:]
        // Selection only while selecting: with it bound, a tap on a row picks it instead of opening it.
        List(selection: editMode.isEditing ? $picked : nil) {
            titleRow
            ForEach(query.conversations) { conversation in
                NavigationLink(value: conversation.id) {
                    ConversationRow(
                        conversation: conversation,
                        accountTag: tags[conversation.accountID],
                        labels: labelNames[conversation.id] ?? [],
                        showsSentTime: showsSentTime
                    )
                }
                .navigationLinkIndicatorVisibility(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 16))
                .listRowBackground(Color.canvas)
                .listRowSeparatorTint(Color.line)
                .swipeActions(edge: .leading, allowsFullSwipe: true) { leadingActions(conversation) }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) { trailingActions(conversation) }
                .contextMenu { ConversationMenu(conversation: conversation) }
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
        .scrollContentBackground(.hidden)
        .background(Color.canvas)
        .id(Identity(mailbox: model.mailbox, account: model.accountFilter, searching: model.searchResults != nil))
        .refreshable { await model.session.refresh() }
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 36 } action: { _, collapsed in
            withAnimation(.easeOut(duration: 0.15)) { isTitleCollapsed = collapsed }
        }
        .overlay {
            if query.conversations.isEmpty, !query.isLoading {
                EmptyList(message: emptyMessage)
            }
        }
        .navigationTitle(editMode.isEditing ? pickedTitle : model.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .searchable(text: $model.searchText, prompt: "Search mail")
        .task(id: request) { await query.load(request) }
        .onChange(of: query.conversations.map(\.id), initial: true) { _, ids in
            model.listOrder = ids
            picked.formIntersection(ids)
            // The first few open instantly: their bodies load while you look at the list.
            if model.width > 0 { model.session.pages.prefetch(Array(ids.prefix(4)), dark: colorScheme == .dark, width: model.width) }
        }
        .onChange(of: model.mailbox) { _, _ in stopPicking() }
        .onChange(of: model.accountFilter) { _, _ in stopPicking() }
        .sensoryFeedback(.selection, trigger: picked.count) { _, _ in editMode.isEditing }
    }

    /// The large title, as the list's first row: iOS's own large title can't hold a menu you can tap.
    private var titleRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            TitleMenu(title: editMode.isEditing ? pickedTitle : model.title, isLarge: true, isEnabled: !editMode.isEditing)
            SyncLine(isLarge: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 16)
        .padding(.bottom, 6)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.canvas)
        .selectionDisabled()
    }

    private var request: ConversationsRequest {
        switch model.mailbox {
        case let .tab(tab): ConversationsRequest(tab: tab, accountID: model.accountFilter, searchIDs: model.searchResults)
        case let .label(id): ConversationsRequest(tab: .inbox, accountID: model.accountFilter, labelID: id, searchIDs: model.searchResults)
        }
    }

    /// A new list for each view, so it opens at the top instead of where the last one was scrolled.
    private struct Identity: Hashable {
        var mailbox: Mailbox
        var account: Account.ID?
        var searching: Bool
    }

    private var showsSentTime: Bool {
        model.mailbox == .tab(.sent) || model.mailbox == .tab(.tracked)
    }

    private var pickedTitle: String {
        picked.isEmpty ? "Select" : "\(picked.count) Selected"
    }

    private var emptyMessage: String {
        if model.searchResults != nil { return "No mail matches that." }
        switch model.mailbox {
        case .label: return "Nothing has this label yet."
        case let .tab(tab):
            switch tab {
            case .inbox: return model.session.syncStatus.lastSyncedAt == nil ? "Fetching your mail" : "Nothing left."
            case .starred: return "Star a conversation to keep it here."
            case .sent: return "Mail you send shows up here."
            case .done: return "Conversations you mark done land here."
            case .tracked: return "Turn on tracking when you write to see opens and clicks here."
            case .spam: return "No spam."
            case .trash: return "Trash is empty."
            }
        }
    }

    // MARK: - Swipes

    @ViewBuilder private func leadingActions(_ conversation: Conversation) -> some View {
        let target: Folder = conversation.folder == .inbox ? .done : .inbox
        Button(role: removes(conversation, to: target) ? .destructive : nil) {
            model.move([conversation.id], to: target)
        } label: {
            Label(target == .done ? "Done" : "Inbox", systemImage: target == .done ? "checkmark" : "tray.and.arrow.down")
        }
        .tint(target == .done ? Color.success : Color.accent)
        Button {
            model.toggleRead([conversation.id])
        } label: {
            Label(conversation.isRead ? "Unread" : "Read", systemImage: conversation.isRead ? "envelope.badge" : "envelope.open")
        }
        .tint(Color.link)
    }

    @ViewBuilder private func trailingActions(_ conversation: Conversation) -> some View {
        if conversation.folder != .trash {
            Button(role: removes(conversation, to: .trash) ? .destructive : nil) {
                model.move([conversation.id], to: .trash)
            } label: {
                Label("Trash", systemImage: "trash")
            }
            .tint(Color.danger)
        }
        Button {
            model.toggleStar([conversation.id])
        } label: {
            Label(conversation.isStarred ? "Unstar" : "Star", systemImage: conversation.isStarred ? "star.slash" : "star")
        }
        .tint(Color.warning)
    }

    /// Whether moving the conversation takes it out of this list, so a full swipe slides the row away instead of
    /// springing it back.
    private func removes(_ conversation: Conversation, to folder: Folder) -> Bool {
        guard model.searchResults == nil else { return false }
        switch model.mailbox {
        case let .tab(tab):
            switch tab {
            case .inbox, .done, .spam, .trash: return tab.folder != folder
            case .starred: return folder == .trash
            case .sent, .tracked: return false
            }
        case .label: return folder == .trash || folder == .spam
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        // Shown once the header row has scrolled away, so the title is never on screen twice.
        ToolbarItem(placement: .title) {
            VStack(spacing: 0) {
                TitleMenu(title: editMode.isEditing ? pickedTitle : model.title, isLarge: false, isEnabled: !editMode.isEditing)
                SyncLine(isLarge: false)
            }
            .opacity(isTitleCollapsed ? 1 : 0)
            .allowsHitTesting(isTitleCollapsed)
            .accessibilityHidden(!isTitleCollapsed)
        }
        if editMode.isEditing {
            ToolbarItem(placement: .topBarLeading) {
                Button(picked.count == query.conversations.count ? "Deselect All" : "Select All") {
                    picked = picked.count == query.conversations.count ? [] : Set(query.conversations.map(\.id))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done", role: .confirm) { stopPicking() }
            }
            ToolbarItemGroup(placement: .bottomBar) { PickedActions(picked: Array(picked), mailbox: model.mailbox, finish: stopPicking) }
        } else {
            ToolbarItem(placement: .topBarLeading) { AccountMenu() }
                .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarTrailing) {
                Button("Select") { withAnimation { editMode = .active } }
                    .disabled(query.conversations.isEmpty)
            }
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
            ToolbarSpacer(.fixed, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button { model.compose() } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("New message")
            }
        }
    }

    private func stopPicking() {
        withAnimation {
            editMode = .inactive
            picked = []
        }
    }
}

/// The actions for picked conversations, along the bottom while selecting.
private struct PickedActions: View {
    let picked: [Conversation.ID]
    let mailbox: Mailbox
    let finish: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let restores = mailbox == .tab(.done) || mailbox == .tab(.spam) || mailbox == .tab(.trash)
        Button { act { model.move(picked, to: restores ? .inbox : .done) } } label: {
            Image(systemName: restores ? "tray.and.arrow.down" : "checkmark")
        }
        .accessibilityLabel(restores ? "Move to inbox" : "Mark as done")
        Button { act { model.move(picked, to: .trash) } } label: { Image(systemName: "trash") }
            .accessibilityLabel("Move to trash")
            .disabled(mailbox == .tab(.trash))
        Button { act { model.toggleStar(picked) } } label: { Image(systemName: "star") }
            .accessibilityLabel("Star")
        Button { act { model.toggleRead(picked) } } label: { Image(systemName: "envelope.badge") }
            .accessibilityLabel("Mark read or unread")
        Menu {
            Button("Label", systemImage: "tag") { act { model.label(picked) } }
            Button(mailbox == .tab(.spam) ? "Not spam" : "Report spam", systemImage: "exclamationmark.octagon") {
                act { model.move(picked, to: mailbox == .tab(.spam) ? .inbox : .spam) }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("More")
    }

    private func act(_ action: () -> Void) {
        action()
        finish()
    }
}

/// Long press on a conversation: everything you can do to it.
struct ConversationMenu: View {
    let conversation: Conversation
    @Environment(AppModel.self) private var model

    var body: some View {
        let id = conversation.id
        Section {
            Button("Reply", systemImage: "arrowshape.turn.up.left") { model.respond(to: id, .reply) }
            Button("Reply All", systemImage: "arrowshape.turn.up.left.2") { model.respond(to: id, .replyAll) }
            Button("Forward", systemImage: "arrowshape.turn.up.right") { model.respond(to: id, .forward) }
        }
        Section {
            if conversation.folder == .inbox {
                Button("Mark as Done", systemImage: "checkmark") { model.move([id], to: .done) }
            } else {
                Button("Move to Inbox", systemImage: "tray.and.arrow.down") { model.move([id], to: .inbox) }
            }
            Button(conversation.isStarred ? "Unstar" : "Star", systemImage: conversation.isStarred ? "star.slash" : "star") {
                model.toggleStar([id])
            }
            Button(conversation.isRead ? "Mark as Unread" : "Mark as Read", systemImage: conversation.isRead ? "envelope.badge" : "envelope.open") {
                model.toggleRead([id])
            }
            Button("Label", systemImage: "tag") { model.label([id]) }
        }
        Section {
            if conversation.folder != .spam {
                Button("Report Spam", systemImage: "exclamationmark.octagon") { model.move([id], to: .spam) }
            }
            if conversation.folder != .trash {
                Button("Move to Trash", systemImage: "trash", role: .destructive) { model.move([id], to: .trash) }
            }
        }
    }
}

/// The title, which is also where you switch views: tap it for every view and label.
private struct TitleMenu: View {
    let title: String
    let isLarge: Bool
    let isEnabled: Bool

    var body: some View {
        if isEnabled {
            Menu {
                MailboxMenu()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: isLarge ? 8 : 4) {
                    label
                    Image(systemName: "chevron.down")
                        .font(.system(size: isLarge ? 17 : 12, weight: .bold))
                        .foregroundStyle(Color.textMuted)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows your views and labels")
        } else {
            label
        }
    }

    private var label: some View {
        Text(title)
            .font(isLarge ? .phone(32, .bold, relativeTo: .largeTitle) : .phone(17, .semibold, relativeTo: .headline))
            .tracking(isLarge ? -0.6 : 0)
            .foregroundStyle(Color.textPrimary)
            .lineLimit(1)
            .contentTransition(.opacity)
    }
}

/// Under the title: "Checking for mail" while a stale list catches up, then how fresh it is, or what's wrong.
private struct SyncLine: View {
    let isLarge: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        let sync = model.session.syncStatus
        TimelineView(.periodic(from: .now, by: 15)) { context in
            Text(sync.line(at: context.date))
                .font(.phone(isLarge ? 14 : 11, relativeTo: isLarge ? .subheadline : .caption2))
                .foregroundStyle(sync.isCatchingUp ? Color.textSecondary : Color.textMuted)
                .lineLimit(1)
        }
    }
}

/// The title menu: every view, your labels, then spam and trash.
private struct MailboxMenu: View {
    @Environment(AppModel.self) private var model
    @FetchAll(MailLabel.order(by: \.name)) private var labels

    var body: some View {
        @Bindable var model = model
        Picker("View", selection: $model.mailbox) {
            ForEach(MailTab.visible) { tab in
                Label(tab.title, systemImage: tab.symbol).tag(Mailbox.tab(tab))
            }
        }
        if !labels.isEmpty {
            Section("Labels") {
                Picker("Label", selection: $model.mailbox) {
                    ForEach(labels) { label in
                        Label(label.name, systemImage: "tag").tag(Mailbox.label(label.id))
                    }
                }
            }
        }
        Section {
            Picker("Elsewhere", selection: $model.mailbox) {
                ForEach([MailTab.spam, .trash]) { tab in
                    Label(tab.title, systemImage: tab.symbol).tag(Mailbox.tab(tab))
                }
            }
        }
    }
}

/// Your accounts behind your initials: show one or all of them, and settings.
private struct AccountMenu: View {
    @Environment(AppModel.self) private var model
    @FetchAll(Account.order(by: \.position)) private var accounts

    var body: some View {
        @Bindable var model = model
        Menu {
            Picker("Account", selection: $model.accountFilter) {
                Label("All Accounts", systemImage: "tray.2").tag(Account.ID?.none)
                ForEach(accounts) { account in
                    Label(account.address, systemImage: account.kind == .gmail ? "envelope" : "at").tag(Account.ID?.some(account.id))
                }
            }
            Divider()
            Button("Settings", systemImage: "gearshape") { model.sheet = .settings }
        } label: {
            Group {
                if let current = accounts.first(where: { $0.id == model.accountFilter }) {
                    Avatar(current.displayName, size: 34)
                } else {
                    Image(systemName: "tray.2")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(Color.selected, in: .circle)
                }
            }
            .accessibilityLabel(accounts.first { $0.id == model.accountFilter }?.address ?? "All accounts")
        }
    }
}

private struct EmptyList: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.phone(16))
            .foregroundStyle(Color.textMuted)
            .multilineTextAlignment(.center)
            .padding(40)
    }
}

/// The list's rows and what goes next to them, observed so the list redraws whenever sync or your own actions change
/// them.
@MainActor
@Observable
final class ConversationQuery {
    @ObservationIgnored @Fetch(wrappedValue: [], ConversationsRequest(tab: .inbox), animation: .default) var conversations: [Conversation]
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
            rows.compactMap { names[$0.labelID] }.sorted()
        }
    }

    func load(_ request: ConversationsRequest) async {
        isLoading = true
        _ = try? await $conversations.load(request, animation: .default)
        isLoading = false
    }
}
