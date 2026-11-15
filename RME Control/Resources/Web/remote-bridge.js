(function () {
  'use strict';

  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.rme) return;

  var params = new URLSearchParams(window.location.search);
  var bus = params.get('bus');
  var index = parseInt(params.get('index'), 10);
  if ((bus !== 'input' && bus !== 'output') || !Number.isFinite(index)) return;

  var panel = window.location.pathname.indexOf('/compressor') >= 0 ? 'compressor'
    : window.location.pathname.indexOf('/eq') >= 0 ? 'eq' : '';
  if (!panel) return;

  var base = [
    'html, body { height:100%; }',
    'body { display:flex; align-items:center; justify-content:center; padding:16px; overflow:auto;',
    '  background:#000000; -webkit-text-size-adjust:100%; }',
    '#root { width:100%; max-width:760px; height:auto; min-height:0; }',
    '.app { height:auto; min-height:0; padding:14px; border-radius:20px; gap:12px;',
    '  border:1px solid rgba(255,255,255,.1); background:#151519;',
    '  box-shadow:0 24px 70px rgba(0,0,0,.45); }',
    '.header { height:44px; gap:10px; padding:0 2px; }',
    '.header .switch { width:42px; height:24px; }',
    '.header .switch .knob { width:18px; height:18px; top:2px; left:2px; }',
    '.header .switch.on .knob { transform:translateX(20px); }',
    '.header .title { font-size:16px; font-weight:700; letter-spacing:-.01em; }',
    '.header .close { height:30px; padding:0 11px; border-radius:9px; font-size:9px;',
    '  color:#b9b9c4; background:rgba(255,255,255,.075); }',
    '.header .close:hover { color:#fff; background:rgba(255,255,255,.14); }',
    '@media (max-width:560px) {',
    '  body { padding:0; align-items:stretch; }',
    '  #root { max-width:none; }',
    '  .app { border:0; border-radius:0; box-shadow:none; min-height:100dvh;',
    '    padding:calc(12px + env(safe-area-inset-top)) 12px calc(16px + env(safe-area-inset-bottom)); }',
    '  .header .title { font-size:15px; }',
    '}'
  ];

  var compressorStyles = [
    '.body { flex:0 0 auto; display:flex; flex-direction:column; gap:12px; }',
    '.rail { order:-1; flex:0 0 auto; width:100%; height:82px;',
    '  display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:8px; }',
    '.vmeter { padding:6px 0 4px; gap:5px; border-radius:12px;',
    '  background:rgba(255,255,255,.035); border:1px solid rgba(255,255,255,.06); }',
    '.vmeter .bar { width:9px; }',
    '.main { flex:0 0 auto; display:flex; flex-direction:column; gap:12px; padding-bottom:0; }',
    '.curve { height:184px; flex:0 0 auto; border-radius:14px; background:#000000; }',
    '.knobs { display:grid; grid-template-columns:repeat(5,minmax(0,1fr)); gap:8px; }',
    '.knobs .knob { flex:none; width:auto; min-width:0; padding:9px 4px 8px;',
    '  border-radius:13px; background:rgba(255,255,255,.035); border:1px solid rgba(255,255,255,.06); }',
    '.knobs .svgwrap { width:100%; max-width:76px; height:76px; display:grid;',
    '  place-items:center; touch-action:none; -webkit-tap-highlight-color:transparent; }',
    '.knobs .svgwrap svg { width:48px; height:48px; }',
    '.knobs .kval { font-size:12px; }',
    '.knobs .klab { font-size:8px; }',
    '.preset-row { margin-top:2px; }',
    '.preset-label { font-size:8px; }',
    '.dd-btn { height:36px; border-radius:10px; font-size:12px; background:#0b0b0e; }',
    '.dd-menu { max-height:220px; border-radius:12px; }',
    '.dd-item { height:30px; font-size:11px; }',
    '@media (max-width:680px) {',
    '  .curve { height:154px; }',
    '  .knobs { grid-template-columns:repeat(3,minmax(0,1fr)); }',
    '}',
    '@media (max-width:360px) {',
    '  .curve { height:138px; }',
    '  .knobs { grid-template-columns:repeat(2,minmax(0,1fr)); }',
    '  .rail { height:76px; }',
    '}'
  ];

  var eqStyles = [
    '.graph { flex:0 0 auto; height:auto; min-height:0; aspect-ratio:414 / 272;',
    '  border-radius:16px; background:#000000; }',
    '.graph svg { position:absolute; inset:0; width:100%; height:100%; }',
    '.band-tip { padding:5px; border-radius:11px; }',
    '.tip-grid { gap:6px; }',
    '.tip-chip { width:34px; height:34px; font-size:10px; }',
    '.bands { display:grid; grid-template-columns:repeat(4,minmax(0,1fr)); gap:10px; }',
    '.band-card { --band:#64d2ff; min-width:0; padding:10px; border-radius:14px;',
    '  background:rgba(255,255,255,.035); border:1px solid rgba(255,255,255,.06); }',
    '.band-card.band-1 { --band:#ff9f0a; }',
    '.band-card.band-2 { --band:#64d2ff; }',
    '.band-card.band-3 { --band:#30d158; }',
    '.band-card.band-cut { --band:#bf5af2; }',
    '.band-head { display:flex; align-items:center; gap:6px; min-height:24px; }',
    '.band-dot { width:7px; height:7px; flex:0 0 auto; border-radius:50%; background:var(--band); }',
    '.band-title { font-size:10px; font-weight:800; letter-spacing:.1em; color:#a8a8b3; }',
    '.band-select { margin-left:auto; max-width:112px; padding:4px 5px; border-radius:7px;',
    '  border:1px solid rgba(255,255,255,.1); background:#202027; color:#d8d8df; font:inherit; font-size:9px; }',
    '.band-fixed { margin-left:auto; font-size:9px; font-weight:700; color:#73737f; }',
    '.band-control { display:grid; grid-template-columns:32px minmax(0,1fr) 52px;',
    '  align-items:center; gap:7px; margin-top:7px; font-size:10px; color:#8e8e9a; }',
    '.band-control input[type=range] { width:100%; height:24px; margin:0; }',
    '.band-value { text-align:right; font-size:10px; color:#c5c5ce; font-variant-numeric:tabular-nums; white-space:nowrap; }',
    '.band-power { width:100%; height:30px; margin-top:12px; border-radius:9px;',
    '  background:rgba(255,255,255,.07); color:#8e8e9a; font-size:10px; font-weight:800; letter-spacing:.08em; }',
    '.band-power.on { background:rgba(191,90,242,.2); color:#e0b4ff; }',
    '@media (max-width:760px) {',
    '  .bands { grid-template-columns:repeat(2,minmax(0,1fr)); }',
    '}',
    '@media (max-width:430px) {',
    '  .bands { grid-template-columns:1fr; }',
    '  .graph { border-radius:14px; }',
    '}'
  ];

  var style = document.createElement('style');
  style.textContent = base.concat(panel === 'compressor' ? compressorStyles : eqStyles).join('\n');
  document.head.appendChild(style);

  window.rmeRemoteSend = function (message) {
    if (!message) return;
    if (message.action === 'close') {
      window.location.href = '/';
      return;
    }
    if (message.action === 'ready') return;
    var body = Object.assign({ bus: bus, index: index }, message);
    fetch('/api/' + panel, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    }).catch(function () {});
  };

  function poll() {
    fetch('/api/' + panel + '?bus=' + encodeURIComponent(bus) + '&index=' + index)
      .then(function (r) { return r.json(); })
      .then(function (data) {
        if (window.rme && window.rme.update) window.rme.update(data);
      })
      .catch(function () {});
  }

  poll();
  setInterval(poll, 80);
})();
