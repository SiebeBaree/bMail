import Foundation

extension OAuthClient {
    /// Google, as an iOS-type OAuth client (no secret, redirect on the reversed client id), which is what Google
    /// supports for native Mac apps. Asks for Gmail access.
    public static func google(clientID: String) -> OAuthClient {
        let reversed = clientID.split(separator: ".").reversed().joined(separator: ".")
        return OAuthClient(Configuration(
            authorizeURL: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
            clientID: clientID,
            redirectURI: "\(reversed):/oauth2redirect",
            scopes: ["openid", "email", "profile", "https://www.googleapis.com/auth/gmail.modify"],
            // offline + consent is what makes Google return a refresh token every time.
            extraParameters: ["access_type": "offline", "prompt": "consent"]
        ))
    }
}
