import Foundation
import SonoclesCore

// sonocles-cli — the measurement instrument.
//
//   swift run -c release sonocles-cli [--engine fluid160|fluid320|fluid1280|apple]
//                                     [--http 7357] [--ws 7358]
//                                     [--no-http] [--no-ws] [--idle]
//                                     [--locale en-CA] [--tap 4096]
//                                     [--plain] [--quiet]
//
// Not a lesser version of the app: it drives the identical `Service`, and it is
// how every latency figure in docs/ENGINES.md was produced — so any claim about
// this project can be re-run rather than believed.

var config = Service.Config()
var plain = false
var quiet = false
var idle = false

do {
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let a = it.next() {
        switch a {
        case "--engine":
            if let v = it.next(), let choice = EngineChoice(rawValue: v) { config.sidecar.engine = choice }
        case "--http", "--sse": if let v = it.next(), let p = UInt16(v) { config.httpPort = p }
        case "--ws": if let v = it.next(), let p = UInt16(v) { config.wsPort = p }
        case "--no-http", "--no-sse": config.http = false
        case "--no-ws": config.websocket = false
        case "--idle": idle = true
        case "--locale": if let v = it.next() { config.sidecar.locale = v }
        case "--tap": if let v = it.next(), let n = UInt32(v) { config.sidecar.tapFrames = n }
        case "--plain": plain = true
        case "--quiet": quiet = true
        case "--help", "-h":
            print("""
            sonocles-cli — on-device speech sidecar

              --engine   fluid160 (default) · fluid320 · fluid1280 · apple
              --http     HTTP/SSE port (default 7357)
              --ws       WebSocket port (default 7358)
              --no-http  do not start the HTTP transport
              --no-ws    do not start the WebSocket transport
              --idle     bind sockets but do not start capture until POST /start
              --locale   BCP-47, apple engine only (default: system)
              --tap      mic tap frames (default 4096)
              --plain    one line per event, no ANSI
              --quiet    finals only, no partial trace

            Control API (Basic auth when configured in the app):
              GET  /events   server-sent event stream
              GET  /status   listening state, engine, client count, uptime
              POST /start    begin capture
              POST /stop     end capture
            """)
            exit(0)
        default: break
        }
    }
}

let monitor = Monitor(plain: plain, quiet: quiet)
monitor.start()

let service = Service(config: config) { monitor.note($0) }

service.onLevel = { monitor.observe(peak: $0) }
service.onFrame = { hypothesis, frame, nanos in
    if hypothesis.isFinal {
        monitor.final(hypothesis.text, lagMs: frame.lagMs, audio: hypothesis.audio, at: nanos)
    } else {
        monitor.partial(hypothesis.text, lagMs: frame.lagMs, audio: hypothesis.audio, at: nanos)
    }
}

do {
    try service.bind()
} catch {
    monitor.note("could not bind: \(error.localizedDescription)")
    exit(1)
}

var endpoints: [String] = []
if config.http { endpoints.append("http http://127.0.0.1:\(config.httpPort) (/events /status /start /stop)") }
if config.websocket { endpoints.append("ws ws://127.0.0.1:\(config.wsPort)") }
monitor.note(endpoints.isEmpty ? "no transports — measuring only" : endpoints.joined(separator: " · "))
monitor.note(CredentialStore.current() == nil
    ? "control API is open (no credentials configured)"
    : "control API requires Basic auth")

if idle {
    monitor.note("idle — POST /start to begin capture")
} else {
    service.startListening()
}

monitor.note("columns: elapsed · kind · gap since last arrival · Δwords · lag behind live edge")

RunLoop.main.run()
