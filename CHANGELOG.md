# Changelog

What changed for people using Sonocles, release by release. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/). Every release on GitHub carries its
section from this file, and the release workflow refuses to run without one.

## [Unreleased]

## [0.1.4] — 2026-09-13

### Changed

- The popover says more, in plain words. The transcript pane shows the last four lines — settled utterances dim above the live one, newest at the bottom — and says *Words appear here as you say them* until there are any. The engine is chosen in two steps: the model (Parakeet, or Apple on macOS 26) with a line saying what it is, then for Parakeet a speed — 160, 320 or 1280 ms — each with what it costs and is for. **Connected apps** replaces the Control API disclosure: how many apps are connected, the key with Show, Copy and Rotate and a sentence saying what they do, and the two ports with what each is for. A strip along the bottom carries the version, the model and speed, and the connected count.
- If the sockets cannot bind, the popover says **Down** and shows why, with a Relaunch button, instead of controls that would do nothing.
- The NativePHP popover matches the Swift one row for row: the same transcript window, engine picker and speed rows, Connected apps section (which it did not have before — the key, Copy, and a two-click Rotate), strip, and the down panel with Relaunch when its engine is starting, refusing the key, or missing.

## [0.1.3] — 2026-09-13

### Added

- Install with Homebrew: `brew install --cask artisan-build/tap/sonocles`. Each release updates the cask, so `brew upgrade` follows along.
- Engine selection in the control API: `GET /engine` lists what this Mac can run, `POST /engine` switches, `/status` carries `engineId`, and an `engine` event goes out on both transports when it changes. The popover's picker follows a switch made over the API and only offers engines the machine supports.
- `GET /` answers with the name, version, auth scheme and ports, so a client can find its way in without reading the docs.
- `POST /token/rotate` issues a fresh token; the popover's Rotate button does the same after a second click to confirm.
- Documentation at [sonocles.com/docs](https://sonocles.com/docs): getting started, the menu bar app, the protocol, engines and how latency is measured, authentication, the control API, engine selection, troubleshooting, and an API reference generated from `docs/openapi.yaml`.
- A NativePHP front end for the engine in `php/`, driving the same control API and stream — a feasibility build, not yet packaged for download.

### Changed

- Every route now takes a bearer token in place of Basic auth. The token lives at `~/Library/Application Support/Sonocles/token`, the popover shows it with Show and Copy, SSE clients pass it as `?access_token=`, and WebSocket clients send `{"auth": "<token>"}` as their first frame. Existing clients need updating; the username and password are gone.
- The popover wears the site's palette — limestone ground, ink, terracotta — with Fraunces, Instrument Sans and IBM Plex Mono bundled, instead of the dark theme it launched with.

## [0.1.2] — 2026-09-05

### Fixed

- The build number stamped into the app counts the full history again, so 0.1.2 no longer reports the same build as 0.1.0 and updates register as updates.

## [0.1.1] — 2026-09-05

### Changed

- The app and the disk image are signed with a Developer ID and notarized, and the `sonocles-cli` inside the bundle is signed too. It opens without a Gatekeeper warning, and the microphone permission carries over between updates instead of being asked again after each one.
- The version shown by the app is the version that was tagged, rather than a hand-written 0.1.0.

## [0.1.0] — 2026-09-04

### Added

- The menu bar app: on-device speech-to-text streamed live over WebSocket (`ws://127.0.0.1:7358`) and SSE (`GET /events` on 7357), word by word, each frame carrying the audio timestamp of when it was spoken and how far behind it is.
- `sonocles-cli`, the same engine without a window, for scripts and other apps.
- The control API on 7357: `/status`, `/start`, `/stop`, with the input level reported in `/status`.
- Model download and compilation progress shown in the popover and reported in `/status`, so first run explains its wait.
- A signed DMG on every release, with a download link that always points at the latest one.

[Unreleased]: https://github.com/artisan-build/sonocles/compare/v0.1.4...HEAD
[0.1.4]: https://github.com/artisan-build/sonocles/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/artisan-build/sonocles/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/artisan-build/sonocles/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/artisan-build/sonocles/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/artisan-build/sonocles/releases/tag/v0.1.0
