import Foundation

extension OAuthClient {
    /// Google, as an iOS-type OAuth client (no secret, redirect on the reversed client id), which is what Google
    /// supports for native Mac apps. `mail` adds Gmail access on top of signing in.
    public static func google(clientID: String, mail: Bool) -> OAuthClient {
        let reversed = clientID.split(separator: ".").reversed().joined(separator: ".")
        return OAuthClient(Configuration(
            authorizeURL: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
            clientID: clientID,
            redirectURI: "\(reversed):/oauth2redirect",
            scopes: ["openid", "email", "profile"] + (mail ? ["https://www.googleapis.com/auth/gmail.modify"] : []),
            // offline + consent is what makes Google return a refresh token every time.
            extraParameters: mail ? ["access_type": "offline", "prompt": "consent"] : [:]
        ))
    }

    /// Microsoft, as a public client on the common endpoint, so personal and work accounts both work.
    public static func microsoft(clientID: String) -> OAuthClient {
        OAuthClient(Configuration(
            authorizeURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!,
            tokenURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!,
            clientID: clientID,
            redirectURI: "msauth.be.baree.mail://auth",
            scopes: ["openid", "email", "offline_access", "https://graph.microsoft.com/Mail.ReadWrite", "https://graph.microsoft.com/Mail.Send"]
        ))
    }
}
