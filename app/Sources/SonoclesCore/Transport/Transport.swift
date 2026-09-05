import Foundation

/// Somewhere frames go.
///
/// Both transports carry the identical JSON payload — the choice is about how a
/// consumer prefers to listen, never about what it receives. SSE is one-way and
/// reconnects itself, which suits a browser that only wants to read. WebSocket
/// is bidirectional, which is what a consumer needs when it eventually wants to
/// talk back and reconfigure the source mid-session.
public protocol Transport: Sendable {
    var label: String { get }
    func start() throws
    /// Cancel the listener and drop every client.
    ///
    /// Not optional. A transport that is dropped without this leaves an
    /// orphaned `NWListener` holding the port, which then accepts connections
    /// and answers them with nothing — a failure that looks exactly like a
    /// hung server and took a live debugging session to pin down.
    func stop()
    func broadcast(_ json: String)
    var clientCount: Int { get }
}

/// Fans one frame out to every transport that is running.
///
/// Both can be up at once. Nothing about a hypothesis depends on who is
/// listening, so there is no reason to make the user choose at launch.
public final class Broadcaster: @unchecked Sendable {
    private let transports: [Transport]

    public init(_ transports: [Transport]) {
        self.transports = transports
    }

    public func start() throws {
        for transport in transports { try transport.start() }
    }

    public func stop() {
        for transport in transports { transport.stop() }
    }

    public func broadcast(_ json: String) {
        for transport in transports { transport.broadcast(json) }
    }

    public var summary: String {
        transports.map { "\($0.label) (\($0.clientCount))" }.joined(separator: " · ")
    }
}
