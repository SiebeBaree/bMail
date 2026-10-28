import AuthenticationServices
import DesignSystem
import MailCore
import MailUI
import Providers
import SQLiteData
import SwiftUI

/// Accounts, labels, AI and your domains with the server behind them, as one sheet. Every way to add an address starts from
/// Add Account, and your server only shows up once you want your own domain.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @FetchAll(Account.order(by: \.position)) private var accounts
    @FetchAll(Domain.order(by: \.name)) private var domains
    @FetchAll(MailLabel.order(by: \.name)) private var labels
    @State private var newAddressDomain: Domain?
    @State private var newAddress = ""
    @State private var isAddingDomain = false
    @State private var newDomain = ""
    @State private var renaming: String?
    @State private var newLabelName = ""
    @State private var deleting: String?
    @State private var isSettingUpServer = false
    @State private var isConfirmingDisconnect = false
    @State private var isConnecting = false
    /// Nil until the server says. A server needs your Resend key before its first domain.
    @State private var hasResend: Bool?
    @State private var resendKey = ""
    @State private var isSavingKey = false

    var body: some View {
        NavigationStack {
            List {
                accountsSection
                labelsSection
                aiSection
                if let server = model.session.server {
                    domainsSection
                    serverSection(server)
                } else {
                    Section {} footer: { version }
                }
            }
            .navigationDestination(isPresented: $isSettingUpServer) { ServerSetupScreen() }
            .task(id: model.session.server?.baseURL) {
                hasResend = model.session.server == nil ? nil : try? await model.session.admin.hasResend()
            }
            .font(.phone(16))
            .scrollContentBackground(.hidden)
            .background(Color.chrome)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { dismiss() }
                }
            }
            .alert("New address on \(newAddressDomain?.name ?? "")", isPresented: Binding { newAddressDomain != nil } set: { if !$0 { newAddressDomain = nil } }) {
                TextField("name", text: $newAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) {}
                Button("Create") { if let domain = newAddressDomain { createAddress(on: domain) } }
            } message: {
                Text("Mail to this address arrives here, and you can send from it.")
            }
            .alert("Add a domain", isPresented: $isAddingDomain) {
                TextField("example.com", text: $newDomain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("Cancel", role: .cancel) {}
                Button("Add", action: addDomain)
            }
            .alert("Rename label", isPresented: Binding { renaming != nil } set: { if !$0 { renaming = nil } }) {
                TextField("Name", text: $newLabelName)
                Button("Cancel", role: .cancel) {}
                Button("Rename") { if let label = renaming { rename(label) } }
            }
            .confirmationDialog(
                "Delete \u{201C}\(deleting ?? "")\u{201D}?",
                isPresented: Binding { deleting != nil } set: { if !$0 { deleting = nil } },
                titleVisibility: .visible
            ) {
                Button("Delete label", role: .destructive) { if let label = deleting { delete(label) } }
            } message: {
                Text("It comes off every conversation that has it.")
            }
            .confirmationDialog(
                "Disconnect \(model.session.server?.host ?? "your server")?",
                isPresented: $isConfirmingDisconnect,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) { model.session.disconnectServer() }
            } message: {
                Text("Your domains' mail and all tracking leave bMail. Gmail stays.")
            }
        }
        .presentationBackground(Color.chrome)
    }

    // Split out of `body`: as one expression it takes the CI compiler too long to type-check.
    private var accountsSection: some View {
        Section("Accounts") {
            ForEach(accounts) { account in
                NavigationLink {
                    AccountSettings(account: account, isCatchAll: isCatchAll(account))
                } label: {
                    AccountRow(account: account)
                }
            }
            addAccount
        }
        .listRowBackground(Color.raised)
    }

    private func isCatchAll(_ account: Account) -> Bool {
        domains.contains { $0.catchAllMailboxID == account.id }
    }

    private var labelsSection: some View {
        Section {
            ForEach(labels.names, id: \.self) { label in
                Button {
                    newLabelName = label
                    renaming = label
                } label: {
                    Label(label, systemImage: "tag").foregroundStyle(Color.textPrimary)
                }
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) { deleting = label }
                }
            }
        } header: {
            Text("Labels")
        } footer: {
            if labels.isEmpty { Text("Label a conversation to create your first one.") }
        }
        .listRowBackground(Color.raised)
    }

    private var aiSection: some View {
        Section {
            NavigationLink {
                AISettingsView()
            } label: {
                Label("AI", systemImage: "sparkle").foregroundStyle(Color.textPrimary)
            }
        } footer: {
            Text("Suggestions while you write and auto labelling, on your own key.")
        }
        .listRowBackground(Color.raised)
    }

    @ViewBuilder private var domainsSection: some View {
        if hasResend == false, domains.isEmpty {
            resendSection
        } else {
            domainList
        }
    }

    /// Your server sends and receives through your Resend account, so it asks for a key once, before your first domain.
    private var resendSection: some View {
        Section {
            SecureField("re_…", text: $resendKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(saveResendKey)
            Button(isSavingKey ? "Saving" : "Save key", action: saveResendKey)
                .disabled(resendKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingKey)
        } header: {
            Text("Your domains")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sending and receiving go through your Resend account. Paste a full access API key.")
                Link("Create a key on Resend", destination: URL(string: "https://resend.com/api-keys")!)
            }
        }
        .listRowBackground(Color.raised)
    }

    private var domainList: some View {
        Section {
            ForEach(domains) { domain in
                NavigationLink {
                    DomainSettings(domainID: domain.id)
                } label: {
                    HStack {
                        Text(domain.name).font(.phone(16, .medium))
                        Spacer()
                        StatusDot(domain.status.color)
                        Text(domain.status.label).font(.phone(14)).foregroundStyle(Color.textMuted)
                    }
                }
            }
            Button("Add domain", systemImage: "plus") {
                newDomain = ""
                isAddingDomain = true
            }
        } header: {
            Text("Your domains")
        } footer: {
            if domains.isEmpty { Text("Add a domain you own to send and receive from it. You'll get the DNS records to add at your registrar.") }
        }
        .listRowBackground(Color.raised)
    }

    private func serverSection(_ server: ServerConnection) -> some View {
        Section {
            LabeledContent("Server") {
                Text(server.host).font(.phoneMono(14))
            }
            Button("Disconnect server", role: .destructive) { isConfirmingDisconnect = true }
                .foregroundStyle(Color.danger)
        } footer: {
            version
        }
        .listRowBackground(Color.raised)
    }

    private var version: some View {
        Text("bMail \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
            .font(.phone(13, relativeTo: .footnote))
            .foregroundStyle(Color.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }

    @ViewBuilder private var addAccount: some View {
        Menu {
            if model.session.google != nil {
                Button("Gmail", systemImage: "envelope", action: connectGmail)
            }
            if model.session.server == nil {
                Button("Address on your own domain", systemImage: "at") { isSettingUpServer = true }
            }
            ForEach(domains.filter { $0.status == .verified }) { domain in
                Button("Address on \(domain.name)", systemImage: "at") {
                    newAddress = ""
                    newAddressDomain = domain
                }
            }
        } label: {
            Label(isConnecting ? "Connecting Gmail" : "Add account", systemImage: "plus")
        }
        .disabled(isConnecting)
    }

    private func connectGmail() {
        isConnecting = true
        Task {
            defer { isConnecting = false }
            do {
                try await model.connectGmail(using: webAuthenticationSession)
            } catch {
                fail("Couldn't connect Gmail.", error)
            }
        }
    }

    private func saveResendKey() {
        let key = resendKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        isSavingKey = true
        Task {
            defer { isSavingKey = false }
            do {
                try await model.session.admin.setResendKey(key)
                Haptics.success()
                resendKey = ""
                hasResend = true
            } catch {
                fail("Couldn't save the key.", error)
            }
        }
    }

    private func createAddress(on domain: Domain) {
        let localPart = newAddress.trimmingCharacters(in: .whitespaces).lowercased()
        guard !localPart.isEmpty else { return }
        run("Couldn't create \(localPart)@\(domain.name).") {
            try await model.session.admin.addMailbox(localPart: localPart, displayName: localPart.capitalized, on: domain.id)
        }
    }

    private func addDomain() {
        let name = newDomain.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty else { return }
        run("Couldn't add \(name).") { try await model.session.admin.addDomain(name) }
    }

    private func rename(_ label: String) {
        let name = newLabelName
        Task {
            do { try await model.session.renameLabel(named: label, to: name) } catch { fail("Couldn't rename \(label).", error) }
        }
    }

    private func delete(_ label: String) {
        Task {
            do { try await model.session.deleteLabel(named: label) } catch { fail("Couldn't delete \(label).", error) }
        }
    }

    private func run(_ failure: String, _ operation: @escaping () async throws -> ChangeSet) {
        Task {
            do {
                try model.session.store.merge(try await operation(), source: "settings")
            } catch {
                fail(failure, error)
            }
        }
    }

    private func fail(_ title: String, _ error: any Error) {
        Haptics.failure()
        model.session.toasts.show(Toast(title, detail: error.localizedDescription, symbol: "exclamationmark.triangle", tone: .failure))
    }
}

private struct AccountRow: View {
    let account: Account

    var body: some View {
        HStack(spacing: 12) {
            Avatar(account.displayName, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(account.address).font(.phone(16, .medium)).lineLimit(1)
                Text(account.kind.label).font(.phone(13)).foregroundStyle(Color.textMuted)
            }
        }
        .padding(.vertical, 2)
    }
}

/// One account: its signature, and the way to remove it.
private struct AccountSettings: View {
    let account: Account
    let isCatchAll: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var signature = ""
    @State private var isConfirmingRemoval = false

    var body: some View {
        List {
            Section {
                AccountRow(account: account)
                if isCatchAll {
                    Text("Also gets mail sent to addresses on \(account.address.split(separator: "@").last.map(String.init) ?? "the domain") that don't exist.")
                        .font(.phone(14))
                        .foregroundStyle(Color.textMuted)
                }
            }
            .listRowBackground(Color.raised)
            Section {
                TextEditor(text: $signature)
                    .font(.phone(16))
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
                    .overlay(alignment: .topLeading) {
                        if signature.isEmpty {
                            Text("Goes under everything you write from this address.")
                                .font(.phone(16))
                                .foregroundStyle(Color.textFaint)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            } header: {
                Text("Signature")
            }
            .listRowBackground(Color.raised)
            Section {
                Button(account.kind == .domain ? "Delete address" : "Disconnect", role: .destructive) { isConfirmingRemoval = true }
                    .foregroundStyle(Color.danger)
            }
            .listRowBackground(Color.raised)
        }
        .font(.phone(16))
        .scrollContentBackground(.hidden)
        .background(Color.chrome)
        .navigationTitle(account.address)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { signature = Signatures.text(for: account.id) }
        .onChange(of: signature) { _, text in Signatures.set(text, for: account.id) }
        .confirmationDialog(
            account.kind == .domain ? "Delete \(account.address) and all its mail?" : "Disconnect \(account.address)?",
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button(account.kind == .domain ? "Delete" : "Disconnect", role: .destructive, action: remove)
        } message: {
            Text(account.kind == .domain ? "The address stops receiving mail. This can't be undone." : "Its mail leaves bMail. Gmail keeps everything.")
        }
    }

    private func remove() {
        Task {
            do {
                if account.kind == .domain {
                    try model.session.store.merge(try await model.session.admin.removeMailbox(account.id), source: "settings")
                } else {
                    try model.session.disconnect(account)
                }
                dismiss()
            } catch {
                Haptics.failure()
                model.session.toasts.show(Toast("Couldn't remove \(account.address).", detail: error.localizedDescription, symbol: "exclamationmark.triangle", tone: .failure))
            }
        }
    }
}
