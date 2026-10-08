import AuthenticationServices
import CryptoKit
import DesignSystem
import MailCore
import Providers
import SwiftUI

/// Apple, Google or email and password, all ending in a Better Auth session on your server. Social sign-in happens
/// natively and only the resulting ID token goes to the server.
struct SignInView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.colorScheme) private var colorScheme
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var isWorking = false
    @State private var appleNonce = ""
    @FocusState private var focus: Field?

    enum Field { case email, password }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "envelope")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.onInverted)
                .frame(width: 36, height: 36)
                .background(Color.inverted, in: .rect(cornerRadius: 9))
                .padding(.bottom, 8)
            Text("Sign in to Baree Mail").font(.geist(22, .semibold)).tracking(-0.4)

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
            if let error {
                Text(error).foregroundStyle(Color.danger).fixedSize(horizontal: false, vertical: true)
            }
            Button(action: signInWithPassword) {
                Text(isWorking ? "Signing in" : "Sign in").frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary)
            .disabled(email.isEmpty || password.isEmpty || isWorking)
            Text(model.server.baseURL.host() ?? "")
                .font(.meta)
                .foregroundStyle(Color.textFaint)
                .padding(.top, 8)
        }
        .frame(width: 340)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas)
    }

    private func run(_ signIn: @escaping () async throws -> Void) {
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            do {
                try await signIn()
                model.start()
            } catch let failure as ASWebAuthenticationSessionError where failure.code == .canceledLogin {
                return
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func signInWithPassword() {
        guard !email.isEmpty, !password.isEmpty else { return }
        run { try await model.server.signIn(email: email, password: password) }
    }

    private func signInWithGoogle() {
        guard let client = BuildSettings.googleSignIn else { return }
        run {
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
            try await model.server.signIn(provider: "google", idToken: idToken)
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
            run { try await model.server.signIn(provider: "apple", idToken: token, nonce: nonce) }
        case let .failure(failure):
            if (failure as? ASAuthorizationError)?.code != .canceled { error = failure.localizedDescription }
        }
    }
}
