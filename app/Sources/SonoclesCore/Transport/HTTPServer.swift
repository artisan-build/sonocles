import Foundation
import Network
import os

/// The HTTP surface: the event stream and the control API, on one port.
///
/// This server **outlives the capture session**. That is the whole design
/// constraint, and it was learned the hard way: when the transports lived
/// inside the sidecar, stopping capture left an orphaned `NWListener` holding
/// the port with a deallocated handler behind it, so the next connection was
/// accepted and then silently answered with nothing. It also made
/// `POST /start` impossible in principle — you cannot ask a stopped thing to
/// start itself over a socket it took down when it stopped.
///
/// So: sockets are infrastructure and stay up for the life of the process;
/// capture is a session that comes and goes underneath them.
///
/// Every route is behind the bearer token, the event stream included. The
/// token is checked before routing, so an unknown path is 401 before it is
/// 404 and the route table is not enumerable without the token.
///
/// `@unchecked Sendable`: every mutable member is only touched inside closures
/// dispatched on `queue`, so access is already serialized.
public final class HTTPServer: Transport, @unchecked Sendable {
    public let label = "http"
    public let port: UInt16

    /// What the control routes can ask for.
    public struct Handlers: Sendable {
        public var discovery: @Sendable () -> Discovery
        public var start: @Sendable () -> Void
        public var stop: @Sendable () -> Void
        public var status: @Sendable () -> Status
        /// Write a new token and make it the one every later request — on
        /// both transports — is compared against. Returns the new token.
        public var rotateToken: @Sendable () throws -> String

        public init(
            discovery: @escaping @Sendable () -> Discovery,
            start: @escaping @Sendable () -> Void,
            stop: @escaping @Sendable () -> Void,
            status: @escaping @Sendable () -> Status,
            rotateToken: @escaping @Sendable () throws -> String
        ) {
            self.discovery = discovery
            self.start = start
            self.stop = stop
            self.status = status
            self.rotateToken = rotateToken
        }
    }

    /// `GET /` — who am I, how do I authenticate, where are the sockets.
    ///
    /// The first call a client makes. `auth` is always `bearer`; it is here
    /// so a client written against a future scheme can tell which one it has
    /// reached rather than guessing from a 401.
    public struct Discovery: Codable, Sendable, Equatable {
        public let name: String
        public let version: String
        public let auth: String
        public let ports: Ports

        public struct Ports: Codable, Sendable, Equatable {
            public let http: UInt16
            public let ws: UInt16?

            public init(http: UInt16, ws: UInt16?) {
                self.http = http
                self.ws = ws
            }
        }

        public init(name: String, version: String, auth: String, ports: Ports) {
            self.name = name
            self.version = version
            self.auth = auth
            self.ports = ports
        }
    }

    public struct Status: Encodable, Sendable {
        /// `idle` · `starting` · `listening`.
        ///
        /// Three states rather than a boolean, because `POST /start` returns
        /// before capture is up — models load, permission may be asked for —
        /// and answering `listening: false` to a request that just succeeded
        /// reads as a failure. A caller polls until this says `listening`.
        public let state: String
        public let listening: Bool
        public let engine: String
        public let clients: Int
        public let uptime: Double
        /// Peak input level in dBFS, or nil when not capturing.
        ///
        /// Here because "is it hearing anything" is otherwise unanswerable from
        /// outside the process — establishing that thirty seconds of piano
        /// produced no text required starting a second sidecar just to watch a
        /// meter. Signal without text is a working microphone and a quiet room;
        /// no signal at all is a different problem, and a consumer should not
        /// have to guess which it has.
        public let levelDb: Double?
        /// What the engine is doing before it can listen, when that is not
        /// instant. Absent once models are resident.
        public let preparing: String?
        /// Fraction complete where one is knowable — absent while compiling,
        /// which has no measurable progress and should not have one invented.
        public let preparingFraction: Double?

        public init(
            state: String, listening: Bool, engine: String, clients: Int, uptime: Double,
            levelDb: Double?, preparing: String?, preparingFraction: Double?
        ) {
            self.state = state
            self.listening = listening
            self.engine = engine
            self.clients = clients
            self.uptime = uptime
            self.levelDb = levelDb
            self.preparing = preparing
            self.preparingFraction = preparingFraction
        }
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "sonocles.http")
    private var streams: [ObjectIdentifier: NWConnection] = [:]
    private let ready = DispatchSemaphore(value: 0)
    private let startError = OSAllocatedUnfairLock<Error?>(initialState: nil)

    /// Mirrors `streams.count` behind its own lock.
    ///
    /// `clientCount` used to be `queue.sync { streams.count }`, which deadlocked
    /// the instant anything on `queue` asked for it — and `GET /status` does
    /// exactly that, since the status payload reports connected clients. A
    /// serial queue calling `sync` on itself simply stops, and the symptom is an
    /// accepted connection that answers nothing. Hence a separate lock that is
    /// safe to read from anywhere, including from inside a request handler.
    private let liveCount = OSAllocatedUnfairLock(initialState: 0)

    /// Set by the owner once the service exists. Absent until then, so a
    /// control request arriving during boot is refused rather than crashing.
    public var handlers: Handlers?

    /// The bearer token every route is behind. Shared with the WebSocket
    /// server, so a rotation lands on both at once.
    private let auth: BearerAuth

    public init(port: UInt16, auth: BearerAuth) throws {
        self.port = port
        self.auth = auth

        // Nagle coalesces small writes, exactly the wrong trade for a stream of
        // one-line frames: it can hold a hypothesis up to 40 ms waiting for
        // company. Irrelevant next to a 3.8 s engine; a fifth of the budget
        // next to a 180 ms one.
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true

        let params = NWParameters(tls: nil, tcp: tcp)
        params.allowLocalEndpointReuse = true
        // Loopback only. This is a local sidecar, not a network service, and
        // the control API is a reason to be stricter about that rather than
        // looser.
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)

        listener = try NWListener(using: params)
    }

    /// Bind, and return only once the port is actually held — or throw.
    ///
    /// `NWListener.start` is asynchronous and reports a taken port as a state
    /// change, not an error. Waiting here means a caller that gets a return
    /// can send a request, and one that gets a throw knows the port is busy
    /// rather than finding out from a refused connection.
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
            for (_, conn) in self.streams { conn.cancel() }
            self.streams.removeAll()
            self.liveCount.withLock { $0 = 0 }
        }
        listener.cancel()
    }

    public var clientCount: Int { liveCount.withLock { $0 } }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)

        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, _, _ in
            guard let self, let data, let request = Request(data) else {
                conn.cancel()
                return
            }

            self.route(request, on: conn)
        }
    }

    private func route(_ request: Request, on conn: NWConnection) {
        // Preflight, so a browser page can POST control requests. Unauthenticated
        // by necessity: the browser sends it before it will attach the header.
        if request.method == "OPTIONS" {
            respond(conn, status: "204 No Content", body: nil)
            return
        }

        guard auth.authorizes(request) else {
            respond(
                conn, status: "401 Unauthorized",
                body: "{\"error\":\"authentication required\"}",
                extra: "WWW-Authenticate: Bearer realm=\"Sonocles\"\r\n")
            return
        }

        switch (request.method, request.path) {
        case ("GET", "/"):
            respondJSON(conn, encodable: handlers?.discovery())

        case ("GET", "/events"):
            openStream(on: conn)

        case ("GET", "/status"):
            respondJSON(conn, encodable: handlers?.status())

        case ("POST", "/start"):
            handlers?.start()
            respondJSON(conn, encodable: handlers?.status())

        case ("POST", "/stop"):
            handlers?.stop()
            respondJSON(conn, encodable: handlers?.status())

        case ("POST", "/token/rotate"):
            guard let handlers else {
                respondJSON(conn, encodable: [String: String]?.none)
                return
            }
            do {
                let token = try handlers.rotateToken()
                respondJSON(conn, encodable: ["token": token])
            } catch {
                respond(
                    conn, status: "500 Internal Server Error",
                    body: "{\"error\":\"could not write the token file\"}")
            }

        default:
            respond(conn, status: "404 Not Found", body: "{\"error\":\"no such route\"}")
        }
    }

    /// The event stream is behind the same token as everything else.
    ///
    /// `EventSource` cannot set an Authorization header, which is why an
    /// earlier design left the stream open. The token in the query string
    /// (`/events?access_token=…`, RFC 6750 §2.3) is what makes locking it
    /// possible: on loopback the URL form exposes nothing a local page could
    /// not already see in the header form, and the transcript of everything
    /// said near the microphone is not a thing to leave readable by any page.
    private func openStream(on conn: NWConnection) {
        let headers = """
            HTTP/1.1 200 OK\r
            Content-Type: text/event-stream\r
            Cache-Control: no-cache\r
            Connection: keep-alive\r
            Access-Control-Allow-Origin: *\r
            \r

            """
        conn.send(content: headers.data(using: .utf8), completion: .contentProcessed { _ in })
        conn.send(
            content: ": connected\n\n".data(using: .utf8), completion: .contentProcessed { _ in })

        queue.async {
            self.streams[ObjectIdentifier(conn)] = conn
            self.liveCount.withLock { $0 = self.streams.count }
        }

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }

            switch state {
            case .failed, .cancelled:
                self.queue.async {
                    self.streams[ObjectIdentifier(conn)] = nil
                    self.liveCount.withLock { $0 = self.streams.count }
                }
            default:
                break
            }
        }
    }

    private func respondJSON(_ conn: NWConnection, encodable: (some Encodable)?) {
        let body =
            encodable
            .flatMap { try? JSONEncoder().encode($0) }
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? "{\"error\":\"service not ready\"}"

        respond(conn, status: "200 OK", body: body)
    }

    private func respond(_ conn: NWConnection, status: String, body: String?, extra: String = "") {
        let payload = body ?? ""
        let response = """
            HTTP/1.1 \(status)\r
            Content-Type: application/json\r
            Content-Length: \(payload.utf8.count)\r
            Access-Control-Allow-Origin: *\r
            Access-Control-Allow-Methods: GET, POST, OPTIONS\r
            Access-Control-Allow-Headers: Authorization, Content-Type\r
            \(extra)Connection: close\r
            \r
            \(payload)
            """

        conn.send(
            content: response.data(using: .utf8),
            completion: .contentProcessed { _ in
                conn.cancel()
            })
    }

    public func broadcast(_ json: String) {
        guard let data = "data: \(json)\n\n".data(using: .utf8) else { return }

        queue.async {
            for (_, conn) in self.streams {
                conn.send(content: data, completion: .contentProcessed { _ in })
            }
        }
    }

    /// Just enough of an HTTP request to route and authenticate one.
    ///
    /// Internal rather than private so it can be tested directly. Parsing is the
    /// one part of this file that is pure, and it is also the part that silently
    /// drops a connection when it gets something wrong.
    struct Request {
        let method: String
        let path: String
        /// The query string, decoded. Only `access_token` is read, and only
        /// because `EventSource` has nowhere else to put it.
        let query: [String: String]
        let headers: [String: String]

        init(
            method: String, path: String, query: [String: String] = [:],
            headers: [String: String] = [:]
        ) {
            self.method = method
            self.path = path
            self.query = query
            self.headers = headers
        }

        init?(_ data: Data) {
            guard let text = String(data: data, encoding: .utf8),
                let head = text.components(separatedBy: "\r\n\r\n").first
            else { return nil }

            var lines = head.components(separatedBy: "\r\n")
            guard !lines.isEmpty else { return nil }

            let parts = lines.removeFirst().split(separator: " ")
            guard parts.count >= 2 else { return nil }

            method = String(parts[0])

            // The query is split off the path so "/status?x" does not 404, and
            // kept so "/events?access_token=…" can authenticate.
            let target = String(parts[1])
            var query: [String: String] = [:]
            if let q = target.firstIndex(of: "?") {
                path = String(target[..<q])
                for pair in target[target.index(after: q)...].split(separator: "&") {
                    let kv = pair.split(separator: "=", maxSplits: 1)
                    guard let key = kv.first?.removingPercentEncoding else { continue }
                    query[key] = kv.count > 1 ? (String(kv[1]).removingPercentEncoding ?? "") : ""
                }
            } else {
                path = target
            }
            self.query = query

            var collected: [String: String] = [:]
            for line in lines {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[line.startIndex..<colon].lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                collected[key] = value
            }
            headers = collected
        }
    }
}
