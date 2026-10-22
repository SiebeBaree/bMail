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
                FeatureRow(
                    detail: "Finishes your sentences in gray as you write. Tab accepts.",
                    choice: $ai.completion, provider: ai.provider, key: ai.key
                )
                LearningRow()
            }
            VStack(alignment: .leading, spacing: 0) {
                SettingsHeader(title: "Auto labelling") {
                    Toggle(isOn: $ai.isLabellingOn) { EmptyView() }
                        .toggleStyle(.mailSwitch)
                        .accessibilityLabel("Auto labelling")
                }
                FeatureRow(
                    detail: "Puts your labels on new mail in the inbox when it fits their description. Takes a label off and it learns.",
                    choice: $ai.labelling, provider: ai.provider, key: ai.key
                )
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
            SettingsHeader(title: "Provider") { EmptyView() }
            HStack(spacing: 8) {
                Button { isOpen.toggle() } label: {
                    HStack(spacing: 6) {
                        Text(ai.provider.title)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.textMuted)
                    }
                }
                .buttonStyle(.secondary)
                .dropdown(isPresented: $isOpen) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Button {
                            isOpen = false
                            ai.provider = provider
                        } label: {
                            HStack {
                                Text(provider.title)
                                Spacer(minLength: 16)
                                if provider == ai.provider {
                                    Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                                }
                            }
                        }
                        .buttonStyle(.dropdownItem)
                    }
                }
                SecureField("\(ai.provider.title) API key", text: $ai.key)
                    .textFieldStyle(.field)
                    .onSubmit(check)
                Button(status == .checking ? "Checking" : "Check", action: check)
                    .buttonStyle(.secondary)
                    .disabled(ai.key.isEmpty || status == .checking)
            }
            .padding(.top, 16)
            HStack(spacing: 6) {
                switch status {
                case .connected(let milliseconds):
                    StatusDot(.success)
                    Text("Connected, \(milliseconds) ms")
                case .failed(let message):
                    StatusDot(.danger)
                    Text(message)
                case .checking, nil:
                    if let problem = model.session.aiProblem {
                        StatusDot(.danger)
                        Text(problem)
                    } else {
                        Text("Kept in this Mac's keychain. Mail goes from here to \(ai.provider.title), never through your server.")
                            .foregroundStyle(Color.textMuted)
                        Link("Get a key", destination: ai.provider.keysURL).foregroundStyle(Color.link)
                    }
                }
            }
            .lineLimit(2)
            .padding(.top, 10)
        }
        .onChange(of: ai.provider) { _, _ in status = nil }
        .onChange(of: ai.key) { _, _ in status = nil }
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

/// What a feature does, and the model and reasoning it uses.
private struct FeatureRow: View {
    let detail: String
    @Binding var choice: ModelChoice
    let provider: AIProvider
    let key: String
    @State private var modelID = ""
    @State private var models: [String] = []
    @State private var isModelsOpen = false
    @State private var isReasoningOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(detail).foregroundStyle(Color.textMuted)
            HStack(spacing: 8) {
                Text("Model").foregroundStyle(Color.textSecondary).frame(width: 72, alignment: .leading)
                TextField(provider.defaultModel, text: $modelID)
                    .textFieldStyle(.field)
                    .font(.meta)
                    .frame(width: 260)
                    .onSubmit(saveModel)
                Button { isModelsOpen.toggle() } label: {
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.ghost)
                .disabled(matches.isEmpty)
                .help("Models your key can use")
                .dropdown(isPresented: $isModelsOpen) {
                        ForEach(matches, id: \.self) { id in
                            Button(id) {
                                isModelsOpen = false
                                modelID = id
                                choice.model = id
                            }
                            .buttonStyle(.dropdownItem)
                        }
                    }
                Text("Reasoning").foregroundStyle(Color.textSecondary).padding(.leading, 12)
                Button { isReasoningOpen.toggle() } label: {
                    HStack(spacing: 6) {
                        Text(choice.reasoning.title)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.textMuted)
                    }
                }
                .buttonStyle(.secondary)
                .dropdown(isPresented: $isReasoningOpen) {
                    ForEach(Reasoning.allCases, id: \.self) { level in
                        Button {
                            isReasoningOpen = false
                            choice.reasoning = level
                        } label: {
                            HStack {
                                Text(level.title)
                                Spacer(minLength: 16)
                                if level == choice.reasoning {
                                    Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                                }
                            }
                        }
                        .buttonStyle(.dropdownItem)
                    }
                }
            }
        }
        .padding(.vertical, 16)
        .onAppear { modelID = choice.model }
        .onChange(of: choice.model) { _, model in modelID = model }
        .task(id: "\(provider.rawValue).\(key)") {
            models = []
            // Waits out the typing of a key, so each keystroke isn't a request.
            try? await Task.sleep(for: .milliseconds(600))
            guard !key.isEmpty, !Task.isCancelled else { return }
            models = (try? await AIClient(provider: provider, key: key).models()) ?? []
        }
    }

    /// Models whose id contains what's typed, so a gateway's long list stays short.
    private var matches: [String] {
        let typed = modelID.trimmingCharacters(in: .whitespaces).lowercased()
        return Array(models.filter { typed.isEmpty || $0.lowercased().contains(typed) }.prefix(12))
    }

    private func saveModel() {
        let id = modelID.trimmingCharacters(in: .whitespaces)
        isModelsOpen = false
        choice.model = id.isEmpty ? provider.defaultModel : id
    }
}

/// Learning mode, until there's enough of your own mail to sound like you.
private struct LearningRow: View {
    @FetchOne(Message.where { $0.direction.eq(Direction.outbound) }.count()) private var sent = 0

    var body: some View {
        HStack(spacing: 6) {
            if sent >= CompletionPrompt.minimumSentMails {
                StatusDot(.success)
                Text("Writes like you, from \(sent) emails you sent.")
            } else {
                StatusDot(.warning)
                Text("Learning. Suggestions start once you've sent \(CompletionPrompt.minimumSentMails) emails, \(sent) so far.")
            }
        }
        .foregroundStyle(Color.textSecondary)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

/// What belongs under each label, in your words. Only labels with a description are applied by AI.
private struct LabelDescriptions: View {
    @FetchAll(MailLabel.order(by: \.name)) private var labels

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(labels) { LabelDescriptionRow(label: $0) }
            if labels.isEmpty {
                HStack(spacing: 6) {
                    Text("Press").foregroundStyle(Color.textMuted)
                    KeyCap("L")
                    Text("on a conversation to create your first label.").foregroundStyle(Color.textMuted)
                }
                .padding(.vertical, 16)
            }
        }
    }
}

private struct LabelDescriptionRow: View {
    let label: MailLabel
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "tag").font(.system(size: 11)).foregroundStyle(Color.textMuted).frame(width: 28)
            Text(label.name).font(.uiMedium).frame(width: 140, alignment: .leading).lineLimit(1)
            VStack(alignment: .leading, spacing: 4) {
                TextField("What belongs here, so AI can use it", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1...4)
                if let error { Text(error).foregroundStyle(Color.danger) }
            }
        }
        .padding(.vertical, 15)
        .overlay(alignment: .bottom) { Hairline() }
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
