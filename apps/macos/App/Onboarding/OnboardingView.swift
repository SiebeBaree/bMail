import Agents
import AuthenticationServices
import DesignSystem
import MailCore
import MailUI
import SQLiteData
import SwiftUI

/// Setup, one step at a time in one column, with the intro over it on a first launch. Also what shows after every
/// account is removed, then with just your mail.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @FetchAll(Account.order(by: \.position)) private var accounts
    @FetchAll(Domain.order(by: \.name)) private var domains
    /// Your server's sync cursor, there once its first pass landed. A Gmail sync before it doesn't count.
    @FetchOne(SyncCursor.where { $0.source.eq("server") }.count()) private var serverCursors = 0
    /// Nil until the server says.
    @State private var hasResend: Bool?
    @State private var landing = CGRect.zero

    private static let wordmarkSize: CGFloat = 26

    var body: some View {
        let onboarding = model.onboarding
        let progress = Onboarding.Progress(
            accounts: accounts, domains: domains, hasServer: model.session.server != nil, hasResend: hasResend,
            hasSynced: serverCursors > 0
        )
        let current = onboarding.current(progress)
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                Wordmark(size: Self.wordmarkSize)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { landing = $0 }
                    .padding(.bottom, 28)
                if let current {
                    step(current, progress)
                        .id(current)
                        .transition(.opacity)
                        .opacity(onboarding.showsIntro ? 0 : 1)
                        .offset(y: onboarding.showsIntro ? 8 : 0)
                }
            }
            .frame(width: 480, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 96)
            .padding(.bottom, 40)
            .animation(.easeOut(duration: 0.2), value: current)
            if onboarding.showsIntro {
                Intro(landing: landing, wordmarkSize: Self.wordmarkSize) {
                    withAnimation(.easeOut(duration: 0.5)) { onboarding.endIntro() }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        case .resend: StepPage("Connect Resend", bars: bars) { ResendKeyStep { hasResend = true } }
        case .domain: DomainStep(domain: domain, bars: bars, back: back)
        case .address: if let domain { AddressStep(domain: domain, bars: bars, back: back) }
        case .ai: AIStep(bars: bars, back: back)
        case .agents: AgentsStep(accounts: accounts, bars: bars, back: back)
        case .keys: KeysStep(bars: bars, back: back)
        }
    }
}

/// One step: a title, a line on what it's for, what you do and a row along the bottom with where you are and what's
/// next.
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
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.geist(22, .semibold)).tracking(-0.4)
            if let note {
                Text(note).foregroundStyle(Color.textMuted).fixedSize(horizontal: false, vertical: true)
            }
            content()
            Spacer(minLength: 24)
            HStack(spacing: 8) {
                bars
                Spacer()
                if let back { Button("Back", action: back).buttonStyle(.ghost) }
                actions()
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// The primary button that moves setup on, with Return.
private struct NextButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String = "Continue", action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                KeyCap("↵")
            }
        }
        .buttonStyle(.primary)
        .keyboardShortcut(.defaultAction)
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
                    HStack(spacing: 12) {
                        Avatar(account.displayName, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.address).font(.uiMedium)
                            Text(account.kind.label).font(.geist(12)).foregroundStyle(Color.textMuted)
                        }
                        Spacer()
                        Image(systemName: "checkmark").font(.smallIcon.weight(.semibold)).foregroundStyle(Color.success)
                    }
                    .padding(.vertical, 12)
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
                Text(error).foregroundStyle(Color.danger).fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            if !accounts.isEmpty || model.session.server != nil {
                NextButton { model.onboarding.pass(.mail) }
            }
        }
    }

    private func option(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.rowIcon)
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Color.selected, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.uiMedium)
                    Text(detail).font(.geist(12)).foregroundStyle(Color.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.controlIcon).foregroundStyle(Color.textFaint)
            }
            .padding(.vertical, 12)
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
                Text(failure.message).foregroundStyle(Color.danger).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var note: String {
        if let server = model.session.server { return "Connected to \(server.host). Checking it." }
        return "Your domains and tracking run on a server you host. Free on Vercel, about two minutes."
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
                note: "Add these where you bought the domain. DNS can take a while, so you don't have to wait here. bMail keeps checking.",
                bars: bars, back: back
            ) {
                RecordTable(records: domain.records)
                errorText
            } actions: {
                Button(isWorking ? "Checking" : "Check DNS") { verify(domain) }
                    .buttonStyle(.secondary)
                    .disabled(isWorking)
                NextButton { model.onboarding.pass(.domain) }
            }
            .task(id: domain.status == .pending || !domain.trackingHostVerified) {
                while domain.status == .pending || !domain.trackingHostVerified, !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    if !Task.isCancelled { verify(domain) }
                }
            }
        } else {
            StepPage("Add your domain", note: "The domain your address goes on. Next come the records to add where you bought it.", bars: bars, back: back) {
                HStack(spacing: 8) {
                    TextField("example.com", text: $name)
                        .textFieldStyle(.field)
                        .focused($isFocused)
                        .onSubmit(add)
                    Button(isWorking ? "Adding" : "Add domain", action: add)
                        .buttonStyle(.primary)
                        .disabled(trimmed.isEmpty || isWorking)
                }
                errorText
            }
            .onAppear { isFocused = true }
        }
    }

    @ViewBuilder private var errorText: some View {
        if let error {
            Text(error).foregroundStyle(Color.danger).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces).lowercased() }

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
            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    TextField("name", text: $localPart)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                        .onSubmit(create)
                    Text("@\(domain.name)").foregroundStyle(Color.textMuted)
                }
                .padding(.horizontal, 10)
                .frame(height: Metrics.controlHeight)
                .background(Color.canvas, in: .rect(cornerRadius: Metrics.controlRadius))
                .overlay(RoundedRectangle(cornerRadius: Metrics.controlRadius).strokeBorder(Color.lineStrong))
                Button(action: create) {
                    HStack(spacing: 8) {
                        Text(isCreating ? "Creating" : "Create")
                        KeyCap("↵")
                    }
                }
                .buttonStyle(.primary)
                .disabled(trimmed.isEmpty || isCreating)
            }
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Catch-all")
                    Text("Mail to any other address on \(domain.name) lands here too.").font(.geist(12)).foregroundStyle(Color.textMuted)
                }
                Spacer()
                Toggle(isOn: $isCatchAll) { EmptyView() }.toggleStyle(.mailSwitch).accessibilityLabel("Catch-all")
            }
            .padding(.vertical, 12)
            .overlay(alignment: .top) { Hairline() }
            .overlay(alignment: .bottom) { Hairline() }
            .padding(.top, 6)
            if let error {
                Text(error).foregroundStyle(Color.danger).fixedSize(horizontal: false, vertical: true)
            }
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
                guard isCatchAll, let mailbox = changes.accounts.first else { return }
                do {
                    try session.store.merge(try await session.admin.setCatchAll(mailbox.id, for: domain.id), source: "settings")
                } catch {
                    session.toasts.show(Toast("Couldn't make it the catch-all.", detail: error.localizedDescription, symbol: "exclamationmark.triangle", tone: .failure))
                }
            } catch {
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
        StepPage("AI on your own key", note: "Requests go from this Mac straight to the provider. Nothing passes through a server.", bars: bars, back: back) {
            VStack(alignment: .leading, spacing: 20) {
                ProviderGroup()
                SettingsGroup("Features") {
                    GroupRow("Tab completion", note: "Gray text after the cursor. Tab accepts.") {
                        Toggle(isOn: $ai.isCompletionOn) { EmptyView() }.toggleStyle(.mailSwitch).accessibilityLabel("Tab completion")
                    }
                    GroupRow("Auto labelling", note: "Labels new mail once a label has a description in Settings.") {
                        Toggle(isOn: $ai.isLabellingOn) { EmptyView() }.toggleStyle(.mailSwitch).accessibilityLabel("Auto labelling")
                    }
                }
            }
        } actions: {
            NextButton(ai.key.isEmpty ? "Skip" : "Continue") { model.onboarding.pass(.ai) }
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

private struct AgentsStep: View {
    let accounts: [Account]
    let bars: StepBars
    let back: (() -> Void)?
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var agents = model.agents
        StepPage(
            "Agents",
            note: "Claude Code, Codex and other agents on this Mac can work with your mail over MCP. Each account starts at Off.",
            bars: bars, back: back
        ) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Let agents use bMail")
                    Spacer()
                    Toggle(isOn: $agents.isEnabled) { EmptyView() }.toggleStyle(.mailSwitch).accessibilityLabel("Let agents use bMail")
                }
                .frame(height: 52)
                .overlay(alignment: .top) { Hairline() }
                .overlay(alignment: .bottom) { Hairline() }
                if agents.isEnabled {
                    if let problem = agents.problem {
                        Text(problem).foregroundStyle(Color.danger).padding(.vertical, 12)
                    }
                    ForEach(accounts) { AgentAccessRow(account: $0) }
                    AgentConnection(token: agents.token, newToken: agents.newToken)
                }
            }
        } actions: {
            NextButton(agents.isEnabled ? "Continue" : "Skip") { model.onboarding.pass(.agents) }
        }
    }
}
