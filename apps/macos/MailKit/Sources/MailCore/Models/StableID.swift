import CryptoKit
import Foundation

extension UUID {
    /// The same UUID for the same name, every time: a Gmail thread id always maps to one conversation id, so a resync
    /// updates rows instead of duplicating them. Shaped like a version 5 UUID, hashed with SHA-256.
    public init(stableFrom name: String) {
        var bytes = Array(SHA256.hash(data: Data(name.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        self = bytes.withUnsafeBytes { raw in
            UUID(uuid: raw.load(as: uuid_t.self))
        }
    }
}
