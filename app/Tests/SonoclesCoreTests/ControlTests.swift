import Foundation
import Testing

@testable import SonoclesCore

/// The control API can switch on a microphone, so its lock is load-bearing.
@Suite("Basic auth")
struct CredentialsTests {
    private let credentials = Credentials(username: "sono", password: "s3cret")

    private func header(_ user: String, _ password: String) -> String {
        "Basic " + Data("\(user):\(password)".utf8).base64EncodedString()
    }

    @Test("Correct credentials are accepted")
    func accepts() {
        #expect(credentials.matches(header("sono", "s3cret")))
    }

    @Test("Wrong password is refused")
    func wrongPassword() {
        #expect(!credentials.matches(header("sono", "wrong")))
    }

    @Test("Wrong username is refused")
    func wrongUsername() {
        #expect(!credentials.matches(header("someone", "s3cret")))
    }

    @Test("A missing header is refused")
    func missing() {
        #expect(!credentials.matches(nil))
    }

    /// Curl and browsers disagree about capitalisation, and a scheme match that
    /// is case-sensitive would reject perfectly valid requests.
    @Test("The scheme is matched case-insensitively")
    func schemeCase() {
        let encoded = Data("sono:s3cret".utf8).base64EncodedString()
        #expect(credentials.matches("basic " + encoded))
        #expect(credentials.matches("BASIC " + encoded))
    }

    /// Malformed input must be refused, never crash: this parses bytes that
    /// arrived off a socket.
    @Test(
        "Malformed headers are refused without crashing",
        arguments: [
            "Basic", "Basic !!!not-base64!!!", "Bearer abc123", "", "Basic ",
        ])
    func malformed(_ value: String) {
        #expect(!credentials.matches(value))
    }

    /// A prefix of the real password must not pass. Guards the length check in
    /// the constant-time compare.
    @Test("A truncated password is refused")
    func truncated() {
        #expect(!credentials.matches(header("sono", "s3cre")))
    }
}

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
                "GET /status HTTP/1.1\r\nHost: 127.0.0.1:7357\r\nAuthorization: Basic abc\r\n\r\n"))

        #expect(request.method == "GET")
        #expect(request.path == "/status")
        #expect(request.headers["authorization"] == "Basic abc")
    }

    @Test("Header names are matched case-insensitively")
    func headerCase() throws {
        let request = try #require(parse("GET / HTTP/1.1\r\nAUTHORIZATION: Basic xyz\r\n\r\n"))

        #expect(request.headers["authorization"] == "Basic xyz")
    }

    /// No route uses a query string, so one must not turn /status into a 404.
    @Test("A query string is stripped from the path")
    func queryString() throws {
        let request = try #require(parse("GET /status?verbose=1 HTTP/1.1\r\nHost: x\r\n\r\n"))

        #expect(request.path == "/status")
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
