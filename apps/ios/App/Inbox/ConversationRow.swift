import DesignSystem
import MailCore
import MailUI
import SwiftUI

/// One conversation in the list: who, when, the subject and the start of the latest message. Unread ones carry a dot
/// and heavier type.
struct ConversationRow: View {
    let conversation: Conversation
    let accountTag: String?
    let labels: [String]
    let showsSentTime: Bool

    var body: some View {
        let isRead = conversation.isRead
        HStack(alignment: .top, spacing: 0) {
            Circle()
                .fill(isRead ? Color.clear : Color.link)
                .frame(width: 9, height: 9)
                .frame(width: 24)
                .padding(.top, 7)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(conversation.participants.isEmpty ? "(no sender)" : conversation.participants)
                        .font(.phone(16, isRead ? .medium : .semibold))
                        .foregroundStyle(isRead ? Color.textSecondary : Color.textPrimary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if conversation.messageCount > 1 {
                        Text("\(conversation.messageCount)").font(.phoneMono(12)).foregroundStyle(Color.textFaint)
                    }
                    Spacer(minLength: 6)
                    if conversation.isStarred {
                        Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(Color.warning)
                    }
                    if conversation.hasAttachments {
                        Image(systemName: "paperclip").font(.system(size: 12)).foregroundStyle(Color.textMuted)
                    }
                    Text(MailDate.short(showsSentTime ? conversation.lastOutboundAt ?? conversation.lastMessageAt : conversation.lastMessageAt))
                        .font(.phoneMono(13))
                        .foregroundStyle(Color.textMuted)
                        .fixedSize()
                        .layoutPriority(2)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(conversation.subject.isEmpty ? "(no subject)" : conversation.subject)
                        .font(.phone(15, isRead ? .regular : .medium))
                        .foregroundStyle(isRead ? Color.textSecondary : Color.textPrimary)
                        .lineLimit(1)
                    if let marks {
                        Spacer(minLength: 0)
                        Text(marks).font(.phone(12, relativeTo: .caption)).foregroundStyle(Color.textFaint).lineLimit(1)
                    }
                }
                if !conversation.snippet.isEmpty {
                    Text(conversation.snippet)
                        .font(.phone(15))
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 11)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// Labels, then the account it reached when every account shows together.
    private var marks: String? {
        let marks = labels + (accountTag.map { [$0] } ?? [])
        return marks.isEmpty ? nil : marks.joined(separator: " · ")
    }

    private var accessibilityText: String {
        let parts: [String?] = [
            conversation.isRead ? nil : "Unread",
            conversation.participants,
            conversation.subject,
            conversation.isStarred ? "Starred" : nil,
            MailDate.short(conversation.lastMessageAt),
            conversation.snippet,
        ]
        return parts.compactMap(\.self).joined(separator: ", ")
    }
}
