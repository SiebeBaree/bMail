import DesignSystem
import MailCore
import MailUI
import SQLiteData
import SwiftUI

/// ⌘K. Commands, conversations and accounts in one list, ranked by how well they match and how often you use them.
/// Every command shows its key, so the palette teaches the keyboard as you use it.
struct CommandPalette: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        let items = results
        ZStack(alignment: .top) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { model.isPaletteOpen = false }
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Color.textMuted)
                    TextField("Type a command or search", text: $query)
                        .textFieldStyle(.plain)
                        .font(.geist(15))
                        .focused($isFocused)
                        .onSubmit { run(items[safe: highlighted]) }
                        .onKeyPress(.downArrow) { move(1, in: items) }
                        .onKeyPress(.upArrow) { move(-1, in: items) }
                        .onChange(of: query) { _, _ in highlighted = 0 }
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                Hairline()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                PaletteRow(item: item, query: query, isHighlighted: index == highlighted)
                                    .id(item.id)
                                    .onTapGesture { run(item) }
                            }
                        }
                    }
                    .frame(height: min(CGFloat(max(items.count, 1)) * 40, 360))
                    .onChange(of: highlighted) { _, index in
                        if let item = items[safe: index] { proxy.scrollTo(item.id) }
                    }
                }
                Hairline()
                HStack(spacing: 16) {
                    HStack(spacing: 6) { KeyCap("↑"); KeyCap("↓"); Text("Move") }
                    HStack(spacing: 6) { KeyCap("↵"); Text("Run") }
                    HStack(spacing: 6) { KeyCap("Esc"); Text("Close") }
                    Spacer()
                }
                .font(.geist(12))
                .foregroundStyle(Color.textMuted)
                .padding(.horizontal, 16)
                .frame(height: 36)
            }
            .frame(width: 640)
            .background(Color.raised, in: .rect(cornerRadius: Metrics.windowRadius))
            .overlay(RoundedRectangle(cornerRadius: Metrics.windowRadius).strokeBorder(Color.lineStrong))
            .shadow(color: .black.opacity(0.45), radius: 30, y: 16)
            .padding(.top, 96)
        }
        .onAppear { isFocused = true }
        .transition(.opacity)
    }

    private var results: [PaletteItem] {
        let usage = PaletteUsage.counts
        let commands = Command.allCases
            .filter(\.isInPalette)
            .filter { !$0.needsConversation || model.selection != nil }
            .map(PaletteItem.command)
        let accounts = model.session.accounts.map(PaletteItem.account)
        let labels = ((try? model.session.store.database.read { db in try MailLabel.order(by: \.name).fetchAll(db) }) ?? []).names.map(PaletteItem.label)
        let conversations: [PaletteItem] = query.count < 2 ? [] : conversationMatches.map(PaletteItem.conversation)

        let scored = (commands + accounts + labels).compactMap { item -> (PaletteItem, Double)? in
            guard let score = FuzzyMatch.score(query, in: item.title) else { return nil }
            // Usage lifts what you run often; among equals the shorter title wins, so "rep" lands on Reply.
            return (item, score + Double(usage[item.id] ?? 0) * 0.5 - Double(item.title.count) * 0.01)
        }
        return scored.sorted { $0.1 > $1.1 }.map(\.0) + conversations
    }

    private var conversationMatches: [Conversation] {
        guard let ids = try? model.session.store.search(query, limit: 6), !ids.isEmpty else { return [] }
        let found = (try? model.session.store.database.read { db in try Conversation.where { $0.id.in(ids) }.fetchAll(db) }) ?? []
        return ids.compactMap { id in found.first { $0.id == id } }
    }

    private func move(_ offset: Int, in items: [PaletteItem]) -> KeyPress.Result {
        guard !items.isEmpty else { return .ignored }
        highlighted = (highlighted + offset + items.count) % items.count
        return .handled
    }

    private func run(_ item: PaletteItem?) {
        guard let item else { return }
        model.isPaletteOpen = false
        PaletteUsage.record(item.id)
        switch item {
        case let .command(command): model.perform(command)
        case let .account(account): model.accountFilter = account.id
        case let .label(name): model.labelFilter = name
        case let .conversation(conversation):
            model.searchText = query
            model.selection = conversation.id
        }
    }
}

enum PaletteItem: Identifiable {
    case command(Command)
    case account(Account)
    case label(String)
    case conversation(Conversation)

    var id: String {
        switch self {
        case let .command(command): "command.\(command.title)"
        case let .account(account): "account.\(account.id)"
        case let .label(name): "label.\(name)"
        case let .conversation(conversation): "conversation.\(conversation.id)"
        }
    }

    var title: String {
        switch self {
        case let .command(command): command.title
        case let .account(account): "Switch to \(account.address)"
        case let .label(name): "Go to \(name)"
        case let .conversation(conversation): conversation.subject
        }
    }
}

private struct PaletteRow: View {
    let item: PaletteItem
    let query: String
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 18)
                .foregroundStyle(isHighlighted ? Color.textPrimary : Color.textMuted)
            FuzzyMatch.highlighted(item.title, query: query)
                .lineLimit(1)
            Spacer()
            trailing
        }
        .foregroundStyle(isHighlighted ? Color.textPrimary : Color.textSecondary)
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(isHighlighted ? Color.selected : .clear)
        .contentShape(.rect)
    }

    private var symbol: String {
        switch item {
        case let .command(command): command.symbol
        case .account: "person.crop.circle"
        case .label: "tag"
        case .conversation: "envelope"
        }
    }

    @ViewBuilder private var trailing: some View {
        switch item {
        case let .command(command):
            HStack(spacing: 4) { ForEach(command.keys, id: \.self) { KeyCap($0) } }
        case .account, .label:
            EmptyView()
        case let .conversation(conversation):
            Text("\(conversation.participants) · \(MailDate.short(conversation.lastMessageAt))")
                .font(.geist(12))
                .foregroundStyle(Color.textMuted)
                .lineLimit(1)
        }
    }
}

/// Subsequence matching with a preference for prefixes and word starts: "rep" finds Reply before Report spam.
enum FuzzyMatch {
    static func score(_ query: String, in text: String) -> Double? {
        let query = query.lowercased()
        let text = text.lowercased()
        guard !query.isEmpty else { return 0 }
        if text.hasPrefix(query) { return 100 }
        if text.contains(" " + query) { return 80 }
        if text.contains(query) { return 60 }
        var index = text.startIndex
        for character in query {
            guard let found = text[index...].firstIndex(of: character) else { return nil }
            index = text.index(after: found)
        }
        return 20
    }

    static func highlighted(_ text: String, query: String) -> Text {
        var attributed = AttributedString(text)
        if !query.isEmpty, let range = attributed.range(of: query, options: .caseInsensitive) {
            attributed[range].foregroundColor = Color.textPrimary
            attributed[range].font = Font.uiSemibold
        }
        return Text(attributed)
    }
}

/// How often each palette entry was run, so the ones you use rise to the top.
enum PaletteUsage {
    private static let key = "paletteUsage"

    static var counts: [String: Int] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
    }

    static func record(_ id: String) {
        var counts = counts
        counts[id, default: 0] += 1
        UserDefaults.standard.set(counts, forKey: key)
    }
}
