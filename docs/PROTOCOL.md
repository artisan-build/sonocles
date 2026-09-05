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
| `GET /events` | the SSE stream |
| `GET /status` | current state |
| `POST /start` | begin capture |
| `POST /stop` | end capture |

```json
{ "state": "listening", "listening": true,
  "engine": "Parakeet EOU 120M (160 ms)", "clients": 1, "uptime": 41.2 }
```

`state` is `idle` · `starting` · `listening`. Three states rather than a
boolean because `POST /start` returns before capture is up — models load,
macOS may ask for the microphone — and answering `listening: false` to a
request that just succeeded reads as a failure. Poll until `listening`.

### Authentication

HTTP Basic on `/status`, `/start` and `/stop`, configured in the app's popover
and stored in the Keychain. The control API can switch on a microphone, so its
credential is a real secret and does not belong in a plist.

`/events` is deliberately left open. `EventSource` cannot set an `Authorization`
header, so locking the stream would mean credentials in a URL — worse than a
loopback-only read endpoint. The control routes are the ones that change state
and the ones a hostile local page could reach, so those carry the lock.

## Consuming it

```js
const es = new EventSource('http://127.0.0.1:7357/events')
es.onmessage = (e) => {
  const f = JSON.parse(e.data)
  if (f.lagMs != null) { /* trust f.audioEnd for timing */ }
}
```

```js
const ws = new WebSocket('ws://127.0.0.1:7358')
ws.onmessage = (e) => handle(JSON.parse(e.data))
```

```bash
curl -u user:pass -X POST http://127.0.0.1:7357/start
curl -u user:pass http://127.0.0.1:7357/status
```
