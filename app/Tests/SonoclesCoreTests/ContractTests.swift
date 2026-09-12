@preconcurrency import AVFoundation
import Foundation
import Testing

@testable import SonoclesCore

/// The contract test: bind the real `Service`, hit every path in
/// `docs/openapi.yaml`, and validate the live responses against the schemas
/// the YAML declares. Drift either way — an undocumented field, a missing one,
/// a wrong type, a path the server serves but the YAML omits — fails here, so
/// the site's generated reference and the code cannot disagree without CI
/// saying so. The pattern is Rheocles' `ContractTests`.
///
/// Capture is never real. `POST /start` is driven through a session that
/// emits one frame and opens no microphone, so the test needs no grant and
/// can raise no dialog — and the frame it emits is validated against the
/// `Frame` schema on the way through `GET /events`.
///
/// The YAML is the source of truth. macOS ships Ruby with a YAML and JSON
/// library, so the test converts it to JSON with a one-liner rather than
/// taking a Swift YAML dependency.
@Suite("OpenAPI contract", .serialized)
struct ContractTests {
    // MARK: Load the spec

    static func specURL() -> URL {
        // docs/ is two up from app/; walk up until it is found.
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            dir.deleteLastPathComponent()
            let candidate = dir.appendingPathComponent("docs/openapi.yaml")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return URL(fileURLWithPath: "docs/openapi.yaml")
    }

    static func loadSpec() throws -> [String: Any] {
        let yaml = specURL()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ruby")
        process.arguments = [
            "-ryaml", "-rjson", "-e", "print JSON.dump(YAML.load_file(ARGV[0]))", yaml.path,
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ContractError.specUnreadable }
        return json
    }

    enum ContractError: Error { case specUnreadable, noFrame }

    // MARK: A tiny JSON Schema validator (the subset the spec uses)

    struct Validator {
        let spec: [String: Any]

        func resolve(_ schema: [String: Any]) -> [String: Any] {
            guard let ref = schema["$ref"] as? String else { return schema }
            // "#/components/schemas/Name"
            var node: Any = spec
            for part in ref.split(separator: "/").dropFirst() {
                node = (node as? [String: Any])?[String(part)] ?? [:]
            }
            return (node as? [String: Any]).map(resolve) ?? [:]
        }

        /// Returns a failure description, or nil if `value` matches `schema`.
        func check(_ value: Any, against rawSchema: [String: Any], path: String) -> String? {
            let schema = resolve(rawSchema)
            if let const = schema["const"] {
                if "\(const)" != "\(value)" {
                    return "\(path): expected const \(const), got \(value)"
                }
            }
            if let type = schema["type"] as? String {
                if let mismatch = typeMismatch(value, type: type, path: path) { return mismatch }
            }
            if let enumValues = schema["enum"] as? [Any] {
                let strings = enumValues.map { "\($0)" }
                if !strings.contains("\(value)") {
                    return "\(path): \(value) not in enum \(strings)"
                }
            }
            if let type = schema["type"] as? String, type == "object",
                let object = value as? [String: Any]
            {
                let properties = (schema["properties"] as? [String: Any]) ?? [:]
                for required in (schema["required"] as? [String]) ?? []
                where object[required] == nil {
                    return "\(path): missing required '\(required)'"
                }
                if (schema["additionalProperties"] as? Bool) == false {
                    for key in object.keys where properties[key] == nil {
                        return "\(path): undocumented property '\(key)'"
                    }
                }
                for (key, sub) in properties {
                    guard let present = object[key], !(present is NSNull) else { continue }
                    if let subSchema = sub as? [String: Any],
                        let fail = check(present, against: subSchema, path: "\(path).\(key)")
                    {
                        return fail
                    }
                }
            }
            if let type = schema["type"] as? String, type == "array", let array = value as? [Any],
                let items = schema["items"] as? [String: Any]
            {
                for (i, element) in array.enumerated() {
                    if let fail = check(element, against: items, path: "\(path)[\(i)]") {
                        return fail
                    }
                }
            }
            return nil
        }

        private func typeMismatch(_ value: Any, type: String, path: String) -> String? {
            switch type {
            case "object": return value is [String: Any] ? nil : "\(path): expected object"
            case "array": return value is [Any] ? nil : "\(path): expected array"
            case "string": return value is String ? nil : "\(path): expected string, got \(value)"
            case "boolean": return value is Bool ? nil : "\(path): expected boolean"
            case "integer":
                return
                    (value is Int || (value as? NSNumber).map { !CFNumberIsFloatType($0) } == true)
                    ? nil : "\(path): expected integer, got \(value)"
            case "number": return value is NSNumber ? nil : "\(path): expected number"
            default: return nil
            }
        }
    }

    // MARK: The server under test

    /// A directory of our own, so nothing here touches the real token file.
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sonocles-contract-\(UUID().uuidString)", isDirectory: true)
    }

    /// Both transports up on random spare ports, retried: something else on
    /// the machine may hold the pair. Capture goes through `ScriptedSession`.
    private func running() throws -> Service {
        var lastError: Error?
        for _ in 0..<5 {
            let base = UInt16.random(in: 20000...60000)
            let config = Service.Config(
                httpPort: base, wsPort: base + 1,
                tokenStore: TokenStore(
                    fileURL: temporaryDirectory().appendingPathComponent("token")),
                makeSession: { _, _ in ScriptedSession() })
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
        _ service: Service, _ method: String, _ path: String, token: String?,
        body: String? = nil
    ) async throws -> (Int, String, Data) {
        var request = URLRequest(
            url: URL(string: "http://127.0.0.1:\(service.config.httpPort)\(path)")!)
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(body.utf8)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as! HTTPURLResponse
        return (http.statusCode, http.value(forHTTPHeaderField: "Content-Type") ?? "", data)
    }

    /// The response schema a spec operation declares for a status code.
    private func responseSchema(
        _ spec: [String: Any], path: String, method: String, status: Int, contentType: String
    ) -> [String: Any]? {
        guard let paths = spec["paths"] as? [String: Any],
            let op = (paths[path] as? [String: Any])?[method] as? [String: Any],
            let responses = op["responses"] as? [String: Any],
            let response = responses["\(status)"] as? [String: Any]
        else { return nil }
        // `$ref` at the response level (the shared Unauthorized).
        let resolved = Validator(spec: spec).resolve(response)
        guard let content = resolved["content"] as? [String: Any],
            let media = content[
                contentType.split(separator: ";").first.map(String.init) ?? contentType]
                as? [String: Any]
        else { return nil }
        return media["schema"] as? [String: Any]
    }

    @Test("Every documented path's live response validates against its schema")
    func contract() async throws {
        let spec = try Self.loadSpec()
        let validator = Validator(spec: spec)
        let service = try running()
        defer { service.shutdown() }
        let token = try #require(service.token)

        var seen = Set<String>()
        func validate(
            _ method: String, _ path: String, _ specPath: String, token: String?, expect: Int,
            body: String? = nil
        ) async throws {
            let (status, contentType, data) = try await request(
                service, method, path, token: token, body: body)
            if token != nil { seen.insert("\(method) \(specPath)") }
            #expect(status == expect, "\(method) \(specPath) answered \(status)")
            guard contentType.hasPrefix("application/json") else {
                Issue.record(Comment(rawValue: "\(method) \(specPath): not JSON (\(contentType))"))
                return
            }
            guard
                let schema = responseSchema(
                    spec, path: specPath, method: method.lowercased(), status: status,
                    contentType: "application/json")
            else {
                Issue.record(Comment(rawValue: "\(method) \(specPath): no schema for \(status)"))
                return
            }
            let json = try JSONSerialization.jsonObject(with: data)
            if let fail = validator.check(json, against: schema, path: "\(method) \(specPath)") {
                Issue.record(Comment(rawValue: fail))
            }
        }

        // The 401 shape, on the shared response every path references.
        try await validate("GET", "/", "/", token: nil, expect: 401)
        try await validate("GET", "/status", "/status", token: "not-the-token", expect: 401)

        try await validate("GET", "/", "/", token: token, expect: 200)
        try await validate("GET", "/status", "/status", token: token, expect: 200)

        // Attach to the stream before starting, the way a consumer does, so
        // the frame the scripted session emits on start is what arrives.
        let events = URL(
            string: "http://127.0.0.1:\(service.config.httpPort)/events?access_token=\(token)")!
        let (bytes, eventsResponse) = try await URLSession.shared.bytes(from: events)
        let http = eventsResponse as! HTTPURLResponse
        #expect(http.statusCode == 200)
        #expect(http.value(forHTTPHeaderField: "Content-Type") == "text/event-stream")
        seen.insert("GET /events")

        try await validate("POST", "/start", "/start", token: token, expect: 200)

        // The first `data:` line is a Frame and must match the schema the
        // YAML names in x-events, which is how the docs describe the stream.
        var frame: Any?
        for try await line in bytes.lines where line.hasPrefix("data: ") {
            frame = try JSONSerialization.jsonObject(with: Data(line.dropFirst(6).utf8))
            break
        }
        let frameSchema = try #require(
            ((spec["components"] as? [String: Any])?["schemas"] as? [String: Any])?["Frame"]
                as? [String: Any])
        if let fail = validator.check(try #require(frame), against: frameSchema, path: "Frame") {
            Issue.record(Comment(rawValue: fail))
        }

        // The engine routes, while listening: the switch is a stop and a
        // start, and the engine event goes out on the stream a consumer is
        // already holding. The restarted scripted session emits its frame
        // too, in no fixed order with the event, so read until the event.
        try await validate("GET", "/engine", "/engine", token: token, expect: 200)
        try await validate(
            "POST", "/engine", "/engine", token: token, expect: 200,
            body: #"{"engine": "fluid320"}"#)
        var event: Any?
        for try await line in bytes.lines where line.hasPrefix("data: ") {
            let json = try JSONSerialization.jsonObject(with: Data(line.dropFirst(6).utf8))
            guard (json as? [String: Any])?["event"] != nil else { continue }
            event = json
            break
        }
        let eventSchema = try #require(
            ((spec["components"] as? [String: Any])?["schemas"] as? [String: Any])?["EngineEvent"]
                as? [String: Any])
        if let fail = validator.check(
            try #require(event), against: eventSchema, path: "EngineEvent")
        {
            Issue.record(Comment(rawValue: fail))
        }
        // The documented 400, in the error shape.
        try await validate(
            "POST", "/engine", "/engine", token: token, expect: 400,
            body: #"{"engine": "whisper"}"#)
        try await validate("GET", "/status", "/status", token: token, expect: 200)

        try await validate("POST", "/stop", "/stop", token: token, expect: 200)
        #expect(!service.isListening)

        // Rotate last: it invalidates the token everything above used.
        try await validate("POST", "/token/rotate", "/token/rotate", token: token, expect: 200)
        #expect(try await request(service, "GET", "/", token: token).0 == 401)

        // Coverage: every path in the YAML was exercised.
        let documented = Set(
            ((spec["paths"] as? [String: Any]) ?? [:]).flatMap { path, ops in
                ((ops as? [String: Any]) ?? [:]).keys
                    .filter { ["get", "post", "patch", "put", "delete"].contains($0) }
                    .map { "\($0.uppercased()) \(path)" }
            })
        let missing = documented.subtracting(seen)
        #expect(missing.isEmpty, "documented but not exercised: \(missing.sorted())")
    }
}

/// A capture session that opens nothing. `start` emits one frame — the one
/// the docs use as their example — so the event stream has something to
/// validate; then it reports listening.
final class ScriptedSession: CaptureSession, @unchecked Sendable {
    let engineName = "Scripted"
    let hardwareFormat: AVAudioFormat? = nil
    let engineFormat: AVAudioFormat? = nil
    var onFrame: (@Sendable (Hypothesis, Frame, UInt64) -> Void)?
    var onPreparation: (@Sendable (Preparation) -> Void)?
    var onLevel: (@Sendable (Double) -> Void)?

    func start() async throws {
        let hypothesis = Hypothesis(text: "the menu bar", isFinal: false, audio: 40.28...40.8)
        onFrame?(hypothesis, Frame(hypothesis: hypothesis, seq: 3, lagMs: 200), 0)
    }

    func stop() {}
}
