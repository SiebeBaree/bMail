import APIClient
import Foundation
import MailCore

/// Tracking for mail sent from Gmail. The api adds the open pixel and tracked links and keeps the record,
/// so opens and clicks arrive through its sync like those of mail sent from your own domains.
public struct ServerTracking: Sendable {
    private let connection: ServerConnection

    public init(connection: ServerConnection) {
        self.connection = connection
    }

    /// `html` as it should go out, tracked under `id`, which must be the id the provider's copy of the message will
    /// have locally. Asking again with the same id returns the same html.
    func instrument(_ html: String, id: Message.ID) async throws -> String {
        let response: Operations.TrackMessage.Output
        do {
            response = try await connection.client.trackMessage(body: .json(.init(id: id.wire, html: html)))
        } catch {
            throw ProviderError(.unavailable, "Can't reach \(connection.baseURL.host() ?? "the server") to track this message.")
        }
        switch response {
        case let .ok(ok): return try ok.body.json.html
        default: throw ProviderError(.unavailable, "Couldn't turn on tracking for this message. Trying again shortly.")
        }
    }
}
