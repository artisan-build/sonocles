<!doctype html>
<html lang="en" data-binary="{{ $binary ? 'yes' : 'no' }}">
<head>
<meta charset="utf-8">
<meta name="csrf-token" content="{{ csrf_token() }}">
<title>Sonocles</title>
<style>
  /*
   * Palette from docs/BRAND.md. Fraunces and Instrument Sans are not bundled —
   * shipping two webfonts into a menu bar popover to set nine words of chrome is
   * not a trade worth making — so this falls back to the system stack and keeps
   * the colours, which are the part that carries the identity.
   */
  :root {
    --slip:#100C0A; --panel:#1C1611; --raised:#241C16; --field:#2B211A;
    --bone:#EFE3D0; --body:#CDBBA3; --faint:#9A8874;
    --script:#6B5C4B;              /* the colour of an absent value */
    --terracotta:#C86F45; --verdigris:#7FA88C; --oxide:#B4453A; --ochre:#D9A441;
    --mono: ui-monospace, "SF Mono", "IBM Plex Mono", Menlo, monospace;
  }
  * { box-sizing:border-box; }
  body {
    margin:0; padding:16px; background:var(--panel); color:var(--body);
    font:13px/1.45 system-ui, -apple-system, "Instrument Sans", sans-serif;
    -webkit-font-smoothing:antialiased; user-select:none;
    display:flex; flex-direction:column; height:100vh;
  }
  header { display:flex; align-items:center; gap:9px; margin-bottom:14px; }
  .mark { width:20px; height:20px; flex:none; }
  h1 { font:600 15px/1 ui-serif, Georgia, serif; color:var(--bone); margin:0; letter-spacing:.01em; }
  .state { margin-left:auto; font:11px/1 var(--mono); letter-spacing:.08em; text-transform:uppercase; color:var(--script); }
  .state[data-s="listening"] { color:var(--verdigris); }
  .state[data-s="starting"]  { color:var(--ochre); }
  .state[data-s="down"]      { color:var(--oxide); }

  .meter { height:4px; background:var(--field); border-radius:2px; overflow:hidden; margin-bottom:12px; }
  .meter i { display:block; height:100%; width:0; background:var(--terracotta); transition:width .08s linear; }

  .stream {
    flex:1; min-height:0; overflow-y:auto; background:var(--slip); border-radius:7px;
    padding:11px 12px; font:13px/1.6 var(--mono); color:var(--body);
    display:flex; flex-direction:column; gap:7px; scrollbar-width:thin;
  }
  .stream .empty { color:var(--script); font-style:italic; }
  .f { display:block; }
  .f.partial { color:var(--faint); }
  .f.final   { color:var(--bone); }
  .f b { font-weight:400; color:var(--terracotta); }

  .stats { display:grid; grid-template-columns:repeat(3,1fr); gap:8px; margin:12px 0 10px; }
  .stat { background:var(--raised); border-radius:6px; padding:7px 9px; }
  .stat span { display:block; font:9px/1 var(--mono); letter-spacing:.09em; text-transform:uppercase; color:var(--script); margin-bottom:4px; }
  .stat b { font:600 14px/1 var(--mono); color:var(--bone); }
  /* An absent measurement is rendered in the colour of absence, never as 0. */
  .stat b.absent { color:var(--script); font-weight:400; }

  footer { display:flex; gap:8px; align-items:center; }
  button {
    flex:1; font:500 12px/1 inherit; padding:8px 10px; border-radius:6px; border:0;
    background:var(--field); color:var(--bone); cursor:pointer;
  }
  button:hover:not(:disabled) { background:#352920; }
  button:disabled { opacity:.4; cursor:default; }
  button.go { background:var(--terracotta); color:var(--slip); }
  button.stop { background:var(--oxide); color:#fff; }
  .note { font:10px/1.4 var(--mono); color:var(--script); margin-top:9px; }
</style>
</head>
<body>

<header>
  <svg class="mark" viewBox="0 0 100 100" fill="none" aria-hidden="true">
    <circle cx="30" cy="50" r="8.5" fill="#C86F45"/>
    <g stroke="#C86F45" stroke-width="7" stroke-linecap="round" fill="none">
      <path d="M44 36 A24 24 0 0 1 44 64"/>
      <path d="M52 27 A40 40 0 0 1 52 73"/>
      <path d="M60 18 A56 56 0 0 1 60 82"/>
    </g>
  </svg>
  <h1>Sonocles</h1>
  <div class="state" id="state" data-s="idle">starting</div>
</header>

<div class="meter"><i id="meter"></i></div>

<div class="stream" id="stream"><div class="empty" id="empty">nothing yet</div></div>

<div class="stats">
  <div class="stat"><span>lag</span><b class="absent" id="lag">—</b></div>
  <div class="stat"><span>gap</span><b class="absent" id="gap">—</b></div>
  <div class="stat"><span>ui&nbsp;cost</span><b class="absent" id="ui">—</b></div>
</div>

<footer>
  <button id="toggle" disabled>…</button>
</footer>

<div class="note" id="note"></div>

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
    node.textContent = '—'; node.classList.add('absent'); return
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
      el('state').textContent = j.binary ? 'starting' : 'no engine'
      el('toggle').disabled = true
      el('toggle').textContent = j.binary ? 'waiting for engine' : 'engine not bundled'
      el('note').textContent = j.binary ? '' : 'extras/sonocles-cli is missing — run bin/sync-sidecar.sh'
    } else {
      listening = !!s.listening
      el('state').dataset.s = s.state
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
