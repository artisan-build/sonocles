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
/// inbound path yet beyond the auth frame, so other incoming frames are handed
/// to `onMessage` and otherwise dropped — but the receive loop is wired now so
/// the channel is not a later rewrite.
///
/// Auth: the first frame must be `{"auth": "<token>"}`; until it has arrived,
/// every other frame is answered 401 and no event is delivered. A header on
/// the upgrade request would be the HTTP-shaped way, but a browser `WebSocket`
/// cannot set one and Network.framework's upgrade handler cannot tell which
/// connection a request belongs to, so the frame is the one way that works
/// for every client and it is the only way.
public final class WebSocketServer: Transport, @unchecked Sendable {
    public let label = "ws"
    public let port: UInt16

    private let listener: NWListener
    private let queue = DispatchQueue(label: "sonocles.ws")
    private let auth: BearerAuth
    /// Connected clients and whether each has authenticated.
    private var clients: [ObjectIdentifier: (NWConnection, Bool)] = [:]
    private let ready = DispatchSemaphore(value: 0)
    private let startError = OSAllocatedUnfairLock<Error?>(initialState: nil)

    /// Mirrors `clients.count` behind its own lock, so reading it from inside a
    /// handler already running on `queue` cannot deadlock. See the note in
    /// `HTTPServer`; this is the same trap, one queue over.
    private let liveCount = OSAllocatedUnfairLock(initialState: 0)

    /// Called with any text frame an *authenticated* client sends that is not
    /// itself an auth frame. Not yet used; wired so the control channel is a
    /// handler away rather than a redesign.
    public var onMessage: (@Sendable (String) -> Void)?

    public init(port: UInt16, auth: BearerAuth) throws {
        self.port = port
        self.auth = auth

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

    /// Bind, and return only once the port is actually held — or throw. Same
    /// reasoning as `HTTPServer.start`.
    public func start() throws {
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.ready.signal()
            case .failed(let error):
                self.startError.withLock { $0 = error }
                self.ready.signal()
            case .cancelled:
                self.ready.signal()
            default:
                break
            }
        }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 5)
        if let error = startError.withLock({ $0 }) { throw error }
    }

    public func stop() {
        queue.async {
            for (_, (conn, _)) in self.clients { conn.cancel() }
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
                    self.clients[ObjectIdentifier(conn)] = (conn, false)
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

            if error != nil {
                self.queue.async {
                    self.clients[ObjectIdentifier(conn)] = nil
                    self.liveCount.withLock { $0 = self.clients.count }
                }
                return
            }

            if let data, !data.isEmpty,
                let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                    as? NWProtocolWebSocket.Metadata,
                metadata.opcode == .text
            {
                self.handle(data, from: conn)
            }

            self.receive(on: conn)
        }
    }

    /// The auth frame, or anything else. Only `auth` and `id` are read; the
    /// rest of a frame is the future control channel's business.
    struct Frame: Decodable {
        var id: JSONValue?
        var auth: String?
    }

    private func handle(_ data: Data, from conn: NWConnection) {
        let frame = try? JSONDecoder().decode(Frame.self, from: data)
        let id = frame?.id.map { (try? JSONEncoder().encode($0)) ?? Data("null".utf8) }

        if let token = frame?.auth {
            let ok = auth.matches(token: token)
            // `handle` runs on `queue`, so this write is serialized with the
            // reads below and with `broadcast`.
            if ok { clients[ObjectIdentifier(conn)]?.1 = true }
            send(
                conn, id: id, status: ok ? 200 : 401,
                body: ok ? #"{"authenticated":true}"# : #"{"error":"authentication required"}"#)
            return
        }

        guard clients[ObjectIdentifier(conn)]?.1 == true else {
            send(conn, id: id, status: 401, body: #"{"error":"authentication required"}"#)
            return
        }

        if let text = String(data: data, encoding: .utf8) {
            onMessage?(text)
        }
    }

    private func send(_ conn: NWConnection, id: Data?, status: Int, body: String) {
        var frame = Data(#"{"id":"#.utf8)
        frame.append(id ?? Data("null".utf8))
        frame.append(Data(#","status":\#(status),"body":"#.utf8))
        frame.append(Data(body.utf8))
        frame.append(Data("}".utf8))
        sendText(conn, frame)
    }

    private func sendText(_ conn: NWConnection, _ data: Data) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "frame", metadata: [metadata])
        conn.send(content: data, contentContext: context, completion: .contentProcessed { _ in })
    }

    /// Frames go only to authenticated clients: the token gates reading too.
    public func broadcast(_ json: String) {
        guard let data = json.data(using: .utf8) else { return }

        queue.async {
            for (_, (conn, authenticated)) in self.clients where authenticated {
                self.sendText(conn, data)
            }
        }
    }
}

/// Just enough JSON to carry a frame's `id` through untouched, so a reply can
/// be matched to the frame that asked for it whatever type the client chose.
public enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .object(try c.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n):
            if n == n.rounded(), abs(n) < 1e15 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}
