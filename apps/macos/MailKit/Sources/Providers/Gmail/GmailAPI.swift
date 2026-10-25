import Foundation
import MailCore

/// The part of the Gmail REST api this app uses, typed by hand: a handful of endpoints doesn't need Google's SDK.
struct GmailAPI: Sendable {
    let tokens: TokenStore
    private let base = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/")!
    private let pacer = Pacer()

    func get<Response: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> Response {
        try await send(path, method: "GET", query: query, body: Optional<Empty>.none)
    }

    func post<Response: Decodable>(_ path: String, body: some Encodable) async throws -> Response {
        try await send(path, method: "POST", query: [:], body: body)
    }

    func patch<Response: Decodable>(_ path: String, body: some Encodable) async throws -> Response {
        try await send(path, method: "PATCH", query: [:], body: body)
    }

    func delete(_ path: String) async throws {
        let _: Empty = try await send(path, method: "DELETE", query: [:], body: Optional<Empty>.none)
    }

    struct Empty: Codable {}

    private func send<Response: Decodable>(_ path: String, method: String, query: [String: String], body: (some Encodable)?) async throws -> Response {
        var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        var attempt = 0
        while true {
            try await pacer.wait()
            request.setValue("Bearer \(try await tokens.accessToken())", forHTTPHeaderField: "authorization")
            let data: Data
            let response: HTTPURLResponse
            do {
                let (bytes, urlResponse) = try await URLSession.shared.data(for: request)
                guard let http = urlResponse as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                (data, response) = (bytes, http)
            } catch {
                throw ProviderError(.unavailable, "Can't reach Gmail.")
            }
            switch response.statusCode {
            case 200..<300:
                // A delete answers with no body at all.
                if data.isEmpty, let empty = Empty() as? Response { return empty }
                return try JSONDecoder().decode(Response.self, from: data)
            case 401: throw ProviderError(.unauthorized, "Gmail needs you to sign in again.")
            case 404: throw GmailNotFound()
            case 403 where !Self.isRateLimit(data), 400:
                throw ProviderError(.rejected, "Gmail refused that: \(Self.message(in: data))")
            case 403, 429, 500...:
                // Rate limits come back as 429 or as a 403 with a rate limit reason. Both clear on their own.
                guard attempt < 4 else { throw ProviderError(.unavailable, "Gmail asked us to slow down. Trying again shortly.") }
                let retryAfter = response.value(forHTTPHeaderField: "retry-after").flatMap(Double.init)
                try await Task.sleep(for: .seconds(retryAfter ?? pow(2, Double(attempt))))
                attempt += 1
            default:
                throw ProviderError(.unavailable, "Gmail is having trouble. Trying again shortly.")
            }
        }
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable {
            struct Reason: Decodable { var reason: String? }
            var message: String?
            var status: String?
            var errors: [Reason]?
        }

        var error: Detail
    }

    private static func isRateLimit(_ data: Data) -> Bool {
        guard let error = try? JSONDecoder().decode(ErrorBody.self, from: data).error else { return false }
        let reasons = (error.errors ?? []).compactMap(\.reason)
        return error.status == "RESOURCE_EXHAUSTED" || reasons.contains { $0 == "rateLimitExceeded" || $0 == "userRateLimitExceeded" }
    }

    private static func message(in data: Data) -> String {
        (try? JSONDecoder().decode(ErrorBody.self, from: data).error.message) ?? String(decoding: data.prefix(200), as: UTF8.self)
    }
}

/// Gmail meters each user at roughly 250 quota units a second and a thread fetch costs 10, so a first sync firing
/// requests as fast as it can trips the limit within a second. Spacing requests 50 ms apart stays under it.
private actor Pacer {
    private var next = ContinuousClock.now

    func wait() async throws {
        let slot = max(next, .now)
        next = slot + .milliseconds(50)
        try await Task.sleep(until: slot)
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

    struct LabelList: Decodable {
        var labels: [Label]?
    }

    struct Label: Decodable {
        var id: String
        var name: String
        /// `system` for INBOX, UNREAD and the rest Gmail made; `user` for yours.
        var type: String?
    }

    struct Sent: Decodable {
        var id: String
        var threadId: String
    }

    struct AttachmentBody: Decodable {
        var data: String
    }
}
