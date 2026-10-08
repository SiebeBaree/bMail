import Foundation
import MailCore

/// The part of the Gmail REST api this app uses, typed by hand: a handful of endpoints doesn't need Google's SDK.
struct GmailAPI: Sendable {
    let tokens: TokenStore
    private let base = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/")!

    func get<Response: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> Response {
        try await send(path, method: "GET", query: query, body: Optional<Empty>.none)
    }

    func post<Response: Decodable>(_ path: String, body: some Encodable) async throws -> Response {
        try await send(path, method: "POST", query: [:], body: body)
    }

    struct Empty: Codable {}

    private func send<Response: Decodable>(_ path: String, method: String, query: [String: String], body: (some Encodable)?) async throws -> Response {
        var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(try await tokens.accessToken())", forHTTPHeaderField: "authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ProviderError(.unavailable, "Can't reach Gmail.")
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300: return try JSONDecoder().decode(Response.self, from: data)
        case 401: throw ProviderError(.unauthorized, "Gmail needs you to sign in again.")
        case 404: throw GmailNotFound()
        case 400, 403: throw ProviderError(.rejected, "Gmail refused that: \(String(decoding: data, as: UTF8.self).prefix(200))")
        default: throw ProviderError(.unavailable, "Gmail is having trouble. Trying again shortly.")
        }
    }
}

/// A thread that was deleted, or a history id too old to sync from.
struct GmailNotFound: Error {}

enum Gmail {
    struct Profile: Decodable {
        var emailAddress: String
        var historyId: String
    }

    struct ThreadList: Decodable {
        struct Item: Decodable { var id: String }
        var threads: [Item]?
        var nextPageToken: String?
    }

    struct Thread: Decodable {
        var id: String
        var historyId: String?
        var messages: [Message]?
    }

    struct Message: Decodable {
        var id: String
        var threadId: String
        var labelIds: [String]?
        var snippet: String?
        var internalDate: String?
        var payload: Part?
    }

    struct Part: Decodable {
        struct Header: Decodable {
            var name: String
            var value: String
        }

        struct Body: Decodable {
            var attachmentId: String?
            var size: Int?
            var data: String?
        }

        var partId: String?
        var mimeType: String?
        var filename: String?
        var headers: [Header]?
        var body: Body?
        var parts: [Part]?
    }

    struct HistoryList: Decodable {
        struct Entry: Decodable {
            struct Change: Decodable { var message: MessageRef }
            struct MessageRef: Decodable { var threadId: String }
            var messagesAdded: [Change]?
            var messagesDeleted: [Change]?
            var labelsAdded: [Change]?
            var labelsRemoved: [Change]?
        }

        var history: [Entry]?
        var historyId: String
        var nextPageToken: String?
    }

    struct Sent: Decodable {
        var id: String
        var threadId: String
    }

    struct AttachmentBody: Decodable {
        var data: String
    }
}
