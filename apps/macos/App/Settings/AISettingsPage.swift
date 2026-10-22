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

    var body: some View {
        @Bindable var ai = model.session.ai
        VStack(alignment: .leading, spacing: 48) {
            ProviderSection()
            VStack(alignment: .leading, spacing: 0) {
                SettingsHeader(title: "Tab completion") {
                    Toggle(isOn: $ai.isCompletionOn) { EmptyView() }
                        .toggleStyle(.mailSwitch)
                        .accessibilityLabel("Tab completion")
                }
                ModelRows(choice: $ai.completion, provider: ai.provider, key: ai.key, reasoningNote: "Off is fastest.")
                LearningRow()
            }
            VStack(alignment: .leading, spacing: 0) {
                SettingsHeader(title: "Auto labelling") {
                    Toggle(isOn: $ai.isLabellingOn) { EmptyView() }
                        .toggleStyle(.mailSwitch)
                        .accessibilityLabel("Auto labelling")
                }
                ModelRows(choice: $ai.labelling, provider: ai.provider, key: ai.key, reasoningNote: nil)
                LabelDescriptions()
            }
        }
        .onChange(of: ai.isLabellingOn) { _, isOn in if isOn { model.session.labelNewMail() } }
    }
}

/// The provider, your key for it and a check that both work.
private struct ProviderSection: View {
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
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(title: "Provider") {
                Button { isOpen.toggle() } label: { DropdownLabel(ai.provider.title) }
                    .buttonStyle(.secondary)
                    .dropdown(isPresented: $isOpen, alignment: .trailing) {
                        ForEach(AIProvider.allCases, id: \.self) { provider in
                            DropdownOption(provider.title, isSelected: provider == ai.provider) {
                                isOpen = false
                                ai.provider = provider
                            }
                        }
                    }
            }
            SettingRow("API key", note: keyNote(ai)) {
                HStack(spacing: 8) {
                    SecureField("Paste your key", text: $ai.key)
                        .textFieldStyle(.field)
                        .frame(width: 240)
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

    /// What's known about the key: the last check, the last thing that went wrong, or where to get one.
    private func keyNote(_ ai: AISettings) -> Text {
        switch status {
        case let .connected(milliseconds): return Text("Connected, \(milliseconds) ms")
        case let .failed(message): return Text(message).foregroundStyle(Color.danger)
        case .checking, nil:
            if let problem = model.session.aiProblem { return Text(problem).foregroundStyle(Color.danger) }
            // From a String, so the link is read as markdown.
            if ai.key.isEmpty {
                return Text(LocalizedStringKey("In this Mac's keychain, never on your server. [Get a key](\(ai.provider.keysURL.absoluteString))"))
            }
            return Text("In this Mac's keychain, never on your server.")
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

/// The model a feature uses and how hard it thinks.
private struct ModelRows: View {
    @Binding var choice: ModelChoice
    let provider: AIProvider
    let key: String
    let reasoningNote: String?
    @State private var models: [String] = []
    @State private var isModelsOpen = false
    @State private var isReasoningOpen = false

    var body: some View {
        SettingRow("Model") {
            Button { isModelsOpen.toggle() } label: { DropdownLabel(choice.model, mono: true) }
                .buttonStyle(.secondary)
                .dropdown(isPresented: $isModelsOpen, alignment: .trailing) {
                    if models.isEmpty {
                        Text(key.isEmpty ? "Add your key to see models" : "Loading models")
                            .foregroundStyle(Color.textMuted)
                            .padding(.horizontal, 8)
                            .frame(minHeight: 32)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(models, id: \.self) { id in
                                    DropdownOption(id, isSelected: id == choice.model, mono: true) {
                                        isModelsOpen = false
                                        choice.model = id
                                    }
                                }
                            }
                        }
                        .frame(width: 320, height: min(CGFloat(models.count) * 32, 320))
                    }
                }
        }
        SettingRow("Reasoning", note: reasoningNote) {
            Button { isReasoningOpen.toggle() } label: { DropdownLabel(choice.reasoning.title) }
                .buttonStyle(.secondary)
                .dropdown(isPresented: $isReasoningOpen, alignment: .trailing) {
                    ForEach(Reasoning.allCases, id: \.self) { level in
                        DropdownOption(level.title, isSelected: level == choice.reasoning) {
                            isReasoningOpen = false
                            choice.reasoning = level
                        }
                    }
                }
        }
        .task(id: "\(provider.rawValue).\(key)") {
            models = []
            // Waits out the typing of a key, so each keystroke isn't a request.
            try? await Task.sleep(for: .milliseconds(600))
            guard !key.isEmpty, !Task.isCancelled else { return }
            models = (try? await AIClient(provider: provider, key: key).models()) ?? []
        }
    }
}

/// Only while there's too little sent mail to write like you.
private struct LearningRow: View {
    @FetchOne(Message.where { $0.direction.eq(Direction.outbound) }.count()) private var sent = 0

    var body: some View {
        if sent < CompletionPrompt.minimumSentMails {
            SettingRow("Learning your style", note: "Starts after \(CompletionPrompt.minimumSentMails) sent emails. \(sent) so far.")
        }
    }
}

/// What belongs under each label, in your words. Only described labels are applied.
private struct LabelDescriptions: View {
    @FetchAll(MailLabel.order(by: \.name)) private var labels

    var body: some View {
        SettingRow(
            "Labels",
            note: labels.isEmpty ? "Press L on a conversation to create one." : "AI only uses labels you've described. Labels you remove become corrections."
        )
        ForEach(labels) { LabelDescriptionRow(label: $0) }
    }
}

private struct LabelDescriptionRow: View {
    let label: MailLabel
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label.name).frame(width: 160, alignment: .leading).lineLimit(1)
            VStack(alignment: .leading, spacing: 2) {
                TextField("What belongs here", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1...4)
                if let error { Text(error).font(.geist(12)).foregroundStyle(Color.danger) }
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .top) { Hairline() }
        .onAppear { text = label.description ?? "" }
        // Saved once you stop typing, like a signature.
        .task(id: text) {
            let description = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard description != (label.description ?? "") else { return }
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            do {
                try await model.session.describeLabel(label.id, as: description)
                error = nil
                model.session.labelNewMail()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// A dropdown button's label: the current value and a chevron.
private struct DropdownLabel: View {
    let title: String
    let mono: Bool

    init(_ title: String, mono: Bool = false) {
        self.title = title
        self.mono = mono
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(mono ? .meta : .uiMedium)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.textMuted)
        }
    }
}

/// One choice in a dropdown, with a check on the current one.
private struct DropdownOption: View {
    let title: String
    let isSelected: Bool
    let mono: Bool
    let action: () -> Void

    init(_ title: String, isSelected: Bool, mono: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.mono = mono
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(mono ? .meta : .ui)
                Spacer(minLength: 16)
                Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).opacity(isSelected ? 1 : 0)
            }
        }
        .buttonStyle(.dropdownItem)
    }
}
