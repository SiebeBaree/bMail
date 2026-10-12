import DesignSystem
import MailCore
import MailUI
import SQLiteData
import SwiftUI

/// Your labels for one or more conversations. Tap to put one on or take it off; type a name that doesn't exist yet to
/// create it.
struct LabelPicker: View {
    let conversations: [Conversation.ID]
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @FetchAll(MailLabel.order(by: \.name)) private var labels
    @FetchAll(ConversationLabel.all) private var assignments
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if let name = newName {
                    Button {
                        model.session.createLabel(named: name, on: conversations)
                        query = ""
                    } label: {
                        Label("Create \u{201C}\(name)\u{201D}", systemImage: "plus")
                            .font(.phone(16))
                            .foregroundStyle(Color.textPrimary)
                    }
                    .listRowBackground(Color.raised)
                }
                ForEach(matches) { label in
                    Button {
                        model.session.toggleLabel(label.id, on: conversations)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: symbol(for: label))
                                .font(.system(size: 19))
                                .foregroundStyle(symbol(for: label) == "circle" ? Color.textFaint : Color.accent)
                                .contentTransition(.symbolEffect(.replace))
                            Text(label.name).font(.phone(16)).foregroundStyle(Color.textPrimary)
                            Spacer(minLength: 0)
                        }
                        .contentShape(.rect)
                    }
                    .listRowBackground(Color.raised)
                    .accessibilityAddTraits(symbol(for: label) == "checkmark.circle.fill" ? .isSelected : [])
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.chrome)
            .overlay {
                if labels.isEmpty, newName == nil {
                    Text("Type a name to create your first label.")
                        .font(.phone(16))
                        .foregroundStyle(Color.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(40)
                }
            }
            .navigationTitle(conversations.count > 1 ? "Label \(conversations.count) Conversations" : "Label")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find or create a label")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.chrome)
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    private var matches: [MailLabel] {
        trimmed.isEmpty ? labels : labels.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    /// The name to create, when what you typed isn't a label yet.
    private var newName: String? {
        guard !trimmed.isEmpty, !labels.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return nil }
        return trimmed
    }

    /// Filled when every conversation has the label, a dash when only some do.
    private func symbol(for label: MailLabel) -> String {
        let targets = Set(conversations)
        let count = assignments.count { $0.labelID == label.id && targets.contains($0.conversationID) }
        return count == 0 ? "circle" : count == targets.count ? "checkmark.circle.fill" : "minus.circle.fill"
    }
}
