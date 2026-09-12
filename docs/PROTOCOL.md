# Wire protocol

Every consumer gets the same JSON, whichever transport it listens on.

## Transports

| | endpoint | direction |
|---|---|---|
| SSE | `GET http://127.0.0.1:7357/events` | one-way |
| WebSocket | `ws://127.0.0.1:7358` | bidirectional |

Both bind loopback only, and both come up when the app launches — not when
capture starts. That distinction matters: it is what lets `POST /start` work on
a process that has never been told to listen, and it is the fix for a bug where
stopping capture orphaned the listeners, leaving ports bound to a deallocated
server that accepted connections and answered nothing.

They are not alternatives. Run both; a browser reading over SSE and a tool
holding a socket can want the same stream at the same time.

## Authentication

A bearer token, always, on every route and both transports. The sidecar
writes it to `~/Library/Application Support/Sonocles/token` (mode 0600) the
first time the sockets come up; any app running as the same user reads the
file and is paired. It is 64 hex characters on one line. Rotating the token —
from the popover, or over `POST /token/rotate` — invalidates the old one on
the next request.

- **HTTP:** `Authorization: Bearer <token>` on every request, including
  `GET /`. Missing or wrong → `401` with `{ "error": "authentication required" }`
  and `WWW-Authenticate: Bearer realm="Sonocles"`. The check runs before
  routing, so an unknown path is `401` without the token and `404` with it.
  `OPTIONS` preflight is the one unauthenticated answer, because a browser
  sends it before it will attach the header.
- **SSE:** `EventSource` cannot set headers, so
  `GET /events?access_token=<token>` is accepted as well (RFC 6750 §2.3).
  Loopback only, so the URL form exposes nothing a local page could not read
  from the header form.
- **WebSocket:** the first frame must be `{"auth": "<token>"}`, answered
  `{"id": null, "status": 200, "body": {"authenticated": true}}`. Until then
  every other frame is answered `{"id": …, "status": 401, "body": {"error":
  "authentication required"}}` and no event is delivered. A header on the
  upgrade would be the HTTP-shaped way, but a browser `WebSocket` cannot set
  one, so the frame is the one way that works everywhere and it is the only
  way. An `id` in the frame, of any JSON type, is echoed in the answer.

This replaces an earlier scheme: optional HTTP Basic on the control routes,
with `/events` left open because `EventSource` had no way to carry a
credential. Two things were wrong with it. The lock was off by default, so a
fresh install let any page in the user's browser switch on the microphone;
and the transcript of everything said near that microphone was readable by
the same page regardless. The token in the query string is what makes closing
the stream possible, and the file is what makes the lock cost nothing to turn
on — it is on, always, and same-machine apps pair by reading it.

## Frames

```json
{
  "type": "partial",
  "text": "and this week we are looking at",
  "ts": 1788569799791,
  "seq": 41,
  "audioStart": 5.04,
  "audioEnd": 11.36,
  "lagMs": 180
}
```

| field | meaning |
|---|---|
| `type` | `partial` (volatile, revised as you speak) or `final` (settled) |
| `text` | the hypothesis |
| `ts` | epoch ms **at emit** — when we learned, not when it was said |
| `seq` | monotonic; a gap means a dropped or reordered frame |
| `audioStart` / `audioEnd` | seconds into the session's audio the text covers |
| `lagMs` | live audio edge minus `audioEnd`, at emit |

`text` and `ts` are the original prompter-ears contract and have not moved.
Everything else is additive: a consumer reading only `text` is unaffected.

### The engine event

One other thing travels on the stream, on both transports:

```json
{ "event": "engine", "engine": "fluid320", "label": "Parakeet 320 ms" }
```

Sent when the engine changes — from the popover or over `POST /engine` —
so no client has to poll `/status` to learn that another one switched it
underneath them. Frames have `type`; this has `event`. A consumer that only
handles frames skips it the way it already skips the WebSocket auth answer,
and the snippets under *Consuming it* show the one-line check.

`engine` is the slug, `label` the name for humans. If capture was running
when the switch happened it was stopped and is starting again on the new
engine, so the event is followed by a gap in frames and `/status` says
`starting` until the new engine is up.

### `text` is the current utterance, not the session

Each `final` closes an utterance and the next `partial` starts empty. A consumer
that wants a running transcript accumulates the finals itself.

This is not merely a preference. The underlying engine latches its
end-of-utterance flag until it is reset and accumulates the transcript
indefinitely otherwise, so an earlier build finalised only the *first* utterance
of a session and grew `text` without bound — thirty-five seconds in, every frame
still carried every word since second three, five times a second. Over a talk
that is untenable.

Resetting between utterances costs the engine's token timings, which restart at
zero. The sidecar keeps its own offset so `audioStart` and `audioEnd` stay
absolute on the session timeline across every reset:

| utterance | window |
|---|---|
| one | 0.76 – 4.76 |
| two | 9.28 – 11.60 |
| three | 16.20 – 18.76 |

That is what makes the timestamps usable for placing markers rather than merely
ordering words.

### On `lagMs` being signed, and sometimes absent

Negative means the engine reported audio ahead of what we had captured — a real
clock disagreement, surfaced rather than clamped. Absent means the engine did
not report timing for that hypothesis.

Absent is **not** zero, and the field is omitted rather than zeroed on purpose.
An early build rendered "no measurement" as `+0ms` and spent an entire session
insisting it was real-time while measuring nothing at all. Treat a missing
`lagMs` as unknown.

### Why consumers should use `audioEnd`, not `ts`

Arrival time is a lossy proxy for spoken time. Delivery clusters rather than
ticking evenly, so `ts` carries the jitter of the delivery schedule on top of
the actual timing. Anything placing a marker accurately, or leading a scroll by
a fixed amount, wants `audioEnd`.

## Control API

On the HTTP port. JSON in, JSON out.

| route | does |
|---|---|
| `GET /` | discovery: name, version, auth scheme, ports |
| `GET /events` | the SSE stream |
| `GET /status` | current state |
| `POST /start` | begin capture |
| `POST /stop` | end capture |
| `GET /engine` | the engine as configured, and which ones this Mac can run |
| `POST /engine` | `{ "engine": "<slug>" }` → the same shape, after the change |
| `POST /token/rotate` | `{}` → `{ "token" }` — new token, old one dead after the response |

Every one of them is behind the token. `GET /` is the first call a client
makes:

```json
{ "name": "Sonocles", "version": "0.1.2", "auth": "bearer",
  "ports": { "http": 7357, "ws": 7358 } }
```

`version` is what the bundle was stamped with, or `dev` from the CLI, which
has no bundle. `ws` is absent when the WebSocket transport was not started.

`POST /token/rotate` takes no body and answers `{ "token": "<64 hex>" }`. If
the file cannot be written it answers `500` with the error shape and the old
token stays valid — a rotation that half-happened would lock everyone out,
the caller included.

`GET /status`, and the answer to `POST /start` and `POST /stop`:

```json
{ "state": "listening", "listening": true,
  "engine": "Parakeet EOU 120M (160 ms)", "engineId": "fluid160",
  "clients": 1, "uptime": 41.2, "levelDb": -19.4 }
```

`engine` is the engine's own name once running, else the configured
choice's label — for a display. `engineId` is the slug the control routes
speak, so a client polling `/status` knows what it is looking at without a
second call.

`levelDb` is the peak input level in dBFS, and it is absent when not capturing —
absent meaning unmeasured, never zero, as everywhere else here.

It exists because "is it hearing anything" is otherwise unanswerable from
outside the process. Signal with no text is a working microphone in a quiet
room, or a room with something in it that is not speech; no signal at all is a
different problem entirely. Establishing that thirty seconds of piano at -9 dBFS
peak produced zero words required starting a second sidecar purely to watch a
meter, which is a silly thing to need.

`state` is `idle` · `starting` · `listening`. Three states rather than a
boolean because `POST /start` returns before capture is up — models load,
macOS may ask for the microphone — and answering `listening: false` to a
request that just succeeded reads as a failure. Poll until `listening`.

### Engine selection

The engine on the wire is the **slug**, which is what `sonocles-cli
--engine` already takes: `fluid160` · `fluid320` · `fluid1280` · `apple`.
The label is for humans and stays a label.

```json
GET  /engine
→ { "engine": "fluid160", "label": "Parakeet 160 ms",
    "available": ["fluid160", "fluid320", "fluid1280", "apple"] }

POST /engine   { "engine": "fluid320" }
→ { "engine": "fluid320", "label": "Parakeet 320 ms",
    "available": ["fluid160", "fluid320", "fluid1280", "apple"] }
```

`available` is there because `apple` is gated to macOS 26: a client on 15
is not offered it and does not have to find out from a 400. Offer exactly
what `available` lists.

`POST /engine` is the one route that takes a body. An unknown slug, or one
this Mac cannot run, is `400` in the error shape and nothing changes. The
same engine again changes nothing and announces nothing.

**Switching while listening is a stop and a start.** A half-swapped
pipeline would report numbers belonging to neither engine, so capture
stops, the engine changes, and capture starts again — `/status` says
`starting` in between, a consumer on `/events` sees a gap in frames, and
the `engine` event goes out on both transports. Switching while idle only
changes what the next `start` runs.

## Consuming it

```js
const token = '…'  // the contents of ~/Library/Application Support/Sonocles/token

const es = new EventSource(`http://127.0.0.1:7357/events?access_token=${token}`)
es.onmessage = (e) => {
  const f = JSON.parse(e.data)
  if (f.event === 'engine') return picker.select(f.engine)   // not a frame
  if (f.lagMs != null) { /* trust f.audioEnd for timing */ }
}
```

```js
const ws = new WebSocket('ws://127.0.0.1:7358')
ws.onopen = () => ws.send(JSON.stringify({ auth: token }))
ws.onmessage = (e) => {
  const m = JSON.parse(e.data)
  if ('status' in m) return   // the auth answer; frames have no status
  if (m.event === 'engine') return picker.select(m.engine)   // not a frame
  handle(m)
}
```

```bash
TOKEN="$(cat ~/Library/Application\ Support/Sonocles/token)"
curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:7357/
curl -H "Authorization: Bearer $TOKEN" -X POST http://127.0.0.1:7357/start
curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:7357/status
curl -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
     -d '{"engine": "fluid320"}' http://127.0.0.1:7357/engine
curl -sN "http://127.0.0.1:7357/events?access_token=$TOKEN"
```

Or `make start`, `make status`, `make engine`, `make engine ENGINE=fluid320`,
`make events`: the Makefile reads the file.
