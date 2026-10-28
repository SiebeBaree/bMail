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
    @State private var isDeploying = false
    @State private var address = ""
    @State private var error: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(isDeploying ? "Waiting for Vercel" : "Set up on Vercel") {
                isDeploying = true
                openURL(ServerSetup.deployURL)
            }
            .buttonStyle(PhoneButtonStyle(.primary))
            if isDeploying {
                Text("Finish the deploy in Safari. bMail picks up the server when it's done.")
                    .font(.phone(14))
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isTypingAddress {
                TextField("mail-api.example.com", text: $address)
                    .textFieldStyle(PhoneFieldStyle())
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .focused($isFocused)
                    .onSubmit(connect)
                Button("Continue", action: connect)
                    .buttonStyle(PhoneButtonStyle(.secondary))
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
            } else {
                Button("Connect existing") {
                    isTypingAddress = true
                    isFocused = true
                }
                .buttonStyle(PhoneButtonStyle(.secondary))
            }
            if let error {
                Text(error).font(.phone(15)).foregroundStyle(Color.danger).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func connect() {
        guard let url = ServerConnection.baseURL(from: address) else {
            Haptics.failure()
            error = "Enter an address like mail-api.example.com."
            return
        }
        error = nil
        isFocused = false
        model.connect(to: url)
    }
}

/// Asks before connecting to a server, whether it came from a link or was typed. A fresh server becomes yours; one with
/// an owner takes its claim code.
struct ConnectServerSheet: View {
    let url: URL
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var ownership: ServerConnection.Ownership?
    @State private var code = ""
    @State private var error: String?
    @State private var isWorking = false
    @FocusState private var isCodeFocused: Bool

    private var host: String { url.host() ?? url.absoluteString }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(ownership == .owned ? "This server has an owner" : "Connect \(host)?")
                .font(.phone(22, .semibold, relativeTo: .title2))
                .tracking(-0.4)
                .fixedSize(horizontal: false, vertical: true)
            Text(message).font(.phone(16)).foregroundStyle(Color.textSecondary).fixedSize(horizontal: false, vertical: true)
            if ownership == .owned {
                TextField("Claim code", text: $code)
                    .textFieldStyle(PhoneFieldStyle())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($isCodeFocused)
                    .onSubmit(connect)
            }
            if let error {
                Text(error).font(.phone(15)).foregroundStyle(Color.danger).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(isWorking ? "Connecting" : "Connect", action: connect)
                .buttonStyle(PhoneButtonStyle(.primary))
                .disabled(!canConnect)
            Button("Cancel") { dismiss() }
                .buttonStyle(PhoneButtonStyle(.secondary))
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationBackground(Color.chrome)
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
                Haptics.success()
                // You came for your own domain, which setup carries on with. After setup it's in Settings.
                let needsDomain = !model.session.accounts.contains(where: { $0.kind == .domain })
                model.sheet = model.onboarding.isFinished && needsDomain ? .settings : nil
            } catch {
                Haptics.failure()
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

/// Settings' way to your own domain when there's no server yet.
struct ServerSetupScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your domains and tracking run on a server you host. Free on Vercel, about two minutes.")
                    .font(.phone(16))
                    .foregroundStyle(Color.textMuted)
                ServerChoice()
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.chrome)
        .navigationTitle("Your own domain")
        .navigationBarTitleDisplayMode(.inline)
    }
}
