import Foundation
import Security

/// Secrets the app keeps: your server's token, each Gmail account's OAuth tokens and the agents' token. Stored as generic
/// passwords readable only by this app.
///
/// `synced` items go to iCloud Keychain, which is how an iPhone finds what you set up on the Mac. They live in the data
/// protection keychain, which on the Mac needs the `keychain-access-groups` entitlement and so a provisioning profile.
/// Builds without one (tests, a release signed without a profile) keep the item on this device instead.
///
/// Items stay readable while the device is locked after the first unlock, so a message sent just before locking still
/// goes out.
public enum Keychain {
    /// The bundle id, which both shipped apps share. A copy built under another id keeps its own items and never sees
    /// the installed app's.
    private static let service = Bundle.main.bundleIdentifier ?? "be.baree.mail"

    public static func read(_ key: String) -> String? {
        for base in [syncedQuery, localQuery] {
            var item: CFTypeRef?
            var query = base(key)
            query[kSecReturnData] = true
            if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data {
                return String(data: data, encoding: .utf8)
            }
        }
        return nil
    }

    public static func write(_ value: String, for key: String, synced: Bool = false) {
        let data = Data(value.utf8)
        if synced, store(data, query: syncedQuery(key), accessible: kSecAttrAccessibleAfterFirstUnlock) {
            // Moved to iCloud, so an older copy on this device mustn't shadow it later.
            SecItemDelete(localQuery(key) as CFDictionary)
            return
        }
        _ = store(data, query: localQuery(key), accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
    }

    public static func delete(_ key: String) {
        SecItemDelete(syncedQuery(key) as CFDictionary)
        SecItemDelete(localQuery(key) as CFDictionary)
    }

    /// The keys of every item whose key starts with `prefix`, synced or not. Nil when the keychain couldn't be read,
    /// for example on an iPhone that hasn't been unlocked since it started, which is different from finding none.
    public static func keys(withPrefix prefix: String) -> Set<String>? {
        var keys = Set<String>()
        for base in [syncedQuery(nil), localQuery(nil)] {
            var items: CFTypeRef?
            var query = base
            query[kSecReturnAttributes] = true
            query[kSecMatchLimit] = kSecMatchLimitAll
            switch SecItemCopyMatching(query as CFDictionary, &items) {
            case errSecSuccess:
                for attributes in items as? [[CFString: Any]] ?? [] {
                    if let key = attributes[kSecAttrAccount] as? String, key.hasPrefix(prefix) { keys.insert(key) }
                }
            case errSecItemNotFound, errSecMissingEntitlement: continue
            default: return nil
            }
        }
        return keys
    }

    private static func store(_ data: Data, query: [CFString: Any], accessible: CFString) -> Bool {
        let attributes: [CFString: Any] = [kSecValueData: data, kSecAttrAccessible: accessible]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            return SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    private static func syncedQuery(_ key: String?) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrSynchronizable: true,
            kSecUseDataProtectionKeychain: true,
        ]
        if let key { query[kSecAttrAccount] = key }
        return query
    }

    /// The Mac's file keychain, where every item lived before items synced. On iPhone it's the same keychain as the
    /// synced items, minus the ones that sync.
    private static func localQuery(_ key: String?) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
        ]
        if let key { query[kSecAttrAccount] = key }
        return query
    }
}
