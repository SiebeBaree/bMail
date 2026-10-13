import Foundation
import MailCore

/// Wraps a message's html in a document the reader can show safely and legibly.
///
/// Two kinds of mail need two treatments. Plain mail (what people write) gets our type and colors, also in dark mode.
/// Designed mail (newsletters, receipts with their own backgrounds and table layouts) is shown exactly as sent, on a
/// light surface, because recoloring it breaks it. Nothing is ever color-inverted.
///
/// On iPhone the document is pinned to `width`, the reader's full width, and plain mail brings its own margins. Mail
/// wider than that is scaled down to fit by `fitScript`, so nothing scrolls sideways.
public enum EmailDocument {
    public struct Rendered {
        public var html: String
        public var isDesigned: Bool
    }

    /// Plain mail's side margins on iPhone, where the body spans the screen and carries its own.
    public static let phoneMargin = 16

    public static func render(_ message: Message, dark: Bool, width: Int? = nil) -> Rendered {
        let body = message.html.map(withoutDarkMode) ?? textAsHTML(message.text ?? "")
        let designed = message.html.map(isDesigned) ?? false
        let viewport = width.map { #"<meta name="viewport" content="width=\#($0), initial-scale=1, maximum-scale=1, user-scalable=no">"# } ?? ""
        let html = """
            <!doctype html>
            <html\(width.map { #" data-fit-width="\#($0)""# } ?? "")>
            <head>
            <meta charset="utf-8">
            \(viewport)
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src * data: cid:; style-src 'unsafe-inline' *; font-src * data: mail-asset:; media-src *">
            <meta name="color-scheme" content="\(designed || !dark ? "light" : "dark")">
            <style>
            /* The web view is as tall as its content and the thread scrolls around it, so it never shows bars of its own.
               A page sized to the view (html, body { height: 100% }, common in newsletters) grows with it and the view
               with the page, forever. :root outranks the mail's own selectors. */
            ::-webkit-scrollbar { display: none; }
            :root, :root > body { height: auto !important; min-height: 0 !important; }
            html { -webkit-text-size-adjust: 100%; }
            \(width.map { ":root { width: \($0)px !important; }" } ?? "")
            \(designed ? designedStyle(phone: width != nil) : plainStyle(dark: dark, phone: width != nil))</style>
            </head>
            <body>\(body)</body>
            </html>
            """
        return Rendered(html: html, isDesigned: designed)
    }

    /// Scales the body down when its content is wider than the document's `data-fit-width`, and again when a late image
    /// widens it. The page is pinned to that width because a page loading ahead of time isn't on screen yet and lays out
    /// at WebKit's default 980. The body scales rather than the root, so the pinned width stays the screen's. Runs in the
    /// app's own script world, since the mail's scripts are off, and in every page: one without a width only reports in.
    public static let fitScript = """
        (() => {
            const width = Number(document.documentElement.dataset.fitWidth);
            const body = document.body;
            const fit = () => {
                if (!width || !body) return;
                body.style.zoom = '';
                // The body's, not the root's: off screen the root scrolls as wide as the 980 point viewport. Content
                // that overflows leaves the body's right padding out of its scroll width.
                const overflows = body.scrollWidth > body.clientWidth;
                const content = body.scrollWidth + (overflows ? parseFloat(getComputedStyle(body).paddingRight) || 0 : 0);
                if (content > width + 1) body.style.zoom = String(width / content);
            };
            fit();
            for (const image of document.images) {
                if (!image.complete) image.addEventListener('load', fit, { once: true });
            }
            window.webkit.messageHandlers.fitted.postMessage(null);
        })();
        """

    /// Turns off a mail's own dark mode styles. They expect a client that also darkens everything they don't style, and
    /// the reader never does: in a dark app they paint light text onto the white surface designed mail sits on. An
    /// unknown value makes the media query false.
    public static func withoutDarkMode(_ html: String) -> String {
        html.replacingOccurrences(of: #"prefers-color-scheme\s*:\s*dark"#, with: "prefers-color-scheme: never", options: [.regularExpression, .caseInsensitive])
    }

    /// Own backgrounds or a fixed-width table layout mean someone designed this and expects it shown as is.
    public static func isDesigned(_ html: String) -> Bool {
        let patterns = [
            #"bgcolor\s*=\s*["']?#?(?!fff\b|ffffff\b|white\b)[0-9a-z]+"#,
            #"background(-color)?\s*:\s*(?!transparent|#fff\b|#ffffff\b|white\b|none)"#,
            #"<table[^>]+width\s*=\s*["']?[4-9]\d\d"#,
        ]
        return patterns.contains { html.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    private static func plainStyle(dark: Bool, phone: Bool) -> String {
        let text = dark ? "#d4d4d4" : "#262626"
        let muted = dark ? "#8f8f8f" : "#737373"
        let link = dark ? "#52a8ff" : "#0068d6"
        let line = dark ? "#2e2e2e" : "#e5e5e5"
        let font = phone ? "16px/1.6" : "14px/1.65"
        let margin = phone ? "0 \(phoneMargin)px" : "0"
        return """
            @font-face { font-family: Geist; src: url(mail-asset://fonts/Geist-Variable.ttf); font-weight: 100 900; }
            html, body { margin: 0; padding: 0; background: transparent; }
            body { font: \(font) Geist, -apple-system, sans-serif; color: \(text); overflow-wrap: anywhere; -webkit-font-smoothing: antialiased; padding: \(margin); }
            body * { color: inherit !important; background-color: transparent !important; font-family: inherit !important; }
            p { margin: 0 0 10px; }
            a, a * { color: \(link) !important; text-decoration: none; }
            a:hover { text-decoration: underline; }
            blockquote { margin: 8px 0; padding-left: 12px; border-left: 2px solid \(line); color: \(muted) !important; }
            blockquote * { color: \(muted) !important; }
            img { max-width: 100%; height: auto; }
            pre, code { font: 12.5px/1.6 ui-monospace, Menlo, monospace; white-space: pre-wrap; }
            hr { border: 0; border-top: 1px solid \(line); }
            table { max-width: 100%; }
            """
    }

    /// Light no matter what the mail declares, so system colors (text without a color of its own) stay dark on white.
    private static func designedStyle(phone: Bool) -> String {
        """
        :root { color-scheme: only light !important; }
        html { background: #ffffff; }
        body { margin: 0; padding: \(phone ? "12px" : "20px"); background: #ffffff; color: #111111; font: 14px/1.5 -apple-system, sans-serif; }
        img { max-width: 100%; height: auto; }
        """
    }

    public static func textAsHTML(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return escaped
            .components(separatedBy: "\n\n")
            .map { "<p>\($0.replacingOccurrences(of: "\n", with: "<br>"))</p>" }
            .joined()
    }
}
