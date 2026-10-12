import AuthenticationServices
import CryptoKit
import DesignSystem
import MailCore
import MailUI
import Providers
import SwiftUI

/// Two steps. First your server: there is no shared one, so everyone signs in to the api they host. Then Apple, Google
/// or email and password, all ending in a Better Auth session there. Social sign-in happens natively and only the
/// resulting ID token goes to the server.
struct SignInView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.colorScheme) private var colorScheme
    @State private var isChangingServer = false
    @State private var address = ""
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var isWorking = false
    @State private var appleNonce = ""
    @FocusState private var focus: Field?

    enum Field { case server, email, password }

    private static let selfHostingGuide = URL(string: "https://github.com/SiebeBaree/bMail#host-your-api")!

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LogoMark(size: 36)
                .padding(.bottom, 8)
            if let server = model.session.server, !isChangingServer {
                signIn(to: server)
            } else {
                serverStep
            }
        }
        .frame(width: 340)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas)
        .onAppear { if model.session.server == nil { focus = .server } }
    }

    @ViewBuilder private var serverStep: some View {
        Text("Connect your server").font(.geist(22, .semibold)).tracking(-0.4)
        TextField("mail-api.example.com", text: $address)
            .textFieldStyle(.field)
            .textContentType(.URL)
            .autocorrectionDisabled()
            .focused($focus, equals: .server)
            .onSubmit(connect)
        errorMessage
        Button(action: connect) {
            Text(isWorking ? "Connecting" : "Continue").frame(maxWidth: .infinity)
        }
        .buttonStyle(.primary)
        .disabled(address.isEmpty || isWorking)
        HStack(spacing: 4) {
            Text("No server yet?").foregroundStyle(Color.textFaint)
            Link("Host your own", destination: Self.selfHostingGuide).foregroundStyle(Color.link)
        }
        .font(.geist(12))
    }

    @ViewBuilder private func signIn(to server: ServerConnection) -> some View {
        Text("Sign in to bMail").font(.geist(22, .semibold)).tracking(-0.4)

        VStack(spacing: 10) {
            if BuildSettings.signInWithApple {
                SignInWithAppleButton(.continue) { request in
                    appleNonce = UUID().uuidString
                    request.requestedScopes = [.email, .fullName]
                    request.nonce = SHA256.hash(data: Data(appleNonce.utf8)).map { String(format: "%02x", $0) }.joined()
                } onCompletion: { result in
                    signInWithApple(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: Metrics.controlHeight + 4)
            }

            if BuildSettings.googleSignIn != nil {
                Button(action: signInWithGoogle) {
                    Text("Continue with Google").frame(maxWidth: .infinity)
                }
                .buttonStyle(.secondary)
            }
        }
        .padding(.top, 8)

        if BuildSettings.signInWithApple || BuildSettings.googleSignIn != nil {
            HStack(spacing: 10) {
                Hairline()
                Text("or").font(.geist(12)).foregroundStyle(Color.textFaint)
                Hairline()
            }
            .padding(.vertical, 4)
        }

        VStack(spacing: 10) {
            TextField("Email", text: $email)
                .textFieldStyle(.field)
                .textContentType(.username)
                .focused($focus, equals: .email)
                .onSubmit { focus = .password }
            SecureField("Password", text: $password)
                .textFieldStyle(.field)
                .textContentType(.password)
                .focused($focus, equals: .password)
                .onSubmit(signInWithPassword)
        }
        errorMessage
        Button(action: signInWithPassword) {
            Text(isWorking ? "Signing in" : "Sign in").frame(maxWidth: .infinity)
        }
        .buttonStyle(.primary)
        .disabled(email.isEmpty || password.isEmpty || isWorking)
        HStack(spacing: 6) {
            Text(server.baseURL.host() ?? "").font(.meta).foregroundStyle(Color.textFaint)
            Button("Change") {
                address = server.baseURL.absoluteString
                error = nil
                isChangingServer = true
                focus = .server
            }
            .buttonStyle(.plain)
            .font(.geist(12))
            .foregroundStyle(Color.link)
        }
        .padding(.top, 8)
    }

    @ViewBuilder private var errorMessage: some View {
        if let error {
            Text(error).foregroundStyle(Color.danger).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Checks that a bMail api answers at the address before the app switches to it.
    private func connect() {
        guard let url = ServerConnection.baseURL(from: address) else {
            error = "Enter an address like mail-api.example.com."
            return
        }
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            do {
                try await ServerConnection(baseURL: url).checkServer()
                try model.session.connect(to: url)
                isChangingServer = false
                focus = .email
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func run(_ signIn: @escaping (ServerConnection) async throws -> Void) {
        guard let server = model.session.server else { return }
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            do {
                try await signIn(server)
                model.session.start()
            } catch let failure as ASWebAuthenticationSessionError where failure.code == .canceledLogin {
                return
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func signInWithPassword() {
        guard !email.isEmpty, !password.isEmpty else { return }
        run { try await $0.signIn(email: email, password: password) }
    }

    private func signInWithGoogle() {
        guard let client = BuildSettings.googleSignIn else { return }
        run { server in
            let attempt = client.start()
            let callback = try await webAuthenticationSession.authenticate(
                using: attempt.url,
                callback: .customScheme(attempt.callbackScheme),
                preferredBrowserSession: .shared,
                additionalHeaderFields: [:]
            )
            guard let idToken = try await client.finish(attempt, callback: callback).idToken else {
                throw ProviderError(.rejected, "Google didn't confirm who you are. Try again.")
            }
            try await server.signIn(provider: "google", idToken: idToken)
        }
    }

    private func signInWithApple(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let token = credential.identityToken.map({ String(decoding: $0, as: UTF8.self) })
            else {
                error = "Apple didn't confirm who you are. Try again."
                return
            }
            let nonce = appleNonce
            run { try await $0.signIn(provider: "apple", idToken: token, nonce: nonce) }
        case let .failure(failure):
            if (failure as? ASAuthorizationError)?.code != .canceled { error = failure.localizedDescription }
        }
    }
}
