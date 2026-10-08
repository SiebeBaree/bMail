import AppKit
import DesignSystem
import MailCore
import SwiftUI
import WebKit

/// One message body. JavaScript is off, trackers are blocked by a content rule list, links open in your browser and the
/// view is as tall as its content, so the thread scrolls as one page.
struct MailWebView: View {
    let message: Message
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var page: WebPage?
    @State private var height: CGFloat = 40

    var body: some View {
        let rendered = EmailDocument.render(message, dark: colorScheme == .dark)
        Group {
            if let page {
                WebView(page)
                    .webViewContentBackground(.hidden)
                    .webViewOnScrollGeometryChange(for: CGFloat.self, of: \.contentSize.height) { _, newHeight in
                        height = max(newHeight, 20)
                    }
                    .frame(height: height)
            } else {
                Color.clear.frame(height: height)
            }
        }
        .padding(rendered.isDesigned ? 0 : 0)
        .background(rendered.isDesigned ? Color.white : Color.clear, in: .rect(cornerRadius: Metrics.popoverRadius))
        .clipShape(.rect(cornerRadius: rendered.isDesigned ? Metrics.popoverRadius : 0))
        .task(id: rendered.html) {
            let page = await WebPageFactory.make(model: model)
            self.page = page
            // The load starts right away; its navigation events don't matter here.
            _ = page.load(html: rendered.html, baseURL: WebPageFactory.baseURL)
        }
    }
}

@MainActor
enum WebPageFactory {
    static let baseURL = URL(string: "mail-asset://message/")!
    private static var rules: WKContentRuleList?

    static func make(model: AppModel) async -> WebPage {
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultNavigationPreferences.allowsContentJavaScript = false
        if let scheme = URLScheme("mail-asset") { configuration.urlSchemeHandlers[scheme] = AssetSchemeHandler() }
        if let rules = await trackerRules() { configuration.userContentController.add(rules) }
        return WebPage(configuration: configuration, navigationDecider: LinkDecider(model: model))
    }

    /// Blocks open pixels: ours on every `t.` host and the api, and the common ones other senders use. This is what keeps
    /// you from counting as an open on mail you sent to yourself.
    private static func trackerRules() async -> WKContentRuleList? {
        if let rules { return rules }
        let patterns = [
            #"^https?://t\.[^/]+/o/"#,
            "^https?://" + NSRegularExpression.escapedPattern(for: AppModel.serverURL.host() ?? "") + "/o/",
            #"^https?://[^/]+/wf/open"#,
            #"^https?://[^/]*list-manage\.com/track/open"#,
            #"^https?://[^/]*mandrillapp\.com/track/open"#,
            #"^https?://[^/]*(mailtrack\.io|mixmax\.com|yesware\.com|streak\.com|superhuman\.com|hubspot(links)?\.com)/"#,
            #"^https?://[^/]+/(e/)?(open|pixel|track(ing)?/open)[^/]*\.(gif|png)"#,
        ]
        let json = "[" + patterns.map { #"{"trigger":{"url-filter":"\#($0.replacingOccurrences(of: "\\", with: "\\\\"))"},"action":{"type":"block"}}"# }.joined(separator: ",") + "]"
        rules = try? await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "trackers", encodedContentRuleList: json)
        return rules
    }
}

/// Serves the bundled font to web content, which runs in another process and can't see the app's registered fonts.
private struct AssetSchemeHandler: URLSchemeHandler {
    func reply(for request: URLRequest) -> AsyncThrowingStream<URLSchemeTaskResult, any Error> {
        AsyncThrowingStream { continuation in
            let name = request.url?.deletingPathExtension().lastPathComponent ?? ""
            guard let url = request.url, let data = Typography.fontData(named: name) else {
                continuation.finish(throwing: URLError(.fileDoesNotExist))
                return
            }
            continuation.yield(.response(URLResponse(url: url, mimeType: "font/ttf", expectedContentLength: data.count, textEncodingName: nil)))
            continuation.yield(.data(data))
            continuation.finish()
        }
    }
}

/// The first load is the document itself; every later navigation is a click, which opens in the browser. A click on
/// one of our tracked links opens the original destination directly, so you never count as a click on your own mail.
private struct LinkDecider: WebPage.NavigationDeciding {
    let model: AppModel

    func decidePolicy(for action: WebPage.NavigationAction, preferences: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
        guard let url = action.request.url, url.scheme == "http" || url.scheme == "https" || url.scheme == "mailto" else {
            return .allow
        }
        if url.scheme == "mailto" {
            model.composer = ComposerModel.new(app: model, mailto: url)
        } else {
            NSWorkspace.shared.open(model.store.trackedLinkDestination(for: url) ?? url)
        }
        return .cancel
    }
}
