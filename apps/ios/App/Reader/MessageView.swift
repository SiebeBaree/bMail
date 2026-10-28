import DesignSystem
import MailCore
import MailUI
import SwiftUI
import WebKit

/// One open message: who sent it to whom, the body across the full width, then its files and, for mail you tracked,
/// what happened to it.
struct MessageView: View {
    let message: Message
    let events: [MessageEvent]
    /// Folds the message back to one line. Nil when it's the only one.
    let collapse: (() -> Void)?
    @Environment(AppModel.self) private var model
    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if showsDetails { details }
            MailWebView(message: message)
            if !message.listedAttachments.isEmpty {
                AttachmentList(message: message)
            }
            if let failure = events.last(where: { $0.kind.isFailure }) {
                FailureNote(event: failure).padding(.horizontal, 16)
            }
            if message.direction == .outbound, message.trackingEnabled {
                ActivityView(message: message, events: events).padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 14)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(message.from.displayName, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(message.direction == .outbound ? "You" : message.from.displayName)
                        .font(.phone(16, .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if message.direction == .outbound, let status = message.deliveryStatus, status != .sent {
                        HStack(spacing: 5) {
                            StatusDot(status.color)
                            Text(status.label).font(.phone(12, relativeTo: .caption)).foregroundStyle(Color.textMuted)
                        }
                    }
                    Text(MailDate.short(message.sentAt)).font(.phoneMono(13)).foregroundStyle(Color.textMuted)
                }
                Button {
                    withAnimation(.snappy(duration: 0.25)) { showsDetails.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(recipients).lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.phone(10, .semibold, relativeTo: .caption2))
                            .rotationEffect(.degrees(showsDetails ? 180 : 0))
                    }
                    .font(.phone(14))
                    .foregroundStyle(Color.textMuted)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showsDetails ? "Hide details" : "Show details, \(recipients)")
            }
        }
        .padding(.horizontal, 16)
        .contentShape(.rect)
        .onTapGesture { collapse?() }
    }

    /// Every address in full, and the exact time.
    private var details: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
            detail("From", [message.from])
            if !message.to.isEmpty { detail("To", message.to) }
            if !message.cc.isEmpty { detail("Cc", message.cc) }
            if !message.bcc.isEmpty { detail("Bcc", message.bcc) }
            GridRow {
                Text("Date").foregroundStyle(Color.textMuted)
                Text(message.sentAt.formatted(date: .complete, time: .shortened)).foregroundStyle(Color.textSecondary)
            }
        }
        .font(.phone(14))
        .textSelection(.enabled)
        .padding(.horizontal, 16)
        .padding(.leading, 48)
        .transition(.opacity)
    }

    private func detail(_ title: String, _ addresses: [Address]) -> some View {
        GridRow {
            Text(title).foregroundStyle(Color.textMuted)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(addresses, id: \.email) { address in
                    Text(address.name.map { "\($0) <\(address.email)>" } ?? address.email)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    private var recipients: String {
        let own = Set(model.session.accounts.map { $0.address.lowercased() })
        let names = (message.to + message.cc).map { own.contains($0.email.lowercased()) ? "you" : $0.displayName }
        return names.isEmpty ? "no recipients" : "to " + ListFormatter.localizedString(byJoining: names)
    }
}

/// A message body. JavaScript is off, trackers are blocked, links open outside the app and the view is as tall as its
/// content, so the thread scrolls as one page. Mail wider than the screen is scaled to fit. The page itself usually
/// loaded before you opened the conversation.
struct MailWebView: View {
    let message: Message
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if model.width > 0 {
            MailPageView(entry: model.session.pages.entry(for: message, dark: colorScheme == .dark, width: model.width))
        }
    }
}

private struct MailPageView: View {
    let entry: MailPages.Entry

    var body: some View {
        if let page = entry.page {
            WebView(page)
                .webViewContentBackground(.hidden)
                .webViewOnScrollGeometryChange(for: CGFloat.self, of: \.contentSize.height) { _, height in
                    entry.measure(max(height, 20))
                }
                // A preview loads the link, and in your own tracked mail that counts you as a click.
                .webViewLinkPreviews(.disabled)
                .webViewMagnificationGestures(.disabled)
                .webViewBackForwardNavigationGestures(.disabled)
                .scrollDisabled(true)
                .frame(height: entry.height ?? 80)
                .background(entry.isDesigned ? Color.white : Color.clear)
                // Hidden until the document is laid out at this width, so it never shows as an empty box first.
                .opacity(entry.height == nil ? 0 : 1)
                .animation(.easeOut(duration: 0.15), value: entry.height == nil)
        }
    }
}

/// Why a message didn't arrive, in the words the receiving server or Resend used.
private struct FailureNote: View {
    let event: MessageEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(Color.danger)
            Text("\(Text("\(event.kind.title). ").foregroundStyle(Color.textPrimary))\(Text(event.detail ?? "No reason given.").foregroundStyle(Color.textMuted))")
        }
        .font(.phone(15))
    }
}
