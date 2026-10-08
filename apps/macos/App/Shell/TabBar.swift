import DesignSystem
import MailCore
import SQLiteData
import SwiftUI

/// The views, Vercel-style: text tabs with a line under the current one, unread counts in mono.
struct TabBar: View {
    @Environment(AppModel.self) private var model
    @FetchOne(Conversation.where { $0.folder.eq(Folder.inbox) && !$0.isRead }.count()) private var unread = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 22) {
            ForEach(tabs) { tab in
                TabButton(tab: tab, count: tab == .inbox ? unread : nil, isSelected: model.tab == tab && model.searchResults == nil) {
                    model.perform(.go(tab))
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
    private var tabs: [Tab] {
        Tab.visible.contains(model.tab) ? Tab.visible : Tab.visible + [model.tab]
    }
}

private struct TabButton: View {
    let tab: Tab
    let count: Int?
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(tab.title)
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
        .help("G then \(tab.key.uppercased())")
    }
}

/// "Synced 4s ago", or what's wrong. Updates every few seconds, never animates.
private struct SyncLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            Group {
                if model.syncStatus.isOffline {
                    HStack(spacing: 6) {
                        StatusDot(.warning)
                        Text("Offline")
                    }
                } else if let date = model.syncStatus.lastSyncedAt {
                    Text("Synced \(relative(date, now: context.date))")
                } else {
                    Text("Syncing")
                }
            }
            .font(.meta)
            .foregroundStyle(Color.textMuted)
        }
    }

    private func relative(_ date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        return "\(seconds / 60)m ago"
    }
}
