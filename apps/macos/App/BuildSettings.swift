import Foundation
import Providers

/// The OAuth client this build was configured with, from project.yml. Without an id Gmail is simply not offered.
enum BuildSettings {
    static var google: OAuthClient? {
        clientID("GoogleClientID").map(OAuthClient.google)
    }

    private static func clientID(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else { return nil }
        return value
    }
}
