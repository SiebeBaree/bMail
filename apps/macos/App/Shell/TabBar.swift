import DesignSystem
import MailCore
import MailUI
import SQLiteData
import SwiftUI

/// The views, Vercel-style: text tabs with a line under the current one, unread counts in mono.
struct TabBar: View {
    @Environment(AppModel.self) private var model
    @FetchOne(Conversation.where { $0.folder.eq(Folder.inbox) && !$0.isRead }.count()) private var unread = 0
    @FetchAll(MailLabel.order(by: \.name)) private var labels

    var body: some View {
        HStack(alignment: .bottom, spacing: 22) {
            ForEach(tabs) { tab in
                TabButton(
                    title: tab.title, count: tab == .inbox ? unread : nil, help: "G then \(tab.key.uppercased())",
                    isSelected: model.tab == tab && model.labelFilter == nil && model.searchResults == nil
                ) {
                    model.perform(.go(tab))
                }
            }
            if !labels.isEmpty {
                Rectangle().fill(Color.lineStrong).frame(width: 1, height: 14).padding(.bottom, 14)
                ForEach(labels.names, id: \.self) { name in
                    TabButton(title: name, count: nil, help: "Label", isSelected: model.labelFilter == name && model.searchResults == nil) {
                        model.labelFilter = name
                    }
                }
            }
            Spacer()
            SyncLabel()
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 20)
        .frame(height: 42)
        .background(Color.chrome)
    }

    /// Spam and trash join the bar only while you're in them.
    private var tabs: [MailTab] {
        MailTab.visible.contains(model.tab) ? MailTab.visible : MailTab.visible + [model.tab]
    }
}

private struct TabButton: View {
    let title: String
    let count: Int?
    let help: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                if let count, count > 0 {
                    Text("\(count)").font(.meta).foregroundStyle(Color.textMuted)
                }
            }
            .foregroundStyle(isSelected || isHovered ? Color.textPrimary : Color.textMuted)
            .padding(.bottom, 12)
            .overlay(alignment: .bottom) {
                if isSelected { Rectangle().fill(Color.textPrimary).frame(height: 2) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
    }
}

/// "Checking for mail" while a stale list catches up, "Updated just now" after, or what's wrong. Updates every few
/// seconds, never animates.
private struct SyncLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let sync = model.session.syncStatus
        TimelineView(.periodic(from: .now, by: 5)) { context in
            HStack(spacing: 6) {
                if !sync.failing.isEmpty { StatusDot(.warning) }
                Text(sync.line(at: context.date))
            }
            .font(.meta)
            .foregroundStyle(sync.isCatchingUp ? Color.textSecondary : Color.textMuted)
            .help(help(sync))
        }
    }

    private func help(_ sync: SyncStatus) -> String {
        if !sync.failing.isEmpty { return sync.failing.values.map(\.message).sorted().joined(separator: "\n") }
        return sync.lastSyncedAt.map { "Last synced \(MailDate.long($0))" } ?? ""
    }
}
