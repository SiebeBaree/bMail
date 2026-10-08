import AppKit
import MailCore

/// Wraps a message's html in a document the reader can show safely and legibly.
///
/// Two kinds of mail need two treatments. Plain mail (what people write) gets our type and colors, also in dark mode.
/// Designed mail (newsletters, receipts with their own backgrounds and table layouts) is shown exactly as sent, on a
/// light surface, because recoloring it breaks it. Nothing is ever color-inverted.
enum EmailDocument {
    struct Rendered {
        var html: String
        var isDesigned: Bool
    }

    static func render(_ message: Message, dark: Bool) -> Rendered {
        let body = message.html ?? textAsHTML(message.text ?? "")
        let designed = message.html.map(isDesigned) ?? false
        let html = """
            <!doctype html>
            <html>
            <head>
            <meta charset="utf-8">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src * data: cid:; style-src 'unsafe-inline' *; font-src * data: mail-asset:; media-src *">
            <meta name="color-scheme" content="\(designed || !dark ? "light" : "dark")">
            <style>
            /* The web view is as tall as its content and the thread scrolls around it, so it never shows bars of its own. */
            ::-webkit-scrollbar { display: none; }
            \(designed ? designedStyle : plainStyle(dark: dark))</style>
            </head>
            <body>\(body)</body>
            </html>
            """
        return Rendered(html: html, isDesigned: designed)
    }

    /// Own backgrounds or a fixed-width table layout mean someone designed this and expects it shown as is.
    static func isDesigned(_ html: String) -> Bool {
        let patterns = [
            #"bgcolor\s*=\s*["']?#?(?!fff\b|ffffff\b|white\b)[0-9a-z]+"#,
            #"background(-color)?\s*:\s*(?!transparent|#fff\b|#ffffff\b|white\b|none)"#,
            #"<table[^>]+width\s*=\s*["']?[4-9]\d\d"#,
        ]
        return patterns.contains { html.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    private static func plainStyle(dark: Bool) -> String {
        let text = dark ? "#d4d4d4" : "#262626"
        let muted = dark ? "#8f8f8f" : "#737373"
        let link = dark ? "#52a8ff" : "#0068d6"
        let line = dark ? "#2e2e2e" : "#e5e5e5"
        return """
            @font-face { font-family: Geist; src: url(mail-asset://fonts/Geist-Variable.ttf); font-weight: 100 900; }
            html, body { margin: 0; padding: 0; background: transparent; }
            body { font: 14px/1.65 Geist, -apple-system, sans-serif; color: \(text); overflow-wrap: anywhere; -webkit-font-smoothing: antialiased; }
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

    private static let designedStyle = """
        html { background: #ffffff; }
        body { margin: 0; padding: 20px; background: #ffffff; color: #111111; font: 14px/1.5 -apple-system, sans-serif; }
        img { max-width: 100%; height: auto; }
        """

    static func textAsHTML(_ text: String) -> String {
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
