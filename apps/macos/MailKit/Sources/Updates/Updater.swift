import AppKit
import DesignSystem
import Foundation
import Observation
import OSLog
import Sparkle

private let log = Logger(subsystem: "be.baree.mail", category: "Updates")

/// Sparkle behind bMail's own UI. Sparkle checks GitHub's latest release every hour (Info.plist), downloads a newer one
/// in the background and hands over its install, which `restart()` runs. That install path never shows a Sparkle
/// window, not even the progress window it puts up while the app is closed. Ignore the prompt and the update installs
/// when bMail quits.
@MainActor
@Observable
public final class Updater: NSObject {
    /// The version waiting for a restart.
    public private(set) var readyVersion: String?
    @ObservationIgnored private var install: (() -> Void)?
    /// What the user driver was shown, since its ready call doesn't say which version.
    @ObservationIgnored private var foundVersion: String?
    /// Check for Updates answers with toasts. Checks Sparkle starts on its own stay quiet until there's something to
    /// install.
    @ObservationIgnored private var isAsked = false
    @ObservationIgnored private var checkingToast: Toast.ID?
    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private let toasts: ToastCenter

    public init(toasts: ToastCenter) {
        self.toasts = toasts
    }

    /// Debug builds don't update: Sparkle would swap the build you're running for the release. They share defaults
    /// with the release, so they don't announce versions either.
    public func start() {
        #if !DEBUG
            announceUpdate()
            let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
            do {
                try updater.start()
                self.updater = updater
            } catch {
                log.error("Sparkle didn't start: \(error.localizedDescription, privacy: .public)")
            }
        #endif
    }

    /// Check for Updates in the bMail menu. It runs the same background check Sparkle schedules, so an update it finds
    /// installs the same quiet way. A check that's already running answers instead.
    public func check() {
        if let readyVersion { return toasts.show(readyToast(readyVersion)) }
        guard !isAsked, let updater else { return }
        isAsked = true
        let toast = Toast("Checking for updates", symbol: "arrow.clockwise", duration: .seconds(30))
        checkingToast = toast.id
        toasts.show(toast)
        if updater.canCheckForUpdates { updater.checkForUpdatesInBackground() }
    }

    /// Quits bMail, installs the update and opens the new version.
    public func restart() {
        install?()
    }

    private func ready(_ version: String, install: @escaping () -> Void) {
        readyVersion = version
        self.install = install
        answer(readyToast(version))
    }

    /// Only when you asked. Otherwise the dot on your avatar is all that says so.
    private func readyToast(_ version: String) -> Toast {
        Toast(
            "bMail \(version) is ready.", detail: "Restart to update.", symbol: "arrow.down.circle",
            action: .init("Restart") { [weak self] in self?.restart() }, duration: .seconds(10)
        )
    }

    /// Replaces the Checking toast with the answer to Check for Updates, if it was asked.
    private func answer(_ toast: Toast) {
        guard isAsked else { return }
        isAsked = false
        if let checkingToast { toasts.dismiss(checkingToast) }
        checkingToast = nil
        toasts.show(toast)
    }

    /// Once after an update, whether it came from Restart or from quitting. Compares with the version that ran last.
    private func announceUpdate() {
        let defaults = UserDefaults.standard
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard let version else { return }
        defer { defaults.set(version, forKey: "lastLaunchedVersion") }
        guard let last = defaults.string(forKey: "lastLaunchedVersion"), last != version else { return }
        let notes = URL(string: "https://github.com/SiebeBaree/bMail/releases/tag/v\(version)")!
        toasts.show(Toast(
            "Updated to bMail \(version)", tone: .success,
            action: .init("What's new") { NSWorkspace.shared.open(notes) }, duration: .seconds(10)
        ))
    }
}

extension Updater: SPUUpdaterDelegate {
    /// The quiet path: downloaded and prepared in the background. Returning true keeps the install for `restart()`.
    public func updater(
        _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock: @escaping () -> Void
    ) -> Bool {
        ready(item.displayVersionString, install: immediateInstallationBlock)
        return true
    }

    public func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        guard isAsked, let checkingToast else { return }
        toasts.update(checkingToast, title: "Downloading bMail \(item.displayVersionString)")
    }

    public func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        answer(Toast("You're on the latest version"))
    }

    public func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        guard (error as NSError).code != SUError.noUpdateError.rawValue else { return }
        log.error("Update failed: \(error.localizedDescription, privacy: .public)")
        answer(Toast(
            "Couldn't update.", detail: error.localizedDescription, symbol: "exclamationmark.circle", tone: .failure
        ))
    }
}

/// Sparkle's UI, which bMail answers without windows. It only runs when the quiet path can't: an update that was
/// already downloaded or installing at launch.
extension Updater: SPUUserDriver {
    public func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    public func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}

    public func showUpdateFound(
        with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        if appcastItem.isInformationOnlyUpdate {
            reply(.dismiss)
        } else if state.stage == .installing {
            // Install now would quit right away, so that waits for Restart.
            ready(appcastItem.displayVersionString) { reply(.install) }
        } else {
            foundVersion = appcastItem.displayVersionString
            reply(.install)
        }
    }

    public func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    public func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    public func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    public func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    public func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    public func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    public func showDownloadDidReceiveData(ofLength length: UInt64) {}
    public func showDownloadDidStartExtractingUpdate() {}
    public func showExtractionReceivedProgress(_ progress: Double) {}

    public func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        ready(foundVersion ?? "") { reply(.install) }
    }

    public func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void
    ) {}

    public func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    public func dismissUpdateInstallation() {
        readyVersion = nil
        install = nil
        foundVersion = nil
    }
}
