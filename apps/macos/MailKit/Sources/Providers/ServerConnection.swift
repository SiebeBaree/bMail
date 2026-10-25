import APIClient
import Foundation
import HTTPTypes
import MailCore
import OpenAPIRuntime
import OpenAPIURLSession

/// Your server's address and the token that proves this app owns it. Kept as one synced Keychain item, so connecting
/// on the Mac connects your iPhone too.
public struct ServerLink: Codable, Equatable, Sendable {
    public var url: URL
    public var token: String

    static let key = "server"

    public init(url: URL, token: String) {
        self.url = url
        self.token = token
    }

    /// The saved link. Builds from before items synced kept the address in defaults and a sign-in session in the
    /// Keychain; the server turned those sessions into owner tokens, so that pair moves over as it is.
    public static func load() -> ServerLink? {
        if let stored = Keychain.read(key).flatMap({ try? JSONDecoder().decode(ServerLink.self, from: Data($0.utf8)) }) {
            return stored
        }
        let defaults = UserDefaults.standard
        guard let url = defaults.string(forKey: "serverURL").flatMap(URL.init(string:)), let token = Keychain.read("server.session") else {
            return nil
        }
        let link = ServerLink(url: url, token: token)
        link.save()
        Keychain.delete("server.session")
        defaults.removeObject(forKey: "serverURL")
        defaults.removeObject(forKey: "cacheServerURL")
        return link
    }

    public func save() {
        Keychain.write(String(decoding: (try? JSONEncoder().encode(self)) ?? Data(), as: UTF8.self), for: Self.key, synced: true)
    }

    public static func forget() {
        Keychain.delete(key)
    }
}

/// The api for your own domains and tracking: where it lives, the owner token and a configured generated client.
public final class ServerConnection: Sendable {
    /// Whether anyone owns the server yet. The first app to connect to a fresh one becomes its owner.
    public enum Ownership: Sendable { case fresh, owned }

    public let baseURL: URL
    let client: Client
    /// Never stores or sends cookies: the api only ever reads the bearer token.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        return URLSession(configuration: configuration)
    }()

    /// The server address someone typed or a link carried, as a base url. A bare host means https. Nil when it isn't an
    /// address.
    public static func baseURL(from text: String) -> URL? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme), url.host()?.isEmpty == false else { return nil }
        return url
    }

    public convenience init(_ link: ServerLink) {
        self.init(baseURL: link.url, token: link.token)
    }

    /// Without a token only `ownership` and `claim` work.
    public convenience init(baseURL: URL, token: String? = nil) {
        self.init(baseURL: baseURL, token: token, transport: URLSessionTransport(configuration: .init(session: Self.session)))
    }

    /// Tests pass a transport that answers like the api does, to check the generated client against real responses.
    init(baseURL: URL, token: String?, transport: any ClientTransport) {
        self.baseURL = baseURL
        self.client = Client(
            serverURL: baseURL,
            configuration: Configuration(dateTranscoder: .iso8601WithFractionalSeconds),
            transport: transport,
            middlewares: token.map { [BearerMiddleware(token: $0)] } ?? []
        )
    }

    public var host: String { baseURL.host() ?? baseURL.absoluteString }

    /// Whether a bMail api answers at `baseURL` and whether it has an owner, so a mistyped address fails before anything
    /// else happens.
    public func ownership() async throws -> Ownership {
        guard case let .ok(ok)? = try? await client.health(), let health = try? ok.body.json else {
            throw ProviderError(.unavailable, "No bMail server answers at \(host).")
        }
        return health.claimed ? .owned : .fresh
    }

    /// Makes this app the server's owner. A server that has one already takes its `CLAIM_CODE` instead, which replaces
    /// every other owner token.
    public func claim(code: String? = nil) async throws -> ServerLink {
        let response: Operations.Claim.Output
        do {
            response = try await client.claim(body: .json(.init(code: code)))
        } catch {
            throw ProviderError(.unavailable, "Can't reach \(host).")
        }
        switch response {
        case let .ok(ok): return ServerLink(url: baseURL, token: try ok.body.json.token)
        case let .conflict(error): throw ProviderError(.rejected, try error.body.json.message)
        default: throw ProviderError(.unavailable, "\(host) didn't answer the way a bMail server does.")
        }
    }
}

/// Adds the owner token to every generated call.
private struct BearerMiddleware: ClientMiddleware {
    let token: String

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        request.headerFields[.authorization] = "Bearer \(token)"
        return try await next(request, body, baseURL)
    }
}
