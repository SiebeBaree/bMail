import DesignSystem
import MailCore
import SQLiteData
import SwiftUI

/// L. Your labels for the open or picked conversations: type to filter, Enter to put the highlighted one on or take it
/// off, and a name that doesn't exist yet creates it.
struct LabelPicker: View {
    @Environment(AppModel.self) private var model
    @FetchAll(MailLabel.order(by: \.name)) private var labels
    @FetchAll(ConversationLabel.all) private var assignments
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var isFocused: Bool

    private enum Item: Identifiable {
        case label(MailLabel)
        case create(String)

        var id: String {
            switch self {
            case let .label(label): label.id.uuidString
            case let .create(name): "create.\(name)"
            }
        }
    }

    var body: some View {
        let items = items
        ZStack(alignment: .top) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { model.isLabelPickerOpen = false }
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "tag").foregroundStyle(Color.textMuted)
                    TextField(model.targetIDs.count > 1 ? "Label \(model.targetIDs.count) conversations" : "Label as", text: $query)
                        .textFieldStyle(.plain)
                        .font(.geist(15))
                        .focused($isFocused)
                        .onSubmit { run(items[safe: highlighted]) }
                        .onKeyPress(.downArrow) { move(1, in: items) }
                        .onKeyPress(.upArrow) { move(-1, in: items) }
                        .onChange(of: query) { _, _ in highlighted = 0 }
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                Hairline()
                if items.isEmpty {
                    Text("Type a name to create your first label.")
                        .foregroundStyle(Color.textMuted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                row(item, isHighlighted: index == highlighted)
                                    .onTapGesture { run(item) }
                            }
                        }
                    }
                    .frame(height: min(CGFloat(items.count) * 38, 304))
                }
            }
            .frame(width: 420)
            .background(Color.raised, in: .rect(cornerRadius: Metrics.windowRadius))
            .overlay(RoundedRectangle(cornerRadius: Metrics.windowRadius).strokeBorder(Color.lineStrong))
            .shadow(color: .black.opacity(0.45), radius: 30, y: 16)
            .padding(.top, 96)
        }
        .onAppear { isFocused = true }
    }

    private var items: [Item] {
        let name = query.trimmingCharacters(in: .whitespaces)
        let matches = labels
            .compactMap { label in FuzzyMatch.score(name, in: label.name).map { (label, $0) } }
            .sorted { $0.1 > $1.1 }
            .map { Item.label($0.0) }
        let exists = labels.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        return matches + (name.isEmpty || exists ? [] : [.create(name)])
    }

    private func row(_ item: Item, isHighlighted: Bool) -> some View {
        HStack(spacing: 12) {
            switch item {
            case let .label(label):
                Image(systemName: symbol(for: label))
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundStyle(symbol(for: label) == "circle" ? Color.textFaint : Color.accent)
                Text(label.name)
            case let .create(name):
                Image(systemName: "plus").font(.system(size: 12)).frame(width: 18)
                Text("Create \u{201C}\(name)\u{201D}")
            }
            Spacer()
        }
        .foregroundStyle(isHighlighted ? Color.textPrimary : Color.textSecondary)
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(isHighlighted ? Color.selected : .clear)
        .contentShape(.rect)
    }

    /// Filled when every target has the label, a dash when only some do.
    private func symbol(for label: MailLabel) -> String {
        let targets = Set(model.targetIDs)
        let count = assignments.count { $0.labelID == label.id && targets.contains($0.conversationID) }
        return count == 0 ? "circle" : count == targets.count ? "checkmark.circle.fill" : "minus.circle.fill"
    }

    private func move(_ offset: Int, in items: [Item]) -> KeyPress.Result {
        guard !items.isEmpty else { return .ignored }
        highlighted = (highlighted + offset + items.count) % items.count
        return .handled
    }

    private func run(_ item: Item?) {
        guard let item else { return }
        model.isLabelPickerOpen = false
        switch item {
        case let .label(label): model.toggleLabel(label.id)
        case let .create(name): model.createLabel(named: name)
        }
    }
}
