import AppKit
import DesignSystem
import MailCore
import SQLiteData
import SwiftUI
import WebKit

/// Message bodies kept loaded, so a conversation shows its mail the moment it opens. Loading a page means starting a web
/// process, parsing and fetching images; that's what made mail appear as an empty box first. The conversations next to
/// the selection load ahead of time and the most recent pages stay around.
@MainActor
final class MailPages {
    /// One loaded body. Its height is measured once it's on screen and remembered for the next time.
    @MainActor
    @Observable
    final class Entry {
        fileprivate(set) var page: WebPage?
        let isDesigned: Bool
        /// The height to show, once the document is in. Until then the measurements are the empty page's.
        private(set) var height: CGFloat?
        private var isCommitted = false
        private var measured: CGFloat?

        fileprivate init(isDesigned: Bool) {
            self.isDesigned = isDesigned
        }

        func measure(_ height: CGFloat) {
            measured = height
            if isCommitted { self.height = height }
        }

        /// A document no taller than the empty page measures the same, so no new measurement may follow.
        fileprivate func commit() {
            isCommitted = true
            if let measured { height = measured }
        }
    }

    private struct Key: Hashable {
        var messageID: Message.ID
        var dark: Bool
    }

    /// Each page can hold a web process, so the cache stays small.
    private static let capacity = 12

    private let model: AppModel
    private var entries: [Key: Entry] = [:]
    /// Least recently used first.
    private var order: [Key] = []

    init(model: AppModel) {
        self.model = model
    }

    /// Compiles the tracker rules and starts a web process before the first message is opened.
    func warmUp() {
        _ = WebPageFactory.page(html: "", model: model) {}
    }

    func entry(for message: Message, dark: Bool) -> Entry {
        let key = Key(messageID: message.id, dark: dark)
        if let entry = entries[key] {
            touch(key)
            return entry
        }
        let rendered = EmailDocument.render(message, dark: dark)
        let entry = Entry(isDesigned: rendered.isDesigned)
        entry.page = WebPageFactory.page(html: rendered.html, model: model) { [weak entry] in entry?.commit() }
        entries[key] = entry
        touch(key)
        return entry
    }

    /// Loads what the reader would open for the conversations around the selection: the newest message and the unread
    /// ones before it.
    func prefetch(around selection: Conversation.ID?, in order: [Conversation.ID], dark: Bool) {
        guard let selection, let index = order.firstIndex(of: selection) else { return }
        let ids = [index, index + 1, index - 1, index + 2]
            .filter { order.indices.contains($0) }
            .map { order[$0] }
        let messages = (try? model.store.database.read { db in
            try Message.where { ids.contains($0.conversationID) }.order(by: \.sentAt).fetchAll(db)
        }) ?? []
        let unread = Set((try? model.store.database.read { db in
            try Conversation.where { ids.contains($0.id) && !$0.isRead }.select(\.id).fetchAll(db)
        }) ?? [])
        for id in ids {
            let thread = messages.filter { $0.conversationID == id }
            for message in unread.contains(id) ? Array(thread.suffix(3)) : Array(thread.suffix(1)) {
                _ = entry(for: message, dark: dark)
            }
        }
    }

    private func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > Self.capacity {
            entries[order.removeFirst()] = nil
        }
    }
}

@MainActor
enum WebPageFactory {
    static let baseURL = URL(string: "mail-asset://message/")!
    private static var rules: WKContentRuleList?
    /// One store for every message, so WebKit can reuse its web content processes instead of starting fresh each time.
    private static let dataStore = WKWebsiteDataStore.nonPersistent()

    /// A page loading `html`. The tracker rules are in place before its first request, or your own pixel would count
    /// as an open.
    static func page(html: String, model: AppModel, committed: @escaping @MainActor () -> Void) -> WebPage {
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = dataStore
        configuration.defaultNavigationPreferences.allowsContentJavaScript = false
        if let scheme = URLScheme("mail-asset") { configuration.urlSchemeHandlers[scheme] = AssetSchemeHandler() }
        let controller = configuration.userContentController
        let page = WebPage(configuration: configuration, navigationDecider: LinkDecider(model: model))
        Task {
            if let rules = await trackerRules() { controller.add(rules) }
            for try await event in page.load(html: html, baseURL: baseURL) where event == .committed {
                committed()
            }
        }
        return page
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
