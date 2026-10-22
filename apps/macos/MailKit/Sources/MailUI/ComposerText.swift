import DesignSystem
import Foundation
import Observation
import SwiftUI

/// The body of a message being written, and the suggestion that may sit gray after the cursor.
///
/// The suggestion lives in the text the editor shows, so the editor lays it out like the rest. `body` never holds it:
/// sending, signatures and "is there anything to lose" all read `body`, and the editor reads and writes `editorText`,
/// which puts the suggestion in and takes every edit back out.
@MainActor
@Observable
public final class ComposerText {
    /// What you wrote. Never the suggestion.
    public var body: AttributedString {
        didSet { if body != oldValue, !isReconciling { suggestion = nil } }
    }
    public var selection = AttributedTextSelection()
    public private(set) var suggestion: Suggestion?
    /// Asks for what comes next, given the text before and after the cursor. Nil while completion is off or learning.
    @ObservationIgnored public var suggest: (@MainActor (_ before: String, _ after: String) async -> String?)?
    @ObservationIgnored private var request: Task<Void, Never>?
    @ObservationIgnored private var isReconciling = false
    /// The last edit that came back changed. The editor sends each edit twice, and the second copy still has the
    /// suggestion in it.
    @ObservationIgnored private var lastReconciled: String?
    @ObservationIgnored private var shown: (body: AttributedString, suggestion: Suggestion, text: AttributedString)?

    /// What follows the gray text to say which key accepts it. The iPhone has a button above the keyboard instead.
    @ObservationIgnored private let hint: String?

    public init(_ body: AttributedString = AttributedString(), hint: String? = nil) {
        self.body = body
        self.hint = hint
    }

    /// What the editor shows and edits. The same copy every time until something changes, because a selection only
    /// holds in the copy its indices came from.
    public var editorText: AttributedString {
        get {
            guard let suggestion else { return body }
            if let shown, shown.body == body, shown.suggestion == suggestion { return shown.text }
            let text = suggestion.display(in: body)
            shown = (body, suggestion, text)
            return text
        }
        set {
            let characters = String(newValue.characters)
            if characters == lastReconciled { return }
            lastReconciled = nil
            guard let suggestion else {
                guard newValue != body else { return }
                body = newValue
                suggestAfterPause()
                return
            }
            let edit = suggestion.reconcile(body: body, edited: newValue)
            if String(edit.suggestion.map { $0.display(in: edit.body) }?.characters ?? edit.body.characters) != characters {
                lastReconciled = characters
            }
            isReconciling = true
            body = edit.body
            isReconciling = false
            self.suggestion = edit.suggestion
            if let cursor = edit.cursor { place(cursor) }
            if edit.suggestion == nil { suggestAfterPause() }
        }
    }

    /// Puts the cursor at the start of the body.
    public func moveToStart() {
        selection = AttributedTextSelection(range: body.startIndex..<body.startIndex)
    }

    /// Writes the suggestion into the body. False when there's none, so Tab does what it always does.
    @discardableResult
    public func accept() -> Bool {
        guard let suggestion else { return false }
        // The cursor moved away: Tab is a tab again.
        guard cursorOffset == suggestion.offset else {
            dismissSuggestion()
            return false
        }
        isReconciling = true
        body.characters.insert(contentsOf: suggestion.text, at: body.characters.index(body.startIndex, offsetBy: suggestion.offset))
        isReconciling = false
        self.suggestion = nil
        place(suggestion.offset + suggestion.text.count)
        suggestAfterPause()
        return true
    }

    /// Takes the suggestion away, for Esc and for leaving the body. False when there's none.
    @discardableResult
    public func dismissSuggestion() -> Bool {
        request?.cancel()
        guard let suggestion else { return false }
        // Keeps the cursor where it is on screen, wherever that is relative to the gray text.
        let shown = editorText
        var cursor = suggestion.offset
        if case let .insertionPoint(index) = selection.indices(in: shown) {
            let offset = shown.characters.distance(from: shown.startIndex, to: index)
            cursor = offset <= suggestion.offset ? offset : max(suggestion.offset, offset - suggestion.length)
        }
        self.suggestion = nil
        place(cursor)
        return true
    }

    // MARK: - Asking

    /// Asks once you stop typing for a moment, with the cursor at the end of a line. Every edit cancels the request in
    /// flight, and an answer only shows if the text and the cursor are still where they were when it was asked.
    private func suggestAfterPause() {
        request?.cancel()
        guard let suggest else { return }
        request = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self, self.suggestion == nil, let cursor = self.cursorOffset else { return }
            let text = String(self.body.characters)
            let before = String(text.prefix(cursor))
            let after = String(text.dropFirst(cursor))
            guard after.first?.isNewline ?? true else { return }
            guard let answer = await suggest(before, after), !Task.isCancelled, self.suggestion == nil,
                String(self.body.characters) == text, self.cursorOffset == cursor
            else { return }
            self.suggestion = Suggestion(text: answer, offset: cursor, hint: self.hint)
            self.place(cursor)
        }
    }

    /// Where the cursor is in `body`, or nil while text is selected.
    private var cursorOffset: Int? {
        let shown = editorText
        guard case let .insertionPoint(index) = selection.indices(in: shown) else { return nil }
        let offset = shown.characters.distance(from: shown.startIndex, to: index)
        if let suggestion, offset > suggestion.offset { return nil }
        return offset
    }

    /// Puts the cursor at a character offset into the shown text. Again on the next turn of the run loop too: when the
    /// shown text changes, the editor puts its cursor at the end after taking the new text.
    private func place(_ offset: Int) {
        setCursor(offset)
        Task { @MainActor [weak self] in self?.setCursor(offset) }
    }

    private func setCursor(_ offset: Int) {
        let shown = editorText
        let index = shown.characters.index(shown.startIndex, offsetBy: min(offset, shown.characters.count))
        selection = AttributedTextSelection(range: index..<index)
    }
}

/// Gray text after the cursor that Tab accepts, at a character offset into the body.
public struct Suggestion: Equatable, Sendable {
    public var text: String
    public var offset: Int
    /// Plain text on purpose: the editor drops images and draws a background the full height of the line.
    public var hint: String?

    public init(text: String, offset: Int, hint: String? = nil) {
        self.text = text
        self.offset = offset
        self.hint = hint
    }

    /// How many characters it takes up in the editor: the text and the hint after it.
    var length: Int { text.count + (hint.map { $0.count + 1 } ?? 0) }

    /// The body with the suggestion in it, gray, and the hint after it.
    func display(in body: AttributedString) -> AttributedString {
        var shown = body
        var gray = AttributedString(text)
        gray.foregroundColor = Color.textFaint
        if let hint {
            var small = AttributedString(" \(hint)")
            small.foregroundColor = Color.textMuted
            small.font = .keyCap
            gray += small
        }
        shown.insert(gray, at: shown.characters.index(shown.startIndex, offsetBy: offset))
        return shown
    }

    /// Splits what the editor wrote back into your body and what's left of the suggestion. Typing the suggestion's
    /// next letters walks through it; anything else drops it. `cursor` is where the cursor belongs when the shown text
    /// is about to change under it.
    func reconcile(body: AttributedString, edited: AttributedString) -> (body: AttributedString, suggestion: Suggestion?, cursor: Int?) {
        let old = Array(display(in: body).characters)
        let new = Array(edited.characters)
        let range = offset..<(offset + length)

        // Typing at the cursor, the usual case: everything before and after it is as it was.
        if new.count >= old.count, new.starts(with: old[..<offset]), new.reversed().starts(with: old[offset...].reversed()) {
            let typed = new.count - old.count
            var body = edited
            body.removeSubrange(Self.indices(offset + typed..<offset + typed + length, in: body))
            body = Self.plain(body)
            if typed == 0 { return (body, self, nil) }
            let inserted = String(new[offset..<offset + typed])
            guard text.hasPrefix(inserted), inserted.count < text.count else { return (body, nil, offset + typed) }
            var rest = self
            rest.text = String(text.dropFirst(typed))
            rest.offset = offset + typed
            return (body, rest, offset + typed)
        }

        // Anything else: whatever survived of the suggestion comes out and it's gone.
        var prefix = 0
        while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(old.count, new.count) - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        let delta = new.count - old.count
        let before = range.clamped(to: 0..<prefix)
        let after = range.clamped(to: (old.count - suffix)..<old.count)
        var body = edited
        if !after.isEmpty { body.removeSubrange(Self.indices(after.lowerBound + delta..<after.upperBound + delta, in: body)) }
        if !before.isEmpty { body.removeSubrange(Self.indices(before, in: body)) }
        return (Self.plain(body), nil, new.count - suffix - before.count)
    }

    private static func indices(_ range: Range<Int>, in text: AttributedString) -> Range<AttributedString.Index> {
        let start = text.characters.index(text.startIndex, offsetBy: range.lowerBound)
        return start..<text.characters.index(start, offsetBy: range.count)
    }

    /// Letters typed next to the suggestion can pick up its gray. Mail carries no colors, so they all go.
    private static func plain(_ text: AttributedString) -> AttributedString {
        var text = text
        text.foregroundColor = nil
        return text
    }
}
