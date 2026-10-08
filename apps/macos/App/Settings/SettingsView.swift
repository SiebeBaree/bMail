import AuthenticationServices
import DesignSystem
import MailCore
import Providers
import SwiftUI

struct SettingsView: View {
    @State private var pane: Pane = .domains

    enum Pane: String, CaseIterable, Identifiable {
        case domains = "Domains"
        case accounts = "Accounts"
        case shortcuts = "Shortcuts"
        var id: Self { self }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Pane.allCases) { item in
                    Button { pane = item } label: {
                        Text(item.rawValue)
                            .foregroundStyle(pane == item ? Color.textPrimary : Color.textSecondary)
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                            .background(pane == item ? Color.selected : .clear, in: .rect(cornerRadius: Metrics.controlRadius))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 52)
            .frame(width: 200)
            .background(Color.chrome)
            Hairline(.vertical)
            ScrollView {
                Group {
                    switch pane {
                    case .domains: DomainSettings()
                    case .accounts: AccountSettings()
                    case .shortcuts: ShortcutSettings()
                    }
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color.canvas)
        }
        .font(.ui)
        .foregroundStyle(Color.textPrimary)
        .frame(minWidth: 940, minHeight: 640)
        .ignoresSafeArea()
        .containerBackground(Color.canvas, for: .window)
        .toolbar(removing: .title)
    }
}

private struct AccountSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var error: String?
    @State private var connecting: Account.Kind?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Accounts").font(.pageTitle)
                Spacer()
                if BuildSettings.google != nil {
                    Button(connecting == .gmail ? "Connecting" : "Connect Gmail") { connect(.gmail) }
                        .buttonStyle(.secondary)
                        .disabled(connecting != nil)
                }
                if BuildSettings.microsoft != nil {
                    Button(connecting == .outlook ? "Connecting" : "Connect Outlook") { connect(.outlook) }
                        .buttonStyle(.secondary)
                        .disabled(connecting != nil)
                }
            }
            if let error { Text(error).foregroundStyle(Color.danger) }
            ForEach(Array(model.accounts.enumerated()), id: \.element.id) { index, account in
                HStack(spacing: 12) {
                    Avatar(account.displayName, size: 24)
                    Text(account.address)
                    Text(account.kind.label).foregroundStyle(Color.textMuted)
                    Spacer()
                    if account.kind != .domain {
                        Button("Disconnect") { try? model.disconnect(account) }
                            .buttonStyle(.ghost)
                    }
                    if index < 9 { KeyCap("⌘\(index + 1)") }
                }
                .frame(height: 40)
                .overlay(alignment: .bottom) { Hairline() }
            }
            Text("Gmail and Outlook connect straight from this Mac. Their mail never passes through your server.")
                .foregroundStyle(Color.textMuted)
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

extension Account.Kind {
    var label: String {
        switch self {
        case .domain: "Your domain"
        case .gmail: "Gmail"
        case .outlook: "Outlook"
        }
    }
}

private struct ShortcutSettings: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shortcuts").font(.pageTitle).padding(.bottom, 10)
            ForEach(Command.allCases.filter(\.isInPalette)) { command in
                HStack {
                    Text(command.title).foregroundStyle(Color.textSecondary)
                    Spacer()
                    HStack(spacing: 4) { ForEach(command.keys, id: \.self) { KeyCap($0) } }
                }
                .frame(height: 30)
            }
        }
    }
}
