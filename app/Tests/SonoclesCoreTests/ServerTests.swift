import Foundation
import Testing
import os

@testable import SonoclesCore

/// Real sockets on spare ports, spoken to the way a consumer does. Capture is
/// never started: these bind, ask, and stop, and no test here needs a
/// microphone.
@Suite("Server", .serialized)
struct ServerTests {
    private let scratch = Scratch()

    /// A directory of our own, so nothing here touches the real token file.
    private func temporaryDirectory() -> URL {
        scratch.directory()
    }

    /// Both transports up on random spare ports, retried: something else on
    /// the machine may hold the pair.
    private func running() throws -> Service {
        var lastError: Error?
        for _ in 0..<5 {
            let base = UInt16.random(in: 20000...60000)
            let config = Service.Config(
                httpPort: base, wsPort: base + 1,
                tokenStore: TokenStore(
                    fileURL: temporaryDirectory().appendingPathComponent("token")))
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

    private func url(_ service: Service, _ path: String) -> URL {
        URL(string: "http://127.0.0.1:\(service.config.httpPort)\(path)")!
    }

    private func request(
        _ service: Service, _ method: String, _ path: String, token: String?
    ) async throws -> (HTTPURLResponse, Data) {
        var request = URLRequest(url: url(service, path))
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        return (response as! HTTPURLResponse, data)
    }

    private func get(_ service: Service, _ path: String, token: String?) async throws -> Int {
        try await request(service, "GET", path, token: token).0.statusCode
    }

    private func error(_ data: Data) throws -> String? {
        try JSONDecoder().decode([String: String].self, from: data)["error"]
    }

    @Test("The token file is created on bind and is what the service reports")
    func tokenFile() throws {
        let service = try running()
        defer { service.shutdown() }
        let token = try #require(service.token)
        #expect(token.count == 64)
        let path = service.config.tokenStore.fileURL.path
        #expect(
            try String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .newlines)
                == token)
    }

    @Test("GET / answers discovery with the bearer token")
    func discovery() async throws {
        let service = try running()
        defer { service.shutdown() }
        let (response, data) = try await request(service, "GET", "/", token: service.token)
        #expect(response.statusCode == 200)
        let discovery = try JSONDecoder().decode(HTTPServer.Discovery.self, from: data)
        #expect(discovery.name == "Sonocles")
        #expect(discovery.auth == "bearer")
        #expect(discovery.version == Service.version)
        #expect(discovery.ports.http == service.config.httpPort)
        #expect(discovery.ports.ws == service.config.wsPort)
    }

    @Test("No token, or the wrong token, is 401 with the error shape and a challenge")
    func unauthorized() async throws {
        let service = try running()
        defer { service.shutdown() }
        let (response, data) = try await request(service, "GET", "/", token: nil)
        #expect(response.statusCode == 401)
        #expect(try error(data) == "authentication required")
        #expect(
            response.value(forHTTPHeaderField: "WWW-Authenticate") == "Bearer realm=\"Sonocles\"")
        #expect(try await get(service, "/", token: "nope") == 401)
        #expect(try await get(service, "/status", token: nil) == 401)
        #expect(try await get(service, "/events", token: nil) == 401)
        #expect(try await request(service, "POST", "/start", token: nil).0.statusCode == 401)
    }

    @Test("GET /status is idle with the token, and never started capture to say so")
    func status() async throws {
        let service = try running()
        defer { service.shutdown() }
        let (response, data) = try await request(service, "GET", "/status", token: service.token)
        #expect(response.statusCode == 200)
        let status = try JSONDecoder().decode([String: JSONValue].self, from: data)
        #expect(status["state"] == .string("idle"))
        #expect(status["listening"] == .bool(false))
        #expect(!service.isListening)
    }

    @Test("Unknown routes are 404 with the token and 401 without it")
    func routing() async throws {
        let service = try running()
        defer { service.shutdown() }
        #expect(try await get(service, "/nope", token: service.token) == 404)
        #expect(try await get(service, "/nope", token: nil) == 401)
    }

    /// A browser sends the preflight before it will attach the header, so it
    /// is the one request that cannot be behind the token.
    @Test("OPTIONS preflight is answered without the token")
    func preflight() async throws {
        let service = try running()
        defer { service.shutdown() }
        #expect(try await request(service, "OPTIONS", "/start", token: nil).0.statusCode == 204)
    }

    @Test("GET /events opens with access_token in the query, as EventSource sends it")
    func eventsByQuery() async throws {
        let service = try running()
        defer { service.shutdown() }
        let token = try #require(service.token)
        let (bytes, response) = try await URLSession.shared.bytes(
            from: url(service, "/events?access_token=\(token)"))
        let http = response as! HTTPURLResponse
        #expect(http.statusCode == 200)
        #expect(http.value(forHTTPHeaderField: "Content-Type") == "text/event-stream")
        var lines = bytes.lines.makeAsyncIterator()
        #expect(try await lines.next() == ": connected")
        #expect(try await get(service, "/events?access_token=nope", token: nil) == 401)
    }

    @Test("POST /token/rotate issues a new token and the old one is dead")
    func rotate() async throws {
        let service = try running()
        defer { service.shutdown() }
        let old = try #require(service.token)
        let (response, data) = try await request(service, "POST", "/token/rotate", token: old)
        #expect(response.statusCode == 200)
        let new = try #require(try JSONDecoder().decode([String: String].self, from: data)["token"])
        #expect(new.count == 64)
        #expect(new != old)
        #expect(service.token == new)
        #expect(try await get(service, "/status", token: old) == 401)
        #expect(try await get(service, "/status", token: new) == 200)
        let path = service.config.tokenStore.fileURL.path
        #expect(
            try String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .newlines)
                == new)
    }
}

/// The transports on their own, for what needs `broadcast`: the service keeps
/// them private, and the point here is who receives a frame, not what it says.
@Suite("Transports", .serialized)
struct TransportTests {
    private let token = String(repeating: "ab", count: 32)

    private func http() throws -> HTTPServer {
        var lastError: Error?
        for _ in 0..<5 {
            do {
                let server = try HTTPServer(
                    port: UInt16.random(in: 20000...60000), auth: BearerAuth(token: token))
                try server.start()
                return server
            } catch {
                lastError = error
            }
        }
        throw lastError!
    }

    private func websocket() throws -> WebSocketServer {
        var lastError: Error?
        for _ in 0..<5 {
            do {
                let server = try WebSocketServer(
                    port: UInt16.random(in: 20000...60000), auth: BearerAuth(token: token))
                try server.start()
                return server
            } catch {
                lastError = error
            }
        }
        throw lastError!
    }

    @Test("SSE: an authenticated stream receives what is broadcast")
    func sseBroadcast() async throws {
        let server = try http()
        defer { server.stop() }
        let (bytes, response) = try await URLSession.shared.bytes(
            from: URL(string: "http://127.0.0.1:\(server.port)/events?access_token=\(token)")!)
        #expect((response as! HTTPURLResponse).statusCode == 200)
        var lines = bytes.lines.makeAsyncIterator()
        #expect(try await lines.next() == ": connected")
        // Registration happens on the server's queue after the headers go
        // out; wait for it rather than racing the broadcast against it.
        while server.clientCount == 0 { try await Task.sleep(for: .milliseconds(10)) }
        server.broadcast(#"{"type":"final","text":"hello"}"#)
        #expect(try await lines.next() == #"data: {"type":"final","text":"hello"}"#)
    }

    private func socket(_ server: WebSocketServer) -> URLSessionWebSocketTask {
        let task = URLSession.shared.webSocketTask(
            with: URL(string: "ws://127.0.0.1:\(server.port)/")!)
        task.resume()
        return task
    }

    private func receive(_ task: URLSessionWebSocketTask) async throws -> [String: JSONValue] {
        guard case .string(let reply) = try await task.receive() else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try JSONDecoder().decode([String: JSONValue].self, from: Data(reply.utf8))
    }

    private func roundTrip(_ task: URLSessionWebSocketTask, _ json: String) async throws
        -> [String: JSONValue]
    {
        try await task.send(.string(json))
        return try await receive(task)
    }

    @Test("WebSocket: frames are 401 until the auth frame, and a wrong token stays 401")
    func authFrame() async throws {
        let server = try websocket()
        defer { server.stop() }
        let task = socket(server)
        let refused = try await roundTrip(task, #"{"id": "a", "method": "GET", "path": "/"}"#)
        #expect(refused["status"] == .number(401))
        #expect(refused["id"] == .string("a"))
        #expect(refused["body"] == .object(["error": .string("authentication required")]))
        let junk = try await roundTrip(task, "not json")
        #expect(junk["status"] == .number(401))
        #expect(junk["id"] == .null)
        let wrong = try await roundTrip(task, #"{"auth": "nope"}"#)
        #expect(wrong["status"] == .number(401))
        let ok = try await roundTrip(task, #"{"id": 7, "auth": "\#(token)"}"#)
        #expect(ok["status"] == .number(200))
        #expect(ok["id"] == .number(7))
        #expect(ok["body"] == .object(["authenticated": .bool(true)]))
        task.cancel(with: .normalClosure, reason: nil)
    }

    @Test("WebSocket: only authenticated clients receive a broadcast")
    func broadcast() async throws {
        let server = try websocket()
        defer { server.stop() }
        let paired = socket(server)
        let stranger = socket(server)
        let ok = try await roundTrip(paired, #"{"auth": "\#(token)"}"#)
        #expect(ok["status"] == .number(200))
        // The stranger is connected — its first frame is answered — but has
        // not authenticated.
        #expect(try await roundTrip(stranger, "{}")["status"] == .number(401))
        while server.clientCount < 2 { try await Task.sleep(for: .milliseconds(10)) }

        server.broadcast(#"{"type":"partial","text":"hello"}"#)
        let frame = try await receive(paired)
        #expect(frame["type"] == .string("partial"))
        #expect(frame["text"] == .string("hello"))

        // The stranger got nothing: its next frame in is the 401 to a fresh
        // ping, not the broadcast.
        #expect(try await roundTrip(stranger, "{}")["status"] == .number(401))
        paired.cancel(with: .normalClosure, reason: nil)
        stranger.cancel(with: .normalClosure, reason: nil)
    }

    @Test("WebSocket: after the auth frame, other frames reach onMessage")
    func onMessage() async throws {
        let server = try websocket()
        defer { server.stop() }
        let received = OSAllocatedUnfairLock<[String]>(initialState: [])
        server.onMessage = { text in received.withLock { $0.append(text) } }
        let task = socket(server)
        _ = try await roundTrip(task, #"{"auth": "\#(token)"}"#)
        try await task.send(.string(#"{"hello": "there"}"#))
        while received.withLock({ $0.isEmpty }) { try await Task.sleep(for: .milliseconds(10)) }
        #expect(received.withLock { $0 } == [#"{"hello": "there"}"#])
        task.cancel(with: .normalClosure, reason: nil)
    }
}
