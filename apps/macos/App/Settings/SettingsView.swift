import AuthenticationServices
import DesignSystem
import MailCore
import Providers
import SQLiteData
import SwiftUI

/// One page: the addresses you read and send from, then the domains behind your own addresses. Every way to add an
/// address starts from the same button.
struct SettingsView: View {
    @FocusState private var isDomainFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 48) {
                Text("Settings").font(.pageTitle).tracking(-0.3)
                AccountsSection(isDomainFieldFocused: $isDomainFieldFocused)
                DomainsSection(isDomainFieldFocused: $isDomainFieldFocused)
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
    @State private var connecting: Account.Kind?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(title: "Accounts") {
                Button { isAddOpen.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                        Text(connecting.map { "Connecting \($0.label)" } ?? "Add account")
                    }
                }
                .buttonStyle(.secondary)
                .disabled(connecting != nil)
                .dropdown(isPresented: $isAddOpen, alignment: .trailing) { addOptions }
            }
            if let error {
                Text(error).foregroundStyle(Color.danger).padding(.vertical, 12)
            }
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                AccountRow(account: account, number: index + 1, isCatchAll: isCatchAll(account)) { remove(account) }
            }
            if let domain = domains.first(where: { $0.id == newAddressDomain }) {
                NewAddressRow(domain: domain, create: { createAddress($0, on: domain) }, cancel: { newAddressDomain = nil })
            } else if accounts.isEmpty {
                Text("No accounts yet. Add Gmail, Outlook or an address on your own domain.")
                    .foregroundStyle(Color.textMuted)
                    .padding(.vertical, 16)
            }
        }
    }

    @ViewBuilder private var addOptions: some View {
        if BuildSettings.google != nil {
            option("Gmail", detail: "Sign in with Google", symbol: "envelope") { connect(.gmail) }
        }
        if BuildSettings.microsoft != nil {
            option("Outlook", detail: "Sign in with Microsoft", symbol: "envelope") { connect(.outlook) }
        }
        if !domains.isEmpty, BuildSettings.google != nil || BuildSettings.microsoft != nil {
            Hairline().padding(.vertical, 4)
        }
        ForEach(domains) { domain in
            option("Address on \(domain.name)", detail: "name@\(domain.name)", symbol: "at") { newAddressDomain = domain.id }
        }
        if domains.isEmpty {
            option("Address on your own domain", detail: "Add the domain first, below", symbol: "at") {
                isDomainFieldFocused.wrappedValue = true
            }
        }
    }

    private func option(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            isAddOpen = false
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
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
                let changes = try await ServerAdmin(connection: model.server)
                    .addMailbox(localPart: localPart, displayName: localPart.capitalized, on: domain.id)
                try model.store.merge(changes, source: "settings")
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
                    try model.store.merge(try await ServerAdmin(connection: model.server).removeMailbox(account.id), source: "settings")
                } else {
                    try model.disconnect(account)
                }
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func connect(_ kind: Account.Kind) {
        guard let client = kind == .gmail ? BuildSettings.google : BuildSettings.microsoft else { return }
        connecting = kind
        error = nil
        Task {
            defer { connecting = nil }
            do {
                let attempt = client.start()
                let callback = try await webAuthenticationSession.authenticate(
                    using: attempt.url,
                    callback: .customScheme(attempt.callbackScheme),
                    preferredBrowserSession: .ephemeral,
                    additionalHeaderFields: [:]
                )
                try model.connect(kind, tokens: try await client.finish(attempt, callback: callback))
            } catch let failure as ASWebAuthenticationSessionError where failure.code == .canceledLogin {
                return
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct AccountRow: View {
    let account: Account
    let number: Int
    let isCatchAll: Bool
    let remove: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Avatar(account.displayName, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.address).font(.uiMedium)
                Text(isCatchAll ? "\(account.kind.label) · catch-all" : account.kind.label)
                    .font(.geist(12))
                    .foregroundStyle(Color.textMuted)
            }
            Spacer()
            ConfirmButton(
                title: account.kind == .domain ? "Delete" : "Disconnect",
                confirmation: account.kind == .domain ? "Delete with all its mail" : "Disconnect from this Mac",
                action: remove
            )
            .opacity(isHovered ? 1 : 0)
            if number <= 9 { KeyCap("⌘\(number)") }
        }
        .frame(height: 56)
        .overlay(alignment: .bottom) { Hairline() }
        .contentShape(.rect)
        .onHover { isHovered = $0 }
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

extension Account.Kind {
    var label: String {
        switch self {
        case .domain: "Your domain"
        case .gmail: "Gmail"
        case .outlook: "Outlook"
        }
    }
}
