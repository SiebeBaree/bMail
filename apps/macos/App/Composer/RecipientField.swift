import DesignSystem
import MailCore
import SwiftUI

/// Addresses as tokens. Type and press Return, Tab or a comma to add one; Backspace on an empty field removes the last.
/// Suggestions come from people you've written to, most frequent first.
struct RecipientField: View {
    let label: String
    @Binding var addresses: [Address]
    var focusOnAppear = false
    @Environment(AppModel.self) private var app
    @State private var input = ""
    @State private var suggestions: [Contact] = []
    @State private var highlighted = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(Color.textMuted).frame(width: 56, alignment: .leading)
            FlowLayout(spacing: 6) {
                ForEach(addresses, id: \.email) { address in
                    Token(address: address) { addresses.removeAll { $0.email == address.email } }
                }
                TextField("", text: $input)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .frame(minWidth: 140)
                    .onSubmit { commit(suggestion: suggestions[safe: highlighted]) }
                    .onKeyPress(.tab) { commit(suggestion: suggestions[safe: highlighted]) ? .handled : .ignored }
                    .onKeyPress(.downArrow) { move(1) }
                    .onKeyPress(.upArrow) { move(-1) }
                    .onKeyPress(.delete) {
                        guard input.isEmpty, !addresses.isEmpty else { return .ignored }
                        addresses.removeLast()
                        return .handled
                    }
                    .onChange(of: input) { _, text in
                        if text.hasSuffix(",") || text.hasSuffix(";") {
                            input.removeLast()
                            commit(suggestion: nil)
                        } else {
                            suggestions = (try? app.store.contacts(matching: text.trimmingCharacters(in: .whitespaces))) ?? []
                            if text.isEmpty { suggestions = [] }
                            highlighted = 0
                        }
                    }
                    .onChange(of: isFocused) { _, focused in if !focused { commit(suggestion: nil) } }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) { Hairline() }
        .overlay(alignment: .topLeading) {
            if isFocused, !suggestions.isEmpty {
                Suggestions(contacts: suggestions, highlighted: highlighted) { commit(suggestion: $0) }
                    .offset(x: 88, y: 40)
            }
        }
        .zIndex(isFocused ? 1 : 0)
        .onAppear { if focusOnAppear { isFocused = true } }
    }

    private func move(_ offset: Int) -> KeyPress.Result {
        guard !suggestions.isEmpty else { return .ignored }
        highlighted = (highlighted + offset + suggestions.count) % suggestions.count
        return .handled
    }

    @discardableResult
    private func commit(suggestion: Contact?) -> Bool {
        let address: Address?
        if let suggestion {
            address = Address(name: suggestion.name, email: suggestion.email)
        } else {
            let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
            address = text.isEmpty ? nil : Address(email: text)
        }
        guard let address else { return false }
        if !addresses.contains(where: { $0.email.caseInsensitiveCompare(address.email) == .orderedSame }) {
            addresses.append(address)
        }
        input = ""
        suggestions = []
        return true
    }
}

private struct Token: View {
    let address: Address
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(address.name ?? address.email)
                .foregroundStyle(address.email.isPlausibleEmail ? Color.textPrimary : Color.danger)
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Color.selected, in: .rect(cornerRadius: Metrics.keyCapRadius))
        .help(address.email)
    }
}

private struct Suggestions: View {
    let contacts: [Contact]
    let highlighted: Int
    let choose: (Contact) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(contacts.enumerated()), id: \.element.email) { index, contact in
                HStack(spacing: 10) {
                    Avatar(contact.name ?? contact.email, size: 20)
                    Text(contact.name ?? contact.email).foregroundStyle(Color.textPrimary)
                    if contact.name != nil { Text(contact.email).foregroundStyle(Color.textMuted) }
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(index == highlighted ? Color.selected : .clear)
                .contentShape(.rect)
                .onTapGesture { choose(contact) }
            }
        }
        .frame(width: 360)
        .background(Color.raised, in: .rect(cornerRadius: Metrics.popoverRadius))
        .overlay(RoundedRectangle(cornerRadius: Metrics.popoverRadius).strokeBorder(Color.lineStrong))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
    }
}

/// Lays children out left to right and wraps, like words. Used for recipient tokens.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                let isLast = index == subviews.count - 1
                let width = isLast ? max(size.width, bounds.maxX - x) : size.width
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(width: width, height: size.height))
                x += width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if let last = rows.last, !last.indices.isEmpty, last.width + spacing + size.width > width {
                rows.append(Row())
            }
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += (rows[rows.count - 1].indices.count > 1 ? spacing : 0) + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
