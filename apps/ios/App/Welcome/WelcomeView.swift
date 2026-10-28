import AuthenticationServices
import DesignSystem
import MailUI
import SwiftUI

/// What a first launch shows, and what's left after you remove every account. There's no bMail account: Gmail connects
/// straight to Google, and your own domains go through a server you host. Accounts set up on your Mac arrive through
/// iCloud Keychain and skip this screen.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var isChoosingServer = false
    @State private var isConnecting = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                LogoMark(size: 44)
                    .padding(.bottom, 14)
                if isChoosingServer {
                    Text("Your own domain").font(.phone(28, .semibold, relativeTo: .title)).tracking(-0.5)
                    Text("Your domains and tracking run on a server you host. Free on Vercel, about two minutes.")
                        .font(.phone(16))
                        .foregroundStyle(Color.textMuted)
                        .padding(.bottom, 10)
                    ServerChoice()
                    Button("Back") { isChoosingServer = false }
                        .font(.phone(15))
                        .foregroundStyle(Color.link)
                        .padding(.top, 6)
                } else {
                    Text("Add your mail").font(.phone(28, .semibold, relativeTo: .title)).tracking(-0.5)
                        .padding(.bottom, 10)
                    VStack(spacing: 0) {
                        if model.session.google != nil {
                            option("Gmail", detail: isConnecting ? "Waiting for Google" : "Sign in with Google", symbol: "envelope", action: connectGmail)
                        }
                        option("Your own domain", detail: "Set up or connect a server", symbol: "at") { isChoosingServer = true }
                    }
                    .overlay(alignment: .top) { Hairline() }
                    if let error {
                        Text(error).font(.phone(15)).foregroundStyle(Color.danger).fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Add more in Settings.").font(.phone(14)).foregroundStyle(Color.textFaint).padding(.top, 6)
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
        .animation(.snappy(duration: 0.3), value: isChoosingServer)
    }

    private func option(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(Color.selected, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.phone(17, .medium)).foregroundStyle(Color.textPrimary)
                    Text(detail).font(.phone(14)).foregroundStyle(Color.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.phone(13, .semibold, relativeTo: .footnote)).foregroundStyle(Color.textFaint)
            }
            .padding(.vertical, 14)
            .contentShape(.rect)
            .overlay(alignment: .bottom) { Hairline() }
        }
        .buttonStyle(.plain)
        .disabled(isConnecting)
    }

    private func connectGmail() {
        isConnecting = true
        error = nil
        Task {
            defer { isConnecting = false }
            do {
                try await model.connectGmail(using: webAuthenticationSession)
            } catch {
                Haptics.failure()
                self.error = error.localizedDescription
            }
        }
    }
}
