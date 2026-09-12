import Foundation
import os

/// The bearer token, provisioned to a file so same-machine apps pair with
/// zero clicks. The scheme is Rheocles', copied rather than redesigned.
///
/// `~/Library/Application Support/Sonocles/token`, mode 0600, created the
/// first time the sockets come up. Any process running as the user reads it
/// and is paired; a web page in the user's browser cannot, which is the whole
/// threat model on loopback. Rotation writes a new token and the old one stops
/// working on the next request.
///
/// This replaces a Basic auth password in the Keychain. That design had two
/// problems the file does not: the lock was optional, so the default install
/// let any local page switch on the microphone, and `EventSource` cannot send
/// a header, so the event stream had to stay open regardless.
///
/// The token is 32 random bytes as 64 hex characters: plain ASCII, no
/// padding, safe in a header, a query string or a pairing code shown in a UI.
public struct TokenStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The default location.
    public static var standard: TokenStore {
        TokenStore(fileURL: applicationSupport.appendingPathComponent("token"))
    }

    /// `~/Library/Application Support/Sonocles/`.
    public static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sonocles", isDirectory: true)
    }

    /// The current token, creating one if the file does not exist.
    ///
    /// A file that exists but is empty or malformed is replaced rather than
    /// served: an empty token would authenticate `Authorization: Bearer ` and
    /// a lock that opens for nothing is worse than none.
    public func loadOrCreate() throws -> String {
        if let existing = try? String(contentsOf: fileURL, encoding: .utf8) {
            let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.isWellFormed(trimmed) {
                try enforcePermissions()
                return trimmed
            }
        }
        return try rotate()
    }

    /// Replace the token. Returns the new one.
    @discardableResult
    public func rotate() throws -> String {
        let token = Self.generate()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        // Write with the final mode from the first byte: create-then-chmod
        // leaves a window where the file is world-readable.
        let tmp = fileURL.appendingPathExtension("tmp-\(ProcessInfo.processInfo.processIdentifier)")
        try Data((token + "\n").utf8).write(to: tmp, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)
        try enforcePermissions()
        return token
    }

    /// Re-assert 0600. A user who chmods the file to share it with another
    /// account has defeated the point; the sidecar quietly puts it back.
    private func enforcePermissions() throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func isWellFormed(_ token: String) -> Bool {
        token.count == 64 && token.allSatisfy { $0.isHexDigit }
    }
}

/// Checks a presented credential against the token.
///
/// Accepts `Authorization: Bearer <token>` on any request, and — for the two
/// places a browser cannot set a header, `EventSource` and `WebSocket` — the
/// same token as an `access_token` query parameter (RFC 6750 §2.3) or as the
/// first WebSocket message. Loopback only, so the URL form costs nothing a
/// local page could not already see in the header form.
public final class BearerAuth: Sendable {
    /// Behind a lock so a rotation takes effect for every later request on
    /// both transports at once.
    private let token: OSAllocatedUnfairLock<String>

    public init(token: String) {
        self.token = OSAllocatedUnfairLock(initialState: token)
    }

    /// Replace the token; every request after this compares against the new
    /// one. In-flight responses already sent are unaffected.
    public func update(to newToken: String) {
        token.withLock { $0 = newToken }
    }

    /// The token as it stands, for the process that owns it to show or copy.
    public var current: String { token.withLock { $0 } }

    /// Compare a candidate token in constant time.
    ///
    /// This is a local service, but a timing-variable string compare on a
    /// secret is the kind of thing that is free to get right and awkward to
    /// explain later.
    public func matches(token candidate: String?) -> Bool {
        guard let candidate else { return false }
        let a = Array(candidate.utf8)
        let b = Array(token.withLock { $0 }.utf8)
        guard a.count == b.count, !b.isEmpty else { return false }
        var difference: UInt8 = 0
        for i in 0..<a.count { difference |= a[i] ^ b[i] }
        return difference == 0
    }

    /// Compare an `Authorization` header value.
    public func matches(header: String?) -> Bool {
        guard let header else { return false }
        let parts = header.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0].lowercased() == "bearer" else { return false }
        return matches(token: parts[1].trimmingCharacters(in: .whitespaces))
    }

    /// Header first, then the query parameter.
    func authorizes(_ request: HTTPServer.Request) -> Bool {
        matches(header: request.headers["authorization"])
            || matches(token: request.query["access_token"])
    }
}
