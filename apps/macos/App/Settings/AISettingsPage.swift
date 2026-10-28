import Assist
import DesignSystem
import MailCore
import MailUI
import SQLiteData
import SwiftUI

/// Your own AI key and the two features that use it: tab completion and auto labelling. Requests go from this Mac
/// straight to the provider.
struct AISettingsPage: View {
    @Environment(AppModel.self) private var model
    @FetchOne(Message.where { $0.direction.eq(Direction.outbound) }.count()) private var sent = 0
    @State private var models: [AIModel] = []

    var body: some View {
        @Bindable var ai = model.session.ai
        VStack(alignment: .leading, spacing: 28) {
            ProviderGroup()
            // The same names as the iPhone's settings.
            SettingsGroup("Writing") {
                GroupRow("Suggestions", note: "Gray text after the cursor. Tab accepts.") {
                    Toggle(isOn: $ai.isCompletionOn) { EmptyView() }.toggleStyle(.mailSwitch).accessibilityLabel("Suggestions")
                }
                GroupRow("Model") { ModelPicker(choice: $ai.completion, provider: ai.provider, models: models) }
                if sent < CompletionPrompt.minimumSentMails {
                    GroupRow("Learning your style", note: "Starts after \(CompletionPrompt.minimumSentMails) sent emails. \(sent) so far.")
                }
            }
            SettingsGroup("Labels") {
                GroupRow("Auto labelling", note: "Labels new inbox mail that matches a description below.") {
                    Toggle(isOn: $ai.isLabellingOn) { EmptyView() }.toggleStyle(.mailSwitch).accessibilityLabel("Auto labelling")
                }
                GroupRow("Model") { ModelPicker(choice: $ai.labelling, provider: ai.provider, models: models) }
            }
            LabelDescriptions()
        }
        .onChange(of: ai.isLabellingOn) { _, isOn in if isOn { model.session.labelNewMail() } }
        .task(id: "\(ai.provider.rawValue).\(ai.key)") {
            models = []
            // Waits out the typing of a key, so each keystroke isn't a request.
            try? await Task.sleep(for: .milliseconds(600))
            guard let client = ai.client, !Task.isCancelled else { return }
            models = (try? await client.models()) ?? []
        }
    }
}

// MARK: - Layout

/// A muted label over a rounded group of rows, split by hairlines.
struct SettingsGroup<Rows: View>: View {
    let label: String
    @ViewBuilder let rows: () -> Rows

    init(_ label: String, @ViewBuilder rows: @escaping () -> Rows) {
        self.label = label
        self.rows = rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).foregroundStyle(Color.textMuted).padding(.leading, 14)
            VStack(spacing: 0) { rows() }
                .background(Color.raised)
                .clipShape(.rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.line))
        }
    }
}

/// One row: what it is on the left, with a short note under it, and its control on the right. The hairline on top is
/// hidden under the group's border on the first row.
struct GroupRow<Control: View>: View {
    let title: String
    let note: Text?
    @ViewBuilder let control: () -> Control

    init(_ title: String, note: String? = nil, @ViewBuilder control: @escaping () -> Control = { EmptyView() }) {
        self.title = title
        self.note = note.map { Text($0) }
        self.control = control
    }

    init(_ title: String, note: Text?, @ViewBuilder control: @escaping () -> Control = { EmptyView() }) {
        self.title = title
        self.note = note
        self.control = control
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let note { note.font(.geist(12)).foregroundStyle(Color.textMuted) }
            }
            Spacer(minLength: 16)
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .overlay(alignment: .top) { Hairline() }
    }
}

// MARK: - Provider

/// The provider, your key for it and a check that both work.
struct ProviderGroup: View {
    @Environment(AppModel.self) private var model
    @State private var isOpen = false
    @State private var status: Status?

    enum Status: Equatable {
        case checking
        case connected(milliseconds: Int)
        case failed(String)
    }

    var body: some View {
        @Bindable var ai = model.session.ai
        SettingsGroup("Provider") {
            GroupRow("Provider") {
                Button { isOpen.toggle() } label: {
                    HStack(spacing: 7) {
                        LogoView(ai.provider.logo)
                        Text(ai.provider.title)
                        Chevron()
                    }
                }
                .buttonStyle(.secondary)
                .dropdown(isPresented: $isOpen, alignment: .trailing) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Button {
                            isOpen = false
                            ai.provider = provider
                        } label: {
                            HStack(spacing: 10) {
                                LogoView(provider.logo, size: 16)
                                Text(provider.title)
                                Spacer(minLength: 16)
                                Checkmark(isOn: provider == ai.provider)
                            }
                        }
                        .buttonStyle(.dropdownItem)
                    }
                }
            }
            GroupRow("API key", note: keyNote(ai)) {
                HStack(spacing: 8) {
                    SecureField("Paste your key", text: $ai.key)
                        .textFieldStyle(.field)
                        .frame(width: 220)
                        .onSubmit(check)
                    Button(status == .checking ? "Checking" : "Check", action: check)
                        .buttonStyle(.secondary)
                        .disabled(ai.key.isEmpty || status == .checking)
                }
            }
        }
        .onChange(of: ai.provider) { _, _ in status = nil }
        .onChange(of: ai.key) { _, _ in status = nil }
    }

    /// The last check, the last thing that went wrong, or where to get a key.
    private func keyNote(_ ai: AISettings) -> Text {
        switch status {
        case let .connected(milliseconds): return Text("Connected, \(milliseconds) ms")
        case let .failed(message): return Text(message).foregroundStyle(Color.danger)
        case .checking, nil:
            if let problem = model.session.aiProblem { return Text(problem).foregroundStyle(Color.danger) }
            // From a String, so the link is read as markdown.
            return Text(LocalizedStringKey("In this Mac's keychain. [Get a key](\(ai.provider.keysURL.absoluteString))"))
        }
    }

    private func check() {
        let ai = model.session.ai
        guard let client = ai.client else { return }
        status = .checking
        Task {
            do {
                let elapsed = try await client.check(ai.isCompletionOn || !ai.isLabellingOn ? ai.completion : ai.labelling)
                status = .connected(milliseconds: Int(elapsed / .milliseconds(1)))
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }
}

// MARK: - Model and reasoning

/// One button for the model and how hard it thinks. Opens with the models on the left, searchable, and the provider's
/// reasoning levels on the right. Split into small views: as one expression it takes the compiler minutes to check.
private struct ModelPicker: View {
    @Binding var choice: ModelChoice
    let provider: AIProvider
    let models: [AIModel]
    @State private var isOpen = false

    var body: some View {
        Button { isOpen.toggle() } label: { label }
            .buttonStyle(.secondary)
            .dropdown(isPresented: $isOpen, alignment: .trailing) {
                HStack(alignment: .top, spacing: 0) {
                    ModelList(choice: $choice, provider: provider, models: models)
                    Rectangle().fill(Color.line).frame(width: 1, height: 333)
                    ReasoningList(choice: $choice, levels: provider.reasoningLevels)
                }
            }
    }

    private var label: some View {
        HStack(spacing: 7) {
            LogoView(Logo.of(model: choice.model, on: provider))
            Text(models.first { $0.id == choice.model }?.name ?? choice.model).lineLimit(1)
            Rectangle().fill(Color.lineStrong).frame(width: 1, height: 12)
            Image(systemName: "brain").font(.smallIcon).foregroundStyle(Color.textMuted)
            Text(choice.reasoning.title).foregroundStyle(Color.textSecondary)
            Chevron()
        }
    }
}

/// The models the key can use, with a search field over them.
private struct ModelList: View {
    @Binding var choice: ModelChoice
    let provider: AIProvider
    let models: [AIModel]
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.smallIcon).foregroundStyle(Color.textFaint)
                TextField("Search models", text: $search).textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            Hairline()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(matches) { model in
                        ModelRow(model: model, provider: provider, isSelected: model.id == choice.model) { choice.model = model.id }
                    }
                    if matches.isEmpty {
                        Text(models.isEmpty ? "Add your key to see models" : "No models match")
                            .foregroundStyle(Color.textMuted)
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                }
                .padding(.top, 4)
            }
            .frame(height: 300)
        }
        .frame(width: 300)
    }

    /// The picked model stays in the list even when the provider doesn't list it, so it can always be seen. A typed id
    /// nobody lists can be used as is.
    private var matches: [AIModel] {
        let typed = search.trimmingCharacters(in: .whitespaces)
        let listed = models.contains { $0.id == choice.model } ? models : [AIModel(id: choice.model, name: nil)] + models
        guard !typed.isEmpty else { return listed }
        let found = listed.filter { $0.matches(typed) }
        if listed.contains(where: { $0.id == typed }) { return found }
        return [AIModel(id: typed, name: "Use \u{201C}\(typed)\u{201D}")] + found
    }
}

private struct ModelRow: View {
    let model: AIModel
    let provider: AIProvider
    let isSelected: Bool
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 10) {
                LogoView(Logo.of(model: model.id, on: provider), size: 16)
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.name ?? model.id).lineLimit(1)
                    if model.name != nil {
                        Text(model.id).font(.meta).foregroundStyle(Color.textMuted).lineLimit(1)
                    }
                }
                Spacer(minLength: 12)
                Checkmark(isOn: isSelected)
            }
            .padding(.vertical, 3)
        }
        .buttonStyle(.dropdownItem)
    }
}

/// The reasoning levels the provider can express.
private struct ReasoningList: View {
    @Binding var choice: ModelChoice
    let levels: [Reasoning]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Reasoning").font(.geist(12)).foregroundStyle(Color.textMuted).padding(.horizontal, 8).frame(height: 32)
            ForEach(levels, id: \.self) { level in
                Button { choice.reasoning = level } label: {
                    HStack {
                        Text(level.title).foregroundStyle(level == choice.reasoning ? Color.textPrimary : Color.textSecondary)
                        Spacer(minLength: 8)
                        Checkmark(isOn: level == choice.reasoning)
                    }
                }
                .buttonStyle(.dropdownItem)
            }
        }
        .frame(width: 132)
        .padding(.leading, 4)
    }
}

// MARK: - Labels

/// What belongs under each label, in your words. Only described labels are applied.
private struct LabelDescriptions: View {
    @FetchAll(MailLabel.order(by: \.name)) private var labels

    var body: some View {
        SettingsGroup("What belongs under each label") {
            ForEach(labels.names, id: \.self) { LabelDescriptionRow(name: $0) }
            if labels.isEmpty {
                GroupRow("No labels yet", note: "Press L on a conversation to create one.")
            }
        }
    }
}

private struct LabelDescriptionRow: View {
    let name: String
    @Environment(AppModel.self) private var model
    @State private var text = ""

    var body: some View {
        GroupRow(name) {
            TextField("What belongs here", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1...3)
                .frame(maxWidth: 380, alignment: .trailing)
        }
        .onAppear { text = model.session.ai.labelDescriptions[name] ?? "" }
        // Saved once you stop typing, so auto labelling doesn't run on every keystroke.
        .task(id: text) {
            let description = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard description != (model.session.ai.labelDescriptions[name] ?? "") else { return }
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            model.session.describeLabel(named: name, as: description)
        }
    }
}

// MARK: - Bits

private struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.down").font(.controlIcon).foregroundStyle(Color.textMuted)
    }
}

private struct Checkmark: View {
    let isOn: Bool

    var body: some View {
        Image(systemName: "checkmark").font(.controlIcon).opacity(isOn ? 1 : 0)
    }
}
