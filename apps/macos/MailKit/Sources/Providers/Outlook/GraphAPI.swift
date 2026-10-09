import Foundation
import MailCore

/// The part of Microsoft Graph this app uses. Every request asks for immutable ids, so a message keeps its id when it
/// moves between folders, and for html bodies.
struct GraphAPI: Sendable {
    let tokens: TokenStore
    private let base = URL(string: "https://graph.microsoft.com/v1.0/me/")!

    func get<Response: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> Response {
        try await decode(try await send(url(path, query), method: "GET", body: nil))
    }

    func get<Response: Decodable>(absolute url: URL) async throws -> Response {
        try await decode(try await send(url, method: "GET", body: nil))
    }

    func post<Response: Decodable>(_ path: String, body: some Encodable) async throws -> Response {
        try await decode(try await send(url(path, [:]), method: "POST", body: try JSONEncoder().encode(body)))
    }

    func patch(_ path: String, body: some Encodable) async throws {
        _ = try await send(url(path, [:]), method: "PATCH", body: try JSONEncoder().encode(body))
    }

    func post(_ path: String) async throws {
        _ = try await send(url(path, [:]), method: "POST", body: nil)
    }

    private func url(_ path: String, _ query: [String: String]) -> URL {
        var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        return components.url!
    }

    private func decode<Response: Decodable>(_ data: Data) async throws -> Response {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Response.self, from: data)
    }

    private func send(_ url: URL, method: String, body: Data?) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(try await tokens.accessToken())", forHTTPHeaderField: "authorization")
        request.setValue(#"IdType="ImmutableId", outlook.body-content-type="html""#, forHTTPHeaderField: "prefer")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = body
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ProviderError(.unavailable, "Can't reach Outlook.")
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300: return data.isEmpty ? Data("{}".utf8) : data
        case 401: throw ProviderError(.unauthorized, "Outlook needs you to sign in again.")
        case 400, 403, 404: throw ProviderError(.rejected, "Outlook refused that: \(String(decoding: data, as: UTF8.self).prefix(200))")
        default: throw ProviderError(.unavailable, "Outlook is having trouble. Trying again shortly.")
        }
    }
}

enum Graph {
    struct Page<Item: Decodable>: Decodable {
        var value: [Item]
        var nextLink: URL?

        enum CodingKeys: String, CodingKey {
            case value
            case nextLink = "@odata.nextLink"
        }
    }

    struct Folder: Decodable {
        var id: String
    }

    struct Recipient: Codable {
        struct Email: Codable {
            var name: String?
            var address: String
        }

        var emailAddress: Email
    }

    struct Body: Codable {
        var contentType: String
        var content: String
    }

    struct Message: Decodable {
        struct Flag: Decodable { var flagStatus: String? }

        var id: String
        var conversationId: String?
        var subject: String?
        var bodyPreview: String?
        var body: Body?
        var from: Recipient?
        var toRecipients: [Recipient]?
        var ccRecipients: [Recipient]?
        var bccRecipients: [Recipient]?
        var replyTo: [Recipient]?
        var receivedDateTime: Date?
        var sentDateTime: Date?
        var lastModifiedDateTime: Date?
        var isRead: Bool?
        var isDraft: Bool?
        var flag: Flag?
        var parentFolderId: String?
        var internetMessageId: String?
        var internetMessageHeaders: [Header]?
    }

    struct Header: Decodable {
        var name: String
        var value: String
    }

    struct Attachment: Decodable {
        var id: String
        var name: String?
        var contentType: String?
        var size: Int?
        var isInline: Bool?
        var contentId: String?
        var contentBytes: String?
    }

    static let messageFields = [
        "id", "conversationId", "subject", "bodyPreview", "body", "from", "toRecipients", "ccRecipients", "bccRecipients",
        "replyTo", "receivedDateTime", "sentDateTime", "lastModifiedDateTime", "isRead", "isDraft", "flag",
        "parentFolderId", "internetMessageId", "internetMessageHeaders",
    ].joined(separator: ",")
}
