<p align="center"><img src="https://raw.githubusercontent.com/artisan-build/sonocles/main/art/header.png" alt="Sonocles" width="900"></p>

<p align="center">
  <a href="https://github.com/artisan-build/sonocles/actions"><img src="https://github.com/artisan-build/sonocles/workflows/tests/badge.svg" alt="Build Status"></a>
  <a href="https://github.com/artisan-build/sonocles/blob/main/LICENSE"><img src="https://img.shields.io/github/license/artisan-build/sonocles" alt="License"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-1C1611" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Apple%20Silicon-required-C86F45" alt="Apple Silicon">
</p>

# Sonocles

**so-NOK-leez.** An on-device speech sidecar for the Mac. It listens to your
microphone and streams what you say — word by word, about 180&nbsp;milliseconds
behind you, with the audio timestamps that say when each word was actually
spoken.

Everything runs on the Neural Engine. Nothing leaves the machine. Free and open
source, MIT.

```
data: {"type":"partial","text":"the menu bar","audioStart":40.28,"audioEnd":40.8,"lagMs":200,"seq":3}
data: {"type":"partial","text":"the menu bar app","audioStart":40.28,"audioEnd":41.0,"lagMs":200,"seq":4}
```

## Why it exists

The speech-follow built into the teleprompter was fighting the encoder for CPU.
The prompter kept up; the audio did not, and dropped samples on a take you
cannot re-shoot are not a performance problem, they are a lost afternoon.

The Neural Engine was sitting idle the whole time. Moving the listening there
did not make it faster so much as make it **free** — it stopped taking anything
the recording needed.

It was built for [Pteroprompter](https://pteroprompter.com), which is still the
case it is tuned for. Nothing about it is prompter-shaped, though: it streams
words and timestamps to a socket, and what listens is your business.

## Download

[**Download the latest release**](https://github.com/artisan-build/sonocles/releases/latest/download/Sonocles.dmg)
— Apple Silicon, macOS 14+. That link always points at the current version.

Or build it yourself:

## Quick start

```bash
make run          # the CLI monitor — speak, watch words arrive
make launch       # build, sign and start the menu bar app
make test
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

There is also an HTTP control API — `GET /status`, `POST /start`, `POST /stop` —
behind optional Basic auth. Full details in
[docs/PROTOCOL.md](docs/PROTOCOL.md).

## Why not Apple's Speech framework

Because it delivers in fixed ~3.8 second blocks and no exposed knob changes
that.

| engine | arrival gap | behind live | words per arrival |
|---|---|---|---|
| Apple SpeechAnalyzer | 3747 ms | 0 ms, four times | 8.8 |
| Parakeet 320 ms | 302 ms | 540 ms | 2.3 |
| **Parakeet 160 ms** | **206 ms** | **180 ms** | **1.5** |

Measured, reproducible, and written up in [docs/ENGINES.md](docs/ENGINES.md).
The baseline is still one flag away — `make baseline` — so the comparison can be
re-run rather than taken on trust.

If what you actually want is dictation, use [Sonari](https://www.sonari.audio/).
It is very good, it runs locally too, and the use cases genuinely diverge:
Sonari is built around the moment you stop speaking, and this is built around
the moment you have not.

## Layout

A monorepo. Each directory builds independently.

```
app/     the macOS app, the CLI, and the core they share (Swift)
art/     header and plate sources
docs/    findings, protocol, brand, decisions
site/    the marketing page (a single static file)
```

`app/` is a plain SwiftPM package — `swift build` inside it needs nothing from
the rest of the tree.

## Requirements

Apple Silicon, macOS 14 or later. Models download on first run (~219 MB, cached
in `~/Library/Application Support/FluidAudio`). The Apple engine, kept only as
a baseline, needs macOS 26.

## A note on the microphone

If it runs and hears nothing, check `make run` against the same audio before
suspecting anything else. A CLI inherits its terminal's microphone grant; a
signed `.app` has its own identity and needs both `NSMicrophoneUsageDescription`
**and** the `com.apple.security.device.audio-input` entitlement. With the
hardened runtime and no entitlement, the app cannot record and cannot ask to —
it simply never appears in System Settings. `AVAudioEngine` never prompts on its
own; it just returns silence forever.

That failure looks exactly like a healthy pipeline. It is written up in
[docs/ENGINES.md](docs/ENGINES.md) so it costs nothing next time.

## Licence

MIT. See [LICENSE](LICENSE).

---

<p align="center">
  <sub>Built for <a href="https://pteroprompter.com">Pteroprompter</a> by
  <b>ProjektGopher Multimedia</b>, an <b>Artisan Build</b> property.</sub>
</p>
