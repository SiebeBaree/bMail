import Assist
import AuthenticationServices
import DesignSystem
import MailCore
import MailUI
import SQLiteData
import SwiftUI

/// Setup, one step at a time, with the intro over it on a first launch. Also what shows after every account is
/// removed, then with just your mail. Accounts set up on your Mac arrive through iCloud Keychain and skip their steps.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @FetchAll(Account.order(by: \.position)) private var accounts
    @FetchAll(Domain.order(by: \.name)) private var domains
    /// Nil until the server says.
    @State private var hasResend: Bool?
    @State private var landing = CGRect.zero

    private static let wordmarkSize: CGFloat = 30

    var body: some View {
        let onboarding = model.onboarding
        let progress = Onboarding.Progress(
            accounts: accounts, domains: domains, hasServer: model.session.server != nil, hasResend: hasResend,
            hasSynced: model.session.syncStatus.lastSyncedAt != nil
        )
        let current = onboarding.current(progress)
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                Wordmark(size: Self.wordmarkSize)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { landing = $0 }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 26)
                if let current {
                    step(current, progress)
                        .id(current)
                        .transition(.opacity)
                        .opacity(onboarding.showsIntro ? 0 : 1)
                        .offset(y: onboarding.showsIntro ? 8 : 0)
                }
            }
            .frame(maxWidth: 440, maxHeight: .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity)
            .animation(.easeOut(duration: 0.2), value: current)
            if onboarding.showsIntro {
                Intro(landing: landing, wordmarkSize: Self.wordmarkSize) {
                    withAnimation(.easeOut(duration: 0.5)) { onboarding.endIntro() }
                }
                .transition(.opacity)
            }
        }
        .background(Color.canvas)
        .task(id: model.session.server?.baseURL) {
            hasResend = nil
            guard model.session.server != nil else { return }
            // Offline, Resend's step shows and saving the key says what's wrong.
            hasResend = (try? await model.session.admin.hasResend()) ?? false
        }
        .onChange(of: current == nil) { _, isDone in if isDone { onboarding.finish() } }
    }

    @ViewBuilder
    private func step(_ step: Onboarding.Step, _ progress: Onboarding.Progress) -> some View {
        let onboarding = model.onboarding
        let steps = onboarding.steps(progress)
        let bars = StepBars(count: steps.count, current: steps.firstIndex(of: step) ?? 0)
        let back: (() -> Void)? = onboarding.previous(of: step, progress).map { previous in { onboarding.back(to: previous) } }
        // The first domain that has no address yet is the one being set up.
        let domain = domains.first { domain in !accounts.contains { $0.domainID == domain.id } } ?? domains.first
        switch step {
        case .mail: MailStep(accounts: accounts, bars: bars)
        case .server: ServerStep(bars: bars, back: progress.hasServer ? nil : back)
        case .resend: ResendStep(bars: bars) { hasResend = true }
        case .domain: DomainStep(domain: domain, bars: bars, back: back)
        case .address: if let domain { AddressStep(domain: domain, bars: bars, back: back) }
        case .ai: AIStep(bars: bars, back: back)
        // Agents run on the Mac.
        case .agents: EmptyView()
        case .keys: GesturesStep(bars: bars, back: back)
        }
    }
}

/// One step: a title, a line on what it's for and what you do, with where you are and what's next at the bottom,
/// within reach of your thumb.
struct StepPage<Content: View, Actions: View>: View {
    let title: String
    let note: String?
    let bars: StepBars
    let back: (() -> Void)?
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions

    init(
        _ title: String, note: String? = nil, bars: StepBars, back: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.note = note
        self.bars = bars
        self.back = back
        self.content = content
        self.actions = actions
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(.phone(28, .semibold, relativeTo: .title)).tracking(-0.5)
                if let note {
                    Text(note).font(.phone(16)).foregroundStyle(Color.textMuted).fixedSize(horizontal: false, vertical: true)
                }
                content().padding(.top, 6)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                bars.padding(.bottom, 4)
                actions()
                if let back {
                    Button("Back", action: back).font(.phone(15)).foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color.canvas)
        }
    }
}

private struct MailStep: View {
    let accounts: [Account]
    let bars: StepBars
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var isConnecting = false
    @State private var error: String?

    var body: some View {
        StepPage("Add your mail", bars: bars) {
            VStack(spacing: 0) {
                ForEach(accounts) { account in
                    HStack(spacing: 14) {
                        Avatar(account.displayName, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.address).font(.phone(17, .medium)).lineLimit(1)
                            Text(account.kind.label).font(.phone(14)).foregroundStyle(Color.textMuted)
                        }
                        Spacer()
                        Image(systemName: "checkmark").font(.phone(14, .semibold, relativeTo: .subheadline)).foregroundStyle(Color.success)
                    }
                    .padding(.vertical, 14)
                    .overlay(alignment: .bottom) { Hairline() }
                }
                if model.session.google != nil {
                    let title = accounts.contains { $0.kind == .gmail } ? "Another Gmail" : "Gmail"
                    option(title, detail: isConnecting ? "Waiting for Google" : "Sign in with Google", symbol: "envelope", action: connectGmail)
                }
                if !accounts.contains(where: { $0.kind == .domain }) {
                    option("Your own domain", detail: "Set up or connect a server", symbol: "at") { model.onboarding.chooseDomain() }
                }
            }
            .overlay(alignment: .top) { Hairline() }
            if let error {
                Text(error).font(.phone(15)).foregroundStyle(Color.danger).fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            if !accounts.isEmpty || model.session.server != nil {
                Button("Continue") { model.onboarding.pass(.mail) }.buttonStyle(PhoneButtonStyle(.primary))
            }
        }
    }

    private func option(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.phone(16))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(Color.selected, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.phone(17, .medium)).foregroundStyle(Color.textPrimary)
                    Text(detail).font(.phone(14)).foregroundStyle(Color.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.phone(13, .semibold, relativeTo: .footnote)).foregroundStyle(Color.textFaint)
            }
            .padding(.vertical, 14)
            .contentShape(.rect)
            .overlay(alignment: .bottom) { Hairline() }
        }
        .buttonStyle(.plain)
        .disabled(isConnecting)
    }

    private func connectGmail() {
        isConnecting = true
        error = nil
        Task {
            defer { isConnecting = false }
            do {
                try await model.connectGmail(using: webAuthenticationSession)
            } catch {
                Haptics.failure()
                self.error = error.localizedDescription
            }
        }
    }
}

private struct ServerStep: View {
    let bars: StepBars
    let back: (() -> Void)?
    @Environment(AppModel.self) private var model

    var body: some View {
        StepPage("Your own server", note: note, bars: bars, back: back) {
            if model.session.server == nil {
                ServerChoice()
            } else if let failure = model.session.syncStatus.failing.values.first {
                Text(failure.message).font(.phone(15)).foregroundStyle(Color.danger).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var note: String {
        if let server = model.session.server { return "Connected to \(server.host). Checking it." }
        return "Your domains and tracking run on a server you host. Free on Vercel, about two minutes."
    }
}

/// Your server sends and receives through your Resend account, so it asks for a key once, before your first domain.
private struct ResendStep: View {
    let bars: StepBars
    let saved: () -> Void
    @Environment(AppModel.self) private var model
    @State private var key = ""
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        StepPage("Connect Resend", note: "Your server sends and receives mail through your Resend account. Paste a full access API key.", bars: bars) {
            SecureField("re_…", text: $key)
                .textFieldStyle(PhoneFieldStyle())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(save)
            Link("Create a key on Resend", destination: URL(string: "https://resend.com/api-keys")!)
                .font(.phone(15))
                .foregroundStyle(Color.link)
            if let error {
                Text(error).font(.phone(15)).foregroundStyle(Color.danger).fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            Button(isSaving ? "Saving" : "Save key", action: save)
                .buttonStyle(PhoneButtonStyle(.primary))
                .disabled(trimmed.isEmpty || isSaving)
        }
    }

    private var trimmed: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        guard !trimmed.isEmpty, !isSaving else { return }
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                try await model.session.admin.setResendKey(trimmed)
                Haptics.success()
                saved()
            } catch {
                Haptics.failure()
                self.error = error.localizedDescription
            }
        }
    }
}

/// Adds the domain, then shows its records until you continue. DNS doesn't have to be live for that: it's checked
/// every 30 seconds here and in Settings until it is.
private struct DomainStep: View {
    let domain: Domain?
    let bars: StepBars
    let back: (() -> Void)?
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var isWorking = false
    @State private var error: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        if let domain {
            StepPage(
                "Add \(domain.name) to your DNS",
                note: "Add these where you bought the domain. Tap one to copy it. You don't have to wait here, bMail keeps checking.",
                bars: bars, back: back
            ) {
                VStack(spacing: 0) {
                    ForEach(domain.records, id: \.self) { record in
                        RecordRow(record: record) { copy(record.value) }
                            .padding(.vertical, 8)
                            .overlay(alignment: .bottom) { Hairline() }
                    }
                }
                .overlay(alignment: .top) { Hairline() }
                errorText
            } actions: {
                Button("Continue") { model.onboarding.pass(.domain) }.buttonStyle(PhoneButtonStyle(.primary))
                Button(isWorking ? "Checking DNS" : "Check DNS now") { verify(domain) }
                    .font(.phone(15))
                    .foregroundStyle(Color.textSecondary)
                    .disabled(isWorking)
            }
            .task(id: domain.status == .pending || !domain.trackingHostVerified) {
                while domain.status == .pending || !domain.trackingHostVerified, !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    if !Task.isCancelled { verify(domain) }
                }
            }
        } else {
            StepPage("Add your domain", note: "The domain your address goes on. Next come the records to add where you bought it.", bars: bars, back: back) {
                TextField("example.com", text: $name)
                    .textFieldStyle(PhoneFieldStyle())
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .focused($isFocused)
                    .onSubmit(add)
                errorText
            } actions: {
                Button(isWorking ? "Adding" : "Add domain", action: add)
                    .buttonStyle(PhoneButtonStyle(.primary))
                    .disabled(trimmed.isEmpty || isWorking)
            }
            .onAppear { isFocused = true }
        }
    }

    @ViewBuilder private var errorText: some View {
        if let error {
            Text(error).font(.phone(15)).foregroundStyle(Color.danger).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces).lowercased() }

    private func copy(_ value: String) {
        UIPasteboard.general.string = value
        Haptics.tap()
        model.session.toasts.show(Toast("Value copied", symbol: "doc.on.doc", duration: .seconds(2)))
    }

    private func add() {
        guard !trimmed.isEmpty, !isWorking else { return }
        run { try await model.session.admin.addDomain(trimmed) }
    }

    private func verify(_ domain: Domain) {
        guard !isWorking else { return }
        run { try await model.session.admin.verifyDomain(domain.id) }
    }

    private func run(_ operation: @escaping () async throws -> ChangeSet) {
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            do {
                try model.session.store.merge(try await operation(), source: "settings")
            } catch {
                Haptics.failure()
                self.error = error.localizedDescription
            }
        }
    }
}

private struct AddressStep: View {
    let domain: Domain
    let bars: StepBars
    let back: (() -> Void)?
    @Environment(AppModel.self) private var model
    @State private var localPart = ""
    /// On for your first address, so nothing sent to the domain gets lost.
    @State private var isCatchAll = true
    @State private var isCreating = false
    @State private var error: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        StepPage("Pick your address", bars: bars, back: back) {
            HStack(spacing: 0) {
                TextField("name", text: $localPart)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isFocused)
                    .onSubmit(create)
                Text("@\(domain.name)").foregroundStyle(Color.textMuted)
            }
            .font(.phone(17))
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Color.raised, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.lineStrong))
            Toggle(isOn: $isCatchAll) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Catch-all").font(.phone(17))
                    Text("Mail to any other address on \(domain.name) lands here too.").font(.phone(14)).foregroundStyle(Color.textMuted)
                }
            }
            .tint(Color.accent)
            .padding(.vertical, 12)
            if let error {
                Text(error).font(.phone(15)).foregroundStyle(Color.danger).fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            Button(isCreating ? "Creating" : "Create", action: create)
                .buttonStyle(PhoneButtonStyle(.primary))
                .disabled(trimmed.isEmpty || isCreating)
        }
        .onAppear { isFocused = true }
    }

    private var trimmed: String { localPart.trimmingCharacters(in: .whitespaces).lowercased() }

    /// The address arriving moves setup on, so the catch-all is set after it and says so in a toast if it fails.
    private func create() {
        guard !trimmed.isEmpty, !isCreating else { return }
        let localPart = trimmed
        let session = model.session
        isCreating = true
        error = nil
        Task {
            defer { isCreating = false }
            do {
                let changes = try await session.admin.addMailbox(localPart: localPart, displayName: localPart.capitalized, on: domain.id)
                try session.store.merge(changes, source: "settings")
                Haptics.success()
                guard isCatchAll, let mailbox = changes.accounts.first else { return }
                do {
                    try session.store.merge(try await session.admin.setCatchAll(mailbox.id, for: domain.id), source: "settings")
                } catch {
                    session.toasts.show(Toast("Couldn't make it the catch-all.", detail: error.localizedDescription, symbol: "exclamationmark.triangle", tone: .failure))
                }
            } catch {
                Haptics.failure()
                self.error = error.localizedDescription
            }
        }
    }
}

private struct AIStep: View {
    let bars: StepBars
    let back: (() -> Void)?
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var ai = model.session.ai
        StepPage("AI on your own key", note: "Requests go from this iPhone straight to the provider. Nothing passes through a server.", bars: bars, back: back) {
            Menu {
                Picker("Provider", selection: $ai.provider) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Label { Text(provider.title) } icon: { provider.logo.image }.tag(provider)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    ai.provider.logo.image.resizable().scaledToFit().frame(width: 20, height: 20)
                    Text(ai.provider.title).foregroundStyle(Color.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.phone(13, .semibold, relativeTo: .footnote)).foregroundStyle(Color.textFaint)
                }
            }
            .font(.phone(17))
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Color.raised, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.lineStrong))
            SecureField("API key", text: $ai.key)
                .textFieldStyle(PhoneFieldStyle())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Link("Get a key", destination: ai.provider.keysURL).font(.phone(15)).foregroundStyle(Color.link)
            VStack(spacing: 0) {
                Toggle(isOn: $ai.isCompletionOn) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Suggestions").font(.phone(17))
                        Text("The next words as you write.").font(.phone(14)).foregroundStyle(Color.textMuted)
                    }
                }
                .padding(.vertical, 12)
                Hairline()
                Toggle(isOn: $ai.isLabellingOn) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto labelling").font(.phone(17))
                        Text("Labels new mail once a label has a description in Settings.").font(.phone(14)).foregroundStyle(Color.textMuted)
                    }
                }
                .padding(.vertical, 12)
            }
            .tint(Color.accent)
            .padding(.top, 6)
        } actions: {
            Button(ai.key.isEmpty ? "Skip" : "Continue") { model.onboarding.pass(.ai) }.buttonStyle(PhoneButtonStyle(.primary))
        }
        // A key is what you came for, so both features start on with it.
        .onChange(of: ai.key.isEmpty) { _, isEmpty in
            if !isEmpty {
                ai.isCompletionOn = true
                ai.isLabellingOn = true
            }
        }
    }
}
