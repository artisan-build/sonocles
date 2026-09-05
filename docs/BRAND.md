# Sonocles

**so-NOK-leez** — rhymes with Hercules.

## The name is not decoration

*-cles* is Greek, not Roman. It is `-κλῆς` (*-klēs*), from `κλέος` (*kleos*):
glory, renown. The suffix in Sophocles (Σοφοκλῆς), Pericles (Περικλῆς),
Themistocles. It does not mean "maker of" or "master of". It means **known for**.

Heracles (Ἡρακλῆς) is the Greek one; **Hercules is what Rome called him**. The
`-cles` spelling English uses is Greek `-κλῆς` transliterated *through* Latin,
which is why it reads as belonging to both.

And then the part that is genuinely lucky. *Kleos* descends from the
Proto-Indo-European root `*ḱlew-`, **"to hear"** — the same root that gives
Sanskrit *śrávas*, Latin *clueō*, and, through Germanic, the English word
**loud**. *Kleos* is not abstract fame. It is *that which is heard about
someone*. In Homer it is specifically the glory that exists because bards sing
it and people hear it: renown as an acoustic event.

So the suffix does not merely mean famous. It means **heard of**. For a tool
whose entire job is hearing, that is an inheritance rather than a pun, and it is
the single best thing about the name.

One honest note: *sono-* is **Latin** (Greek for sound would be *phōno-*), so
Sonocles is a hybrid coinage. So is *television*. We are not going to pretend
otherwise, and we are not going to rename it Phonocles.

But the classical read is real, and it points somewhere useful. Sophocles wrote
words to be **spoken aloud**, in amphitheatres engineered so that a voice
carried to the back row without amplification — architecture as microphone. And
the oldest job in theatre is the **prompter**: someone in a box, following the
performance closely enough to know exactly where you are, and feeding you the
next line the moment you need it.

That is the whole product. Sonocles listens closely enough to know where you
are. Pteroprompter feeds you the next line.

## Why it exists

The speech-follow built into the teleprompter was fighting the encoder for CPU.
The prompter kept up; the audio did not. Dropped samples on a take you cannot
re-shoot are not a performance problem, they are a lost afternoon.

The Neural Engine was idle the whole time. Moving the listening there did not
make it faster so much as make it **free** — it stopped taking anything the
recording needed.

That story is the strongest thing we have and it should lead. It is specific,
it is checkable, and it explains the architecture without a single adjective.
"Runs on the Neural Engine" is a spec. "Your encoder is not competing with it"
is a reason.

## Licence and posture

Free, open source, MIT. Not a trial, not a freemium tier, not a loss leader for
something else. It exists because we needed it, and keeping it to ourselves
would not make the prompter any better.

Copy should say so plainly and once. A page that keeps insisting it is free
sounds like it is arguing with somebody.

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

**Attic red-figure pottery.** Not Pteroprompter's.

An earlier version of this document argued that sharing the prompter's palette
was accurate family resemblance. It was not; it was borrowing, and it made two
products look like one. They are siblings and one consumes the other, but a tool
with its own name deserves its own colours.

The source is specific rather than vaguely classical. Fifth-century Attic vases
are three materials and nothing else — the terracotta of the clay, the black
slip fired over it, and the pale bone of the unpainted ground — and they are very
often *pictures of performance*: the chorus, the aulos player, the actor holding
a mask. It is the right well to draw from, and it lands nowhere near amber.

The tradition has two techniques, and we use both:

- **Red-figure** — light figures on black slip. The app. It stays dark because
  it sits over whatever you are actually doing, frequently while a camera is
  running, and should never flash white at you mid-take.
- **Black-figure** — dark figures on bare clay. The site. Light, warm, and
  unmistakably not the same page as the prompter's.

Values live in `SonoclesCore/Brand.swift`.

| role | token | value |
|---|---|---|
| black slip, deepest | `slip` | `#100C0A` |
| ground | `ground` | `#16110E` |
| popover | `panel` | `#1C1611` |
| raised | `raised` | `#241C16` |
| inset / meter cell | `field` | `#2B211A` |
| unpainted ground, brightest text | `bone` | `#EFE3D0` |
| body text | `body` | `#CDBBA3` |
| secondary | `faint` | `#9A8874` |
| **absent values** | `script` | `#6B5C4B` |
| **the signature — fired clay** | `terracotta` | `#C86F45` |
| aged bronze — listening, healthy | `verdigris` | `#7FA88C` |
| ochre — attention without alarm | `ochre` | `#D9A441` |
| iron oxide — hot, recording, stop | `oxide` | `#B4453A` |

Views name the *role*, not the pigment, so a palette change stays in one file
instead of spreading through the interface.

`script` is load-bearing beyond its name: it is the colour of a value we do not
have. A missing latency, an unmeasured level, an empty transcript. Absence gets
its own colour so it is never mistaken for a number.

## Type

| use | face | why |
|---|---|---|
| wordmark, kickers | **Cinzel**, letterspaced | Drawn from first-century Roman inscriptional capitals — the origin of our capital letterforms. Used sparingly; it is seasoning. |
| headings | **Cormorant Garamond** | High-contrast old-style. Classical without costume. |
| body | **Instrument Sans** | A workhorse. The page is about a technical tool and has to be read. |
| data, code, frames | **IBM Plex Mono** | Neutral. Numbers should look like numbers. |

No marble textures, no laurel wreaths, no columns. The classical reference lives
in the letterforms and the palette, which is where it can be taken seriously.

## Mark

Concentric arcs. An amphitheatre seen from above and a sound wave are the same
drawing, which is the sort of coincidence worth taking.

At menu bar size the mark gives way to legibility — a filled waveform while
listening, an outline while idle, so state reads from across the room without
opening anything.

## The plates

The site is illustrated with generated Attic red-figure vase paintings, each
captioned as a museum catalogue object — accession line, attribution, century.
The register is academic and completely straight.

That is the whole joke, and it only works if nobody winks. A caption reading
"conventionally read as an allegory of resource contention" is funny precisely
because it is written the way a real label is written. The moment the page
nudges the reader, it becomes a costume rather than a conceit.

`art/make.py` generates them. Prompts obey the real drawing conventions —
reserved figures, black slip, relief line, profile faces — so the only
anachronism is ever the *subject*. A fifth-century painter handed a microphone
would have drawn it exactly like that.

Two working notes. **No lettering, ever**: the model cannot spell Greek, and
gibberish reads as carelessness rather than antiquity, so the wordmark is set in
Cinzel in the page instead. And **specify clothing explicitly** — classical
nudity is authentic to the source and will get a generation refused by content
moderation, which costs a retry and teaches nothing.

The last caption on the page admits they are not ancient. Holding that to the
end is the setup; saying it at all is the manners.

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
