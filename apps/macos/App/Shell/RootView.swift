import DesignSystem
import MailCore
import MailUI
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if model.onboarding.isFinished { MainView() } else { OnboardingView() }
            if let url = model.connectingServer { ConnectServerSheet(url: url) }
            if model.isPaletteOpen { CommandPalette() }
            if model.isShortcutsOpen { ShortcutSheet() }
            if model.isLabelPickerOpen { LabelPicker() }
            ToastStack(model.session.toasts)
        }
        .containerBackground(Color.chrome, for: .window)
        .font(.ui)
        .foregroundStyle(Color.textPrimary)
        .tint(.accent)
        .onAppear { model.openSettings = { openSettings() } }
        .onOpenURL { model.handle($0) }
        .onChange(of: model.session.phase, initial: true) { _, phase in if phase == .welcome { model.onboarding.restart() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.session.syncNow() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeOcclusionStateNotification)) { _ in
            model.session.setVisible(NSApp.occlusionState.contains(.visible))
        }
        .onChange(of: model.session.syncStatus.notice) { _, notice in
            guard let notice else { return }
            model.session.toasts.show(Toast(notice))
            model.session.syncStatus.notice = nil
        }
    }
}
