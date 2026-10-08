import DesignSystem
import MailCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch model.phase {
            case .signedOut: SignInView()
            case .ready: MainView()
            }
            if model.isPaletteOpen { CommandPalette() }
            if model.isShortcutsOpen { ShortcutSheet() }
            ToastStack(model.toasts)
        }
        .containerBackground(Color.chrome, for: .window)
        .font(.ui)
        .foregroundStyle(Color.textPrimary)
        .tint(.accent)
        .onAppear { model.openSettings = { openSettings() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.syncNow() } }
        .onChange(of: model.syncStatus.notice) { _, notice in
            guard let notice else { return }
            model.toasts.show(Toast(notice))
            model.syncStatus.notice = nil
        }
    }
}

extension Toast {
    /// What the sync engine reports, as the toast you see.
    init(_ notice: SyncStatus.Notice) {
        switch notice {
        case let .sent(subject):
            self.init("Sent", detail: subject.isEmpty ? nil : subject, symbol: "paperplane", tone: .success)
        case let .sendFailed(subject, reason):
            self.init("Couldn't send \(subject.isEmpty ? "your message" : "“\(subject)”").", detail: reason, symbol: "exclamationmark.triangle", tone: .failure, duration: .seconds(10))
        case let .rejected(reason):
            self.init(reason, symbol: "exclamationmark.triangle", tone: .failure)
        case .signedOut:
            self.init("Sign in again to keep syncing.", symbol: "person.crop.circle.badge.exclamationmark", tone: .failure, duration: .seconds(10))
        }
    }
}
