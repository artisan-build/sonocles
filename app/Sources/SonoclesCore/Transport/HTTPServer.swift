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
/// `@unchecked Sendable`: every mutable member is only touched inside closures
/// dispatched on `queue`, so access is already serialized.
public final class HTTPServer: Transport, @unchecked Sendable {
    public let label = "http"

    /// What the control routes can ask for.
    public struct Handlers: Sendable {
        public var start: @Sendable () -> Void
        public var stop: @Sendable () -> Void
        public var status: @Sendable () -> Status

        public init(
            start: @escaping @Sendable () -> Void,
            stop: @escaping @Sendable () -> Void,
            status: @escaping @Sendable () -> Status
        ) {
            self.start = start
            self.stop = stop
            self.status = status
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

    /// HTTP Basic credentials for the control routes. Nil means unprotected.
    private let credentials: Credentials?

    public init(port: UInt16, credentials: Credentials?) throws {
        self.credentials = credentials

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

    public func start() {
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        listener.start(queue: queue)
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
        // Preflight, so a browser page can POST control requests.
        if request.method == "OPTIONS" {
            respond(conn, status: "204 No Content", body: nil)
            return
        }

        switch (request.method, request.path) {
        case ("GET", "/events"):
            openStream(on: conn)

        case ("GET", "/status"):
            guard authorized(request, conn) else { return }
            let status = handlers?.status()
            respondJSON(conn, encodable: status)

        case ("POST", "/start"):
            guard authorized(request, conn) else { return }
            handlers?.start()
            respondJSON(conn, encodable: handlers?.status())

        case ("POST", "/stop"):
            guard authorized(request, conn) else { return }
            handlers?.stop()
            respondJSON(conn, encodable: handlers?.status())

        default:
            respond(conn, status: "404 Not Found", body: "{\"error\":\"no such route\"}")
        }
    }

    /// The event stream deliberately is *not* behind Basic auth.
    ///
    /// `EventSource` cannot set an Authorization header, so protecting the
    /// stream would mean credentials in the URL — worse than leaving a
    /// loopback-only read endpoint open. The control routes are what change
    /// state, and those are what a hostile page could reach, so those are what
    /// carry the lock.
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

    private func authorized(_ request: Request, _ conn: NWConnection) -> Bool {
        guard let credentials else { return true }

        if credentials.matches(request.headers["authorization"]) { return true }

        respond(
            conn, status: "401 Unauthorized",
            body: "{\"error\":\"authentication required\"}",
            extra: "WWW-Authenticate: Basic realm=\"Sonocles\"\r\n")

        return false
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
        let headers: [String: String]

        init?(_ data: Data) {
            guard let text = String(data: data, encoding: .utf8),
                let head = text.components(separatedBy: "\r\n\r\n").first
            else { return nil }

            var lines = head.components(separatedBy: "\r\n")
            guard !lines.isEmpty else { return nil }

            let parts = lines.removeFirst().split(separator: " ")
            guard parts.count >= 2 else { return nil }

            method = String(parts[0])
            // Query strings are not used by any route; drop them so "/status?x"
            // does not 404.
            path = String(parts[1].split(separator: "?").first ?? "")

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
