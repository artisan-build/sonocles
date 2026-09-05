# Why Parakeet and not Apple

Sonocles exists because Apple's Speech framework cannot follow a reader. This
is the evidence, and it can be re-run: `--engine apple` is still there for
exactly that reason.

## The measurement

One instrument (`sonocles-cli`), one audio source, one sentence. Driven by `say`
at 160 wpm — synthetic speech is unnaturally clean, which is the point: it
isolates *delivery cadence* from recognition difficulty. We are not measuring
how well a model hears. We are measuring when it tells us.

The trace reports, per arrival:

- **gap** — milliseconds since the previous arrival, stamped inside the results
  loop before any rendering, so the number is the engine's and not the
  terminal's.
- **Δ** — words this arrival added.
- **lag** — the live audio edge minus the end of the audio this text describes.

## Result

| engine | arrival gap (median) | lag behind live | words per arrival |
|---|---|---|---|
| Apple SpeechAnalyzer | 3747 ms | 0 ms, four times | 8.8 |
| Parakeet EOU 320 ms | 302 ms | 540 ms | 2.3 |
| **Parakeet EOU 160 ms** | **206 ms** | **180 ms** | **1.5** |

## What Apple actually does

It accumulates roughly 3.8 seconds of audio, then delivers the entire volatile
evolution of the phrase at once — a dozen results at ~1 ms intervals — each with
its range pinned to the live audio edge:

```
[ 5.127s] burst → audio 0.00– 4.05
[ 8.817s] burst → audio 0.00– 7.76     gap 3689ms, audio advanced 3.71s
[12.720s] burst → audio 0.00–11.64     gap 3876ms, audio advanced 3.88s
[16.525s] burst → audio 0.00–15.43     gap 3747ms, audio advanced 3.79s
```

The wall gap and the audio advance are the same number every time.

This is why "lag 0 ms" for Apple is true and useless in isolation. The text is
never stale — each burst describes audio right to the edge. You simply only
*learn* where the reader is four times in a sixteen-second sentence, and a
presenter covers ten words in that window.

### It is not our pipeline

| configuration | burst period | audio advance |
|---|---|---|
| tap 4096 (85 ms) | mean 3771 ms | 3.71 / 3.88 / 3.79 s |
| tap 1024 (21 ms) | mean 3778 ms | 3.71 / 3.88 / 3.79 s |
| `.high` + `.processLifetime` | 3860 / 3752 ms | 3.88 / 3.79 s |

Cutting 64 ms out of the microphone tap moved the delivery cadence by 7 ms. The
audio advance is identical to the centisecond across runs. Neither
`SpeechAnalyzer.Options(priority:)` nor `modelRetention` touches it. The window
is Apple's and no exposed knob changes it.

Note that Apple's documented "0.3–0.5 s to first volatile result" describes a
*warm start*, not the steady-state cadence. Both numbers are true; only one of
them is about following speech.

## Why this tier of Parakeet

FluidAudio ships four streaming families. Only `StreamingEouAsrManager` conforms
to `StreamingAsrTokenTimestampProvider`, and `getTokenTimestampsMs()` returns
"elapsed time from the start of the conversation" — the same clock our audio
counter runs on. The Nemotron and Unified tiers stream too, but hand back text
with no timing, which would leave control-token placement guessing.

So this is the only path that answers both of the project's questions at once:
where is the reader now, and when was that word actually said.

160 ms wins over 320 ms on both axes — finer *and* less laggy, because a shorter
chunk reaches the decoder sooner. The cost is accuracy: the 120M model misheard
"spoken" as "spoke" and "arrives and" as "around". Acceptable when a fuzzy
matcher consumes the text and pace is the thing we need.

## Known: startup lag transient

`lagMs` opens high and decays (1660 → 1460 → 1380 → 1260 ms observed) before
settling near 180 ms. The buffer feeding the engine is unbounded, so silence
captured before you start speaking accumulates a backlog the engine then has to
chew through. It converges, and starting Sonocles before you start reading
hides it entirely — but it is a real transient and not yet fixed.

## Known: microphone permission is not automatic

`AVAudioEngine` on macOS does not prompt. With no grant it starts perfectly
happily and delivers silence forever, so a denied app presents as a completely
healthy pipeline that transcribes nothing — engine running, sockets bound,
`listening: true`, and not one word.

This hid for a while because a CLI inherits the grant of whatever terminal
launched it. The moment the same code ran inside a signed `.app` with its own
TCC identity, it had no permission and no way to ask. `Sidecar.start()` now
calls `AVCaptureDevice.requestAccess(for: .audio)` first and refuses to report
`listening` without it.

And the hardened runtime gates it a layer earlier still. Signing with
`--options runtime` and no entitlements produces an app that cannot record and
cannot ask to: `com.apple.security.device.audio-input` is checked *before* TCC
is consulted, so no prompt appears and the app never appears in System Settings
> Privacy & Security > Microphone at all. An empty list is not "permission
denied", it is "the request never happened".

`NSMicrophoneUsageDescription` in Info.plist is necessary but not sufficient.
Both it and the entitlement have to be present, and the failure with only one of
them looks identical to the failure with neither.

Three consequences worth remembering:

- Changing how the app is signed changes its TCC identity. Going from ad-hoc to
  Developer ID makes it a *different app* to macOS, and any existing grant does
  not carry over. Sign with the real identity from the start.
- "It runs but hears nothing" should always be checked against the CLI on the
  same audio before anything else is suspected. That one comparison — 15 events
  against 0, same sentence, same second — turned a day of possible theories into
  a two-line fix.
- The states are worth distinguishing when debugging. Stuck on `starting` means
  `requestAccess` is blocking on a dialog someone has to answer. Falling back to
  `idle` means it was refused. Reporting `listening` while silent is the bug
  this whole section exists to prevent, and is now impossible: capture cannot
  claim to be listening without the grant.

## Known: finals lag by the end-of-utterance debounce

A `final` arrives 1.6–3.1 s after the speech it describes, because the engine
waits out `eouDebounceMs` (1280 ms by default) of silence before deciding an
utterance ended, and then still has to finish decoding.

That is fine for what finals are for — they are settled text, and settling takes
evidence — but it means **nothing time-sensitive should wait for one**. Partials
arrive every ~200 ms at ~180 ms behind live and are what should drive a scroll
or fire a cue. Finals are for the transcript.
