import Assist
import DesignSystem
import MailCore
import MailUI
import SQLiteData
import SwiftUI

/// Your own AI key and the two features that use it: suggestions while you write and auto labelling. Requests go from
/// this iPhone straight to the provider.
struct AISettingsView: View {
    @Environment(AppModel.self) private var model
    @FetchOne(Message.where { $0.direction.eq(Direction.outbound) }.count()) private var sent = 0
    @FetchAll(MailLabel.order(by: \.name)) private var labels
    @State private var status: String?
    @State private var isChecking = false

    var body: some View {
        @Bindable var ai = model.session.ai
        List {
            Section {
                Picker("Provider", selection: $ai.provider) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Label { Text(provider.title) } icon: { provider.logo.image }.tag(provider)
                    }
                }
                SecureField("API key", text: $ai.key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(check)
                Button(isChecking ? "Checking" : "Check", action: check)
                    .disabled(ai.key.isEmpty || isChecking)
                if let message = status ?? model.session.aiProblem {
                    Text(message).font(.phone(14)).foregroundStyle(Color.textSecondary)
                }
            } footer: {
                // From a String, so the link in it is read as markdown.
                Text(LocalizedStringKey("Saved in this iPhone's keychain. Requests go straight from here, not through your server. [Get a key](\(ai.provider.keysURL.absoluteString))"))
            }
            .listRowBackground(Color.raised)

            Section {
                Toggle("Suggestions", isOn: $ai.isCompletionOn)
                modelRows($ai.completion, provider: ai.provider)
            } header: {
                Text("Writing")
            } footer: {
                if sent >= CompletionPrompt.minimumSentMails {
                    Text("Suggests the next words as you write. Tap Accept above the keyboard to keep them.")
                } else {
                    Text("Learning your style. Starts after \(CompletionPrompt.minimumSentMails) sent emails. \(sent) so far.")
                }
            }
            .listRowBackground(Color.raised)

            Section {
                Toggle("Auto labelling", isOn: $ai.isLabellingOn)
                modelRows($ai.labelling, provider: ai.provider)
            } header: {
                Text("Labels")
            } footer: {
                Text("Labels new inbox mail that matches a description below. Labels you remove become corrections.")
            }
            .listRowBackground(Color.raised)

            if !labels.isEmpty {
                Section {
                    ForEach(labels.names, id: \.self) { LabelDescriptionRow(name: $0) }
                } header: {
                    Text("What belongs under each label")
                }
                .listRowBackground(Color.raised)
            }
        }
        .font(.phone(16))
        .tint(Color.accent)
        .scrollContentBackground(.hidden)
        .background(Color.chrome)
        .navigationTitle("AI")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: ai.provider) { _, _ in status = nil }
        .onChange(of: ai.key) { _, _ in status = nil }
        .onChange(of: ai.isLabellingOn) { _, isOn in if isOn { model.session.labelNewMail() } }
    }

    @ViewBuilder private func modelRows(_ choice: Binding<ModelChoice>, provider: AIProvider) -> some View {
        NavigationLink {
            ModelPicker(choice: choice, provider: provider, key: model.session.ai.key)
        } label: {
            LabeledContent("Model") {
                HStack(spacing: 6) {
                    LogoView(Logo.of(model: choice.wrappedValue.model, on: provider))
                    Text(choice.wrappedValue.model).font(.phoneMono(14)).lineLimit(1)
                }
            }
        }
        Picker("Reasoning", selection: choice.reasoning) {
            ForEach(provider.reasoningLevels, id: \.self) { Text($0.title).tag($0) }
        }
    }

    private func check() {
        let ai = model.session.ai
        guard let client = ai.client else { return }
        isChecking = true
        Task {
            defer { isChecking = false }
            do {
                let elapsed = try await client.check(ai.isCompletionOn || !ai.isLabellingOn ? ai.completion : ai.labelling)
                status = "Connected, \(Int(elapsed / .milliseconds(1))) ms"
                Haptics.success()
            } catch {
                status = error.localizedDescription
                Haptics.failure()
            }
        }
    }
}

/// Every model the key can use, searchable, or any id you type.
private struct ModelPicker: View {
    @Binding var choice: ModelChoice
    let provider: AIProvider
    let key: String
    @Environment(\.dismiss) private var dismiss
    @State private var models: [AIModel] = []
    @State private var search = ""

    var body: some View {
        List {
            let typed = search.trimmingCharacters(in: .whitespaces)
            if !typed.isEmpty, !models.contains(where: { $0.id == typed }) {
                Button("Use \u{201C}\(typed)\u{201D}") { pick(typed) }
            }
            ForEach(models.filter { typed.isEmpty || $0.matches(typed) }) { model in
                Button { pick(model.id) } label: {
                    HStack(spacing: 12) {
                        LogoView(Logo.of(model: model.id, on: provider), size: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.name ?? model.id).foregroundStyle(Color.textPrimary)
                            if model.name != nil { Text(model.id).font(.phoneMono(12)).foregroundStyle(Color.textMuted) }
                        }
                        Spacer()
                        if model.id == choice.model { Image(systemName: "checkmark").foregroundStyle(Color.accent) }
                    }
                }
            }
            .listRowBackground(Color.raised)
        }
        .scrollContentBackground(.hidden)
        .background(Color.chrome)
        .searchable(text: $search, prompt: provider.defaultModel)
        .textInputAutocapitalization(.never)
        .navigationTitle("Model")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !key.isEmpty else { return }
            models = (try? await AIClient(provider: provider, key: key).models()) ?? []
        }
    }

    private func pick(_ id: String) {
        choice.model = id
        dismiss()
    }
}

private struct LabelDescriptionRow: View {
    let name: String
    @Environment(AppModel.self) private var model
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.phone(16, .medium))
            TextField("What belongs here, so AI can use it", text: $text, axis: .vertical)
                .font(.phone(15))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1...5)
        }
        .padding(.vertical, 4)
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
