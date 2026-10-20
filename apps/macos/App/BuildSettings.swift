import Foundation
import Security
import Providers

/// The OAuth client this build was configured with, from project.yml. Without an id Gmail is simply not offered.
enum BuildSettings {
    static var google: OAuthClient? {
        clientID("GoogleClientID").map(OAuthClient.google)
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
