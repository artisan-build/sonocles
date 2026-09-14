import Foundation
import Testing
import os

@testable import SonoclesCore

/// Parsing is the one pure part of the HTTP server, and the part that silently
/// drops the connection when it gets something wrong — which is exactly how a
/// deadlock and a bad route both presented as "empty reply from server".
@Suite("HTTP request parsing")
struct RequestTests {
    private func parse(_ raw: String) -> HTTPServer.Request? {
        HTTPServer.Request(Data(raw.utf8))
    }

    @Test("A normal request yields method, path and headers")
    func basic() throws {
        let request = try #require(
            parse(
                "GET /status HTTP/1.1\r\nHost: 127.0.0.1:7357\r\nAuthorization: Bearer abc\r\n\r\n")
        )

        #expect(request.method == "GET")
        #expect(request.path == "/status")
        #expect(request.headers["authorization"] == "Bearer abc")
        #expect(request.query.isEmpty)
    }

    @Test("Header names are matched case-insensitively")
    func headerCase() throws {
        let request = try #require(parse("GET / HTTP/1.1\r\nAUTHORIZATION: Bearer xyz\r\n\r\n"))

        #expect(request.headers["authorization"] == "Bearer xyz")
    }

    /// A query string must not turn /status into a 404, and on /events it is
    /// the only place `EventSource` can carry the token.
    @Test("A query string is split off the path and decoded")
    func queryString() throws {
        let request = try #require(
            parse("GET /events?access_token=ab%20cd&flag HTTP/1.1\r\nHost: x\r\n\r\n"))

        #expect(request.path == "/events")
        #expect(request.query["access_token"] == "ab cd")
        #expect(request.query["flag"] == "")
    }

    @Test("POST is parsed like any other method")
    func post() throws {
        let request = try #require(parse("POST /start HTTP/1.1\r\nHost: x\r\n\r\n"))

        #expect(request.method == "POST")
        #expect(request.path == "/start")
    }

    /// `POST /engine` is the one route with a body, and a client may send it
    /// in a second write; the server reads until the head's promise is kept.
    @Test("A body is read up to Content-Length, and a short one is not complete")
    func body() throws {
        let head = "POST /engine HTTP/1.1\r\nContent-Length: 22\r\n\r\n"
        let whole = try #require(parse(head + #"{"engine": "fluid320"}"#))
        #expect(whole.contentLength == 22)
        #expect(whole.isComplete)
        #expect(whole.engineSlug == "fluid320")

        let partial = try #require(parse(head + #"{"engine": "fl"#))
        #expect(!partial.isComplete)
        #expect(partial.engineSlug == nil)

        let none = try #require(parse("POST /engine HTTP/1.1\r\nHost: x\r\n\r\n"))
        #expect(none.contentLength == 0)
        #expect(none.isComplete)
        #expect(none.engineSlug == nil)
        #expect(!HTTPServer.Request.hasHead(Data("POST /engine HTTP/1.1\r\nHost:".utf8)))
    }

    @Test(
        "Garbage is rejected rather than half-parsed",
        arguments: [
            "", "GET\r\n\r\n", "\r\n\r\n",
        ])
    func garbage(_ raw: String) {
        #expect(parse(raw) == nil)
    }
}

@Suite("Engine choice")
struct EngineChoiceTests {
    /// Slugs are the CLI's `--engine` argument and are persisted in settings, so
    /// renaming one silently breaks both.
    @Test("Slugs are stable")
    func slugs() {
        #expect(EngineChoice.fluid160.slug == "fluid160")
        #expect(EngineChoice.fluid320.slug == "fluid320")
        #expect(EngineChoice.fluid1280.slug == "fluid1280")
        #expect(EngineChoice.apple.slug == "apple")
    }

    @Test("Every choice round-trips through its slug")
    func roundTrip() {
        for choice in EngineChoice.allCases {
            #expect(EngineChoice(rawValue: choice.slug) == choice)
        }
    }

    @Test("Parakeet 160 ms is the default the measurements chose")
    func defaultEngine() {
        #expect(Sidecar.Config().engine == .fluid160)
        #expect(Service.Config().sidecar.engine == .fluid160)
    }
}

@Suite("Engine availability")
struct EngineAvailabilityTests {
    private func macOS(_ major: Int) -> OperatingSystemVersion {
        OperatingSystemVersion(majorVersion: major, minorVersion: 0, patchVersion: 0)
    }

    /// `apple` is `SpeechAnalyzer`, which is macOS 26. The check is a pure
    /// function of the version so it can be asserted without an engine — and
    /// so `available` on the wire is the same list on every Mac of one version.
    @Test("Parakeet runs everywhere the package does")
    func parakeet() {
        for major in [14, 15, 26] {
            #expect(EngineChoice.fluid160.isAvailable(on: macOS(major)))
            #expect(EngineChoice.fluid320.isAvailable(on: macOS(major)))
            #expect(EngineChoice.fluid1280.isAvailable(on: macOS(major)))
        }
    }

    @Test("Apple needs macOS 26")
    func apple() {
        #expect(!EngineChoice.apple.isAvailable(on: macOS(14)))
        #expect(!EngineChoice.apple.isAvailable(on: macOS(15)))
        #if compiler(>=6.2)
        #expect(EngineChoice.apple.isAvailable(on: macOS(26)))
        #expect(EngineChoice.apple.isAvailable(on: macOS(27)))
        #endif
    }

    @Test("The available list keeps the popover's order and never invents an engine")
    func available() {
        let available = EngineChoice.available
        #expect(available.first == .fluid160)
        #expect(available == EngineChoice.allCases.filter { available.contains($0) })
        #expect(available.contains(.apple) == EngineChoice.apple.isAvailable)
    }
}

/// `GET /engine`, `POST /engine`, `engineId` on `/status` and the `engine`
/// event — over real sockets, with capture through a session that opens no
/// microphone.
@Suite("Engine route", .serialized)
struct EngineRouteTests {
    private let scratch = Scratch()

    private func temporaryDirectory() -> URL {
        scratch.directory()
    }

    /// Both transports up on random spare ports, retried. `sessions` counts
    /// every capture session made, which is how a restart is observed.
    private func running(sessions: OSAllocatedUnfairLock<Int>? = nil) throws -> Service {
        var lastError: Error?
        for _ in 0..<5 {
            let base = UInt16.random(in: 20000...60000)
            let config = Service.Config(
                httpPort: base, wsPort: base + 1,
                tokenStore: TokenStore(
                    fileURL: temporaryDirectory().appendingPathComponent("token")),
                makeSession: { _, _ in
                    sessions?.withLock { $0 += 1 }
                    return ScriptedSession()
                })
            let service = Service(config: config) { _ in }
            do {
                try service.bind()
                return service
            } catch {
                lastError = error
            }
        }
        throw lastError!
    }

    private func request(
        _ service: Service, _ method: String, _ path: String, body: String? = nil
    ) async throws -> (Int, [String: JSONValue]) {
        var request = URLRequest(
            url: URL(string: "http://127.0.0.1:\(service.config.httpPort)\(path)")!)
        request.httpMethod = method
        request.setValue("Bearer \(service.token!)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(body.utf8)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = try JSONDecoder().decode([String: JSONValue].self, from: data)
        return ((response as! HTTPURLResponse).statusCode, json)
    }

    /// `/status`, without `uptime`, which ticks between two reads.
    private func status(_ service: Service) async throws -> [String: JSONValue] {
        try await request(service, "GET", "/status").1.filter { $0.key != "uptime" }
    }

    @Test("GET /engine answers the slug, the label and what this Mac can run")
    func get() async throws {
        let service = try running()
        defer { service.shutdown() }
        let (code, engine) = try await request(service, "GET", "/engine")
        #expect(code == 200)
        #expect(engine["engine"] == .string("fluid160"))
        #expect(engine["label"] == .string("Parakeet 160 ms"))
        #expect(engine["available"] == .array(EngineChoice.available.map { .string($0.slug) }))
        #expect(try await status(service)["engineId"] == .string("fluid160"))
    }

    @Test("POST /engine with a known slug answers it, and /status agrees")
    func post() async throws {
        let service = try running()
        defer { service.shutdown() }
        let (code, engine) = try await request(
            service, "POST", "/engine", body: #"{"engine": "fluid1280"}"#)
        #expect(code == 200)
        #expect(engine["engine"] == .string("fluid1280"))
        #expect(engine["label"] == .string("Parakeet 1280 ms"))
        #expect(service.engineChoice == .fluid1280)
        let status = try await status(service)
        #expect(status["engineId"] == .string("fluid1280"))
        #expect(status["engine"] == .string("Parakeet 1280 ms"))
        #expect(status["state"] == .string("idle"), "a switch while idle starts nothing")
    }

    @Test("An unknown slug is 400 in the error shape, and /status is unchanged")
    func unknown() async throws {
        let service = try running()
        defer { service.shutdown() }
        let before = try await status(service)
        let (code, answer) = try await request(
            service, "POST", "/engine", body: #"{"engine": "whisper"}"#)
        #expect(code == 400)
        guard case .string(let message)? = answer["error"] else {
            Issue.record("no error field: \(answer)")
            return
        }
        #expect(message.contains("whisper"))
        #expect(service.engineChoice == .fluid160)
        #expect(try await status(service) == before)
    }

    @Test(
        "A body that is not {\"engine\": …} is 400",
        arguments: [nil, "", "{}", "not json", #"{"engine": 160}"#, #"["fluid320"]"#])
    func malformed(_ body: String?) async throws {
        let service = try running()
        defer { service.shutdown() }
        let (code, answer) = try await request(service, "POST", "/engine", body: body)
        #expect(code == 400)
        #expect(answer["error"] != nil)
        #expect(service.engineChoice == .fluid160)
    }

    @Test("An engine this Mac cannot run is refused rather than failing at the next start")
    func unavailable() async throws {
        let service = try running()
        defer { service.shutdown() }
        for choice in EngineChoice.allCases where !choice.isAvailable {
            let (code, _) = try await request(
                service, "POST", "/engine", body: #"{"engine": "\#(choice.slug)"}"#)
            #expect(code == 400)
            #expect(service.engineChoice == .fluid160)
            #expect(throws: EngineError.unavailable(choice)) { try service.use(engine: choice) }
        }
    }

    @Test("The event arrives on /events after a switch, and not for the same engine again")
    func event() async throws {
        let service = try running()
        defer { service.shutdown() }
        let (bytes, response) = try await URLSession.shared.bytes(
            from: URL(
                string:
                    "http://127.0.0.1:\(service.config.httpPort)/events?access_token=\(service.token!)"
            )!)
        #expect((response as! HTTPURLResponse).statusCode == 200)
        var lines = bytes.lines.makeAsyncIterator()
        #expect(try await lines.next() == ": connected")
        while service.status().clients == 0 { try await Task.sleep(for: .milliseconds(10)) }

        // The same engine again: nothing to announce, so the next line on
        // the stream must be the real switch that follows.
        #expect(
            try await request(service, "POST", "/engine", body: #"{"engine": "fluid160"}"#).0 == 200
        )
        #expect(
            try await request(service, "POST", "/engine", body: #"{"engine": "fluid320"}"#).0 == 200
        )
        let line = try #require(try await lines.next())
        #expect(line.hasPrefix("data: "))
        let event = try JSONDecoder().decode(
            [String: JSONValue].self, from: Data(line.dropFirst(6).utf8))
        #expect(event["event"] == .string("engine"))
        #expect(event["engine"] == .string("fluid320"))
        #expect(event["label"] == .string("Parakeet 320 ms"))
        #expect(event["type"] == nil, "frames have type; the event does not")
    }

    @Test("Switching while listening is a stop and a start on the new engine")
    func restart() async throws {
        let sessions = OSAllocatedUnfairLock(initialState: 0)
        let service = try running(sessions: sessions)
        defer { service.shutdown() }
        let changes = OSAllocatedUnfairLock<[EngineChoice]>(initialState: [])
        service.onEngineChanged = { choice in changes.withLock { $0.append(choice) } }

        service.startListening()
        while !service.isListening { try await Task.sleep(for: .milliseconds(10)) }
        #expect(sessions.withLock { $0 } == 1)

        let (code, _) = try await request(
            service, "POST", "/engine", body: #"{"engine": "fluid320"}"#)
        #expect(code == 200)
        while !service.isListening { try await Task.sleep(for: .milliseconds(10)) }
        #expect(sessions.withLock { $0 } == 2, "a second session was made for the new engine")
        #expect(service.engineChoice == .fluid320)
        #expect(try await status(service)["engineId"] == .string("fluid320"))
        #expect(changes.withLock { $0 } == [.fluid320])
    }
}
