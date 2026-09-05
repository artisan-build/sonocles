# Could Sonocles be rebuilt in NativePHP?

**Short answer: the app, yes. The engine, no — and it should not be.**

The shell, the menu bar, the popover, the control plane, the packaging and the
notarisation are all straightforwardly NativePHP. Recognition is not, and no
amount of effort makes it so. What that leaves is not a compromise: it is the
architecture Sonocles already has. The Swift side is *already* a headless
sidecar that speaks over sockets, and a NativePHP front end is simply a second
consumer of a protocol built for consumers.

This directory is that front end, built and running.

Status as written: the PHP application drives the real Swift engine and its
control API. The packaged, signed, notarised bundle is **not yet verified** —
see "What is not yet proven" at the bottom, which is the honest boundary of
this report.

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
- **Bundle size.** Electron plus a static PHP runtime is ~200 MB before the
  16 MB engine and before the ~219 MB of models downloaded on first run. The
  Swift app is a fraction of that.
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

## What is proven

Verified on this machine (Apple Silicon, macOS 26.6.2, PHP 8.4.23,
nativephp/desktop 2.3.0):

- NativePHP desktop v2.3.0 installs on Laravel 13 and scaffolds cleanly.
- The bundled PHP runtime has no `ffi` (read from `php-extensions.txt`).
- `ChildProcess`, `MenuBar`, `NATIVEPHP_EXTRAS_PATH` and the electron-builder
  entitlement/`extendInfo` hooks exist as described (read from source, not docs).
- **PHP drives the real Swift engine.** With `sonocles-cli --idle` running,
  `GET /engine/status` returns the engine's live state through
  `App\Support\Sidecar`:
  ```json
  {"up":true,"engine":{"state":"idle","listening":false,
   "engine":"Parakeet 160 ms","clients":0,"uptime":12.25}}
  ```
- The menu bar template icon renders legibly at 22 pt on both light and dark
  grounds (checked as an alpha composite, not assumed).

## What is not yet proven

Stated plainly rather than glossed, because the difference matters:

1. **The packaged app has not been built.** `native:build` has not run, so the
   bundle layout, the nested-binary signing and `codesign -d --entitlements` on
   both the app and `Contents/extras/sonocles-cli` are unverified. The
   entitlement claim in question 4 is read from configuration, not from a
   signature.
2. **Microphone capture end-to-end inside the Electron bundle is untested.**
   This is the one that could still bite: whether TCC attributes the request to
   the outer app or to the nested binary, and whether `entitlementsInherit`
   actually reaches `extras/`. Everything else in this report is robust to that
   answer; the packaging story is not.
3. **The front end's own latency cost is instrumented but unmeasured.** The
   popover computes it; no speech has been run through it yet.
4. **Notarisation has not been attempted** from this project.

None of these change the answer to the four questions. All of them are the
difference between "this should work" and "this works", and item 2 is the one
worth doing next.
