import DesignSystem
import MailCore
import MailUI
import SwiftUI
import UIKit

/// Addresses as tokens. Type and press return or a comma to add one, or pick a suggestion from the people you write to
/// most. Backspace in an empty field removes the last token; tap a token to remove any of them.
struct RecipientField: View {
    let label: String
    let kind: ComposerModel.RecipientKind
    @Bindable var model: ComposerModel
    @Binding var focused: ComposerModel.RecipientKind?
    /// Return on an empty field moves on to whatever comes next.
    let next: () -> Void
    @Environment(AppModel.self) private var app
    @State private var suggestions: [Contact] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label).font(.phone(16)).foregroundStyle(Color.textMuted)
                FlowLayout(spacing: 6) {
                    ForEach(model.addresses(kind), id: \.email) { address in
                        Token(address: address) { remove(address) }
                    }
                    RecipientInput(
                        text: Binding { model.pending[kind] ?? "" } set: { typed($0) },
                        isFocused: Binding { focused == kind } set: { isFocused in
                            if isFocused {
                                focused = kind
                            } else if focused == kind {
                                focused = nil
                                commit(model.pending[kind] ?? "")
                            }
                        },
                        submit: submit,
                        backspaceWhenEmpty: { if let last = model.addresses(kind).last { remove(last) } }
                    )
                    .frame(minWidth: 100)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .frame(minHeight: 48)
            .contentShape(.rect)
            .onTapGesture { focused = kind }
            Hairline()
            if focused == kind, !suggestions.isEmpty {
                ForEach(suggestions, id: \.email) { contact in
                    Button { choose(contact) } label: {
                        HStack(spacing: 12) {
                            Avatar(contact.name ?? contact.email, size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(contact.name ?? contact.email).font(.phone(16)).foregroundStyle(Color.textPrimary).lineLimit(1)
                                if contact.name != nil {
                                    Text(contact.email).font(.phone(14)).foregroundStyle(Color.textMuted).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .contentShape(.rect)
                    }
                    .buttonStyle(RowPressStyle())
                }
                Hairline()
            }
        }
    }

    private func typed(_ text: String) {
        // A comma, semicolon or line break ends an address: typed, or in a pasted list of them.
        let parts = text.split(omittingEmptySubsequences: false) { $0 == "," || $0 == ";" || $0 == "\n" }
        if parts.count > 1 {
            for part in parts.dropLast() { commit(String(part)) }
        }
        let rest = String(parts.last ?? "")
        model.pending[kind] = rest
        let query = rest.trimmingCharacters(in: .whitespaces)
        suggestions = query.isEmpty ? [] : (try? app.session.store.contacts(matching: query, limit: 5)) ?? []
    }

    private func submit() {
        let text = (model.pending[kind] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = suggestions.first, !text.isPlausibleEmail {
            choose(first)
        } else if text.isEmpty {
            next()
        } else {
            commit(text)
        }
    }

    private func choose(_ contact: Contact) {
        add(Address(name: contact.name, email: contact.email))
        model.pending[kind] = ""
        suggestions = []
    }

    private func commit(_ text: String) {
        let email = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else { return }
        add(Address(email: email))
        model.pending[kind] = ""
        suggestions = []
    }

    private func add(_ address: Address) {
        let current = model.addresses(kind)
        guard !current.contains(where: { $0.email.caseInsensitiveCompare(address.email) == .orderedSame }) else { return }
        model.setAddresses(current + [address], for: kind)
    }

    private func remove(_ address: Address) {
        model.setAddresses(model.addresses(kind).filter { $0.email != address.email }, for: kind)
    }
}

/// One recipient. A name when we know it; red when it can't be an address.
private struct Token: View {
    let address: Address
    let remove: () -> Void

    var body: some View {
        Menu {
            Section(address.email) {
                Button("Copy address", systemImage: "doc.on.doc") { UIPasteboard.general.string = address.email }
                Button("Remove", systemImage: "xmark", role: .destructive, action: remove)
            }
        } label: {
            Text(address.name ?? address.email)
                .font(.phone(15))
                .foregroundStyle(address.email.isPlausibleEmail ? Color.textPrimary : Color.danger)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Color.selected, in: .capsule)
        }
        .accessibilityLabel(address.name.map { "\($0), \(address.email)" } ?? address.email)
    }
}

/// The text part of a recipient field. UIKit's, because only UIKit says when backspace is pressed in an empty field,
/// which is how the last token gets removed.
private struct RecipientInput: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let submit: () -> Void
    let backspaceWhenEmpty: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> Field {
        let field = Field()
        field.delegate = context.coordinator
        field.keyboardType = .emailAddress
        field.textContentType = .emailAddress
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.returnKeyType = .next
        field.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: Theme.geist(16, .regular))
        field.adjustsFontForContentSizeCategory = true
        field.textColor = UIColor(Color.textPrimary)
        field.tintColor = UIColor(Color.accent)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.backspaceWhenEmpty = { context.coordinator.parent.backspaceWhenEmpty() }
        return field
    }

    func updateUIView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        if isFocused, !field.isFirstResponder {
            // The next run loop turn: becoming first responder in the middle of an update is ignored.
            DispatchQueue.main.async { field.becomeFirstResponder() }
        } else if !isFocused, field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: Field, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 100, height: max(28, uiView.intrinsicContentSize.height))
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: RecipientInput

        init(_ parent: RecipientInput) {
            self.parent = parent
        }

        @objc func changed(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            if !parent.isFocused { parent.isFocused = true }
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            if parent.isFocused { parent.isFocused = false }
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            parent.submit()
            return false
        }
    }

    final class Field: UITextField {
        var backspaceWhenEmpty: () -> Void = {}

        override func deleteBackward() {
            if text?.isEmpty ?? true { backspaceWhenEmpty() }
            super.deleteBackward()
        }
    }
}
