# Engine selection belongs in the control API — deferred work

Written 11 Sep 2026, during the app restyle (#2) and the NativePHP blade's
move to the Swift layout (`php-nativephp-feasibility`, 71e29b0). Decided by
Rheocles under the rule its spec §2 states and Sonocles has been living by
without writing down: **if it can be clicked, it can be called.**

## The gap

The Swift popover's engine control — 160 ms · 320 ms · 1280 ms · Apple — is
wired to `SidecarModel.use(_:)`, which calls `Service.use(engine:)`
in-process. Nothing else can reach that call. The control API has `/status`,
`/start`, `/stop` and `/token/rotate`; it has no route that changes the
engine, and `/status` reports the engine only as a display string
(`"engine": "Parakeet EOU 120M (160 ms)"`), not as the slug the CLI accepts.

So the NativePHP blade *reports* the engine and cannot offer a choice. That
was the right call for the blade — a segmented control wired to nothing is
exactly the kind of dressed-up absence BRAND.md forbids — but the blade is
not where the gap is. The Swift app's local-only picker is.

## Do this

One small PR against `main`, in this order, each step green on its own.

### 1. A route

Engine on the wire is the **slug**, which is what `sonocles-cli --engine`
already takes: `fluid160` · `fluid320` · `fluid1280` · `apple`. The label is
for humans and stays where it is.

    GET  /engine            → { "engine": "fluid160", "label": "Parakeet 160 ms",
                                "available": ["fluid160", "fluid320", "fluid1280", "apple"] }
    POST /engine  { "engine": "fluid320" }
                            → the same shape, after the change

`available` matters because `apple` is gated to macOS 26 and a client on 15
should not be offered it and then get a 400. An unknown slug is `400` with the
usual error shape. Behind the token like every other route.

`POST /engine` calls `Service.use(engine:)`, which already does the honest
thing — stops and restarts capture if it was listening, because a half-swapped
pipeline would report numbers belonging to neither engine. Say so in the
protocol doc: switching while listening is a stop and a start, and the
`starting` state will be visible in between.

Also add `"engineId": "fluid160"` (or the slug under whatever name reads best)
to `/status` next to the existing `engine` label, so a client polling `/status`
does not need a second call to know what it is looking at.

### 2. An event

Both apps poll `/status` for state; neither should have to poll to learn the
engine changed underneath it — a switch from one client is a surprise to the
other. Add an engine-change message to the event stream, on both transports,
in the shape the `status` answers on the WebSocket already use for non-frames:

    { "event": "engine", "engine": "fluid320", "label": "Parakeet 320 ms" }

Frames have `type`; this has `event`, so a consumer that only handles frames
skips it the way it already skips the WebSocket auth answer. Document it in
PROTOCOL.md beside the frame shape.

### 3. Wire both apps to it

- **Swift** (`MenuBarView.swift`, `SidecarModel.swift`): the `Segmented`
  stays; `model.use(_:)` goes through the same code path the route uses, and
  the model listens for the engine event so a switch made over HTTP moves the
  segmented control. Today it would not.
- **NativePHP** (`php/resources/views/menubar.blade.php`): replace the
  read-only Engine row with the Swift popover's `Segmented` — same four short
  labels, full name in script beside the label — posting to a new
  `/engine/use` Laravel route that forwards to `POST /engine`. The blade's
  `poll()` reads `engineId` from `/status` to keep the control true.

Keep `ui` on the blade's stat line. It is the measurement FEASIBILITY.md is
built on and it costs nothing.

### 4. Tests

`ControlTests` in the shape of the existing ones: `POST /engine` with a known
slug answers with that slug and `/status` agrees; an unknown slug is 400 and
`/status` is unchanged; the event arrives on `/events` after a switch. The
`apple` availability check is a pure function of the OS version and can be
asserted directly.

## Related, recorded so it is not a mystery

PR #1's branch predates the bearer token (#3). `php/app/Support/Sidecar.php`
sends no `Authorization` header and the blade opens the WebSocket without the
`{"auth": …}` first frame, so against an engine built from current `main`
every control call is 401 and no frame ever arrives. The fix is the pattern
Rheocles' `php/app/Rheocles/` already has — `Token.php` reads the file,
`Client.php` sends the header, `EventStream.php` uses `?access_token=` — read
from `~/Library/Application Support/Sonocles/token`, and `{"auth": token}` as
the WebSocket's first frame per PROTOCOL.md. Not tonight's work; it belongs to
whoever takes PR #1 forward, and step 3 above depends on it.
