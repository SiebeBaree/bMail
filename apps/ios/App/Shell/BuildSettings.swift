import Foundation
import Providers

/// The OAuth client this build was configured with, from project.yml. Without an id Gmail is simply not offered.
enum BuildSettings {
    static var google: OAuthClient? {
        clientID.map(OAuthClient.google)
    }

    private static var clientID: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String, !value.isEmpty else { return nil }
        return value
    }
}
