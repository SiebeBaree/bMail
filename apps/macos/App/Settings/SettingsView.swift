import AuthenticationServices
import DesignSystem
import MailCore
import MailUI
import Providers
import SQLiteData
import SwiftUI

/// Two pages. General: the addresses you read and send from, your labels, the domains behind your own addresses and
/// agents. Every way to add an address starts from the same button, and your server only shows up once you want your
/// own domain. AI: your key and the features that use it.
struct SettingsView: View {
    enum Page: String, CaseIterable { case general = "General", ai = "AI" }

    @Environment(AppModel.self) private var model
    @FocusState private var isDomainFieldFocused: Bool
    @State private var page = Page.general

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 48) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Settings").font(.pageTitle).tracking(-0.3)
                    HStack(spacing: 22) {
                        ForEach(Page.allCases, id: \.self) { page in
                            PageTab(title: page.rawValue, isSelected: self.page == page) { self.page = page }
                        }
                    }
                    .overlay(alignment: .bottom) { Hairline() }
                }
                switch page {
                case .general:
                    AccountsSection(isDomainFieldFocused: $isDomainFieldFocused)
                    LabelsSection()
                    if let server = model.session.server {
                        DomainsSection(server: server, isDomainFieldFocused: $isDomainFieldFocused)
                    }
                    AgentsSection()
                case .ai:
                    AISettingsPage()
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 56)
            .padding(.bottom, 40)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.canvas)
        .font(.ui)
        .foregroundStyle(Color.textPrimary)
        .tint(.accent)
        .frame(minWidth: 720, minHeight: 560)
        .ignoresSafeArea()
        .containerBackground(Color.canvas, for: .window)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}

/// A text tab with a line under the current one, like the main window's.
private struct PageTab: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .foregroundStyle(isSelected || isHovered ? Color.textPrimary : Color.textMuted)
                .padding(.bottom, 10)
                .overlay(alignment: .bottom) {
                    if isSelected { Rectangle().fill(Color.textPrimary).frame(height: 2) }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// A section title with its action on the right, over a hairline.
struct SettingsHeader<Action: View>: View {
    let title: String
    @ViewBuilder let action: () -> Action

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.geist(15, .semibold))
                Spacer()
                action()
            }
            .padding(.bottom, 10)
            Hairline()
        }
    }
}

/// One setting: what it is on the left, with a short note under it, and its control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    let note: Text?
    @ViewBuilder let control: () -> Control

    init(_ title: String, note: String? = nil, @ViewBuilder control: @escaping () -> Control = { EmptyView() }) {
        self.title = title
        self.note = note.map { Text($0) }
        self.control = control
    }

    init(_ title: String, note: Text, @ViewBuilder control: @escaping () -> Control = { EmptyView() }) {
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
            Spacer()
            control()
        }
        .padding(.vertical, 12)
        .frame(minHeight: 52)
        .overlay(alignment: .top) { Hairline() }
    }
}

/// A button that asks once more before something that can't be undone.
struct ConfirmButton: View {
    let title: String
    let confirmation: String
    let action: () -> Void
    @State private var isConfirming = false

    var body: some View {
        Button {
            if isConfirming {
                isConfirming = false
                action()
            } else {
                isConfirming = true
            }
        } label: {
            Text(isConfirming ? confirmation : title).foregroundStyle(isConfirming ? Color.danger : Color.textSecondary)
        }
        .buttonStyle(.ghost)
        .task(id: isConfirming) {
            guard isConfirming else { return }
            try? await Task.sleep(for: .seconds(4))
            isConfirming = false
        }
    }
}

private struct AccountsSection: View {
    var isDomainFieldFocused: FocusState<Bool>.Binding
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @FetchAll(Account.order(by: \.position)) private var accounts
    @FetchAll(Domain.order(by: \.name)) private var domains
    @State private var isAddOpen = false
    @State private var newAddressDomain: Domain.ID?
    @State private var isSettingUpServer = false
    @State private var isConnecting = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(title: "Accounts") {
                Button { isAddOpen.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.controlIcon)
                        Text(isConnecting ? "Connecting Gmail" : "Add account")
                    }
                }
                .buttonStyle(.secondary)
                .disabled(isConnecting)
                .dropdown(isPresented: $isAddOpen, alignment: .trailing) { addOptions }
            }
            if let error {
                Text(error).foregroundStyle(Color.danger).padding(.vertical, 12)
            }
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                AccountRow(account: account, number: index + 1, isCatchAll: isCatchAll(account)) { remove(account) }
            }
            if isSettingUpServer, model.session.server == nil {
                ServerSetupRow { isSettingUpServer = false }
            } else if let domain = domains.first(where: { $0.id == newAddressDomain }) {
                NewAddressRow(domain: domain, create: { createAddress($0, on: domain) }, cancel: { newAddressDomain = nil })
            } else if accounts.isEmpty {
                Text("No accounts yet. Add Gmail or an address on your own domain.")
                    .foregroundStyle(Color.textMuted)
                    .padding(.vertical, 16)
            }
        }
    }

    @ViewBuilder private var addOptions: some View {
        if BuildSettings.google != nil {
            option("Gmail", detail: "Sign in with Google", symbol: "envelope", action: connectGmail)
            Hairline().padding(.vertical, 4)
        }
        if model.session.server == nil {
            option("Address on your own domain", detail: "Sets up your server first", symbol: "at") { isSettingUpServer = true }
        } else if domains.isEmpty {
            option("Address on your own domain", detail: "Add the domain first, below", symbol: "at") {
                isDomainFieldFocused.wrappedValue = true
            }
        }
        ForEach(domains) { domain in
            option("Address on \(domain.name)", detail: "name@\(domain.name)", symbol: "at") { newAddressDomain = domain.id }
        }
    }

    private func option(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            isAddOpen = false
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.smallIcon)
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(detail).font(.geist(11.5)).foregroundStyle(Color.textMuted)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.dropdownItem)
    }

    private func isCatchAll(_ account: Account) -> Bool {
        domains.contains { $0.catchAllMailboxID == account.id }
    }

    private func createAddress(_ localPart: String, on domain: Domain) {
        Task {
            do {
                let changes = try await model.session.admin
                    .addMailbox(localPart: localPart, displayName: localPart.capitalized, on: domain.id)
                try model.session.store.merge(changes, source: "settings")
                newAddressDomain = nil
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func remove(_ account: Account) {
        Task {
            do {
                if account.kind == .domain {
                    try model.session.store.merge(try await model.session.admin.removeMailbox(account.id), source: "settings")
                } else {
                    try model.session.disconnect(account)
                }
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
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

/// Where your own domain starts when there's no server yet: set one up on Vercel or connect yours.
private struct ServerSetupRow: View {
    let cancel: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your own domain").font(.uiMedium)
                Text("Your domains and tracking run on a server you host. Free on Vercel, about two minutes.")
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Cancel", action: cancel)
                    .buttonStyle(.plain)
                    .font(.geist(12))
                    .foregroundStyle(Color.link)
                    .padding(.top, 6)
            }
            Spacer(minLength: 0)
            ServerChoice().frame(width: 300)
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

private struct AccountRow: View {
    let account: Account
    let number: Int
    let isCatchAll: Bool
    let remove: () -> Void
    @State private var isHovered = false
    @State private var isEditingSignature = false
    @State private var signature = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Avatar(account.displayName, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.address).font(.uiMedium)
                    Text(isCatchAll ? "\(account.kind.label) · catch-all" : account.kind.label)
                        .font(.geist(12))
                        .foregroundStyle(Color.textMuted)
                }
                Spacer()
                Group {
                    Button(isEditingSignature ? "Done" : "Signature") { isEditingSignature.toggle() }
                        .buttonStyle(.ghost)
                    ConfirmButton(
                        title: account.kind == .domain ? "Delete" : "Disconnect",
                        confirmation: account.kind == .domain ? "Delete with all its mail" : "Disconnect from bMail",
                        action: remove
                    )
                }
                .opacity(isHovered || isEditingSignature ? 1 : 0)
                if number <= 9 { KeyCap("⌘\(number)") }
            }
            .frame(height: 56)
            if isEditingSignature {
                TextEditor(text: $signature)
                    .font(.ui)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 96)
                    .background(Color.canvas, in: .rect(cornerRadius: Metrics.controlRadius))
                    .overlay(RoundedRectangle(cornerRadius: Metrics.controlRadius).strokeBorder(Color.lineStrong))
                    .overlay(alignment: .topLeading) {
                        if signature.isEmpty {
                            Text("Signature for mail from \(account.address)").foregroundStyle(Color.textFaint).padding(13).allowsHitTesting(false)
                        }
                    }
                    .padding(.leading, 40)
                    .padding(.bottom, 14)
                    .onChange(of: signature) { _, text in Signatures.set(text, for: account.id) }
            }
        }
        .overlay(alignment: .bottom) { Hairline() }
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .onAppear { signature = Signatures.text(for: account.id) }
    }
}

/// The address you're adding on one of your domains, typed in place where it will appear.
private struct NewAddressRow: View {
    let domain: Domain
    let create: (String) -> Void
    let cancel: () -> Void
    @State private var localPart = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                TextField("name", text: $localPart)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit(submit)
                Text("@\(domain.name)").foregroundStyle(Color.textMuted)
            }
            .padding(.horizontal, 10)
            .frame(width: 320, height: Metrics.controlHeight)
            .background(Color.canvas, in: .rect(cornerRadius: Metrics.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: Metrics.controlRadius).strokeBorder(Color.lineStrong))
            Button(action: submit) {
                HStack(spacing: 8) { Text("Create"); KeyCap("↵") }
            }
            .buttonStyle(.primary)
            .disabled(trimmed.isEmpty)
            Button("Cancel", action: cancel).buttonStyle(.ghost)
        }
        .frame(height: 60)
        .onAppear { isFocused = true }
        .onExitCommand(perform: cancel)
    }

    private var trimmed: String { localPart.trimmingCharacters(in: .whitespaces).lowercased() }

    private func submit() {
        guard !trimmed.isEmpty else { return }
        create(trimmed)
    }
}

/// Your labels, across every account, by name. They're created where you use them, with L; here they're renamed and
/// removed, in Gmail and on your server alike.
private struct LabelsSection: View {
    @Environment(AppModel.self) private var model
    @FetchAll(MailLabel.order(by: \.name)) private var labels
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(title: "Labels") { EmptyView() }
            if let error {
                Text(error).foregroundStyle(Color.danger).padding(.vertical, 12)
            }
            ForEach(labels.names, id: \.self) { name in
                LabelRow(label: name, rename: { rename(name, to: $0) }, delete: { delete(name) })
            }
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

    private func rename(_ label: String, to name: String) {
        run { try await model.session.renameLabel(named: label, to: name) }
    }

    private func delete(_ label: String) {
        run { try await model.session.deleteLabel(named: label) }
    }

    private func run(_ operation: @escaping () async throws -> Void) {
        Task {
            do {
                try await operation()
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct LabelRow: View {
    let label: String
    let rename: (String) -> Void
    let delete: () -> Void
    @State private var name = ""
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tag").font(.smallIcon).foregroundStyle(Color.textMuted).frame(width: 28)
            TextField("Label", text: $name)
                .textFieldStyle(.plain)
                .font(.uiMedium)
                .onSubmit { rename(name) }
            Spacer()
            ConfirmButton(title: "Delete", confirmation: "Delete and take it off every conversation", action: delete)
                .opacity(isHovered ? 1 : 0)
        }
        .frame(height: 48)
        .overlay(alignment: .bottom) { Hairline() }
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .onAppear { name = label }
        .onChange(of: label) { _, new in name = new }
    }
}
