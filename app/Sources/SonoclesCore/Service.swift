@preconcurrency import AVFoundation
import Foundation
import os

/// The long-lived process: sockets up, capture optional.
///
/// The split between this and `Sidecar` is the lesson from a real bug. When
/// transports lived inside the capture session, stopping capture orphaned the
/// listeners — they kept the ports, accepted connections, and answered nothing,
/// because the handlers behind them held a weak reference to a deallocated
/// server. It also made a remote `POST /start` impossible even in principle.
///
/// So sockets are infrastructure and live as long as the process. Capture is a
/// session that starts and stops beneath them, and every consumer — the CLI,
/// the menu bar app, an HTTP client — drives the same one.
public final class Service: @unchecked Sendable {
    public struct Config: Sendable {
        public var sidecar: Sidecar.Config
        public var http: Bool
        public var websocket: Bool
        public var httpPort: UInt16
        public var wsPort: UInt16

        public init(
            sidecar: Sidecar.Config = .init(),
            http: Bool = true,
            websocket: Bool = true,
            httpPort: UInt16 = 7357,
            wsPort: UInt16 = 7358
        ) {
            self.sidecar = sidecar
            self.http = http
            self.websocket = websocket
            self.httpPort = httpPort
            self.wsPort = wsPort
        }
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let note: @Sendable (String) -> Void
    private let started = Date()

    private var http: HTTPServer?
    private var websocket: WebSocketServer?
    private var transports: [Transport] = []

    private struct State {
        var config = Config()
        var sidecar: Sidecar?
        var listening = false
        var starting = false
        var levelDb: Double?
    }

    /// Forwarded from the running session, for a UI or a terminal to draw.
    public var onFrame: (@Sendable (Hypothesis, Frame, UInt64) -> Void)?
    public var onLevel: (@Sendable (Double) -> Void)?
    public var onListeningChanged: (@Sendable (Bool) -> Void)?

    public init(config: Config, note: @escaping @Sendable (String) -> Void) {
        self.note = note
        state.withLock { $0.config = config }
    }

    /// Bring the sockets up. Capture is not started here — that is `startListening`.
    public func bind() throws {
        let config = state.withLock { $0.config }
        var built: [Transport] = []

        if config.http {
            let server = try HTTPServer(
                port: config.httpPort, credentials: CredentialStore.current())
            server.handlers = HTTPServer.Handlers(
                start: { [weak self] in self?.startListening() },
                stop: { [weak self] in self?.stopListening() },
                status: { [weak self] in
                    self?.status()
                        ?? .init(
                            state: "idle", listening: false, engine: "-", clients: 0, uptime: 0,
                            levelDb: nil)
                }
            )
            http = server
            built.append(server)
        }

        if config.websocket {
            let server = try WebSocketServer(port: config.wsPort)
            websocket = server
            built.append(server)
        }

        transports = built
        for transport in built { try transport.start() }
    }

    public func shutdown() {
        stopListening()
        for transport in transports { transport.stop() }
        transports = []
        http = nil
        websocket = nil
    }

    public var isListening: Bool { state.withLock { $0.listening } }

    public var engineName: String {
        state.withLock { $0.sidecar?.engineName ?? $0.config.sidecar.engine.label }
    }

    public var hardwareFormat: AVAudioFormat? { state.withLock { $0.sidecar?.hardwareFormat } }
    public var engineFormat: AVAudioFormat? { state.withLock { $0.sidecar?.engineFormat } }

    public func status() -> HTTPServer.Status {
        let (listening, starting, level) = state.withLock {
            ($0.listening, $0.starting, $0.levelDb)
        }

        return HTTPServer.Status(
            state: listening ? "listening" : (starting ? "starting" : "idle"),
            listening: listening,
            engine: engineName,
            clients: transports.reduce(0) { $0 + $1.clientCount },
            uptime: Date().timeIntervalSince(started),
            levelDb: listening ? level : nil
        )
    }

    /// Reconfigure the next session. Restarts capture if it was running, since
    /// a half-swapped pipeline would report numbers belonging to neither engine.
    public func use(engine: EngineChoice) {
        let wasListening = isListening
        if wasListening { stopListening() }
        state.withLock { $0.config.sidecar.engine = engine }
        if wasListening { startListening() }
    }

    public func startListening() {
        let alreadyBusy = state.withLock { state -> Bool in
            if state.listening || state.starting { return true }
            state.starting = true
            return false
        }

        guard !alreadyBusy else { return }

        let config = state.withLock { $0.config.sidecar }

        do {
            let sidecar = try Sidecar(config: config, note: note)

            sidecar.onLevel = { [weak self] db in
                self?.state.withLock { $0.levelDb = db }
                self?.onLevel?(db)
            }
            sidecar.onFrame = { [weak self] hypothesis, frame, nanos in
                guard let self else { return }
                // Wire first, so a consumer is never waiting on a terminal.
                if let json = frame.json {
                    for transport in self.transports { transport.broadcast(json) }
                }
                self.onFrame?(hypothesis, frame, nanos)
            }

            state.withLock { $0.sidecar = sidecar }

            Task { [weak self] in
                guard let self else { return }
                do {
                    try await sidecar.start()
                    self.state.withLock {
                        $0.listening = true; $0.starting = false
                    }
                    self.onListeningChanged?(true)
                    self.note("listening · \(sidecar.engineName)")
                } catch {
                    self.state.withLock {
                        $0.sidecar = nil; $0.starting = false
                    }
                    self.note("could not start: \(error.localizedDescription)")
                }
            }
        } catch {
            state.withLock { $0.starting = false }
            note("could not start: \(error.localizedDescription)")
        }
    }

    public func stopListening() {
        let sidecar = state.withLock { state -> Sidecar? in
            defer {
                state.sidecar = nil
                state.listening = false
                state.starting = false
                state.levelDb = nil
            }
            return state.sidecar
        }

        guard sidecar != nil else { return }

        sidecar?.stop()
        onListeningChanged?(false)
        note("stopped")
    }
}
