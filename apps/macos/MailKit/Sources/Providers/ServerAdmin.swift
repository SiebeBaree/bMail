import APIClient
import Foundation
import MailCore

/// Domain and mailbox management. Each call returns the changed rows as a ChangeSet so settings can merge them into the
/// store right away instead of waiting for the next sync.
public struct ServerAdmin: Sendable {
    private let connection: ServerConnection

    public init(connection: ServerConnection) {
        self.connection = connection
    }

    public func addDomain(_ name: String) async throws -> ChangeSet {
        switch try await connection.client.createDomain(body: .json(.init(name: name))) {
        case let .created(created): return ChangeSet(domain: Domain(try created.body.json))
        case let .badRequest(error): throw ProviderError(.rejected, try error.body.json.issues?.first?.message ?? error.body.json.message)
        case let .conflict(error): throw ProviderError(.rejected, try error.body.json.message)
        case let .badGateway(error): throw ProviderError(.unavailable, try error.body.json.message)
        case .undocumented: throw ProviderError(.unavailable, "Couldn't add \(name). Try again in a moment.")
        }
    }

    /// Asks Resend to check DNS again and returns what it found.
    public func verifyDomain(_ id: Domain.ID) async throws -> ChangeSet {
        switch try await connection.client.verifyDomain(path: .init(id: id.wire)) {
        case let .ok(ok): return ChangeSet(domain: Domain(try ok.body.json))
        case let .notFound(error): throw ProviderError(.rejected, try error.body.json.message)
        case let .badGateway(error): throw ProviderError(.unavailable, try error.body.json.message)
        case .undocumented: throw ProviderError(.unavailable, "Couldn't check DNS. Try again in a moment.")
        }
    }

    public func setCatchAll(_ mailboxID: Account.ID?, for domainID: Domain.ID) async throws -> ChangeSet {
        let domain: Wire.Domain
        if let mailboxID {
            let response = try await connection.client.updateDomain(path: .init(id: domainID.wire), body: .json(.init(catchAllMailboxId: mailboxID.wire)))
            guard case let .ok(ok) = response else { throw ProviderError(.unavailable, "Couldn't change the catch-all.") }
            domain = try ok.body.json
        } else {
            let response = try await connection.client.clearCatchAll(path: .init(id: domainID.wire))
            guard case let .ok(ok) = response else { throw ProviderError(.unavailable, "Couldn't turn the catch-all off.") }
            domain = try ok.body.json
        }
        return ChangeSet(domain: Domain(domain))
    }

    public func removeDomain(_ id: Domain.ID) async throws -> ChangeSet {
        switch try await connection.client.deleteDomain(path: .init(id: id.wire)) {
        case .noContent:
            var changes = ChangeSet()
            changes.removedDomainIDs = [id]
            return changes
        case let .notFound(error): throw ProviderError(.rejected, try error.body.json.message)
        case let .badGateway(error): throw ProviderError(.unavailable, try error.body.json.message)
        case .undocumented: throw ProviderError(.unavailable, "Couldn't remove the domain.")
        }
    }

    public func addMailbox(localPart: String, displayName: String, on domainID: Domain.ID) async throws -> ChangeSet {
        let body = Wire.CreateMailboxInput(id: UUID().wire, domainId: domainID.wire, localPart: localPart, displayName: displayName)
        switch try await connection.client.createMailbox(body: .json(body)) {
        case let .created(created):
            var changes = ChangeSet()
            changes.accounts = [Account(try created.body.json, position: Int.max / 2)]
            return changes
        case let .badRequest(error): throw ProviderError(.rejected, try error.body.json.issues?.first?.message ?? error.body.json.message)
        case let .notFound(error): throw ProviderError(.rejected, try error.body.json.message)
        case let .conflict(error): throw ProviderError(.rejected, try error.body.json.message)
        case .undocumented: throw ProviderError(.unavailable, "Couldn't create the mailbox.")
        }
    }

    public func removeMailbox(_ id: Account.ID) async throws -> ChangeSet {
        switch try await connection.client.deleteMailbox(path: .init(id: id.wire)) {
        case .noContent:
            var changes = ChangeSet()
            changes.removedAccountIDs = [id]
            return changes
        case let .notFound(error): throw ProviderError(.rejected, try error.body.json.message)
        case .undocumented: throw ProviderError(.unavailable, "Couldn't remove the mailbox.")
        }
    }
}

// MARK: - Resend

extension ServerAdmin {
    /// Whether the server has a Resend key, which it needs before your first domain.
    public func hasResend() async throws -> Bool {
        switch try await connection.client.serverStatus() {
        case let .ok(ok): return try ok.body.json.resend
        default: throw ProviderError(.unavailable, "Couldn't reach \(connection.host).")
        }
    }

    /// Gives the server your Resend key. It checks the key and sets up its own webhook with it.
    public func setResendKey(_ key: String) async throws {
        switch try await connection.client.setResendKey(body: .json(.init(apiKey: key))) {
        case .ok: return
        case let .badRequest(error): throw ProviderError(.rejected, try error.body.json.issues?.first?.message ?? error.body.json.message)
        case let .badGateway(error): throw ProviderError(.unavailable, try error.body.json.message)
        default: throw ProviderError(.unavailable, "Couldn't save the key. Try again in a moment.")
        }
    }
}

// MARK: - Labels

extension ServerAdmin {
    /// The id is the app's, so a retry after a lost response returns the same label instead of a duplicate.
    public func createLabel(_ label: MailLabel) async throws -> ChangeSet {
        switch try await connection.client.createLabel(body: .json(.init(id: label.id.wire, name: label.name))) {
        case let .created(created): return ChangeSet(label: MailLabel(try created.body.json))
        case let .badRequest(error): throw ProviderError(.rejected, try error.body.json.issues?.first?.message ?? error.body.json.message)
        case let .conflict(error): throw ProviderError(.rejected, try error.body.json.message)
        case .undocumented: throw ProviderError(.unavailable, "Couldn't create \(label.name).")
        }
    }

    public func renameLabel(_ id: MailLabel.ID, to name: String) async throws -> ChangeSet {
        switch try await connection.client.updateLabel(path: .init(id: id.wire), body: .json(.init(name: name))) {
        case let .ok(ok): return ChangeSet(label: MailLabel(try ok.body.json))
        case let .badRequest(error): throw ProviderError(.rejected, try error.body.json.issues?.first?.message ?? error.body.json.message)
        case let .notFound(error): throw ProviderError(.rejected, try error.body.json.message)
        case let .conflict(error): throw ProviderError(.rejected, try error.body.json.message)
        case .undocumented: throw ProviderError(.unavailable, "Couldn't rename the label.")
        }
    }

    /// Takes the label off every conversation too.
    public func deleteLabel(_ id: MailLabel.ID) async throws -> ChangeSet {
        switch try await connection.client.deleteLabel(path: .init(id: id.wire)) {
        case .noContent:
            var changes = ChangeSet()
            changes.removedLabelIDs = [id]
            return changes
        case let .notFound(error): throw ProviderError(.rejected, try error.body.json.message)
        case .undocumented: throw ProviderError(.unavailable, "Couldn't delete the label.")
        }
    }
}

extension ChangeSet {
    init(label: MailLabel) {
        self.init()
        labels = [label]
    }

    init(domain: Domain) {
        self.init()
        domains = [domain]
    }
}

extension UUID {
    /// How the api writes ids: lowercase.
    var wire: String { uuidString.lowercased() }
}
