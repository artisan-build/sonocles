# Sonocles

**so-NOK-leez** — rhymes with Hercules.

## The name is not decoration

*Sono-* is sound. *-cles* is the Greek `-κλῆς`, meaning glory or renown — the
suffix in Sophocles, Pericles, Themistocles, Heracles. It does not mean
"maker of" or "master of". It means **known for**.

So Sonocles is, roughly, *renowned for sound*. Which is a slightly grand thing
to call a menu bar utility, and the joke is deliberate: a 220 MB model listening
for the word "okay" does not need a heroic name, and having one is funnier than
not having one.

But the classical read is real, and it points somewhere useful. Sophocles wrote
words to be **spoken aloud**, in amphitheatres engineered so that a voice
carried to the back row without amplification — architecture as microphone. And
the oldest job in theatre is the **prompter**: someone in a box, following the
performance closely enough to know exactly where you are, and feeding you the
next line the moment you need it.

That is the whole product. Sonocles listens closely enough to know where you
are. Pteroprompter feeds you the next line.

## What it is

An on-device speech sidecar. It hears you, and it streams what you said to
whatever is listening — 180 milliseconds behind you, and nowhere else.

## What it is not

Not a dictation app. That distinction is the entire positioning:

|  | dictation | Sonocles |
|---|---|---|
| gives you text | when you stop talking | while you are still talking |
| aims at | a text field | a socket |
| latency that matters | none, really | all of it |
| you are | writing | performing |

Dictation apps are excellent and there are many. They are built around a
different moment: you speak, you stop, the text appears, you carry on. Nothing
downstream is waiting.

Sonocles exists for the case where something *is* waiting. A prompter that has
to scroll at your pace. A cue that has to fire on a word. An editor that needs
to know when you said it, not when the transcript arrived. In that world the
gap between "you spoke" and "the software knew" is the only number that matters,
and everything else is negotiable.

## Voice

The way the codebase is commented, extended outward:

- **Say the number.** "180 ms behind you" beats "blazing fast" in every
  instance, because one of them is checkable.
- **Admit what it does not do.** The 120M model mishears "dad" as "debt". Say
  so. The person who finds out from us trusts the rest; the person who finds
  out themselves does not.
- **Never dress up an absence.** Not in the UI, not in the wire format, not in
  the copy. An unmeasured latency is not zero, and a feature that is planned is
  not a feature.
- **Dry, not zany.** The name is already the joke. Spending it once is
  sufficient.
- **No exclamation marks.** Not a rule so much as an observation about what
  happens when you allow the first one.

Things we do not say: blazing, seamless, effortless, magical, revolutionary,
game-changing, powered by AI, unlock, supercharge, "just works".

Things we do say: on-device, measured, 180 ms, loopback only, one time only,
open the CLI and check.

## Palette

Shared with Pteroprompter, deliberately. They are sibling tools by the same
author and one consumes the other; a family resemblance is accurate rather than
lazy. The values live in `SonoclesCore/Brand.swift`, lifted verbatim from
`pteroprompter.com/resources/css/app.css` rather than eyeballed — "close enough"
across two codebases is how a brand quietly drifts.

Warm dark throughout, in both appearances. This is a tool that sits over
whatever you are actually looking at, often while a camera is running. It should
never flash white at you mid-take.

| role | token | value |
|---|---|---|
| deepest ground | `screen` | `#0E0C09` |
| popover ground | `panel` | `#171410` |
| live area | `ink` | `#14110D` |
| inset / meter cell | `field` | `#1E1A15` |
| primary text | `bright` | `#ECE6DA` |
| body text | `body` | `#C9C1B2` |
| secondary | `faint` | `#8F8674` |
| tertiary / absent values | `script` | `#6F6656` |
| accent, signal, action | `stress` | `#F2B45C` |
| listening | `quote` | `#A6CF9E` |
| hot / recording | `rec` | `#E06666` |

Amber against warm near-black reads as lamplight and bronze rather than as
generic dark mode, which suits the name without anyone having to draw a column.

`script` is load-bearing beyond its name: it is the colour of a value we do not
have. A missing latency, an unmeasured level, an empty transcript. Absence gets
its own colour so it is never mistaken for a number.

## Mark

Concentric arcs. An amphitheatre seen from above and a sound wave are the same
drawing, which is the sort of coincidence worth taking.

At menu bar size the mark gives way to legibility — a filled waveform while
listening, an outline while idle, so state reads from across the room without
opening anything.

## Copy

### One-liner

> Words, while you're still saying them.

### Standfirst

> Sonocles listens to your Mac's microphone and streams what you say — word by
> word, about 180 milliseconds behind you. Everything runs on the Neural Engine.
> Nothing leaves the machine.

### The paragraph that does the work

> Dictation gives you a sentence once you have finished saying it. That is fine
> when you are writing and nothing downstream is waiting. It is useless when
> something is: a teleprompter that has to keep your pace, a cue that has to
> fire on a word, an editor that needs to know when you said it rather than when
> the transcript turned up.
>
> Sonocles is built for that second case. It streams partial hypotheses as the
> words arrive, each one carrying the audio timestamp of when it was actually
> spoken — so whatever is listening can lead you rather than trail you.

### Feature lines

**Word by word, not sentence by sentence.**
Arrivals roughly every 200 ms, about one word each. Apple's own Speech framework
delivers the same sentence in four bursts, 3.7 seconds apart. We publish the
measurement and ship the comparison, so you can re-run it: `make baseline`.

**It knows when you said it.**
Every frame carries the audio time it describes, not just the time it arrived.
Arrival time drifts with the delivery schedule; audio time does not. That is the
difference between a marker you can cut on and a marker you have to nudge.

**It does not make things up.**
Thirty seconds of piano at -9 dBFS produced zero words. A transducer emits
tokens as acoustic evidence arrives, so with no speech there is nothing to emit.
Models that hallucinate over music are a genuine hazard when the output drives a
scroll.

**Nothing leaves your Mac.**
The models download once and run on the Neural Engine. The sockets bind to
loopback only. There is no account, no key, and no server — not as a policy, but
because none was ever built.

**Anything can drive it.**
SSE and WebSocket, both live at once. An HTTP control API to start and stop it,
behind Basic auth if you want it. A CLI that reports its own latency, because
the claims above should be yours to check rather than ours to assert.

### Footer line

> Made for Pteroprompter. Useful on its own.
