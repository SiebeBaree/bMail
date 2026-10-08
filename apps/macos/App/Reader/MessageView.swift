import DesignSystem
import MailCore
import SwiftUI

struct MessageView: View {
    let message: Message
    let events: [MessageEvent]
    let collapse: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Avatar(message.from.displayName)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(message.direction == .outbound ? "You" : message.from.displayName).font(.uiSemibold)
                        Text(message.from.email).foregroundStyle(Color.textMuted)
                    }
                    Text(recipients).font(.geist(12)).foregroundStyle(Color.textMuted).lineLimit(1)
                }
                Spacer()
                DeliveryLabel(message: message)
                Text(MailDate.short(message.sentAt))
                    .font(.meta)
                    .foregroundStyle(Color.textMuted)
                    .help(MailDate.long(message.sentAt))
            }
            .contentShape(.rect)
            .onTapGesture(perform: collapse)

            MailWebView(message: message)
                .padding(.leading, 40)

            if !message.listedAttachments.isEmpty {
                AttachmentList(message: message)
                    .padding(.leading, 40)
            }
            if let failure = events.last(where: { $0.kind.isFailure }) {
                FailureNote(event: failure)
                    .padding(.leading, 40)
            }
            if message.direction == .outbound, message.trackingEnabled {
                ActivityView(message: message, events: events)
                    .padding(.leading, 40)
                    .padding(.top, 6)
            }
        }
        .padding(.vertical, 16)
    }

    private var recipients: String {
        let names = (message.to + message.cc).map { address in
            model.accounts.contains { $0.address.caseInsensitiveCompare(address.email) == .orderedSame } ? "you" : address.displayName
        }
        return "to " + ListFormatter.localizedString(byJoining: names)
    }
}

/// Why a message didn't arrive, in the words the receiving server or Resend used.
private struct FailureNote: View {
    let event: MessageEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(Color.danger)
            Text("\(event.kind.title). ").foregroundStyle(Color.textPrimary) + Text(event.detail ?? "No reason given.").foregroundStyle(Color.textMuted)
        }
        .font(.ui)
    }
}

/// Where an outbound message is, in a word. Nothing for inbound mail.
private struct DeliveryLabel: View {
    let message: Message

    var body: some View {
        if message.direction == .outbound, let status = message.deliveryStatus {
            HStack(spacing: 6) {
                StatusDot(color(status))
                Text(label(status)).font(.geist(12)).foregroundStyle(Color.textMuted)
            }
        }
    }

    private func label(_ status: DeliveryStatus) -> String {
        switch status {
        case .sending: "Sending"
        case .sent: "Sent"
        case .delivered: "Delivered"
        case .delayed: "Delayed"
        case .bounced: "Bounced"
        case .complained: "Marked as spam"
        case .failed: "Failed"
        }
    }

    private func color(_ status: DeliveryStatus) -> Color {
        if status.isFailure { return .danger }
        return switch status {
        case .delivered: .success
        case .delayed: .warning
        default: .textMuted
        }
    }
}

private struct AttachmentList: View {
    let message: Message
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            ForEach(message.listedAttachments) { file in
                Button { model.open(file, of: message) } label: {
                    HStack(spacing: 8) {
                    Image(systemName: "doc").font(.system(size: 12)).foregroundStyle(Color.textMuted)
                    Text(file.filename).lineLimit(1)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))
                            .font(.meta)
                            .foregroundStyle(Color.textMuted)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .overlay(RoundedRectangle(cornerRadius: Metrics.controlRadius).strokeBorder(Color.lineStrong))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Download and open")
            }
        }
    }
}
