import AuthenticationServices
import DesignSystem
import MailCore
import MailUI
import Providers
import SQLiteData
import SwiftUI

/// Accounts, labels, your domains and the server, as one sheet. Every way to add an address starts from Add Account.
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
    @State private var renaming: MailLabel?
    @State private var newLabelName = ""
    @State private var deleting: MailLabel?
    @State private var isConfirmingSignOut = false
    @State private var isConnecting = false

    var body: some View {
        NavigationStack {
            List {
                accountsSection
                labelsSection
                domainsSection
                serverSection
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
                "Delete \u{201C}\(deleting?.name ?? "")\u{201D}?",
                isPresented: Binding { deleting != nil } set: { if !$0 { deleting = nil } },
                titleVisibility: .visible
            ) {
                Button("Delete Label", role: .destructive) { if let label = deleting { delete(label) } }
            } message: {
                Text("It comes off every conversation that has it.")
            }
            .confirmationDialog("Sign out of bMail?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    dismiss()
                    Task { await model.signOut() }
                }
            } message: {
                Text("This iPhone forgets your mail and your Gmail sign-ins. Everything syncs again when you sign back in.")
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
            ForEach(labels) { label in
                Button {
                    newLabelName = label.name
                    renaming = label
                } label: {
                    Label(label.name, systemImage: "tag").foregroundStyle(Color.textPrimary)
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

    private var domainsSection: some View {
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
            Button("Add Domain", systemImage: "plus") {
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

    private var serverSection: some View {
        Section {
            LabeledContent("Server") {
                Text(model.session.server?.baseURL.host() ?? "").font(.phoneMono(14))
            }
            Button("Sign Out", role: .destructive) { isConfirmingSignOut = true }
                .foregroundStyle(Color.danger)
        } footer: {
            Text("bMail \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
        }
        .listRowBackground(Color.raised)
    }

    @ViewBuilder private var addAccount: some View {
        Menu {
            if model.session.google != nil {
                Button("Gmail", systemImage: "envelope", action: connectGmail)
            }
            ForEach(domains.filter { $0.status == .verified }) { domain in
                Button("Address on \(domain.name)", systemImage: "at") {
                    newAddress = ""
                    newAddressDomain = domain
                }
            }
        } label: {
            Label(isConnecting ? "Connecting Gmail" : "Add Account", systemImage: "plus")
        }
        .disabled(isConnecting)
    }

    private func connectGmail() {
        guard let client = model.session.google else { return }
        isConnecting = true
        Task {
            defer { isConnecting = false }
            do {
                let attempt = client.start()
                let callback = try await webAuthenticationSession.authenticate(
                    using: attempt.url,
                    callback: .customScheme(attempt.callbackScheme),
                    preferredBrowserSession: .ephemeral,
                    additionalHeaderFields: [:]
                )
                try model.session.connectGmail(tokens: try await client.finish(attempt, callback: callback))
                Haptics.success()
            } catch let failure as ASWebAuthenticationSessionError where failure.code == .canceledLogin {
                return
            } catch {
                fail("Couldn't connect Gmail.", error)
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

    private func rename(_ label: MailLabel) {
        let name = newLabelName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != label.name else { return }
        run("Couldn't rename \(label.name).") { try await model.session.admin.renameLabel(label.id, to: name) }
    }

    private func delete(_ label: MailLabel) {
        run("Couldn't delete \(label.name).") { try await model.session.admin.deleteLabel(label.id) }
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
                Button(account.kind == .domain ? "Delete Address" : "Disconnect", role: .destructive) { isConfirmingRemoval = true }
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
            Text(account.kind == .domain ? "The address stops receiving mail. This can't be undone." : "Its mail leaves this iPhone. Gmail keeps everything.")
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
