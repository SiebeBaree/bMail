import AuthenticationServices
import DesignSystem
import MailUI
import SwiftUI

/// What a first launch shows, and what's left after you remove every account. There's no bMail account: Gmail connects
/// straight to Google, and your own domains go through a server you host.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var isChoosingServer = false
    @State private var isConnecting = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LogoMark(size: 36)
                .padding(.bottom, 8)
            if isChoosingServer {
                Text("Your own domain").font(.geist(22, .semibold)).tracking(-0.4)
                Text("Your domains and tracking run on a server you host. Free on Vercel, about two minutes.")
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                ServerChoice()
                Button("Back") { isChoosingServer = false }
                    .buttonStyle(.plain)
                    .font(.geist(12))
                    .foregroundStyle(Color.link)
            } else {
                Text("Add your mail").font(.geist(22, .semibold)).tracking(-0.4)
                VStack(spacing: 0) {
                    if model.session.google != nil {
                        option("Gmail", detail: isConnecting ? "Waiting for Google" : "Sign in with Google", symbol: "envelope", action: connectGmail)
                    }
                    option("Your own domain", detail: "Set up or connect a server", symbol: "at") { isChoosingServer = true }
                }
                .overlay(alignment: .top) { Hairline() }
                if let error {
                    Text(error).foregroundStyle(Color.danger).fixedSize(horizontal: false, vertical: true)
                }
                Text("Add more in Settings.").font(.geist(12)).foregroundStyle(Color.textFaint)
            }
        }
        .frame(width: 340)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas)
    }

    private func option(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.rowIcon)
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Color.selected, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.uiMedium)
                    Text(detail).font(.geist(12)).foregroundStyle(Color.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.controlIcon).foregroundStyle(Color.textFaint)
            }
            .padding(.vertical, 12)
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
                self.error = error.localizedDescription
            }
        }
    }
}
