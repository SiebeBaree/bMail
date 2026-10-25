import CryptoKit
import Foundation
import MailCore

/// OAuth 2.0 for a public client: authorization code with PKCE, no client secret. Used for Gmail access.
public struct OAuthClient: Sendable {
    public struct Configuration: Sendable {
        var authorizeURL: URL
        var tokenURL: URL
        var clientID: String
        var redirectURI: String
        var scopes: [String]
        var extraParameters: [String: String] = [:]

        /// The scheme ASWebAuthenticationSession listens for.
        public var callbackScheme: String { String(redirectURI.prefix { $0 != ":" }) }
    }

    /// A sign-in that has started: the url to show, and what's needed to finish it.
    public struct Attempt: Sendable {
        public let url: URL
        public let callbackScheme: String
        let verifier: String
        let state: String
    }

    public let configuration: Configuration

    public init(_ configuration: Configuration) {
        self.configuration = configuration
    }

    public func start(loginHint: String? = nil) -> Attempt {
        let verifier = Self.randomString()
        let state = Self.randomString()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        var components = URLComponents(url: configuration.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: configuration.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        + configuration.extraParameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        + (loginHint.map { [URLQueryItem(name: "login_hint", value: $0)] } ?? [])
        return Attempt(url: components.url!, callbackScheme: configuration.callbackScheme, verifier: verifier, state: state)
    }

    /// Exchanges the redirect the browser came back with for tokens.
    public func finish(_ attempt: Attempt, callback: URL) async throws -> OAuthTokens {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value {
            throw ProviderError(.rejected, error == "access_denied" ? "Sign-in was cancelled." : "Sign-in failed: \(error).")
        }
        guard items.first(where: { $0.name == "state" })?.value == attempt.state,
            let code = items.first(where: { $0.name == "code" })?.value
        else { throw ProviderError(.rejected, "Sign-in came back incomplete. Try again.") }
        return try await token([
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": attempt.verifier,
            "redirect_uri": configuration.redirectURI,
        ], previous: nil)
    }

    public func refresh(_ tokens: OAuthTokens) async throws -> OAuthTokens {
        guard let refreshToken = tokens.refreshToken else {
            throw ProviderError(.unauthorized, "Sign in again to keep this account in sync.")
        }
        return try await token(["grant_type": "refresh_token", "refresh_token": refreshToken], previous: tokens)
    }

    private func token(_ parameters: [String: String], previous: OAuthTokens?) async throws -> OAuthTokens {
        var request = URLRequest(url: configuration.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        var form = URLComponents()
        form.queryItems = (parameters.merging(["client_id": configuration.clientID]) { $1 })
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            // invalid_grant means the refresh token was revoked or expired: only a new sign-in fixes that.
            let body = String(decoding: data, as: UTF8.self)
            throw ProviderError(body.contains("invalid_grant") ? .unauthorized : .unavailable, "Sign in again to keep this account in sync.")
        }
        let wire = try JSONDecoder().decode(TokenResponse.self, from: data)
        return OAuthTokens(
            accessToken: wire.access_token,
            refreshToken: wire.refresh_token ?? previous?.refreshToken,
            idToken: wire.id_token ?? previous?.idToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(wire.expires_in ?? 3600) - 60)
        )
    }

    private struct TokenResponse: Decodable {
        // Field names are the OAuth spec's.
        var access_token: String
        var refresh_token: String?
        var id_token: String?
        var expires_in: Int?
    }

    private static func randomString() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded
    }
}

public struct OAuthTokens: Codable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var idToken: String?
    public var expiresAt: Date

    /// The email the ID token was issued for. Decoded without verification: it only names the account locally, the
    /// provider verifies every call.
    public var email: String? {
        guard let payload = idToken?.split(separator: ".").dropFirst().first,
            let data = Data(base64URLEncoded: String(payload)),
            let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return (claims["email"] ?? claims["preferred_username"]) as? String
    }
}

/// Keeps one account's tokens in the Keychain and hands out a valid access token, refreshing when it's about to expire.
public actor TokenStore {
    private let key: String
    private let client: OAuthClient
    private var refreshing: Task<OAuthTokens, any Error>?

    public init(accountID: Account.ID, client: OAuthClient) {
        self.key = Self.keyPrefix + accountID.uuidString
        self.client = client
    }

    /// The Keychain key prefix every account's tokens share. The rest of the key is the account id.
    public static let keyPrefix = "oauth."

    /// Synced, so the account shows up on your other devices too.
    public static func save(_ tokens: OAuthTokens, for accountID: Account.ID) throws {
        Keychain.write(String(decoding: try JSONEncoder().encode(tokens), as: UTF8.self), for: keyPrefix + accountID.uuidString, synced: true)
    }

    public static func load(for accountID: Account.ID) -> OAuthTokens? {
        Keychain.read(keyPrefix + accountID.uuidString).flatMap { try? JSONDecoder().decode(OAuthTokens.self, from: Data($0.utf8)) }
    }

    public static func forget(_ accountID: Account.ID) {
        Keychain.delete(keyPrefix + accountID.uuidString)
    }

    public func accessToken() async throws -> String {
        guard let stored = Keychain.read(key).flatMap({ try? JSONDecoder().decode(OAuthTokens.self, from: Data($0.utf8)) }) else {
            throw ProviderError(.unauthorized, "Sign in again to keep this account in sync.")
        }
        if stored.expiresAt > Date() { return stored.accessToken }
        if let refreshing { return try await refreshing.value.accessToken }
        let task = Task { try await client.refresh(stored) }
        refreshing = task
        defer { refreshing = nil }
        let fresh = try await task.value
        Keychain.write(String(decoding: try JSONEncoder().encode(fresh), as: UTF8.self), for: key, synced: true)
        return fresh.accessToken
    }
}

extension Data {
    var base64URLEncoded: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
