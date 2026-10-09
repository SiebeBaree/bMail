import Foundation
import MailCore

/// One signature per account, kept on this Mac. Plain text: the composer puts it under what you write, where it can
/// still be edited like the rest of the message.
enum Signatures {
    static func text(for account: Account.ID) -> String {
        UserDefaults.standard.string(forKey: key(account)) ?? ""
    }

    static func set(_ text: String, for account: Account.ID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: key(account))
        } else {
            UserDefaults.standard.set(trimmed, forKey: key(account))
        }
    }

    private static func key(_ account: Account.ID) -> String { "signature.\(account.uuidString)" }
}
