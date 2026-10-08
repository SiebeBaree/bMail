import DesignSystem
import MailCore
import SwiftUI

struct ConversationRow: View {
    let conversation: Conversation
    let accountTag: String?
    let showsSentTime: Bool
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(conversation.participants.isEmpty ? "(no sender)" : conversation.participants)
                    .font(conversation.isRead ? .uiMedium : .uiSemibold)
                    .foregroundStyle(conversation.isRead ? Color.textSecondary : Color.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)
                if conversation.messageCount > 1 {
                    Text("\(conversation.messageCount)").font(.meta).foregroundStyle(Color.textFaint)
                }
                Spacer(minLength: 8)
                if conversation.isStarred {
                    Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Color.warning)
                }
                if conversation.hasAttachments {
                    Image(systemName: "paperclip").font(.system(size: 10)).foregroundStyle(Color.textMuted)
                }
                if let accountTag {
                    Text(accountTag).font(.geistMono(11)).foregroundStyle(Color.textFaint)
                }
                Text(MailDate.short(showsSentTime ? conversation.lastOutboundAt ?? conversation.lastMessageAt : conversation.lastMessageAt))
                    .font(.meta)
                    .foregroundStyle(Color.textMuted)
                    .fixedSize()
                    .layoutPriority(2)
            }
            (Text(conversation.subject.isEmpty ? "(no subject)" : conversation.subject)
                .foregroundStyle(conversation.isRead ? Color.textSecondary : Color.textPrimary)
                + Text("  \(conversation.snippet)").foregroundStyle(Color.textMuted))
                .font(.ui)
                .lineLimit(1)
        }
        .padding(.leading, 30)
        .padding(.trailing, 16)
        .padding(.vertical, 11)
        .frame(height: 62)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topLeading) {
            if !conversation.isRead {
                Circle().fill(Color.link).frame(width: 6, height: 6).padding(.leading, 13).padding(.top, 18)
            }
        }
        .background(isSelected ? Color.selected : isHovered ? Color.hover : Color.clear)
        .overlay(alignment: .bottom) { Hairline().opacity(0.6) }
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Dates the way a mail list wants them: the time today, the weekday this week, the date before that.
enum MailDate {
    static func short(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return date.formatted(date: .omitted, time: .shortened) }
        if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 6 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) { return date.formatted(.dateTime.month(.abbreviated).day()) }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    static func long(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }
}
