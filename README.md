# Sonocles

An on-device speech sidecar for the Mac. It listens to your microphone,
transcribes on the Neural Engine, and streams recognised words — with the audio
timestamps that say when each was actually spoken — over SSE or WebSocket.

It knows nothing about your script. It just streams text.

```
data: {"type":"partial","text":"the menu bar","audioStart":40.28,"audioEnd":40.8,"lagMs":200,"seq":3}
data: {"type":"partial","text":"the menu bar app","audioStart":40.28,"audioEnd":41.0,"lagMs":200,"seq":4}
```

One word per frame, roughly every 200 ms, about 180 ms behind what you just
said. Apple's own Speech framework delivers the same sentence in four bursts,
3.7 seconds apart — which is why this exists. The numbers are in
[docs/ENGINES.md](docs/ENGINES.md) and the baseline is still one flag away, so
the comparison can be re-run rather than believed.

## Quick start

```bash
make run          # the CLI monitor — speak, watch words arrive
make launch       # build, sign and start the menu bar app
make test         # the suite
make help         # everything else
```

`make run` prints a live trace: each arrival with the gap since the last one,
the words it added, and how far behind the live audio edge it was.

```
[  9.320s] part   +294ms  Δ +1  lag   +200ms audio    4.24–   8.00  …spoke without pausing so that we can watch
```

The bottom line is a level meter driven straight from the audio thread. That is
not decoration: if the meter moves and no text appears, capture is fine and the
engine is late. If neither moves, check the microphone.

## Layout

A monorepo. Each directory builds independently.

```
app/     the macOS app, the CLI, and the core they share (Swift)
docs/    findings, protocol, decisions
site/    marketing + documentation site (Laravel, deployed on Laravel Cloud)
```

`app/` is a plain SwiftPM package — `swift build` inside it needs nothing from
the rest of the tree. Anything deploying `site/` points at that subdirectory and
never sees the Swift.

Inside `app/`:

| | |
|---|---|
| `SonoclesCore` | engines, capture, clock, transports. No UI, no terminal. |
| `sonocles-cli` | the measurement instrument |
| `Sonocles` | the menu bar app |

The CLI and the app drive the **same** `Service`. Every latency claim in the
docs came out of the CLI, so the thing being measured is the thing that ships.

## Consuming the stream

Both transports carry identical JSON and both come up when the app launches —
not when capture starts. Run both; they are not alternatives.

```js
const es = new EventSource('http://127.0.0.1:7357/events')
const ws = new WebSocket('ws://127.0.0.1:7358')
```

Use `audioEnd`, not `ts`. Arrival time carries the jitter of the delivery
schedule on top of the actual timing; `audioEnd` is when the words were said.
A missing `lagMs` means *unmeasured*, never zero.

Full details in [docs/PROTOCOL.md](docs/PROTOCOL.md).

## Controlling it

```bash
make status       # idle · starting · listening
make start
make stop
```

Or directly, which is the point — anything can drive it:

```bash
curl -X POST http://127.0.0.1:7357/start
curl http://127.0.0.1:7357/status
```

`/status`, `/start` and `/stop` take HTTP Basic auth, configured in the app's
popover and stored in the Keychain. `/events` is deliberately left open:
`EventSource` cannot send an `Authorization` header, so locking the stream would
mean credentials in a URL. The routes that change state carry the lock.

Once credentials are set: `make status USER=sono PASS=…`

## Requirements

macOS 14+ on Apple Silicon. The Apple engine, kept only as a baseline, needs
macOS 26.

Models download on first run (~219 MB, cached in
`~/Library/Application Support/FluidAudio`).

## A note on the microphone

If it runs and hears nothing, check `make run` against the same audio before
suspecting anything else. A CLI inherits its terminal's microphone grant; a
signed `.app` has its own identity and needs both
`NSMicrophoneUsageDescription` **and** the
`com.apple.security.device.audio-input` entitlement. With the hardened runtime
and no entitlement, the app cannot record and cannot ask to — it simply never
appears in System Settings. `AVAudioEngine` never prompts on its own; it just
returns silence forever.

That failure looks exactly like a healthy pipeline. It cost a session to find,
and it is written up in [docs/ENGINES.md](docs/ENGINES.md) so it costs nothing
next time.
