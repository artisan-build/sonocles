# Could Sonocles be rebuilt in NativePHP?

**Short answer: the app, yes. The engine, no — and it should not be.**

Built, signed, notarised, and measured: a NativePHP menu bar app doing live
on-device speech recognition on the Neural Engine, **180 ms behind the speaker**,
with the PHP front end adding **1 ms**.

The shell, the menu bar, the popover, the control plane, the packaging and the
notarisation are all straightforwardly NativePHP. Recognition is not, and no
amount of effort makes it so. What that leaves is not a compromise: it is the
architecture Sonocles already has. The Swift side is *already* a headless
sidecar that speaks over sockets, and a NativePHP front end is simply a second
consumer of a protocol built for consumers.

This directory is that front end, built and running.

Status: **built, signed with a real Developer ID, and verified end to end.**
A packaged `Sonocles.app` runs its own bundled PHP, spawns the Swift engine out
of `Contents/extras`, opens the microphone under the hardened runtime and
transcribes live speech at the same latency the Swift app achieves. The
measurements are below.

---

## The four questions

### 1. Can a NativePHP app do Core ML inference? No.

Two independent reasons, either sufficient:

**The bundled runtime has no FFI.** NativePHP ships static PHP binaries built
with static-php-cli, and the extension set is fixed in `php-extensions.txt`:

```
bcmath bz2 ctype curl dom fileinfo filter gd iconv intl mbstring mbregex
opcache openssl pdo pdo_sqlite phar session simplexml sockets sodium sqlite3
tokenizer xml zip zlib
```

No `ffi`. You *can* replace the binary — `NATIVEPHP_PHP_BINARY_PATH` points at
your own static-php-cli build — so this alone is not fatal.

**Core ML has no C API.** This one is. Core ML is Objective-C and Swift. Even a
custom FFI-enabled PHP could only call a C shim you had written in a compiled
language, which means the native code exists either way; you would have moved
the boundary, not removed it. And the model here is not raw Core ML anyway — it
is FluidAudio's `StreamingEouAsrManager`, a Swift package chosen (per
`docs/ENGINES.md`) because it is the only tier that conforms to
`StreamingAsrTokenTimestampProvider` and hands back the token timings the whole
protocol is built on.

Rewriting that in PHP is not a porting job. It is reimplementing a Swift
inference library against an Objective-C framework from a language that cannot
call either.

### 2. Can it capture microphone audio with real timestamps? Technically yes, usefully no.

The renderer is Chromium, so `getUserMedia` plus an `AudioWorklet` is available
and does give a real capture clock — `AudioContext.currentTime`,
`getOutputTimestamp()`, and per-block frame counts good enough to build a
timeline on.

But PHP cannot reach it. An `AudioWorklet` runs on the audio thread inside the
renderer, and the only way into PHP is to post buffers to the main thread and
ship them over the app's own HTTP or WebSocket server — PCM, in real time, into
a language that then has nothing to do with it, because of question 1. You would
be paying a full serialisation hop to deliver audio to a process that cannot
recognise it and must forward it to a native one regardless.

So the question answers itself: capture belongs wherever recognition is. That is
the sidecar, which already owns `AudioCapture.swift`, the tap, the converter and
`AudioClock.swift` — an engine-independent frame counter at capture rate, which
is precisely the "real timestamps out of the capture clock" the brief asks for.

### 3. Can it hold the ~180 ms budget? Yes — because it never enters the path.

This is the finding that makes the whole thing work, and it is an architectural
answer rather than a performance one.

Sonocles' budget is spent between the microphone and the socket. Both ends of
that are Swift. The PHP application is not a relay: the popover holds
`ws://127.0.0.1:7358` **itself**, in the renderer, so a recognised word goes

```
mic → AudioCapture → Parakeet → WebSocketServer → Chromium → DOM
```

and never enters the PHP process. The 180 ms figure is unchanged because the
code producing it is unchanged and nothing was inserted behind it.

PHP's only traffic is `/status`, `/start` and `/stop` — three calls that happen
when a person clicks something, where latency is invisible.

**Measured**, on a real voice through an SM7B into the running NativePHP app —
70 frames, the front end's own cost sampled per frame as `Date.now() - frame.ts`:

| | min | median | p90 | max |
|---|---|---|---|---|
| engine lag behind live (partials, n=66) | 120 ms | **180 ms** | 220 ms | 240 ms |
| front end's own cost (n=70) | 0 ms | **1 ms** | 2 ms | 3 ms |

The median is 180 ms — the same figure `docs/ENGINES.md` reports for the Swift
app, because it is the same engine and nothing was inserted behind it. Electron
and Laravel together cost about a millisecond, which is what "not in the path"
looks like when you measure it instead of asserting it.

Route frames through PHP instead and you would add a socket hop, a Laravel
request lifecycle and a second serialisation to every ~200 ms arrival, in
exchange for nothing. `resources/views/menubar.blade.php` therefore reports the
front end's own cost (`Date.now() - frame.ts`) as a **separate** number from the
engine's `lagMs`, so the two claims stay distinguishable. Adding them would hide
which one moved.

### 4. Can it be signed, notarised, and given a microphone entitlement? Yes — after one change that is not optional.

Notarisation is already wired: `electron-builder.mjs` sets
`afterSign: 'build/notarize.js'`, which runs `@electron/notarize` with
`notarytool` when `NATIVEPHP_APPLE_ID`, `NATIVEPHP_APPLE_ID_PASS` and
`NATIVEPHP_APPLE_TEAM_ID` are set. `NSMicrophoneUsageDescription` ships by
default under `mac.extendInfo`.

**But the scaffolded entitlements file does not include the microphone.** Both
upstream and as published into this project, `build/entitlements.mac.plist`
contains exactly three keys:

```
com.apple.security.cs.allow-jit
com.apple.security.cs.allow-unsigned-executable-memory
com.apple.security.cs.allow-dyld-environment-variables
```

Ship that as-is and you get the failure this project has already paid for once.
The hardened runtime checks `com.apple.security.device.audio-input` *before* TCC
is consulted, so a signed app without it cannot record and cannot ask to: no
prompt, and the app never appears in System Settings › Privacy & Security ›
Microphone at all. An empty list there is not "denied", it is "the request never
happened" — and it presents exactly like a healthy pipeline that hears nothing.
`docs/ENGINES.md` documents the session that cost.

The fix is one key, applied in `nativephp/electron/build/entitlements.mac.plist`
here. It matters that this file is also electron-builder's `entitlementsInherit`,
which is what gets applied to nested Mach-O binaries inside the bundle —
including `extras/sonocles-cli`, the process that actually opens the microphone.

Worth saying plainly: **this is a real gap in NativePHP's defaults for any app
that records.** It is also the single most useful thing to report upstream.

**Verified against the signature, not the config.** After `native:build`,
`codesign -d --entitlements` reports the microphone entitlement on *both* the
outer app and the nested engine binary — `entitlementsInherit` does reach
`Contents/extras/sonocles-cli`, which was the open risk:

```
Sonocles.app                      flags=0x10000(runtime)  + device.audio-input
Sonocles.app/Contents/extras/sonocles-cli
                                  flags=0x10000(runtime)  + device.audio-input
```

Both carry the hardened runtime and chain to Apple Root CA through
`Developer ID Application: Artisan Build, Inc`. The packaged app then went
`starting` → `listening` and transcribed a spoken sentence at 160-180 ms lag.

**Notarised and stapled**, using the existing `sonocles` keychain profile:

```
status: Accepted
Sonocles.app: accepted
source=Notarized Developer ID
origin=Developer ID Application: Artisan Build, Inc (83AD4SGJLW)
```

That is the answer to question 4 in full. The bundle shape NativePHP produces is
something `codesign --options runtime` accepts, the entitlement survives to the
nested binary, and Apple notarises the result without complaint.

---

## The architecture

```
Sonocles.app  (Electron 38 + static PHP 8.4)
├── menu bar icon ............... MenuBar::create(), template PNG, no Dock icon
├── popover ..................... Blade + vanilla JS
│     ├── control ............... fetch → Laravel → 127.0.0.1:7357  (human speed)
│     └── frames ............... ws://127.0.0.1:7358 direct         (~180 ms path)
└── Contents/extras/sonocles-cli  the Swift engine, spawned as a ChildProcess
      └── mic → Parakeet EOU 120M → Core ML → Neural Engine
```

`ChildProcess::start(..., persistent: true)` is supervisord-shaped: it restarts
the engine if it dies. `App\Support\Sidecar` checks the port first and adopts an
already-running engine rather than spawning, because `sonocles-cli` exits
non-zero when it cannot bind and a persistent child that exits is restarted —
so spawning blindly against a bound 7357 produces a respawn loop rather than an
error.

`extras/` is copied to `Sonocles.app/Contents/extras` by electron-builder and
handed to PHP as `NATIVEPHP_EXTRAS_PATH`, so one lookup serves both development
and the packaged app.

### What the split costs

Honest accounting, because the brief asked for it:

- **Two toolchains.** Shipping needs Xcode *and* Node *and* Composer. CI has to
  build the Swift binary before electron-builder runs. That is a real tax on a
  project that currently needs only `swift build`.
- **Bundle size.** Measured, not estimated: the packaged app is **397M** on
  disk (147M compressed as a DMG), against ** 32M** for the Swift build of the
  same product — and both then download ~219 MB of models on first run. Electron
  plus a static PHP runtime is most of that difference.
- **Two signing surfaces.** The outer app and the nested engine binary both have
  to be signed correctly, and the entitlement has to reach the nested one.
- **A second TCC identity.** A different bundle id means microphone grants do
  not carry over from the Swift app, and should not — but it is one more thing
  a user has to say yes to.
- **No accuracy, latency or CPU benefit whatsoever.** Every number in
  `docs/ENGINES.md` is produced by code this front end does not touch.

What it buys is the UI in Blade instead of SwiftUI. For this project that is not
a trade worth making on engineering grounds, and the brief already says so: the
motivation is reach.

### What it is genuinely good for

The demo is not "Sonocles, rewritten". It is **"a NativePHP app doing real-time
on-device speech recognition on the Neural Engine"** — which is true, is more
interesting than a rewrite, and is honest about where the inference lives. The
ChildProcess-plus-loopback-protocol pattern generalises to every Core ML,
Metal, or AVFoundation capability PHP cannot reach, which is most of them. That
is a more useful article than a port would have been.

---

## Two more NativePHP bugs found on the way

Both cost real time, and both are worth reporting upstream alongside the
entitlement.

**1. `native:install --publish` produces a skeleton that cannot build.** The
prebuilt `electron-plugin/dist` is missing `server/pdfPageSize.js`, which
`server/api/system.js` imports. `npm run build` fails with
`Could not resolve "../pdfPageSize.js"`. The source file
(`electron-plugin/src/server/pdfPageSize.ts`) is present, so the fix is to
rebuild the plugin from source once after publishing:

```bash
cd nativephp/electron && npm run plugin:build
```

What made this expensive is that `native:run` reports **`build the electron main
process successfully`** and *then* fails with the unrelated-looking
`No electron app entry file found: out/main/index.js`. The success line is
printed by a different step than the one that failed; `npm run build` shows the
actual error immediately.

**2. A failed notarisation reports success.** `build/notarize.js` wraps the
`notarize()` call in a try/catch that logs the error and then unconditionally
prints `done notarizing <app-id>.` A build with missing or wrong credentials
therefore ends on a success line with a stack trace scrolled off above it:

```
Error: The appleId property is required when using notarization ...
done notarizing build.artisan.sonocles.php.
```

For this project that is exactly the wrong failure mode, and not
hypothetically: the released v0.1.0 DMG *did* ship ad-hoc signed, presenting to
users as "Sonocles is damaged and can't be opened". It has since been fixed —
v0.1.0's assets were replaced and v0.1.1/v0.1.2 are signed and notarised through
CI — but a pipeline that prints "done notarizing" when it did not notarise is
exactly how that happens a second time.

It is worth naming the pattern, because it is the most transferable thing in
this report and it has nothing to do with language choice. Every expensive
failure across both codebases has been **a plausible success line over a real
failure**, never an exception:

- `codesign --verify --deep --strict` reporting a bundle `valid on disk` while
  a nested executable inside it still carried an ad-hoc signature. Apple's
  notary service was the only check in the pipeline that caught it.
- `git rev-list --count HEAD` returning `1` rather than failing on a
  depth-1 CI clone, so an `|| echo 1` fallback never fired and two releases
  shipped the same build number.
- `AVAudioEngine` starting happily without a microphone grant and delivering
  silence forever.
- `native:run` printing `build the electron main process successfully`
  immediately before dying on the entry file that build did not produce.
- `notarize.js` printing `done notarizing`.

None of these throw. Choosing Swift or PHP does not protect you from any of
them.

## What is proven

Verified on this machine (Apple Silicon, macOS 26.6.2, PHP 8.4.23,
nativephp/desktop 2.3.0, Electron 40.10.2):

- NativePHP desktop v2.3.0 installs on Laravel 13 and scaffolds cleanly.
- The bundled PHP runtime has no `ffi` (read from `php-extensions.txt`).
- The app boots: Electron → bundled PHP on :8100 → `Process [sonocles-engine]
  spawned!` → engine bound on 7357/7358, from `NATIVEPHP_EXTRAS_PATH`.
- The popover renders, drives `/start` and `/stop`, and streams recognised words
  live from the engine's WebSocket.
- **Latency measured on a real voice**: engine median 180 ms, front end median
  1 ms. Table in question 3.
- **Packaged and signed with a real Developer ID.** Hardened runtime and the
  microphone entitlement on both the app and the nested engine binary;
  `codesign --verify --deep --strict` passes and the bundle satisfies its
  Designated Requirement.
- **Microphone capture works in the packaged bundle.** It went `starting` →
  `listening` and transcribed spoken sentences at 160-180 ms.

Non-speech behaviour, WER and CPU are all untouched here — they are properties
of the engine, and this front end does not change them. The gaps
`docs/ENGINES.md` lists remain exactly as they were.

## What is still not proven

1. **Nobody else's Mac has opened it.** Gatekeeper accepts it here, but here is
   the machine that built it. The one caveat worth knowing: I notarised the DMG
   after the fact, which staples the *disk image* — the `.app` inside carries no
   ticket of its own, so a copy of it dragged out and run on an offline machine
   would have nothing local to verify against. Running notarisation through
   NativePHP's own `afterSign` hook (with the three `NATIVEPHP_APPLE_*` variables
   set) staples the app itself, before the DMG is built, and is the right way to
   ship this.
2. **Only this machine, only arm64.** One host, one OS version, one run of each
   measurement. No variance, no repetition count — the same methodological
   thinness `docs/ENGINES.md` admits to, inherited rather than fixed.
3. **The models were already downloaded.** First-run behaviour — a ~219 MB
   download and Core ML compile inside a sandboxed, signed bundle writing to
   `~/Library/Application Support/FluidAudio` — has not been exercised. It is
   the most likely remaining surprise.
4. **Nothing about updates.** `NATIVEPHP_UPDATER_ENABLED=false` here, deliberately.
