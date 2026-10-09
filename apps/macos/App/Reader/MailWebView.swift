import AppKit
import DesignSystem
import MailCore
import SwiftUI
import WebKit

/// One message body. JavaScript is off, trackers are blocked by a content rule list, links open in your browser and the
/// view is as tall as its content, so the thread scrolls as one page. The page itself comes from `MailPages`, usually
/// loaded before you open the conversation.
struct MailWebView: View {
    let message: Message
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MailPageView(entry: model.pages.entry(for: message, dark: colorScheme == .dark))
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
                .frame(height: entry.height ?? 40)
                .overlay(ScrollPassthrough())
                .background(entry.isDesigned ? Color.white : Color.clear, in: .rect(cornerRadius: Metrics.popoverRadius))
                .clipShape(.rect(cornerRadius: entry.isDesigned ? Metrics.popoverRadius : 0))
                // Hidden until the document is laid out at this width, so it never shows as an empty box first.
                .opacity(entry.height == nil ? 0 : 1)
        }
    }
}

/// The web view is as tall as its content, yet it still swallows the scroll wheel, so a thread wouldn't scroll while the
/// pointer is over a message. This layer takes only scroll events and hands them to the thread's scroll view. Clicks,
/// selection and links fall through to the page.
private struct ScrollPassthrough: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { View() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class View: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .scrollWheel ? super.hitTest(point) : nil
        }

        override func scrollWheel(with event: NSEvent) {
            (enclosingScrollView ?? nextResponder)?.scrollWheel(with: event)
        }
    }
}
