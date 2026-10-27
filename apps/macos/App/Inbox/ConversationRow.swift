import DesignSystem
import MailCore
import MailUI
import SwiftUI

struct ConversationRow: View {
    let conversation: Conversation
    let accountTag: String?
    let labels: [String]
    let showsSentTime: Bool
    let isSelected: Bool
    let isChecked: Bool
    /// While anything is picked every row shows its circle; otherwise only the hovered one does.
    let isPicking: Bool
    let toggleCheck: () -> Void
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
                    Image(systemName: "star.fill").font(.smallIcon).foregroundStyle(Color.warning)
                }
                if conversation.hasAttachments {
                    Image(systemName: "paperclip").font(.smallIcon).foregroundStyle(Color.textMuted)
                }
                if !labels.isEmpty {
                    Text(labels.joined(separator: " · ")).font(.geist(11.5)).foregroundStyle(Color.textSecondary).lineLimit(1)
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
            if isChecked || isPicking || isHovered {
                Button(action: toggleCheck) {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.rowIcon)
                        .foregroundStyle(isChecked ? Color.accent : Color.textFaint)
                        .frame(width: 30, height: 40)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Select (X)")
            } else if !conversation.isRead {
                Circle().fill(Color.link).frame(width: 6, height: 6).padding(.leading, 13).padding(.top, 18)
            }
        }
        .background(isChecked ? Color.accent.opacity(0.12) : isSelected ? Color.selected : isHovered ? Color.hover : Color.clear)
        .overlay(alignment: .bottom) { Hairline().opacity(0.6) }
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected || isChecked ? .isSelected : [])
    }
}
