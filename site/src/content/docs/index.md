---
title: Overview
description: Sonocles turns your Mac's microphone into a live stream of text — over WebSocket or server-sent events, word by word, about 180 milliseconds behind you. These pages are how to point something at it.
---

Sonocles is a menu bar app and a small HTTP API. Launch it and two sockets
come up on loopback — server-sent events on `7357`, WebSocket on `7358` —
and stay up for as long as the app runs. Start listening, from the popover or
with `POST /start`, and every word you say arrives on both as a JSON frame
carrying the text, a sequence number, the audio time it was spoken, and how
far behind you it turned up.

It exists because [Pteroprompter](https://pteroprompter.com) needed a
speech-follow that did not fight the encoder for CPU. Nothing about it is
prompter-shaped, though: it streams words and timestamps at a socket, and
what listens is your business.

## The shortest possible consumer

```js title="one line, either transport"
new EventSource('http://127.0.0.1:7357/events').onmessage = (e) => console.log(JSON.parse(e.data).text)
```

```json title="what arrives, five times a second"
{ "type": "partial", "text": "the menu bar", "ts": 1788569799791, "seq": 3,
  "audioStart": 40.28, "audioEnd": 40.8, "lagMs": 200 }
```

Use `audioEnd`, not `ts`. A missing `lagMs` means unmeasured — never zero.
We are quite firm about this, and [the protocol page](/docs/protocol) says
why.

## Where to go next

The pages in the sidebar are in reading order. The two that make Sonocles
different from a dictation app are **The protocol** — what a frame carries
and what each field is for — and **Engines and the measurement** — why it
is Parakeet on the Neural Engine and not Apple's Speech framework, with the
numbers.
