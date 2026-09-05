import Foundation
import Security

/// HTTP Basic credentials for the control API.
///
/// The password lives in the Keychain, never in `UserDefaults`. The control
/// API can start and stop a microphone, so its credential is a real secret and
/// storing it in a plist any process can read would make the lock decorative.
public struct Credentials: Sendable, Equatable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    /// Compare against an `Authorization` header value.
    ///
    /// Constant-time over the decoded bytes: this is a local service, but a
    /// timing-variable string compare on a secret is the kind of thing that is
    /// free to get right and awkward to explain later.
    public func matches(_ header: String?) -> Bool {
        guard let header,
            header.lowercased().hasPrefix("basic "),
            let encoded = header.split(separator: " ").last,
            let data = Data(base64Encoded: String(encoded)),
            let supplied = String(data: data, encoding: .utf8)
        else { return false }

        let expected = "\(username):\(password)"
        let a = Array(supplied.utf8)
        let b = Array(expected.utf8)

        guard a.count == b.count else { return false }

        var difference: UInt8 = 0
        for i in 0..<a.count { difference |= a[i] ^ b[i] }

        return difference == 0
    }
}

/// Keychain storage for the control-API password.
public enum CredentialStore {
    private static let service = "build.artisan.sonocles.control"
    private static let usernameKey = "SonoclesControlUsername"
    private static let enabledKey = "SonoclesControlEnabled"

    /// Whether the control API should require authentication.
    public static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    public static var username: String {
        get { UserDefaults.standard.string(forKey: usernameKey) ?? "sonocles" }
        set { UserDefaults.standard.set(newValue, forKey: usernameKey) }
    }

    /// The credentials to enforce, or nil when the API is left open.
    public static func current() -> Credentials? {
        guard isEnabled, let password = readPassword(), !password.isEmpty else { return nil }

        return Credentials(username: username, password: password)
    }

    public static func save(username: String, password: String) {
        self.username = username
        writePassword(password)
        isEnabled = !password.isEmpty
    }

    public static func readPassword() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data
        else { return nil }

        return String(data: data, encoding: .utf8)
    }

    private static func writePassword(_ password: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]

        SecItemDelete(base as CFDictionary)

        guard !password.isEmpty else { return }

        var insert = base
        insert[kSecValueData as String] = Data(password.utf8)
        // The sidecar starts at login and must read this without a prompt, so
        // it unlocks with the keychain rather than requiring the device to be
        // unlocked at the moment of access.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        SecItemAdd(insert as CFDictionary, nil)
    }
}
