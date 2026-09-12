import Foundation
import Testing

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
