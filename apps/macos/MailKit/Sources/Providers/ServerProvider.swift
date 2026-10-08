import APIClient
import Foundation
import MailCore
import OpenAPIRuntime

/// Your own domains, through the api. One provider serves every mailbox on every domain.
public struct ServerProvider: MailProvider {
    public let source = "server"
    private let connection: ServerConnection

    public init(connection: ServerConnection) {
        self.connection = connection
    }

    public func owns(_ account: Account) -> Bool {
        account.kind == .domain
    }

    public func pull(after cursor: String?) async throws -> ChangeSet {
        let response = try await call { try await connection.client.sync(query: .init(cursor: cursor.flatMap(Int.init), limit: 200)) }
        guard case let .ok(ok) = response else { throw unexpected(response) }
        let wire = try ok.body.json

        var changes = ChangeSet()
        changes.domains = wire.domains.filter { $0.deletedAt == nil }.map(Domain.init)
        changes.removedDomainIDs = wire.domains.filter { $0.deletedAt != nil }.map { UUID(wire: $0.id) }
        changes.accounts = wire.mailboxes.filter { $0.deletedAt == nil }.enumerated().map { Account($1, position: $0) }
        changes.removedAccountIDs = wire.mailboxes.filter { $0.deletedAt != nil }.map { UUID(wire: $0.id) }
        changes.conversations = wire.conversations.map(Conversation.init)
        changes.messages = wire.messages.map(Message.init)
        changes.events = wire.events.map(MessageEvent.init)
        changes.cursor = String(wire.cursor)
        changes.hasMore = wire.hasMore
        return changes
    }

    public func push(_ mutation: Mutation) async throws {
        var body = Wire.UpdateConversationInput()
        switch mutation {
        case let .setRead(_, isRead): body.isRead = isRead
        case let .setStarred(_, isStarred): body.isStarred = isStarred
        case let .move(_, _, to): body.folder = .init(rawValue: to.rawValue)
        }
        let response = try await call {
            try await connection.client.updateConversation(path: .init(id: mutation.conversationID.uuidString.lowercased()), body: .json(body))
        }
        switch response {
        case .ok: return
        case .notFound: throw ProviderError(.rejected, "That conversation doesn't exist on the server anymore.")
        default: throw unexpected(response)
        }
    }

    public func send(_ message: OutgoingMessage) async throws -> ChangeSet {
        var attachmentIDs: [String] = []
        for file in message.attachments {
            attachmentIDs.append(try await upload(file))
        }
        let body = Wire.SendMessageInput(
            id: message.id.uuidString.lowercased(),
            conversationId: message.conversationID.uuidString.lowercased(),
            mailboxId: message.accountID.uuidString.lowercased(),
            to: message.to.map(Wire.RecipientInput.init),
            cc: message.cc.map(Wire.RecipientInput.init),
            bcc: message.bcc.map(Wire.RecipientInput.init),
            subject: message.subject,
            html: message.html,
            text: message.text,
            trackingEnabled: message.trackingEnabled,
            attachmentIds: attachmentIDs
        )
        let response = try await call { try await connection.client.sendMessage(body: .json(body)) }
        switch response {
        case let .ok(ok):
            let sent = try ok.body.json
            var changes = ChangeSet()
            changes.conversations = [Conversation(sent.conversation)]
            changes.messages = [Message(sent.message)]
            return changes
        case let .badRequest(error): throw ProviderError(.rejected, try error.body.json.message)
        case let .notFound(error): throw ProviderError(.rejected, try error.body.json.message)
        case let .conflict(error): throw ProviderError(.rejected, try error.body.json.message)
        case let .badGateway(error): throw ProviderError(.unavailable, try error.body.json.message)
        default: throw unexpected(response)
        }
    }

    /// Reserves the attachment on the server, then PUTs the bytes straight to storage.
    private func upload(_ file: OutgoingAttachment) async throws -> String {
        let response = try await call {
            try await connection.client.createUpload(body: .json(.init(filename: file.filename, contentType: file.contentType, size: file.size)))
        }
        guard case let .created(created) = response else { throw unexpected(response) }
        let upload = try created.body.json
        guard let url = URL(string: upload.uploadUrl) else { throw ProviderError(.unavailable, "The server sent a broken upload link.") }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(file.contentType, forHTTPHeaderField: "content-type")
        let (_, uploadResponse) = try await ServerConnection.session.upload(for: request, fromFile: file.fileURL)
        guard (uploadResponse as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true else {
            throw ProviderError(.unavailable, "Couldn't upload \(file.filename). Trying again shortly.")
        }
        return upload.id
    }

    /// Where to download an attachment from. Links expire after 15 minutes, so ask right before downloading.
    public func downloadURL(for attachment: Attachment.ID) async throws -> URL {
        let response = try await call { try await connection.client.getAttachmentUrl(path: .init(id: attachment.uuidString.lowercased())) }
        guard case let .ok(ok) = response, let url = URL(string: try ok.body.json.url) else { throw unexpected(response) }
        return url
    }

    /// Turns transport failures and 401s into provider errors the engine knows how to handle.
    private func call<Output>(_ operation: () async throws -> Output) async throws -> Output {
        do {
            let output = try await operation()
            if let status = undocumentedStatus(output), status == 401 {
                throw ProviderError(.unauthorized, "Sign in again to keep your domains in sync.")
            }
            return output
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError(.unavailable, "Can't reach \(connection.baseURL.host() ?? "the server").")
        }
    }

    private func unexpected(_ output: some Any) -> ProviderError {
        if let status = undocumentedStatus(output), status == 401 {
            return ProviderError(.unauthorized, "Sign in again to keep your domains in sync.")
        }
        return ProviderError(.unavailable, "The server answered in a way this version doesn't understand.")
    }

    /// Every generated Output has an `undocumented(statusCode:_:)` case; this reads it without a switch per operation.
    private func undocumentedStatus(_ output: some Any) -> Int? {
        guard let child = Mirror(reflecting: output).children.first, child.label == "undocumented" else { return nil }
        return Mirror(reflecting: child.value).children.first?.value as? Int
    }
}
