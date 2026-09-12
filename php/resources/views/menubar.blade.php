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
  .panel { height:92px; display:flex; flex-direction:column; justify-content:center; gap:6px; }
  .panel h2 { margin:0; font:500 12px/1.3 var(--body); color:var(--ink); }
  .panel p { margin:0; font:10.5px/1.4 var(--body); color:var(--ink-faint); }
  .panel .word { font:11px/1 var(--mono); color:var(--oxide); }
  .pulse { display:flex; gap:5px; height:5px; }
  .pulse i { width:5px; height:5px; border-radius:50%; background:var(--terracotta); animation:pulse 1.24s ease-in-out infinite; }
  .pulse i:nth-child(2) { animation-delay:.16s; } .pulse i:nth-child(3) { animation-delay:.32s; }
  @keyframes pulse { 0%,100% { opacity:.25; } 50% { opacity:.95; } }

  .live { height:92px; display:flex; flex-direction:column; gap:11px; }
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
  /* Three lines, reserved, so an arriving word never shoves the rest of the
     popover down. Scrolled to the end, so what shows is the newest — the
     head-truncation the Swift popover gets from lineLimit. */
  .stream { height:45px; overflow:hidden; font:12px/15px var(--mono); color:var(--code-text); }
  .stream .empty { color:var(--script); }
  .f { display:block; }
  .f.partial { color:var(--code-dim); }
  .f.final   { color:var(--code-text); }
  .stats { display:flex; gap:16px; font:10px/1 var(--mono); color:var(--code-dim); }
  .stats b { font:400 11px/1 var(--mono); color:var(--terracotta-soft); margin-left:5px; }
  /* An absent measurement is rendered in the colour of absence, never as 0. */
  .stats b.absent { color:var(--script); }

  /* controls */
  footer { padding:12px 14px; display:flex; flex-direction:column; gap:11px; flex:none; }
  .row { display:flex; align-items:center; gap:15px; }
  .row .label { font:11px/1 var(--body); color:var(--ink-faint); }
  .row .name { font:9.5px/1 var(--mono); color:var(--script); margin-left:auto; }
  .row .port { display:flex; gap:4px; font:10px/1 var(--mono); }
  .row .port span:first-child { color:var(--script); }
  .row .port span:last-child { color:var(--ink-faint); }
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
    <div class="stream" id="stream"><span class="empty" id="empty">Listening…</span></div>
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
    <p id="engine-note">Nothing answered on :{{ \App\Support\Sidecar::HTTP_PORT }}, so the bundled sonocles-cli is being started.</p>
  </div>
</main>
<div class="rule"></div>

<footer>
  {{-- The engine is chosen when sonocles-cli is spawned; the control API has no route to change it, so this reports rather than offers. --}}
  <div class="row">
    <span class="label">Engine</span>
    <span class="name" id="engine">··</span>
  </div>
  {{-- Endpoints, not switches. The sockets bind at launch and stay up. --}}
  <div class="row">
    <span class="port"><span>HTTP</span><span>:{{ \App\Support\Sidecar::HTTP_PORT }}</span></span>
    <span class="port"><span>WS</span><span>:{{ \App\Support\Sidecar::WS_PORT }}</span></span>
    <span class="port"><span>clients</span><span id="clients">··</span></span>
  </div>
  <div class="row">
    <button id="toggle" disabled>…</button>
    <span class="spacer"></span>
    <button id="quit">Quit</button>
  </div>
</footer>

<script>
const csrf = document.querySelector('meta[name=csrf-token]').content
const el = id => document.getElementById(id)

for (let i = 0; i < 20; i++) el('cells').appendChild(document.createElement('i'))

/*
 * Frames arrive here from ws://127.0.0.1:7358 — the engine's own socket, not
 * anything Laravel serves. PHP is not in this path, which is the entire reason
 * a NativePHP front end can wear an engine tuned to 180 ms without spending it.
 */
const WS = @json($websocket)

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

function connect() {
  let ws
  try { ws = new WebSocket(WS) } catch (e) { setTimeout(connect, 1000); return }
  ws.onmessage = e => { try { render(JSON.parse(e.data)) } catch (_) {} }
  ws.onclose = () => setTimeout(connect, 1000)
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

/* Control is PHP's job, and it happens at human speed. */
let listening = false

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
        ? 'Nothing answered on :7357, so the bundled sonocles-cli is being started.'
        : 'extras/sonocles-cli is missing — run bin/sync-sidecar.sh.'
      el('toggle').disabled = true
      el('toggle').textContent = j.binary ? 'Waiting for engine' : 'Engine not bundled'
      el('toggle').className = ''
      el('engine').textContent = '··'
      el('clients').textContent = '··'
    } else {
      listening = !!s.listening
      state(s.state, { idle: 'Idle', starting: 'Starting', listening: 'Listening' }[s.state] ?? s.state)
      el('toggle').disabled = false
      el('toggle').textContent = listening ? 'Stop' : 'Start listening'
      el('toggle').className = listening ? 'stop' : 'go'
      el('engine').textContent = s.engine ?? '··'
      el('clients').textContent = typeof s.clients === 'number' ? s.clients : '··'

      meter(s.levelDb)
      if (!listening) { show('lag', null); show('gap', null); show('ui', null); lastArrival = null }
    }
  } catch (e) {
    state('down', 'Down')
    el('engine-word').textContent = 'Down'
    el('engine-pulse').hidden = true
    el('engine-note').textContent = 'The app could not reach its own server.'
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
