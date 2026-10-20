import AuthenticationServices
import CryptoKit
import DesignSystem
import MailCore
import MailUI
import Providers
import SwiftUI

/// Two steps. First your server: there is no shared one, so everyone signs in to the api they host. Then Apple or email
/// and password, both ending in a Better Auth session there. Sign in with Apple happens natively and only the resulting
/// ID token goes to the server. Google is for Gmail only and connects in Settings.
struct SignInView: View {
    @Environment(AppModel.self) private var model
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
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                LogoMark(size: 44)
                    .padding(.bottom, 14)
                if let server = model.session.server, !isChangingServer {
                    signIn(to: server)
                } else {
                    serverStep
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 72)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.canvas)
        .animation(.snappy(duration: 0.3), value: isChangingServer)
        .animation(.snappy(duration: 0.3), value: model.session.server?.baseURL)
        .onAppear { if model.session.server == nil { focus = .server } }
    }

    @ViewBuilder private var serverStep: some View {
        Text("Connect your server").font(.phone(28, .semibold, relativeTo: .title)).tracking(-0.5)
        Text("bMail talks to the api you host. Enter its address.")
            .font(.phone(16))
            .foregroundStyle(Color.textMuted)
            .padding(.bottom, 10)
        TextField("mail-api.example.com", text: $address)
            .textFieldStyle(PhoneFieldStyle())
            .textContentType(.URL)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.continue)
            .focused($focus, equals: .server)
            .onSubmit(connect)
        errorMessage
        Button(action: connect) {
            Text(isWorking ? "Connecting" : "Continue")
        }
        .buttonStyle(PhoneButtonStyle(.primary))
        .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
        HStack(spacing: 4) {
            Text("No server yet?").foregroundStyle(Color.textFaint)
            Link("Host your own", destination: Self.selfHostingGuide).foregroundStyle(Color.link)
        }
        .font(.phone(14))
        .padding(.top, 6)
    }

    @ViewBuilder private func signIn(to server: ServerConnection) -> some View {
        Text("Sign in to bMail").font(.phone(28, .semibold, relativeTo: .title)).tracking(-0.5)
            .padding(.bottom, 10)

        SignInWithAppleButton(.continue) { request in
            appleNonce = UUID().uuidString
            request.requestedScopes = [.email, .fullName]
            request.nonce = SHA256.hash(data: Data(appleNonce.utf8)).map { String(format: "%02x", $0) }.joined()
        } onCompletion: { result in
            signInWithApple(result)
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 52)
        .clipShape(.rect(cornerRadius: 14))

        HStack(spacing: 12) {
            Hairline()
            Text("or").font(.phone(14)).foregroundStyle(Color.textFaint)
            Hairline()
        }
        .padding(.vertical, 6)

        TextField("Email", text: $email)
            .textFieldStyle(PhoneFieldStyle())
            .textContentType(.username)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .focused($focus, equals: .email)
            .onSubmit { focus = .password }
        SecureField("Password", text: $password)
            .textFieldStyle(PhoneFieldStyle())
            .textContentType(.password)
            .submitLabel(.go)
            .focused($focus, equals: .password)
            .onSubmit(signInWithPassword)
        errorMessage
        Button(action: signInWithPassword) {
            Text(isWorking ? "Signing in" : "Sign in")
        }
        .buttonStyle(PhoneButtonStyle(.primary))
        .disabled(email.isEmpty || password.isEmpty || isWorking)
        HStack(spacing: 6) {
            Text(server.baseURL.host() ?? "").font(.phoneMono(13)).foregroundStyle(Color.textFaint)
            Button("Change") {
                address = server.baseURL.absoluteString
                error = nil
                isChangingServer = true
                focus = .server
            }
            .font(.phone(14))
            .foregroundStyle(Color.link)
        }
        .padding(.top, 6)
    }

    @ViewBuilder private var errorMessage: some View {
        if let error {
            Text(error)
                .font(.phone(15))
                .foregroundStyle(Color.danger)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
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
                Haptics.failure()
                self.error = error.localizedDescription
            }
        }
    }

    private func run(_ signIn: @escaping (ServerConnection) async throws -> Void) {
        guard let server = model.session.server else { return }
        isWorking = true
        error = nil
        focus = nil
        Task {
            defer { isWorking = false }
            do {
                try await signIn(server)
                Haptics.success()
                model.session.start()
            } catch {
                Haptics.failure()
                self.error = error.localizedDescription
            }
        }
    }

    private func signInWithPassword() {
        guard !email.isEmpty, !password.isEmpty else { return }
        run { try await $0.signIn(email: email, password: password) }
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
            run { try await $0.signInWithApple(idToken: token, nonce: nonce) }
        case let .failure(failure):
            if (failure as? ASAuthorizationError)?.code != .canceled { error = failure.localizedDescription }
        }
    }
}

/// A field sized for a thumb: 52 points tall, on a raised surface with a hairline border.
struct PhoneFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.phone(17))
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Color.raised, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.lineStrong))
    }
}

/// The full-width buttons on the sign-in screen.
struct PhoneButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }

    let kind: Kind
    @Environment(\.isEnabled) private var isEnabled

    init(_ kind: Kind) {
        self.kind = kind
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.phone(17, .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(kind == .primary ? Color.onInverted : Color.textPrimary)
            .background(kind == .primary ? Color.inverted : Color.raised, in: .rect(cornerRadius: 14))
            .overlay {
                if kind == .secondary { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.lineStrong) }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .contentShape(.rect(cornerRadius: 14))
    }
}
