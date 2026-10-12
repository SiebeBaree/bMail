import DesignSystem
import MailCore
import SQLiteData
import SwiftUI
import WebKit

/// Message bodies kept loaded, so a conversation shows its mail the moment it opens. Loading a page means starting a web
/// process, parsing and fetching images; that's what made mail appear as an empty box first. The conversations next to
/// the selection load ahead of time and the most recent pages stay around.
@MainActor
public final class MailPages {
    /// One loaded body. Its height is measured once it's on screen and remembered for the next time.
    @MainActor
    @Observable
    public final class Entry {
        public fileprivate(set) var page: WebPage?
        public let isDesigned: Bool
        /// The height to show, once the document is in. Until then the measurements are the empty page's.
        public private(set) var height: CGFloat?
        private var isCommitted = false
        private var measured: CGFloat?

        fileprivate init(isDesigned: Bool) {
            self.isDesigned = isDesigned
        }

        public func measure(_ height: CGFloat) {
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
        var width: Int?
    }

    /// Each page can hold a web process, so the cache stays small.
    private static let capacity = 12

    private let store: MailStore
    private let apiHost: @MainActor () -> String?
    private let open: @MainActor (URL) -> Void
    private var entries: [Key: Entry] = [:]
    /// Least recently used first.
    private var order: [Key] = []

    /// `open` gets every link you tap in a message, already resolved past our own tracking. `apiHost` is your server,
    /// whose open pixel is blocked like every `t.` host's.
    public init(store: MailStore, apiHost: @escaping @MainActor () -> String?, open: @escaping @MainActor (URL) -> Void) {
        self.store = store
        self.apiHost = apiHost
        self.open = open
    }

    /// Compiles the tracker rules and starts web processes before the first message is opened.
    public func warmUp() {
        refillSpares()
    }

    /// `width` is the reader's width on iPhone, where documents are laid out to fit it. Nil on the Mac.
    public func entry(for message: Message, dark: Bool, width: Int? = nil) -> Entry {
        let key = Key(messageID: message.id, dark: dark, width: width)
        if let entry = entries[key] {
            touch(key)
            return entry
        }
        let rendered = EmailDocument.render(message, dark: dark, width: width)
        let entry = Entry(isDesigned: rendered.isDesigned)
        entry.page = page(html: rendered.html, width: width) { [weak entry] in entry?.commit() }
        entries[key] = entry
        touch(key)
        return entry
    }

    /// Loads what the reader would open for the conversations around the selection: the newest message and the unread
    /// ones before it.
    public func prefetch(around selection: Conversation.ID?, in order: [Conversation.ID], dark: Bool, width: Int? = nil) {
        guard let selection, let index = order.firstIndex(of: selection) else { return }
        let ids = [index, index + 1, index - 1, index + 2]
            .filter { order.indices.contains($0) }
            .map { order[$0] }
        prefetch(ids, dark: dark, width: width)
    }

    public func prefetch(_ ids: [Conversation.ID], dark: Bool, width: Int? = nil) {
        let messages = (try? store.database.read { db in
            try Message.where { $0.conversationID.in(ids) }.order(by: \.sentAt).fetchAll(db)
        }) ?? []
        let unread = Set((try? store.database.read { db in
            try Conversation.where { $0.id.in(ids) && !$0.isRead }.select(\.id).fetchAll(db)
        }) ?? [])
        for id in ids {
            let thread = messages.filter { $0.conversationID == id }
            for message in unread.contains(id) ? Array(thread.suffix(3)) : Array(thread.suffix(1)) {
                _ = entry(for: message, dark: dark, width: width)
            }
        }
    }

    /// Lets every page go, for when the system is short on memory.
    public func removeAll() {
        entries = [:]
        order = []
        spares = []
    }

    private func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > Self.capacity {
            entries[order.removeFirst()] = nil
        }
    }

    // MARK: - Pages

    static let baseURL = URL(string: "mail-asset://message/")!
    /// Compiled for one api host, since the rules block its pixel too.
    private static var rules: (apiHost: String, list: WKContentRuleList)?
    /// One store for every message, so WebKit can reuse its web content processes instead of starting fresh each time.
    private static let dataStore = WKWebsiteDataStore.nonPersistent()

    /// A page with its web process already running, waiting for a message. Starting that process is most of the time a
    /// body takes to appear, so a couple wait ready and are refilled as they're taken.
    private struct Spare {
        let page: WebPage
        let fit: FitHandler
        /// Done once the tracker rules are in and the process is up.
        let ready: Task<Void, Never>
    }

    private static let spareCount = 2
    private var spares: [Spare] = []

    /// A page loading `html`. The tracker rules are in place before its first request, or your own pixel would count
    /// as an open. `committed` runs once the document is in and, with a `width`, scaled to fit it.
    private func page(html: String, width: Int?, committed: @escaping @MainActor () -> Void) -> WebPage {
        let spare = spares.isEmpty ? makeSpare() : spares.removeFirst()
        refillSpares()
        Task {
            await spare.ready.value
            // Only now: the empty document that warmed the page up reports in too.
            spare.fit.fitted = width == nil ? nil : committed
            do {
                for try await event in spare.page.load(html: html, baseURL: Self.baseURL) {
                    // Fitting reports in on its own; finishing covers a page whose script never ran.
                    if (event == .committed && width == nil) || event == .finished { committed() }
                }
            } catch {
                // Whatever did load is better than a body that never appears.
                committed()
            }
        }
        return spare.page
    }

    private func refillSpares() {
        while spares.count < Self.spareCount {
            spares.append(makeSpare())
        }
    }

    private func makeSpare() -> Spare {
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = Self.dataStore
        configuration.defaultNavigationPreferences.allowsContentJavaScript = false
        if let scheme = URLScheme("mail-asset") { configuration.urlSchemeHandlers[scheme] = AssetSchemeHandler() }
        let controller = configuration.userContentController
        let fit = FitHandler()
        controller.addUserScript(WKUserScript(source: EmailDocument.fitScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        controller.add(fit, contentWorld: .defaultClient, name: "fitted")
        let page = WebPage(configuration: configuration, navigationDecider: LinkDecider(store: store, open: open))
        let apiHost = apiHost() ?? ""
        let ready = Task {
            if let rules = await Self.trackerRules(apiHost: apiHost) { controller.add(rules) }
            // Loading anything starts the web process.
            do {
                for try await _ in page.load(html: "", baseURL: Self.baseURL) {}
            } catch {}
        }
        return Spare(page: page, fit: fit, ready: ready)
    }

    /// Blocks open pixels: ours on every `t.` host and the api, and the common ones other senders use. This is what keeps
    /// you from counting as an open on mail you sent to yourself.
    private static func trackerRules(apiHost: String) async -> WKContentRuleList? {
        if let rules, rules.apiHost == apiHost { return rules.list }
        let patterns = [
            #"^https?://t\.[^/]+/o/"#,
            "^https?://" + NSRegularExpression.escapedPattern(for: apiHost) + "/o/",
            #"^https?://[^/]+/wf/open"#,
            #"^https?://[^/]*list-manage\.com/track/open"#,
            #"^https?://[^/]*mandrillapp\.com/track/open"#,
            #"^https?://[^/]*(mailtrack\.io|mixmax\.com|yesware\.com|streak\.com|superhuman\.com|hubspot(links)?\.com)/"#,
            #"^https?://[^/]+/(e/)?(open|pixel|track(ing)?/open)[^/]*\.(gif|png)"#,
        ]
        let json = "[" + patterns.map { #"{"trigger":{"url-filter":"\#($0.replacingOccurrences(of: "\\", with: "\\\\"))"},"action":{"type":"block"}}"# }.joined(separator: ",") + "]"
        guard let list = try? await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "trackers", encodedContentRuleList: json) else {
            return nil
        }
        rules = (apiHost, list)
        return list
    }
}

/// Hears from `EmailDocument.fitScript` that the document is laid out at its final scale.
@MainActor
private final class FitHandler: NSObject, WKScriptMessageHandler {
    var fitted: (@MainActor () -> Void)?

    nonisolated func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { fitted?() }
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

/// The document and its anchors load in place. Only a tap or click leaves it; a navigation the mail starts on its own,
/// like a meta refresh, is dropped. A link to one of our tracked urls opens the original destination directly, so you
/// never count as a click on your own mail.
private struct LinkDecider: WebPage.NavigationDeciding {
    let store: MailStore
    let open: @MainActor (URL) -> Void

    func decidePolicy(for action: WebPage.NavigationAction, preferences: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        if url.scheme == MailPages.baseURL.scheme { return .allow }
        guard action.navigationType == .linkActivated else { return .cancel }
        open(store.trackedLinkDestination(for: url) ?? url)
        return .cancel
    }
}
