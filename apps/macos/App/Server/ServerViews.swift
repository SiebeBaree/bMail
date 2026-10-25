import DesignSystem
import MailCore
import MailUI
import Providers
import SwiftUI

/// The two ways to a server: a new one on Vercel, or the address of one you run already. Either way it ends in the
/// sheet that asks before connecting.
struct ServerChoice: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var isTypingAddress = false
    @State private var address = ""
    @State private var error: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { openURL(ServerSetup.deployURL) } label: {
                Text("Set up on Vercel").frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary)
            if isTypingAddress {
                HStack(spacing: 8) {
                    TextField("mail-api.example.com", text: $address)
                        .textFieldStyle(.field)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .focused($isFocused)
                        .onSubmit(connect)
                    Button("Continue", action: connect)
                        .buttonStyle(.secondary)
                        .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                Button {
                    isTypingAddress = true
                    isFocused = true
                } label: {
                    Text("Connect existing").frame(maxWidth: .infinity)
                }
                .buttonStyle(.secondary)
            }
            if let error {
                Text(error).foregroundStyle(Color.danger).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func connect() {
        guard let url = ServerConnection.baseURL(from: address) else {
            error = "Enter an address like mail-api.example.com."
            return
        }
        error = nil
        model.connect(to: url)
    }
}

/// Asks before connecting to a server, whether it came from a link or was typed. A fresh server becomes yours; one with
/// an owner takes its claim code.
struct ConnectServerSheet: View {
    let url: URL
    @Environment(AppModel.self) private var model
    @State private var ownership: ServerConnection.Ownership?
    @State private var code = ""
    @State private var error: String?
    @State private var isWorking = false
    @FocusState private var isCodeFocused: Bool

    private var host: String { url.host() ?? url.absoluteString }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { model.connectingServer = nil }
            VStack(alignment: .leading, spacing: 12) {
                Text(ownership == .owned ? "This server has an owner" : "Connect \(host)?")
                    .font(.geist(16, .semibold))
                    .tracking(-0.2)
                Text(message).foregroundStyle(Color.textSecondary).fixedSize(horizontal: false, vertical: true)
                if ownership == .owned {
                    TextField("Claim code", text: $code)
                        .textFieldStyle(.field)
                        .focused($isCodeFocused)
                        .onSubmit(connect)
                }
                if let error {
                    Text(error).foregroundStyle(Color.danger).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel") { model.connectingServer = nil }
                        .buttonStyle(.ghost)
                        .keyboardShortcut(.cancelAction)
                    Button(isWorking ? "Connecting" : "Connect", action: connect)
                        .buttonStyle(.primary)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canConnect)
                }
                .padding(.top, 4)
            }
            .padding(20)
            .frame(width: 360)
            .background(Color.raised, in: .rect(cornerRadius: Metrics.windowRadius))
            .overlay(RoundedRectangle(cornerRadius: Metrics.windowRadius).strokeBorder(Color.lineStrong))
            .shadow(color: .black.opacity(0.45), radius: 30, y: 16)
        }
        .task(id: url) { await check() }
    }

    private var message: String {
        switch ownership {
        case nil: "Checking the server."
        case .fresh: "It's a new server. Connecting makes your devices its owner."
        case .owned: "If it's yours, add CLAIM_CODE to the project on Vercel, redeploy and enter it here."
        }
    }

    private var canConnect: Bool {
        guard !isWorking, let ownership else { return false }
        return ownership == .fresh || !code.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func check() async {
        do {
            ownership = try await model.session.ownership(of: url)
            if ownership == .owned { isCodeFocused = true }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func connect() {
        guard canConnect else { return }
        isWorking = true
        error = nil
        let code = ownership == .owned ? code.trimmingCharacters(in: .whitespaces) : nil
        Task {
            defer { isWorking = false }
            do {
                try await model.session.claimServer(at: url, code: code)
                model.connectingServer = nil
                // You came for your own domain, and that starts in Settings.
                if !model.session.accounts.contains(where: { $0.kind == .domain }) { model.openSettings() }
            } catch {
                // Someone claimed it since the check, which the owned message already explains.
                if ownership == .fresh, (error as? ProviderError)?.kind == .rejected {
                    ownership = .owned
                    isCodeFocused = true
                } else {
                    self.error = error.localizedDescription
                }
            }
        }
    }
}
