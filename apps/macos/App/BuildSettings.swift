import Foundation
import Security
import Providers

/// The OAuth clients this build was configured with, from project.yml. A provider without an id is simply not offered.
enum BuildSettings {
    static var google: OAuthClient? {
        clientID("GoogleClientID").map { OAuthClient.google(clientID: $0, mail: true) }
    }

    static var googleSignIn: OAuthClient? {
        clientID("GoogleClientID").map { OAuthClient.google(clientID: $0, mail: false) }
    }

    static var microsoft: OAuthClient? {
        clientID("MicrosoftClientID").map(OAuthClient.microsoft)
    }

    /// Sign in with Apple needs its entitlement, which needs a provisioning profile. Builds without one don't offer it.
    static var signInWithApple: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, "com.apple.developer.applesignin" as CFString, nil) != nil
    }

    private static func clientID(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else { return nil }
        return value
    }
}
