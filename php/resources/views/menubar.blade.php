<!doctype html>
<html lang="en" data-binary="{{ $binary ? 'yes' : 'no' }}">
<head>
<meta charset="utf-8">
<meta name="csrf-token" content="{{ csrf_token() }}">
<title>Sonocles</title>
<style>
  /*
   * The popover, styled as sonocles.com is (docs/BRAND.md): limestone
   * ground, ink, the terracotta signature, and a 4 px terracotta rule along
   * the top — the foot of the site's colonnade — so the popover and the site
   * open the same way. Dark is for the stream only, the way the site's stream
   * of frames is dark on the limestone page: it is the one thing here that is
   * data rather than chrome. The Swift popover (app/Sources/Sonocles/
   * MenuBarView.swift) is the reference rendering.
   *
   * The three faces the site loads from Google ship in public/fonts under
   * the OFL, licences beside them. An earlier version of this file argued
   * that two webfonts were too much to spend on nine words of chrome; the
   * Swift app bundles them now, and the two popovers should not disagree
   * about what the wordmark looks like.
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
    /* the dark block — the stream, nowhere else */
    --code-ground:#2A211A; --code-text:#EDE4D6; --code-dim:#9E8F7C; --terracotta-soft:#DD7A4E;

    --wordmark:"Fraunces", ui-serif, Georgia, serif;
    --body:"Instrument Sans", system-ui, -apple-system, sans-serif;
    --mono:"IBM Plex Mono", ui-monospace, "SF Mono", Menlo, monospace;
  }
  * { box-sizing:border-box; }
  html, body { margin:0; height:100%; }
  body {
    background:var(--stone); color:var(--ink);
    font:12px/1.45 var(--body); -webkit-font-smoothing:antialiased; user-select:none;
    display:flex; flex-direction:column; overflow:hidden;
  }
  .top-rule { height:4px; background:var(--terracotta); flex:none; }
  .rule { height:1px; background:var(--stone-line); flex:none; }

  header { display:flex; align-items:center; gap:9px; padding:11px 14px; flex:none; }
  .mark { width:19px; height:19px; flex:none; color:var(--script); }
  .mark[data-s="listening"] { color:var(--terracotta); }
  h1 { font:700 15px/1 var(--wordmark); font-variation-settings:"SOFT" 30,"WONK" 1,"opsz" 24; color:var(--ink); margin:0; }
  .say { font:9px/1 var(--mono); color:var(--ink-faint); margin-left:-2px; }
  .state {
    margin-left:auto; display:inline-flex; align-items:center; gap:5px; padding:3px 7px;
    border-radius:999px; font:500 10.5px/1.2 var(--body); text-transform:capitalize;
    color:var(--script); background:rgba(122,106,89,.12);
  }
  .state::before { content:""; width:6px; height:6px; border-radius:50%; background:currentColor; }
  .state[data-s="listening"] { color:var(--olive); background:rgba(110,122,82,.12); }
  .state[data-s="starting"]  { color:var(--terracotta-ink); background:rgba(168,67,31,.12); }
  .state[data-s="down"]      { color:var(--oxide); background:rgba(180,69,58,.12); }

  /* The centre: meter, stream and the numbers that qualify it, on the inset
     like the site's cards, with the stream itself on ink like the site's. */
  main { flex:1; min-height:0; display:flex; flex-direction:column; padding:13px 14px; background:var(--stone-deep); }
  .meter { height:5px; background:var(--stone-sink); border-radius:999px; overflow:hidden; margin-bottom:11px; flex:none; }
  .meter i { display:block; height:100%; width:0; background:var(--terracotta); transition:width .08s linear; }

  .stream {
    flex:1; min-height:0; overflow-y:auto; background:var(--code-ground); border-radius:7px;
    padding:11px 12px; font:12px/1.6 var(--mono); color:var(--code-text);
    display:flex; flex-direction:column; gap:7px; scrollbar-width:thin;
  }
  .stream .empty { color:var(--script); }
  .f { display:block; }
  .f.partial { color:var(--code-dim); }
  .f.final   { color:var(--code-text); }
  .f b { font-weight:400; color:var(--terracotta-soft); }

  .stats { display:grid; grid-template-columns:repeat(3,1fr); gap:8px; margin:11px 0 0; flex:none; }
  .stat { background:var(--stone); border:1px solid var(--stone-line); border-radius:6px; padding:7px 9px; }
  .stat span { display:block; font:500 9px/1 var(--mono); letter-spacing:.09em; text-transform:uppercase; color:var(--terracotta-ink); margin-bottom:4px; }
  .stat b { font:500 14px/1 var(--mono); color:var(--ink); }
  /* An absent measurement is rendered in the colour of absence, never as 0. */
  .stat b.absent { color:var(--script); font-weight:400; }

  footer { display:flex; gap:8px; align-items:center; padding:12px 14px; flex:none; }
  /* The site's pill button. */
  button {
    font:600 11px/1 var(--body); padding:7px 12px; border-radius:999px; cursor:default;
    background:transparent; color:var(--terracotta-ink); border:1.2px solid var(--terracotta-ink);
  }
  button:disabled { color:var(--script); border-color:var(--script); opacity:.6; }
  button.go { background:var(--terracotta-deep); border-color:var(--terracotta-deep); color:#fff; }
  button.go:hover:not(:disabled) { background:var(--brick); border-color:var(--brick); }
  button.stop { background:var(--oxide); border-color:var(--oxide); color:#fff; }
  .note { margin-left:auto; font:10px/1.4 var(--mono); color:var(--script); text-align:right; }
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
  <h1>Sonocles</h1>
  <span class="say">so-NOK-leez</span>
  <div class="state" id="state" data-s="idle">starting</div>
</header>
<div class="rule"></div>

<main>
  <div class="meter"><i id="meter"></i></div>

  <div class="stream" id="stream"><div class="empty" id="empty">nothing yet</div></div>

  <div class="stats">
    <div class="stat"><span>lag</span><b class="absent" id="lag">··</b></div>
    <div class="stat"><span>gap</span><b class="absent" id="gap">··</b></div>
    <div class="stat"><span>ui&nbsp;cost</span><b class="absent" id="ui">··</b></div>
  </div>
</main>
<div class="rule"></div>

<footer>
  <button id="toggle" disabled>…</button>
  <div class="note" id="note"></div>
</footer>

<script>
const csrf = document.querySelector('meta[name=csrf-token]').content
const el = id => document.getElementById(id)

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

function show(id, value, unit) {
  const node = el(id)
  if (value === null || value === undefined) {
    node.textContent = '··'; node.classList.add('absent'); return
  }
  node.textContent = (value >= 0 ? '' : '') + value + unit
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
  stream.scrollTop = stream.scrollHeight

  // Partials only, and not because finals are unimportant.
  //
  // A final trails its speech by 1.6-3.1 s by construction — it waits out the
  // 1280 ms end-of-utterance debounce and then still has to decode. A partial
  // sits ~180 ms behind the live edge. Those are two unrelated distributions,
  // and a tile that alternates between them reads as wild jitter in a number
  // that is in fact steady. This tile answers "how far behind the speaker are
  // we", which is a question only partials can answer.
  if (frame.type !== 'final') {
    // lagMs is signed and may be absent. Absent is not zero — see PROTOCOL.md.
    show('lag', frame.lagMs ?? null, 'ms')
  }

  const now = performance.now()
  show('gap', lastArrival === null ? null : Math.round(now - lastArrival), 'ms')
  lastArrival = now

  show('ui', uiCost(frame), 'ms')
}

function connect() {
  let ws
  try { ws = new WebSocket(WS) } catch (e) { setTimeout(connect, 1000); return }
  ws.onmessage = e => { try { render(JSON.parse(e.data)) } catch (_) {} }
  ws.onclose = () => setTimeout(connect, 1000)
  ws.onerror = () => ws.close()
}
connect()

/* Control is PHP's job, and it happens at human speed. */
let listening = false

async function poll() {
  try {
    const r = await fetch('/engine/status')
    const j = await r.json()
    const s = j.engine

    if (!j.up) {
      el('state').dataset.s = 'down'
      el('mark').dataset.s = 'down'
      el('state').textContent = j.binary ? 'starting' : 'no engine'
      el('toggle').disabled = true
      el('toggle').textContent = j.binary ? 'waiting for engine' : 'engine not bundled'
      el('note').textContent = j.binary ? '' : 'extras/sonocles-cli is missing — run bin/sync-sidecar.sh'
    } else {
      listening = !!s.listening
      el('state').dataset.s = s.state
      el('mark').dataset.s = s.state
      el('state').textContent = s.state
      el('toggle').disabled = false
      el('toggle').textContent = listening ? 'Stop listening' : 'Start listening'
      el('toggle').className = listening ? 'stop' : 'go'
      el('note').textContent = s.engine + (s.clients ? ' · ' + s.clients + ' client' + (s.clients > 1 ? 's' : '') : '')

      // levelDb is absent when not capturing, and absent is not silence.
      el('meter').style.width = (typeof s.levelDb === 'number')
        ? Math.max(0, Math.min(100, (s.levelDb + 60) / 60 * 100)) + '%'
        : '0%'
      if (!listening) { show('lag', null); show('gap', null); show('ui', null); lastArrival = null }
    }
  } catch (e) {
    el('state').dataset.s = 'down'
    el('mark').dataset.s = 'down'
    el('state').textContent = 'down'
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

poll()
setInterval(poll, 1000)
</script>
</body>
</html>
