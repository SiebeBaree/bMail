import DesignSystem
import MailCore
import MailUI
import SwiftUI
import UIKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    /// The background time asked for when leaving with mail still waiting to go out.
    @State private var background: BackgroundSending?

    var body: some View {
        @Bindable var model = model
        ZStack {
            switch model.session.phase {
            case .welcome: WelcomeView().transition(.opacity)
            case .ready: InboxScreen().transition(.opacity)
            }
        }
        // Here rather than on the inbox, so connecting a server can ask from the welcome screen too.
        .sheet(item: $model.sheet, onDismiss: model.sheetDismissed) { sheet in
            switch sheet {
            case let .composer(composer): ComposerView(model: composer)
            case let .labels(ids): LabelPicker(conversations: ids)
            case .settings: SettingsView()
            case let .connectServer(url): ConnectServerSheet(url: url)
            }
        }
        .onOpenURL { model.handle($0) }
        .animation(.easeInOut(duration: 0.3), value: model.session.phase)
        .font(.phone(16))
        .foregroundStyle(Color.textPrimary)
        // Monochrome like the rest of Vercel's look: blue is kept for what's new, links and sending.
        .tint(Color.textPrimary)
        .background(ToastWindow(center: model.session.toasts))
        .onGeometryChange(for: Int.self) { Int($0.size.width) } action: { model.width = $0 }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                background?.end()
                background = nil
                model.session.setVisible(true)
                model.session.syncNow()
            case .background:
                model.session.setVisible(false)
                finishSending()
            default: break
            }
        }
        .onChange(of: model.session.syncStatus.notice) { _, notice in
            guard let notice else { return }
            if case .sendFailed = notice { Haptics.failure() }
            model.session.toasts.show(Toast(notice))
            model.session.syncStatus.notice = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            model.session.pages.removeAll()
        }
    }

    /// A message sent a moment before leaving is still in its undo window. iOS gives the app about half a minute in the
    /// background, enough to let it go out instead of waiting for the next time the app opens.
    private func finishSending() {
        background?.end()
        background = BackgroundSending(session: model.session)
    }
}

/// One stretch of background time, spent sending what's waiting. It ends once: when the work is done, when iOS runs out
/// of patience or when the app comes back, whichever is first. Each stretch only ever ends itself.
@MainActor
private final class BackgroundSending {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private var work: Task<Void, Never>?

    init(session: MailSession) {
        let work = Task { await session.finishPendingWork() }
        self.work = work
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Send mail") { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
        Task { [weak self] in
            await work.value
            self?.end()
        }
    }

    func end() {
        work?.cancel()
        work = nil
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
