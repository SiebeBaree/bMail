import Foundation
import MailCore
import Observation

/// The first launch on this device: the intro once, then setup a step at a time. Your mail comes first (Gmail, your
/// own domain or both), then AI, agents on the Mac and the keys, which can each be skipped.
///
/// The steps that create something are done once it exists, so quitting halfway reopens where you were. Only two things
/// are stored: that the intro played and that setup is finished. Launch arguments override both, so
/// `--args -intro.played NO -onboarding.finished NO` plays it all again.
@MainActor
@Observable
public final class Onboarding {
    public enum Step: Hashable, Sendable { case mail, server, resend, domain, address, ai, agents, keys }

    /// What exists so far, which decides most of where you are.
    public struct Progress {
        public var accounts: [Account]
        public var domains: [Domain]
        public var hasServer: Bool
        /// Nil until the server says.
        public var hasResend: Bool?
        /// A first pass has landed, so the domains and addresses of a server you connected are in.
        public var hasSynced: Bool

        public init(accounts: [Account], domains: [Domain], hasServer: Bool, hasResend: Bool?, hasSynced: Bool) {
            self.accounts = accounts
            self.domains = domains
            self.hasServer = hasServer
            self.hasResend = hasResend
            self.hasSynced = hasSynced
        }

        var hasAddress: Bool { accounts.contains { $0.kind == .domain } }
    }

    public private(set) var isFinished: Bool
    /// On a first launch, until the intro has played or been skipped.
    public private(set) var showsIntro: Bool
    /// You picked your own domain, so its steps come after your mail.
    public private(set) var wantsDomain = false
    /// Steps you continued past or skipped.
    private var passed: Set<Step>
    private let offersAgents: Bool
    @ObservationIgnored private let defaults: UserDefaults

    private static let introKey = "intro.played"
    private static let finishedKey = "onboarding.finished"

    /// `isReturning` is whether this device synced before this version, so someone updating never sees any of it.
    /// `hasMail` skips Add your mail, for accounts that came through iCloud Keychain or a relaunch halfway through.
    public init(defaults: UserDefaults = .standard, isReturning: Bool, hasMail: Bool, offersAgents: Bool) {
        if isReturning, defaults.object(forKey: Self.introKey) == nil {
            defaults.set(true, forKey: Self.introKey)
            defaults.set(true, forKey: Self.finishedKey)
        }
        self.defaults = defaults
        self.offersAgents = offersAgents
        let isFinished = defaults.bool(forKey: Self.finishedKey)
        let showsIntro = !isFinished && !defaults.bool(forKey: Self.introKey)
        self.isFinished = isFinished
        self.showsIntro = showsIntro
        passed = hasMail ? [.mail] : []
        // Set as it starts, so quitting during the intro doesn't play it again.
        if showsIntro { defaults.set(true, forKey: Self.introKey) }
    }

    public func endIntro() {
        showsIntro = false
    }

    /// Every step on your path in order, for the progress bars.
    public func steps(_ progress: Progress) -> [Step] {
        let domain: [Step] = wantsDomain || progress.hasServer ? [.server, .resend, .domain, .address] : []
        return [.mail] + domain + [.ai] + (offersAgents ? [.agents] : []) + [.keys]
    }

    /// The first step that isn't done. Nil once they all are.
    public func current(_ progress: Progress) -> Step? {
        steps(progress).first { !isDone($0, progress) }
    }

    /// The step Back returns to: the one before, if you got past it by continuing rather than by creating something.
    public func previous(of step: Step, _ progress: Progress) -> Step? {
        let steps = steps(progress)
        guard let index = steps.firstIndex(of: step), index > 0, passed.contains(steps[index - 1]) else { return nil }
        return steps[index - 1]
    }

    private func isDone(_ step: Step, _ progress: Progress) -> Bool {
        switch step {
        case .mail: passed.contains(.mail)
        // Connected isn't enough: until the server answers and syncs, the steps after it can't tell what's there.
        case .server: progress.hasServer && progress.hasResend != nil && progress.hasSynced
        case .resend: progress.hasResend == true || !progress.domains.isEmpty
        case .domain: passed.contains(.domain) || progress.hasAddress
        case .address: progress.hasAddress
        case .ai, .agents, .keys: passed.contains(step)
        }
    }

    public func chooseDomain() {
        wantsDomain = true
        passed.insert(.mail)
    }

    /// Continue or Skip.
    public func pass(_ step: Step) {
        passed.insert(step)
    }

    public func back(to step: Step) {
        passed.remove(step)
        if step == .mail { wantsDomain = false }
    }

    public func finish() {
        isFinished = true
        defaults.set(true, forKey: Self.finishedKey)
    }

    /// After every account is removed, Add your mail comes back on its own, with the domain steps if you pick them but
    /// not the rest. It isn't stored: the next launch with nothing to read comes back here anyway.
    public func restart() {
        guard isFinished else { return }
        isFinished = false
        wantsDomain = false
        passed = [.ai, .agents, .keys]
    }
}
