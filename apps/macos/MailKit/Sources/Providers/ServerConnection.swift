import APIClient
import Foundation
import HTTPTypes
import MailCore
import OpenAPIRuntime
import OpenAPIURLSession

/// The api for your own domains: where it lives, the session token and a configured generated client. Sign-in calls go
/// to Better Auth, which isn't part of the generated client, so they're written out here.
public final class ServerConnection: Sendable {
    public static let sessionKey = "server.session"

    public let baseURL: URL
    let client: Client
    /// Never stores or sends cookies. Better Auth answers sign-in with a session cookie as well as the bearer token, and a
    /// request that carries a cookie without an Origin header fails its CSRF check, so a remembered cookie would break
    /// every sign-in after the first.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        return URLSession(configuration: configuration)
    }()

    /// The server address someone typed, as a base url. A bare host means https. Nil when it isn't an address.
    public static func baseURL(from text: String) -> URL? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme), url.host()?.isEmpty == false else { return nil }
        return url
    }

    public convenience init(baseURL: URL) {
        self.init(baseURL: baseURL, transport: URLSessionTransport(configuration: .init(session: Self.session)))
    }

    /// Tests pass a transport that answers like the api does, to check the generated client against real responses.
    init(baseURL: URL, transport: any ClientTransport) {
        self.baseURL = baseURL
        self.client = Client(
            serverURL: baseURL,
            configuration: Configuration(dateTranscoder: .iso8601WithFractionalSeconds),
            transport: transport,
            middlewares: [BearerMiddleware()]
        )
    }

    public var isSignedIn: Bool { Keychain.read(Self.sessionKey) != nil }

    /// Throws unless a bMail api answers at `baseURL`, so a mistyped address fails before anyone tries to sign in.
    public func checkServer() async throws {
        guard case .ok? = try? await client.health() else {
            throw ProviderError(.unavailable, "No bMail server answers at \(baseURL.host() ?? baseURL.absoluteString).")
        }
    }

    public func signOut() async {
        _ = try? await authRequest("sign-out", body: [String: String]())
        Keychain.delete(Self.sessionKey)
    }

    public func signIn(email: String, password: String) async throws {
        try await authenticate("sign-in/email", body: ["email": email, "password": password])
    }

    /// Hands the ID token Sign in with Apple gave the app to Better Auth, which verifies it and opens a session.
    public func signInWithApple(idToken: String, nonce: String) async throws {
        struct Body: Encodable {
            struct IDToken: Encodable {
                var token: String
                var nonce: String
            }
            var provider: String
            var idToken: IDToken
        }
        try await authenticate("sign-in/social", body: Body(provider: "apple", idToken: .init(token: idToken, nonce: nonce)))
    }

    private func authenticate(_ path: String, body: some Encodable) async throws {
        let (data, response) = try await authRequest(path, body: body)
        guard (200..<300).contains(response.statusCode), let token = response.value(forHTTPHeaderField: "set-auth-token") else {
            let message = (try? JSONDecoder().decode(AuthError.self, from: data))?.message
            throw ProviderError(.rejected, message ?? "Couldn't sign in. Check your details and try again.")
        }
        Keychain.write(token, for: Self.sessionKey)
    }

    private func authRequest(_ path: String, body: some Encodable) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: baseURL.appending(path: "api/auth/\(path)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if let token = Keychain.read(Self.sessionKey) { request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization") }
        request.httpBody = try JSONEncoder().encode(body)
        do {
            let (data, response) = try await Self.session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            return (data, response)
        } catch let error as URLError {
            throw ProviderError(.unavailable, "Can't reach \(baseURL.host() ?? "the server"). \(error.localizedDescription)")
        }
    }

    private struct AuthError: Decodable {
        var message: String?
    }
}

/// Adds the session to every generated call.
private struct BearerMiddleware: ClientMiddleware {
    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        if let token = Keychain.read(ServerConnection.sessionKey) {
            request.headerFields[.authorization] = "Bearer \(token)"
        }
        return try await next(request, body, baseURL)
    }
}
