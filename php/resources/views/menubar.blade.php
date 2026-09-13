<!doctype html>
<html lang="en" data-binary="{{ $binary ? 'yes' : 'no' }}">
<head>
<meta charset="utf-8">
<meta name="csrf-token" content="{{ csrf_token() }}">
<title>Sonocles</title>
<style>
  /*
   * The Swift popover (app/Sources/Sonocles/MenuBarView.swift) is the
   * reference layout and this is it, one to one: a 4 px terracotta rule, the
   * header, a centre panel with exactly one state showing, the controls
   * beneath. Sizes are its points. Styled as sonocles.com is (docs/BRAND.md):
   * limestone ground, ink, the terracotta signature. Dark is for the centre
   * panel while listening only — meter, transcript, the numbers that qualify
   * it — the way the site's stream of frames is dark on the limestone page:
   * it is the one thing here that is data rather than chrome.
   *
   * The three faces the site loads from Google ship in public/fonts under
   * the OFL, licences beside them, so the wordmark looks the same from
   * either popover.
   *
   * Views name the role, not the pigment, so a palette change stays here.
   */
  @font-face { font-family:"Fraunces"; src:url("{{ asset('fonts/Fraunces[SOFT,WONK,opsz,wght].ttf') }}") format("truetype"); font-weight:100 900; }
  @font-face { font-family:"Instrument Sans"; src:url("{{ asset('fonts/InstrumentSans[wdth,wght].ttf') }}") format("truetype"); font-weight:100 900; }
  @font-face { font-family:"IBM Plex Mono"; src:url("{{ asset('fonts/IBMPlexMono-Regular.ttf') }}") format("truetype"); font-weight:400; }
  @font-face { font-family:"IBM Plex Mono"; src:url("{{ asset('fonts/IBMPlexMono-Medium.ttf') }}") format("truetype"); font-weight:500; }

  :root {
    /* ground — the plaster */
    --stone:#FAF2E4; --stone-deep:#EFE5D2; --stone-sink:#E0D4BE; --stone-line:#DED0B8;
    /* ink */
    --ink:#2A211A; --ink-soft:#4E4034; --ink-faint:#6B5C4C;
    /* the signature: fills and marks; -ink for small text; -deep under white */
    --terracotta:#C4552E; --terracotta-ink:#A8431F; --terracotta-deep:#B2461F; --brick:#94331E;
    /* states — a small language the icon and the popover both speak */
    --olive:#6E7A52; --oxide:#B4453A;
    --script:#7A6A59;              /* the colour of an absent value */
    /* the dark block — the site's --ink; code-inset is the empty meter cell */
    --code-ground:#2A211A; --code-inset:#3B2F27; --code-text:#EDE4D6; --code-dim:#9E8F7C; --terracotta-soft:#DD7A4E;

    --wordmark:"Fraunces", ui-serif, Georgia, serif;
    --body:"Instrument Sans", system-ui, -apple-system, sans-serif;
    --mono:"IBM Plex Mono", ui-monospace, "SF Mono", Menlo, monospace;
  }
  * { box-sizing:border-box; }
  [hidden] { display:none !important; }
  html, body { margin:0; }
  body {
    width:344px; background:var(--stone); color:var(--ink);
    font:11.5px/1.35 var(--body); -webkit-font-smoothing:antialiased; user-select:none;
    display:flex; flex-direction:column; overflow:hidden;
  }
  .top-rule { height:4px; background:var(--terracotta); flex:none; }
  .rule { height:1px; background:var(--stone-line); flex:none; }

  /* header */
  header { display:flex; align-items:center; gap:9px; padding:11px 14px; flex:none; }
  .mark { width:19px; height:19px; flex:none; color:var(--script); }
  .mark[data-s="listening"], .mark[data-s="starting"] { color:var(--terracotta); }
  .wordmark { font:700 15px/1 var(--wordmark); font-variation-settings:"SOFT" 30,"WONK" 1,"opsz" 24; color:var(--ink); }
  .say { font:9px/1 var(--mono); color:var(--ink-faint); margin-left:-2px; }
  .spacer { flex:1; }
  .pill {
    display:inline-flex; align-items:center; gap:5px; padding:3px 7px; border-radius:999px;
    font:500 10.5px/1.2 var(--body); color:var(--script); background:rgba(122,106,89,.12);
  }
  .pill i { width:6px; height:6px; border-radius:50%; background:currentColor; }
  .pill[data-s="listening"] { color:var(--olive); background:rgba(110,122,82,.12); }
  .pill[data-s="starting"]  { color:var(--terracotta-ink); background:rgba(168,67,31,.12); }
  .pill[data-s="down"]      { color:var(--oxide); background:rgba(180,69,58,.12); }

  /* centre — one panel, one state. The transcript is data and sits on the
     dark block; the other states are prose and sit on the inset. */
  main { flex:none; padding:13px 14px; background:var(--stone-deep); }
  main[data-s="listening"], main[data-s="starting"] { background:var(--code-ground); }
  /* Every centre state is the same height, so switching never moves the controls. */
  .panel { height:112px; display:flex; flex-direction:column; justify-content:center; gap:6px; }
  .panel h2 { margin:0; font:500 12px/1.3 var(--body); color:var(--ink); }
  .panel p { margin:0; font:10.5px/1.4 var(--body); color:var(--ink-faint); }
  .panel .word { font:11px/1 var(--mono); color:var(--oxide); }
  .pulse { display:flex; gap:5px; height:5px; }
  .pulse i { width:5px; height:5px; border-radius:50%; background:var(--terracotta); animation:pulse 1.24s ease-in-out infinite; }
  .pulse i:nth-child(2) { animation-delay:.16s; } .pulse i:nth-child(3) { animation-delay:.32s; }
  @keyframes pulse { 0%,100% { opacity:.25; } 50% { opacity:.95; } }

  .live { height:112px; display:flex; flex-direction:column; gap:11px; }
  .live > * { flex:none; }
  /* Twenty cells over the useful range, -60 dBFS to clipping; the number
     carries the detail the bar throws away. */
  .meter { display:flex; align-items:center; gap:7px; flex:none; }
  .cells { display:flex; gap:2px; flex:1; }
  .cells i { flex:1; height:13px; border-radius:1.5px; background:var(--code-inset); }
  .cells i.on { background:var(--terracotta-soft); }
  .cells i.hot { background:var(--oxide); }
  .db { width:24px; text-align:right; font:10px/1 var(--mono); color:var(--code-text); }
  .db.absent { color:var(--script); }
  .dbu { font:9px/1 var(--mono); color:var(--code-dim); }
  /* Four lines, a fixed window over the running transcript, so an arriving
     word never shoves the rest of the popover down. Scrolled to the end, so
     what shows is the newest, and faded off the top rather than cut. The
     live line is bright; what has settled sits dim above it, as in the
     Swift popover. Empty, it says what will happen rather than looking broken. */
  .stream { height:60px; overflow:hidden; font:12px/15px var(--mono); color:var(--code-text);
    display:flex; flex-direction:column; justify-content:flex-end;
    -webkit-mask-image:linear-gradient(to bottom, transparent, black 14%); mask-image:linear-gradient(to bottom, transparent, black 14%); }
  .stream .empty { color:var(--script); }
  .f { display:block; flex:none; }
  .f.partial { color:var(--code-text); }
  .f.final   { color:var(--code-dim); }
  .stats { display:flex; gap:16px; font:10px/1 var(--mono); color:var(--code-dim); }
  .stats b { font:400 11px/1 var(--mono); color:var(--terracotta-soft); margin-left:5px; }
  /* An absent measurement is rendered in the colour of absence, never as 0. */
  .stats b.absent { color:var(--script); }

  /* controls */
  footer { padding:12px 14px; display:flex; flex-direction:column; gap:11px; flex:none; }
  .row { display:flex; align-items:center; gap:15px; }
  .row .label { font:11px/1 var(--body); color:var(--ink-faint); }
  .row .name { font:9.5px/1 var(--mono); color:var(--script); margin-left:auto; }
  .row.ports { gap:8px; font:10px/1 var(--mono); color:var(--ink-faint); }
  .row .port { display:flex; gap:4px; }
  .row .port span:first-child { color:var(--script); }
  .row .dot { color:var(--script); }
  .row .clients.absent { color:var(--script); }
  /* When to choose the selected engine — one muted line, follows the selection. */
  .guidance { margin:0; font:10.5px/1.3 var(--body); color:var(--ink-faint); white-space:nowrap; overflow:hidden; text-overflow:ellipsis; padding-top:1px; }
  /* The Control API block, always open: the token, masked, with Show, Copy
     and Rotate, and the file it lives in. */
  .pairing { display:flex; flex-direction:column; gap:7px; }
  .pairing > .label { font:11px/1 var(--body); color:var(--ink-faint); }
  .pairing p { margin:0; font:10px/1.35 var(--body); color:var(--ink-faint); }
  .pairing .file { font:10px/1 var(--mono); color:var(--script); white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .pairing .token {
    align-self:flex-start; max-width:100%; font:11px/1.35 var(--mono); color:var(--ink); user-select:text;
    padding:5px 9px; border:1px solid var(--stone-line); border-radius:6px; background:var(--stone);
    overflow-wrap:anywhere;
  }
  .pairing .token.absent { color:var(--script); }
  .pairing .row { gap:8px; }
  button.compact { font-size:9.5px; padding:4px 8px; }
  button.armed { background:var(--oxide); border-color:var(--oxide); color:#fff; }
  /* The process, in one dark line under everything: which build, which
     engine, how long the sockets have been up. */
  .strip { display:flex; align-items:center; gap:6px; padding:9px 14px; background:var(--code-ground);
    font:9.5px/1 var(--mono); color:var(--code-dim); white-space:nowrap; overflow:hidden; flex:none; }
  .strip i { width:5px; height:5px; border-radius:50%; background:var(--script); flex:none; }
  .strip[data-up="yes"] i { background:var(--terracotta-soft); }
  .strip .name { color:var(--code-text); }
  .strip .absent { color:var(--script); }
  /* The engine control: the site's pill, split into equal segments, as the
     Swift popover draws it. Built from what GET /engine lists as available,
     so on a Mac that cannot run Apple's engine there is no Apple segment. */
  .engine { display:flex; flex-direction:column; gap:6px; }
  .segmented { display:flex; border:1.2px solid var(--terracotta-ink); border-radius:999px; overflow:hidden; }
  .segmented button {
    flex:1; border:0; border-radius:0; padding:5px 0; font:600 11px/1 var(--body);
    color:var(--terracotta-ink); background:transparent;
  }
  .segmented button[aria-checked="true"] { background:var(--terracotta-deep); color:var(--stone); }
  .segmented button:disabled { opacity:.6; }
  .segmented:empty { border-color:var(--script); opacity:.6; min-height:23px; }

  /* The site's pill button. */
  button {
    font:600 11px/1 var(--body); padding:7px 12px; border-radius:999px; cursor:default;
    background:transparent; color:var(--terracotta-ink); border:1.2px solid var(--terracotta-ink);
  }
  button:disabled { color:var(--script); border-color:var(--script); opacity:.6; }
  button.go { background:var(--terracotta-deep); border-color:var(--terracotta-deep); color:#fff; }
  button.go:hover:not(:disabled) { background:var(--brick); border-color:var(--brick); }
  button.stop { background:var(--oxide); border-color:var(--oxide); color:#fff; }
</style>
</head>
<body>

<div class="top-rule"></div>

<header>
  {{-- The mark: arcs struck from one dot. The site's SVG geometry, in currentColor so the state can tint it. --}}
  <svg class="mark" id="mark" viewBox="0 0 32 32" aria-hidden="true">
    <circle cx="7" cy="16" r="3" fill="currentColor"/>
    <g stroke="currentColor" stroke-width="2.6" fill="none" stroke-linecap="round">
      <path d="M12 9.5a10 10 0 0 1 0 13"/>
      <path d="M17.5 6.5a16 16 0 0 1 0 19" opacity=".72"/>
      <path d="M23 3.5a22 22 0 0 1 0 25" opacity=".45"/>
    </g>
  </svg>
  <span class="wordmark">Sonocles</span>
  <span class="say">so-NOK-leez</span>
  <span class="spacer"></span>
  <span class="pill" id="state" data-s="down"><i></i><span id="state-label">Starting</span></span>
</header>
<div class="rule"></div>

<main id="centre" data-s="down">
  {{-- Listening: the meter, the live hypothesis, and the numbers that qualify them. --}}
  <div class="live" id="panel-live" hidden>
    <div class="meter">
      <div class="cells" id="cells"></div>
      <span class="db absent" id="db">––</span>
      <span class="dbu">dB</span>
    </div>
    <div class="stream" id="stream"><span class="empty" id="empty">Words appear here as you say them.</span></div>
    <div class="stats">
      <span>lag<b class="absent" id="lag">··</b></span>
      <span>every<b class="absent" id="gap">··</b></span>
      <span>ui<b class="absent" id="ui">··</b></span>
    </div>
  </div>

  {{-- Idle: the sockets are up, nothing is capturing. --}}
  <div class="panel" id="panel-idle" hidden>
    <h2>Not listening</h2>
    <p>The stream stays open — anything can start it, including a POST to /start.</p>
  </div>

  {{-- The engine itself is not answering: being spawned, or not bundled at all. --}}
  <div class="panel" id="panel-engine" hidden>
    <h2 id="engine-word">Starting the engine</h2>
    <div class="pulse" id="engine-pulse"><i></i><i></i><i></i></div>
    <p id="engine-note">Nothing answered on :{{ \App\Support\Sidecar::httpPort() }}, so the bundled sonocles-cli is being started.</p>
  </div>
</main>
<div class="rule"></div>

<footer>
  {{-- The engine: four short labels to choose from, the full name in script beside. Choosing posts to /engine/use; /status's engineId keeps it true and the engine event moves it when another client switches. --}}
  <div class="engine">
    <div class="row">
      <span class="label">Engine</span>
      <span class="name" id="engine">··</span>
    </div>
    <div class="segmented" id="segmented" role="radiogroup" aria-label="Engine"></div>
    <p class="guidance" id="guidance">&nbsp;</p>
  </div>
  {{-- Endpoints, not switches. The sockets bind at launch and stay up. Who is on them is /status's `clients`. --}}
  <div class="row ports">
    <span class="port"><span>HTTP</span><span>:{{ \App\Support\Sidecar::httpPort() }}</span></span>
    <span class="dot">·</span>
    <span class="port"><span>WS</span><span>:{{ \App\Support\Sidecar::wsPort() }}</span></span>
    <span class="dot">·</span>
    <span class="clients absent" id="clients">·· clients</span>
  </div>
  {{-- The bearer token every route is behind, as the engine's file has it right now. Always open: it is the one thing a new client needs from here. --}}
  <div class="pairing">
    <span class="label">Control API</span>
    <p>Every route is behind this token, the event stream included. Apps running as you read the file; rotating cuts every paired client off.</p>
    {{-- Truncated in the middle, as the Swift popover does, so the file name survives. --}}
    @php($file = \App\Support\Token::path())
    <span class="file" title="{{ $file }}">{{ mb_strlen($file) > 50 ? mb_substr($file, 0, 22).'…'.mb_substr($file, -27) : $file }}</span>
    <span class="token absent" id="token">··</span>
    <div class="row">
      <button class="compact" id="show" disabled>Show</button>
      <button class="compact" id="copy" disabled>Copy</button>
      <span class="spacer"></span>
      <button class="compact" id="rotate" disabled>Rotate</button>
    </div>
  </div>
  <div class="row">
    <button id="toggle" disabled>…</button>
    <span class="spacer"></span>
    <button id="quit">Quit</button>
  </div>
</footer>

{{-- What GET / and /status say about the process: the engine's version, the engine it is set to, and its uptime. --}}
<div class="strip" id="strip" data-up="no">
  <i></i>
  <span class="name" id="strip-name">sonocles ··</span>
  <span>·</span>
  <span id="strip-engine">··</span>
  <span>·</span>
  <span class="absent" id="strip-up">up ··</span>
</div>

<script>
const csrf = document.querySelector('meta[name=csrf-token]').content
const el = id => document.getElementById(id)

for (let i = 0; i < 20; i++) el('cells').appendChild(document.createElement('i'))

/*
 * Frames arrive here from ws://127.0.0.1:7358 — the engine's own socket, not
 * anything Laravel serves. PHP is not in this path, which is the entire reason
 * a NativePHP front end can wear an engine tuned to 180 ms without spending it.
 *
 * The one thing PHP contributes to the socket is the token, fetched from
 * /engine/token at each connect. The engine delivers nothing until the first
 * frame is {"auth": token} (PROTOCOL § Authentication), and a browser
 * WebSocket cannot carry a header, so the frame is the only way in.
 */
const WS = @json($websocket)

const HTTP_PORT = {{ \App\Support\Sidecar::httpPort() }}

let lastArrival = null

/*
 * What the front end costs.
 *
 * `ts` is stamped by the engine at emit. Subtracting it from Date.now() here
 * measures everything the Electron side adds on top of recognition: the socket
 * hop and the renderer waking up to handle it. It is deliberately reported
 * separately from `lag` rather than folded into it, because they are different
 * claims — one is the engine's, one is ours, and adding them would hide which
 * of the two moved.
 *
 * Clock note: both stamps come from the same machine, so this is a real
 * interval and not a comparison across hosts.
 */
function uiCost(frame) {
  if (typeof frame.ts !== 'number') return null
  const d = Date.now() - frame.ts
  return (d < 0 || d > 5000) ? null : d   // a clock step is not a measurement
}

/* A missing measurement reads as "··", never as zero. */
function show(id, value, unit) {
  const node = el(id)
  if (value === null || value === undefined) {
    node.textContent = '··'; node.classList.add('absent'); return
  }
  node.textContent = value + unit
  node.classList.remove('absent')
}

function render(frame) {
  el('empty')?.remove()

  const stream = el('stream')
  const last = stream.lastElementChild
  const openPartial = last && last.classList.contains('partial') ? last : null

  // Partials revise in place; a final settles the line they were revising, and
  // the next partial opens a new one. That mirrors the protocol: `text` is the
  // current utterance, not the session, so a running transcript is something
  // the consumer accumulates rather than something the frame carries.
  const line = openPartial ?? stream.appendChild(document.createElement('div'))
  line.className = 'f ' + (frame.type === 'final' ? 'final' : 'partial')
  line.textContent = frame.text

  while (stream.children.length > 60) stream.firstElementChild.remove()
  // Scrolled to the end, on a line boundary, so the oldest visible line is a
  // whole line rather than the bottom half of one.
  const lineHeight = 15
  stream.scrollTop = Math.ceil((stream.scrollHeight - stream.clientHeight) / lineHeight) * lineHeight

  // Partials only, and not because finals are unimportant.
  //
  // A final trails its speech by 1.6-3.1 s by construction — it waits out the
  // 1280 ms end-of-utterance debounce and then still has to decode. A partial
  // sits ~180 ms behind the live edge. Those are two unrelated distributions,
  // and a number that alternates between them reads as wild jitter in a value
  // that is in fact steady. This answers "how far behind the speaker are we",
  // which is a question only partials can answer.
  if (frame.type !== 'final') {
    // lagMs is signed and may be absent. Absent is not zero — see PROTOCOL.md.
    show('lag', frame.lagMs ?? null, ' ms')
  }

  const now = performance.now()
  show('gap', lastArrival === null ? null : Math.round(now - lastArrival), ' ms')
  lastArrival = now

  show('ui', uiCost(frame), ' ms')
}

async function connect() {
  const retry = ms => setTimeout(connect, ms)

  // Re-read on every connect, so a rotated token is one reconnect away.
  let token = null
  try { token = (await (await fetch('/engine/token')).json()).token } catch (_) {}
  if (!token) { retry(1000); return }

  let ws
  try { ws = new WebSocket(WS) } catch (e) { retry(1000); return }
  let refused = false
  ws.onopen = () => ws.send(JSON.stringify({ auth: token }))
  ws.onmessage = e => {
    let m
    try { m = JSON.parse(e.data) } catch (_) { return }
    // The auth answer has a status; frames have a type; events have an event.
    if ('status' in m) { if (m.status !== 200) { refused = true; ws.close() } return }
    if (m.event === 'engine') { select(m.engine); el('engine').textContent = m.label ?? el('engine').textContent; return }
    if (typeof m.type === 'string') render(m)
  }
  // A refusal is not a dropped socket: the file may not be the engine's yet,
  // and asking again every second would only be noise in its log.
  ws.onclose = () => retry(refused ? 3000 : 1000)
  ws.onerror = () => ws.close()
}
connect()

/*
 * Twenty cells over the useful range, from the peak level /status reports.
 * Below -60 dBFS is silence for our purposes and clipping pins at the top; the
 * top two cells are oxide, so a hot signal reads the way a REC light does.
 * levelDb is absent when not capturing, and absent is not silence.
 */
function meter(db) {
  const cells = el('cells').children
  const filled = typeof db === 'number' ? Math.max(0, Math.min(20, Math.floor((db + 60) / 60 * 20))) : 0
  for (let i = 0; i < 20; i++) cells[i].className = i < filled ? (i >= 18 ? 'hot' : 'on') : ''
  const node = el('db')
  node.textContent = typeof db === 'number' ? Math.round(db) : '––'
  node.classList.toggle('absent', typeof db !== 'number')
}

/* One panel showing, and the header agreeing with it. */
function state(s, label) {
  el('state').dataset.s = s
  el('state-label').textContent = label
  el('mark').dataset.s = s
  el('centre').dataset.s = s
  el('panel-live').hidden = !(s === 'listening' || s === 'starting')
  el('panel-idle').hidden = s !== 'idle'
  el('panel-engine').hidden = s !== 'down'
}

/*
 * The engine control.
 *
 * Segments are built once from GET /engine's `available` — via /engine/choices
 * — and selected from /status's `engineId` on every poll, so the control shows
 * what the engine is running and not what was last clicked here. A click
 * selects at once and posts; if the engine refuses, the next poll puts the
 * selection back where the engine says it is. The `engine` event on the
 * socket does the same for a switch made from the Swift popover or curl.
 */
const SHORT = { fluid160: '160 ms', fluid320: '320 ms', fluid1280: '1280 ms', apple: 'Apple' }
const LABEL = { fluid160: 'Parakeet 160 ms', fluid320: 'Parakeet 320 ms', fluid1280: 'Parakeet 1280 ms', apple: 'Apple SpeechAnalyzer' }
// When to choose it — the Swift popover's lines (MenuBarView.guidance),
// which are the measured and documented numbers and nothing else.
const GUIDANCE = {
  fluid160: 'About 180 ms behind you. The default — for cues and prompting.',
  fluid320: 'More context, fewer misheard words; half a second behind.',
  fluid1280: 'The most context, over a second behind — captions, not cues.',
  apple: "Apple's on-device recogniser. Words arrive in bursts, ~4 s apart.",
}
let engineId = null

function select(id) {
  engineId = id
  for (const b of el('segmented').children) b.setAttribute('aria-checked', b.dataset.engine === id)
  el('guidance').textContent = GUIDANCE[id] ?? '\u00a0'
  el('strip-engine').textContent = LABEL[id] ?? id ?? '··'
}

function setSegmentsDisabled(off) {
  for (const b of el('segmented').children) b.disabled = off
}

async function choices() {
  if (el('segmented').children.length) return
  let j
  try {
    const r = await fetch('/engine/choices')
    if (!r.ok) return
    j = await r.json()
  } catch (_) { return }
  for (const id of j.available ?? []) {
    const b = document.createElement('button')
    b.type = 'button'; b.setAttribute('role', 'radio')
    b.dataset.engine = id
    b.textContent = SHORT[id] ?? id
    b.onclick = () => use(id)
    el('segmented').appendChild(b)
  }
  select(j.engine ?? engineId)
}

async function use(id) {
  if (id === engineId) return
  select(id)
  setSegmentsDisabled(true)
  try {
    await fetch('/engine/use', {
      method: 'POST', headers: { 'X-CSRF-TOKEN': csrf, 'Content-Type': 'application/json' },
      body: JSON.stringify({ engine: id }),
    })
  } catch (_) {}
  // Poll rather than trust the answer: a switch while listening is a stop and
  // a start, and /status says `starting` in between.
  poll()
}

/*
 * The token, as /engine/status carries it on every poll — so a rotation from
 * the Swift popover or curl shows here within a second. Masked to its ends
 * unless shown; copied in full. Rotate is two clicks: the first arms it for
 * six seconds, the second does it, because a rotation cuts off every other
 * paired client and should not be one slip.
 */
let token = null
let tokenShown = false
let rotateArmed = false
let disarm = null

function masked(t) {
  return t.length > 12 ? t.slice(0, 6) + '…' + t.slice(-6) : t
}

function pairing(t) {
  token = t ?? null
  const node = el('token')
  node.textContent = token === null ? '··' : (tokenShown ? token : masked(token))
  node.classList.toggle('absent', token === null)
  for (const id of ['show', 'copy', 'rotate']) el(id).disabled = token === null
  el('show').textContent = tokenShown ? 'Hide' : 'Show'
  el('rotate').textContent = rotateArmed ? 'Really rotate' : 'Rotate'
  el('rotate').classList.toggle('armed', rotateArmed)
}

el('show').onclick = () => { tokenShown = !tokenShown; pairing(token) }
el('copy').onclick = async () => {
  if (token === null) return
  try { await navigator.clipboard.writeText(token) } catch (_) {}
}
el('rotate').onclick = async () => {
  if (!rotateArmed) {
    rotateArmed = true
    pairing(token)
    clearTimeout(disarm)
    disarm = setTimeout(() => { rotateArmed = false; pairing(token) }, 6000)
    return
  }
  clearTimeout(disarm)
  rotateArmed = false
  el('rotate').disabled = true
  try {
    await fetch('/engine/token/rotate', { method: 'POST', headers: { 'X-CSRF-TOKEN': csrf } })
  } catch (_) {}
  // The file is the truth; the next poll reads it back.
  poll()
}

/* `41s`, `12m`, `1h 12m`, `2d 3h` — the two largest units that are not zero. */
function uptime(seconds) {
  const total = Math.floor(seconds)
  const d = Math.floor(total / 86400), h = Math.floor(total % 86400 / 3600), m = Math.floor(total % 3600 / 60)
  if (d > 0) return `${d}d ${h}h`
  if (h > 0) return `${h}h ${m}m`
  if (m > 0) return `${m}m`
  return `${total % 60}s`
}

function strip(up, s) {
  el('strip').dataset.up = up ? 'yes' : 'no'
  const upNode = el('strip-up')
  upNode.textContent = up && typeof s?.uptime === 'number' ? 'up ' + uptime(s.uptime) : 'up ··'
  upNode.classList.toggle('absent', !(up && typeof s?.uptime === 'number'))
}

/*
 * The engine's version, from GET / — asked once each time the engine comes
 * up rather than on every poll, since it cannot change while it is running.
 */
let version = null

async function about() {
  if (version !== null) return
  try {
    const r = await fetch('/engine/about')
    if (!r.ok) return
    version = (await r.json()).version ?? null
  } catch (_) { return }
  if (version !== null) el('strip-name').textContent = `sonocles ${version}`
}

/* Control is PHP's job, and it happens at human speed. */
let listening = false

function clients(n) {
  const node = el('clients')
  node.textContent = typeof n !== 'number' ? '·· clients' : n === 0 ? 'no clients' : n === 1 ? '1 client' : `${n} clients`
  node.classList.toggle('absent', typeof n !== 'number')
}

async function poll() {
  try {
    const r = await fetch('/engine/status')
    const j = await r.json()
    const s = j.engine

    if (!j.up) {
      state('down', j.binary ? 'Starting' : 'No engine')
      el('engine-word').textContent = j.binary ? 'Starting the engine' : 'No engine'
      el('engine-pulse').hidden = !j.binary
      el('engine-note').textContent = j.binary
        ? `Nothing answered on :${HTTP_PORT}, so the bundled sonocles-cli is being started.`
        : 'extras/sonocles-cli is missing — run bin/sync-sidecar.sh.'
      el('toggle').disabled = true
      el('toggle').textContent = j.binary ? 'Waiting for engine' : 'Engine not bundled'
      el('toggle').className = ''
      el('engine').textContent = '··'
      clients(null)
      pairing(null)
      strip(false)
      version = null
      el('strip-name').textContent = 'sonocles ··'
      setSegmentsDisabled(true)
    } else if (!j.paired) {
      // Up, and refusing us. Not "starting": nothing is coming that will fix it
      // except the file changing, which every poll re-reads.
      state('down', 'Not paired')
      el('engine-word').textContent = 'Not paired'
      el('engine-pulse').hidden = true
      el('engine-note').textContent = `The engine on :${HTTP_PORT} refused the token in ~/Library/Application Support/Sonocles/token.`
      el('toggle').disabled = true
      el('toggle').textContent = 'Not paired'
      el('toggle').className = ''
      el('engine').textContent = '··'
      clients(null)
      pairing(j.token)
      strip(false)
      setSegmentsDisabled(true)
    } else {
      listening = !!s.listening
      state(s.state, { idle: 'Idle', starting: 'Starting', listening: 'Listening' }[s.state] ?? s.state)
      el('toggle').disabled = false
      el('toggle').textContent = listening ? 'Stop' : 'Start listening'
      el('toggle').className = listening ? 'stop' : 'go'
      el('engine').textContent = s.engine ?? '··'
      clients(s.clients)
      pairing(j.token)
      strip(true, s)
      about()
      await choices()
      if (typeof s.engineId === 'string') select(s.engineId)
      // Not while a switch or a start is in flight: the engine is between two
      // pipelines and a second click would race the first.
      setSegmentsDisabled(s.state === 'starting')

      meter(s.levelDb)
      if (!listening) { show('lag', null); show('gap', null); show('ui', null); lastArrival = null }
    }
  } catch (e) {
    state('down', 'Down')
    el('engine-word').textContent = 'Down'
    el('engine-pulse').hidden = true
    el('engine-note').textContent = 'The app could not reach its own server.'
    clients(null)
    strip(false)
  }
}

el('toggle').onclick = async () => {
  el('toggle').disabled = true
  await fetch(listening ? '/engine/stop' : '/engine/start', {
    method: 'POST', headers: { 'X-CSRF-TOKEN': csrf },
  })
  // Poll rather than trust the response: /start returns before capture is up.
  poll()
}

el('quit').onclick = () => fetch('/app/quit', { method: 'POST', headers: { 'X-CSRF-TOKEN': csrf } })

poll()
setInterval(poll, 1000)
</script>
</body>
</html>
