import Foundation
import SwiftUI

/// Turns what you typed into the html and text parts of an email. Only what people actually use survives: paragraphs,
/// line breaks, bold, italic, underline and links. Pasted fonts and colors are dropped, so mail looks written, not
/// assembled.
struct BodySerializer {
    let context: Font.Context

    func render(_ body: AttributedString) -> (html: String, text: String) {
        var html = ""
        for run in body.runs {
            var fragment = escape(String(body[run.range].characters))
            let resolved = run.font?.resolve(in: context)
            if resolved?.isBold == true { fragment = "<strong>\(fragment)</strong>" }
            if resolved?.isItalic == true { fragment = "<em>\(fragment)</em>" }
            if run.underlineStyle != nil, run.link == nil { fragment = "<u>\(fragment)</u>" }
            if let link = run.link { fragment = #"<a href="\#(escape(link.absoluteString))">\#(fragment)</a>"# }
            html += fragment
        }
        let paragraphs = html
            .components(separatedBy: "\n\n")
            .map { "<p style=\"margin:0 0 12px\">\($0.replacingOccurrences(of: "\n", with: "<br>"))</p>" }
            .joined()
        return (#"<div style="font-family:-apple-system,Helvetica,Arial,sans-serif;font-size:14px;line-height:1.6">\#(paragraphs)</div>"#, String(body.characters))
    }

    private func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
