import Foundation
import Network
import os

/// WebSocket broadcaster.
///
/// `Network.framework` implements the protocol itself — the HTTP upgrade
/// handshake, frame masking, ping/pong and the close sequence — so this is the
/// same shape as the SSE server with a different options object bolted onto the
/// protocol stack. Hand-rolling RFC 6455 framing to save a dependency we do not
/// have would be pure loss.
///
/// The reason to offer it at all is direction. SSE is one-way by construction:
/// fine while the consumer only reads, useless the moment it wants to select an
/// input device or change engine without a restart. Nothing consumes the
/// inbound path yet, so incoming frames are received and dropped — but the
/// receive loop is wired now so the channel is not a later rewrite.
public final class WebSocketServer: Transport, @unchecked Sendable {
    public let label = "ws"

    private let listener: NWListener
    private let queue = DispatchQueue(label: "sonocles.ws")
    private var clients: [ObjectIdentifier: NWConnection] = [:]

    /// Mirrors `clients.count` behind its own lock, so reading it from inside a
    /// handler already running on `queue` cannot deadlock. See the note in
    /// `HTTPServer`; this is the same trap, one queue over.
    private let liveCount = OSAllocatedUnfairLock(initialState: 0)

    /// Called with any text frame a client sends. Not yet used; wired so the
    /// control channel is a handler away rather than a redesign.
    public var onMessage: (@Sendable (String) -> Void)?

    public init(port: UInt16) throws {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true

        let websocket = NWProtocolWebSocket.Options()
        // Answer pings without waking anything up: a browser tab left open
        // overnight should not need us to keep it alive by hand.
        websocket.autoReplyPing = true

        let params = NWParameters(tls: nil, tcp: tcp)
        params.allowLocalEndpointReuse = true
        params.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)

        listener = try NWListener(using: params)
    }

    public func start() {
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        listener.start(queue: queue)
    }

    public func stop() {
        queue.async {
            for (_, conn) in self.clients { conn.cancel() }
            self.clients.removeAll()
            self.liveCount.withLock { $0 = 0 }
        }
        listener.cancel()
    }

    public var clientCount: Int { liveCount.withLock { $0 } }

    private func accept(_ conn: NWConnection) {
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }

            switch state {
            case .ready:
                self.queue.async {
                    self.clients[ObjectIdentifier(conn)] = conn
                    self.liveCount.withLock { $0 = self.clients.count }
                }
            case .failed, .cancelled:
                self.queue.async {
                    self.clients[ObjectIdentifier(conn)] = nil
                    self.liveCount.withLock { $0 = self.clients.count }
                }
            default:
                break
            }
        }

        conn.start(queue: queue)
        receive(on: conn)
    }

    /// Drain inbound frames. Even with no control channel yet this has to run:
    /// a connection whose messages are never read will eventually stall, and a
    /// close frame would go unnoticed and leak the client.
    private func receive(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }

            if let error {
                self.queue.async {
                    self.clients[ObjectIdentifier(conn)] = nil
                    self.liveCount.withLock { $0 = self.clients.count }
                }
                _ = error
                return
            }

            if let data, !data.isEmpty,
                let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                    as? NWProtocolWebSocket.Metadata,
                metadata.opcode == .text,
                let text = String(data: data, encoding: .utf8)
            {
                self.onMessage?(text)
            }

            self.receive(on: conn)
        }
    }

    public func broadcast(_ json: String) {
        guard let data = json.data(using: .utf8) else { return }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "frame", metadata: [metadata])

        queue.async {
            for (_, conn) in self.clients {
                conn.send(
                    content: data, contentContext: context,
                    completion: .contentProcessed { _ in })
            }
        }
    }
}
