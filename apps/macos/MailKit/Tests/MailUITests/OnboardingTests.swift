import Foundation
import MailCore
import Testing

@testable import MailUI

@MainActor
@Suite struct OnboardingTests {
    let gmail = Account(id: UUID(), kind: .gmail, address: "siebe@gmail.com", displayName: "Siebe", domainID: nil, position: 0)
    let domain = Domain(
        id: UUID(), name: "baree.be", status: .pending, records: [], receivingEnabled: true,
        catchAllMailboxID: nil, trackingHost: "t.baree.be", trackingHostVerified: false
    )

    private func fresh() -> UserDefaults {
        UserDefaults(suiteName: "onboarding.\(UUID())")!
    }

    private func progress(
        _ accounts: [Account] = [], domains: [Domain] = [], server: Bool = false, resend: Bool? = nil, synced: Bool = false
    ) -> Onboarding.Progress {
        Onboarding.Progress(accounts: accounts, domains: domains, hasServer: server, hasResend: resend, hasSynced: synced)
    }

    @Test func gmailGoesFromYourMailThroughTheOptionalSteps() {
        let onboarding = Onboarding(defaults: fresh(), isReturning: false, hasMail: false, offersAgents: true)
        #expect(onboarding.steps(progress()) == [.mail, .ai, .agents, .keys])
        #expect(onboarding.current(progress()) == .mail)
        onboarding.pass(.mail)
        #expect(onboarding.current(progress([gmail])) == .ai)
        onboarding.pass(.ai)
        onboarding.pass(.agents)
        onboarding.pass(.keys)
        #expect(onboarding.current(progress([gmail])) == nil)
    }

    @Test func yourOwnDomainFollowsWhatExistsOnTheServer() {
        let onboarding = Onboarding(defaults: fresh(), isReturning: false, hasMail: false, offersAgents: false)
        onboarding.chooseDomain()
        #expect(onboarding.current(progress()) == .server)
        // Claimed, but until it answers and syncs the next steps can't tell what's there.
        #expect(onboarding.current(progress(server: true, resend: false)) == .server)
        #expect(onboarding.current(progress(server: true, resend: false, synced: true)) == .resend)
        #expect(onboarding.current(progress(server: true, resend: true, synced: true)) == .domain)
        // The records stay up after adding the domain, until you continue.
        #expect(onboarding.current(progress(domains: [domain], server: true, resend: true, synced: true)) == .domain)
        onboarding.pass(.domain)
        #expect(onboarding.current(progress(domains: [domain], server: true, resend: true, synced: true)) == .address)
        let mailbox = Account(id: UUID(), kind: .domain, address: "siebe@baree.be", displayName: "Siebe", domainID: domain.id, position: 1)
        #expect(onboarding.current(progress([mailbox], domains: [domain], server: true, resend: true, synced: true)) == .ai)
    }

    @Test func aServerThatsAlreadySetUpSkipsStraightToAI() {
        let onboarding = Onboarding(defaults: fresh(), isReturning: false, hasMail: true, offersAgents: false)
        let mailbox = Account(id: UUID(), kind: .domain, address: "siebe@baree.be", displayName: "Siebe", domainID: domain.id, position: 1)
        #expect(onboarding.current(progress([mailbox], domains: [domain], server: true, resend: true, synced: true)) == .ai)
    }

    @Test func backOnlyUndoesAContinue() {
        let onboarding = Onboarding(defaults: fresh(), isReturning: false, hasMail: false, offersAgents: true)
        onboarding.chooseDomain()
        #expect(onboarding.previous(of: .server, progress()) == .mail)
        onboarding.back(to: .mail)
        #expect(onboarding.current(progress()) == .mail)
        #expect(onboarding.steps(progress()) == [.mail, .ai, .agents, .keys])
        // Nothing to go back to once the address exists: it was made, not continued past.
        let mailbox = Account(id: UUID(), kind: .domain, address: "siebe@baree.be", displayName: "Siebe", domainID: domain.id, position: 1)
        #expect(onboarding.previous(of: .ai, progress([mailbox], domains: [domain], server: true, resend: true, synced: true)) == nil)
    }

    @Test func theIntroPlaysOncePerDevice() {
        let defaults = fresh()
        #expect(Onboarding(defaults: defaults, isReturning: false, hasMail: false, offersAgents: true).showsIntro)
        // Quit during setup: no intro, but setup is still there.
        let relaunch = Onboarding(defaults: defaults, isReturning: false, hasMail: true, offersAgents: true)
        #expect(!relaunch.showsIntro)
        #expect(!relaunch.isFinished)
        #expect(relaunch.current(progress([gmail])) == .ai)
    }

    @Test func losingYourMailHalfwayBringsBackYourMail() {
        let onboarding = Onboarding(defaults: fresh(), isReturning: false, hasMail: true, offersAgents: true)
        #expect(onboarding.current(progress([gmail])) == .ai)
        #expect(onboarding.current(progress()) == .mail)
        // A server without an address yet still counts, so a relaunch picks up its steps.
        #expect(onboarding.current(progress(server: true, resend: true, synced: true)) == .domain)
    }

    @Test func someoneUpdatingNeverSeesAnyOfIt() {
        let onboarding = Onboarding(defaults: fresh(), isReturning: true, hasMail: true, offersAgents: true)
        #expect(!onboarding.showsIntro)
        #expect(onboarding.isFinished)
    }

    @Test func removingEveryAccountBringsBackOnlyYourMail() {
        let defaults = fresh()
        let onboarding = Onboarding(defaults: defaults, isReturning: false, hasMail: false, offersAgents: true)
        onboarding.finish()
        onboarding.restart()
        #expect(!onboarding.isFinished)
        #expect(onboarding.current(progress()) == .mail)
        onboarding.pass(.mail)
        #expect(onboarding.current(progress([gmail])) == nil)
        #expect(Onboarding(defaults: defaults, isReturning: true, hasMail: false, offersAgents: true).isFinished)
    }
}
