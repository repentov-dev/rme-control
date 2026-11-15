(function () {
  'use strict';

  var h = React.createElement;
  var isWebRemote = window.location.protocol === 'http:' || window.location.protocol === 'https:';
  var useRef = React.useRef;
  var useState = React.useState;
  var useEffect = React.useEffect;
  var useSyncExternalStore = React.useSyncExternalStore;

  var COLORS = {
    low: '#ff9f0a',
    mid: '#64d2ff',
    high: '#30d158',
    cut: '#bf5af2',
    red: '#ff453a'
  };

  var BAND_COLORS = { 1: COLORS.low, 2: COLORS.mid, 3: COLORS.high };
  var BAND_NAMES = { 1: 'LOW', 2: 'MID', 3: 'HIGH' };
  var BAND_TYPES = {
    1: ['Bell', 'Low Shelf', 'High-Pass', 'Low Pass'],
    3: ['Bell', 'High Shelf', 'Low Pass', 'High Pass']
  };
  var SLOPES = ['6', '12', '18', '24'];
  var SLOPE_ORDERS = [1, 2, 3, 4];

  var FS = 48000;

  var ranges = {
    band1Gain: { min: -20, max: 20, step: 0.1 },
    band2Gain: { min: -20, max: 20, step: 0.1 },
    band3Gain: { min: -20, max: 20, step: 0.1 },
    band1Freq: { min: 20, max: 20000, step: 1 },
    band2Freq: { min: 20, max: 20000, step: 1 },
    band3Freq: { min: 20, max: 20000, step: 1 },
    lowCutFreq: { min: 20, max: 500, step: 1 },
    band1Q: { min: 0.4, max: 9.9, step: 0.1 },
    band2Q: { min: 0.4, max: 9.9, step: 0.1 },
    band3Q: { min: 0.4, max: 9.9, step: 0.1 },
    band1Type: { min: 0, max: 3, step: 1 },
    band3Type: { min: 0, max: 3, step: 1 },
    lowCutSlope: { min: 0, max: 3, step: 1 }
  };

  var initialState = {
    name: 'INPUT',
    enabled: false,
    band1Type: 1,
    band1Gain: 0,
    band1Freq: 100,
    band1Q: 0.7,
    band2Gain: 0,
    band2Freq: 1000,
    band2Q: 1,
    band3Type: 1,
    band3Gain: 0,
    band3Freq: 8000,
    band3Q: 0.7,
    lowCutEnabled: false,
    lowCutSlope: 1,
    lowCutFreq: 80
  };

  var store = {
    state: initialState,
    dragging: null,
    listeners: new Set(),
    subscribe: function (fn) {
      store.listeners.add(fn);
      return function () { store.listeners.delete(fn); };
    },
    getSnapshot: function () { return store.state; },
    emit: function () {
      store.listeners.forEach(function (fn) { fn(); });
    },
    setValue: function (key, value) {
      var patch = {};
      patch[key] = value;
      store.state = Object.assign({}, store.state, patch);
      store.emit();
    },
    update: function (patch) {
      if (!patch) return;
      var next = Object.assign({}, store.state, patch);
      if (store.dragging) {
        store.dragging.forEach(function (key) {
          if (patch[key] !== undefined) next[key] = store.state[key];
        });
      }
      store.state = next;
      store.emit();
    }
  };

  window.rme = {
    update: function (patch) { store.update(patch); }
  };

  function send(message) {
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.rme) {
        window.webkit.messageHandlers.rme.postMessage(message);
      } else if (window.rmeRemoteSend) {
        window.rmeRemoteSend(message);
      }
    } catch (error) {}
  }

  function clamp(v, lo, hi) { return Math.min(hi, Math.max(lo, v)); }

  function setParam(key, value) {
    var r = ranges[key];
    if (!r) return;
    var v = clamp(value, r.min, r.max);
    if (r.step >= 1) v = Math.round(v);
    else v = Math.round(v / r.step) * r.step;
    v = Math.round(v * 100) / 100;
    store.setValue(key, v);
    send({ action: 'param', name: key, value: v });
  }

  function fmtFreq(f) {
    if (f >= 1000) return (f / 1000).toFixed(1) + ' kHz';
    return Math.round(f) + ' Hz';
  }

  function fmtGain(g) {
    return (g > 0 ? '+' : '') + g.toFixed(1) + ' dB';
  }

  // --- Biquad response -----------------------------------------------------

  function coeffs(kind, f0, gainDb, Q) {
    var A = Math.pow(10, gainDb / 40);
    var w0 = 2 * Math.PI * clamp(f0, 10, FS / 2 - 10) / FS;
    var cw = Math.cos(w0);
    var sw = Math.sin(w0);

    if (kind === 'peak') {
      var alphaP = sw / (2 * Math.max(Q, 0.05));
      return [
        1 + alphaP * A, -2 * cw, 1 - alphaP * A,
        1 + alphaP / A, -2 * cw, 1 - alphaP / A
      ];
    }
    if (kind === 'lowshelf') {
      var alphaL = sw / (2 * Math.max(Q, 0.05));
      var sqrtA = Math.sqrt(A);
      var twoSqrtAAlpha = 2 * sqrtA * alphaL;
      return [
        A * ((A + 1) - (A - 1) * cw + twoSqrtAAlpha),
        2 * A * ((A - 1) - (A + 1) * cw),
        A * ((A + 1) - (A - 1) * cw - twoSqrtAAlpha),
        (A + 1) + (A - 1) * cw + twoSqrtAAlpha,
        -2 * ((A - 1) + (A + 1) * cw),
        (A + 1) + (A - 1) * cw - twoSqrtAAlpha
      ];
    }
    if (kind === 'highshelf') {
      var alphaH = sw / (2 * Math.max(Q, 0.05));
      var sqrtAH = Math.sqrt(A);
      var twoSqrtAHAlpha = 2 * sqrtAH * alphaH;
      return [
        A * ((A + 1) + (A - 1) * cw + twoSqrtAHAlpha),
        -2 * A * ((A - 1) + (A + 1) * cw),
        A * ((A + 1) + (A - 1) * cw - twoSqrtAHAlpha),
        (A + 1) - (A - 1) * cw + twoSqrtAHAlpha,
        2 * ((A - 1) - (A + 1) * cw),
        (A + 1) - (A - 1) * cw - twoSqrtAHAlpha
      ];
    }
    var alpha = sw / (2 * Math.max(Q, 0.05));
    if (kind === 'highpass') {
      return [
        (1 + cw) / 2, -(1 + cw), (1 + cw) / 2,
        1 + alpha, -2 * cw, 1 - alpha
      ];
    }
    // lowpass
    return [
      (1 - cw) / 2, 1 - cw, (1 - cw) / 2,
      1 + alpha, -2 * cw, 1 - alpha
    ];
  }

  function magnitude(c, f) {
    var w = 2 * Math.PI * f / FS;
    var cw = Math.cos(w);
    var sw = Math.sin(w);
    var cw2 = Math.cos(2 * w);
    var sw2 = Math.sin(2 * w);
    var nr = c[0] + c[1] * cw + c[2] * cw2;
    var ni = -(c[1] * sw + c[2] * sw2);
    var dr = c[3] + c[4] * cw + c[5] * cw2;
    var di = -(c[4] * sw + c[5] * sw2);
    var den = dr * dr + di * di;
    if (den < 1e-12) return 1;
    return Math.sqrt((nr * nr + ni * ni) / den);
  }

  function bandKind(band, type) {
    if (band === 1) return ['peak', 'lowshelf', 'highpass', 'lowpass'][type] || 'peak';
    return ['peak', 'highshelf', 'lowpass', 'highpass'][type] || 'peak';
  }

  function bandMagnitude(band, s, f) {
    var type = band === 1 ? s.band1Type : s.band3Type;
    var freq = band === 1 ? s.band1Freq : s.band3Freq;
    var gain = band === 1 ? s.band1Gain : s.band3Gain;
    var q = band === 1 ? s.band1Q : s.band3Q;
    return magnitude(coeffs(bandKind(band, type), freq, gain, q), f);
  }

  function responseDb(s, f) {
    if (!s.enabled) return 0;
    var m = 1;
    m *= bandMagnitude(1, s, f);
    m *= magnitude(coeffs('peak', s.band2Freq, s.band2Gain, s.band2Q), f);
    m *= bandMagnitude(3, s, f);
    if (s.lowCutEnabled) {
      var order = SLOPE_ORDERS[s.lowCutSlope] || 2;
      m *= 1 / Math.sqrt(1 + Math.pow(s.lowCutFreq / f, 2 * order));
    }
    return 20 * Math.log(Math.max(m, 1e-6)) / Math.LN10;
  }

  // --- Graph ---------------------------------------------------------------

  var GW = 414;
  var GH = 272;
  var PAD_L = 8;
  var PAD_R = 8;
  var PAD_T = 24;
  var PAD_B = 16;

  var TIP_W = 102;
  var TIP_W_CUT = 126;
  var TIP_H = 30;

  function freqToX(f) {
    return PAD_L + (Math.log(f / 20) / Math.log(1000)) * (GW - PAD_L - PAD_R);
  }

  function xToFreq(x) {
    return 20 * Math.pow(1000, (x - PAD_L) / (GW - PAD_L - PAD_R));
  }

  function dbToY(db) {
    var y = PAD_T + ((20 - db) / 40) * (GH - PAD_T - PAD_B);
    return clamp(y, PAD_T, GH - PAD_B);
  }

  function yToDb(y) {
    return 20 - ((y - PAD_T) / (GH - PAD_T - PAD_B)) * 40;
  }

  function bandValue(s, band, suffix) {
    return s['band' + band + suffix];
  }

  function pinBand(band) {
    return ['band' + band + 'Freq', 'band' + band + 'Gain'];
  }

  var TYPE_ICONS = {
    1: ['bell', 'lowshelf', 'highpass', 'lowpass'],
    3: ['bell', 'highshelf', 'lowpass', 'highpass']
  };

  function hasTip(key) {
    return key === 'cut' || key === 'band1' || key === 'band3';
  }

  function TypeIcon(props) {
    var paths = {
      bell: 'M2 9 C6 9 6 3 10 3 C14 3 14 9 18 9',
      lowshelf: 'M2 3 L7 3 C9 3 9 9 11 9 L18 9',
      highshelf: 'M2 9 L7 9 C9 9 9 3 11 3 L18 3',
      highpass: 'M2 9 C7 9 7 3 12 3 L18 3',
      lowpass: 'M2 3 L8 3 C13 3 13 9 18 9'
    };
    return h('svg', {
      width: 14, height: 9, viewBox: '0 0 20 12', fill: 'none',
      stroke: 'currentColor', strokeWidth: 1.5,
      strokeLinecap: 'round', strokeLinejoin: 'round',
      pointerEvents: 'none'
    }, h('path', { d: paths[props.kind] || paths.bell }));
  }

  function Graph(props) {
    var state = props.state;
    var svgRef = useRef(null);
    var dragRef = useRef(null);
    var tipTimer = useRef(null);
    var tipClear = useRef(null);
    var adjustTimer = useRef(null);
    var tipData = useRef(null);
    var activeRef = useRef(null);
    var wheelAccum = useRef(0);
    var tipState = useState(null);
    var tip = tipState[0];
    var setTip = tipState[1];
    var tipOnState = useState(false);
    var tipOn = tipOnState[0];
    var setTipOn = tipOnState[1];
    var activeState = useState(null);
    var active = activeState[0];
    var setActive = activeState[1];

    useEffect(function () {
      activeRef.current = active;
    }, [active]);

    useEffect(function () {
      return function () {
        if (tipTimer.current) clearTimeout(tipTimer.current);
        if (tipClear.current) clearTimeout(tipClear.current);
        if (adjustTimer.current) clearTimeout(adjustTimer.current);
      };
    }, []);

    function clearTimers() {
      if (tipTimer.current) { clearTimeout(tipTimer.current); tipTimer.current = null; }
      if (tipClear.current) { clearTimeout(tipClear.current); tipClear.current = null; }
      if (adjustTimer.current) { clearTimeout(adjustTimer.current); adjustTimer.current = null; }
    }

    function tipAnchor(key) {
      var s = store.state;
      if (key === 'cut') {
        return { x: freqToX(s.lowCutFreq), y: GH - PAD_B - 3 };
      }
      var band = Number(key.slice(4));
      return {
        x: freqToX(s['band' + band + 'Freq']),
        y: dbToY(s['band' + band + 'Gain'])
      };
    }

    function placeTip(key, px, py) {
      var width = key === 'cut' ? TIP_W_CUT : TIP_W;
      var left = clamp(px - width / 2, 6, GW - width - 6);
      var top = key === 'cut' ? py - 14 - TIP_H : py + 14;
      if (key !== 'cut' && top + TIP_H > GH - 4) top = Math.max(4, py - 14 - TIP_H);
      return { key: key, left: left, top: top };
    }

    function scheduleTipShow(key) {
      adjustTimer.current = setTimeout(function () {
        adjustTimer.current = null;
        var data = tipData.current;
        if (data && data.key === key && activeRef.current === key && hasTip(key)) {
          var anchor = tipAnchor(key);
          data = placeTip(key, anchor.x, anchor.y);
          tipData.current = data;
          setTip(data);
          setTipOn(true);
        }
      }, 1000);
    }

    function showTip(key, px, py) {
      if (!hasTip(key)) return;
      clearTimers();
      tipData.current = placeTip(key, px, py);
      setTip(tipData.current);
      setTipOn(false);
      scheduleTipShow(key);
    }

    /// Скрывает подсказку на время изменения параметра и возвращает её,
    /// если ручка всё ещё активна через секунду после последнего изменения.
    function pauseTip(key) {
      if (tipTimer.current) { clearTimeout(tipTimer.current); tipTimer.current = null; }
      if (tipClear.current) { clearTimeout(tipClear.current); tipClear.current = null; }
      if (adjustTimer.current) { clearTimeout(adjustTimer.current); adjustTimer.current = null; }
      if (hasTip(key)) {
        var anchor = tipAnchor(key);
        tipData.current = placeTip(key, anchor.x, anchor.y);
        setTip(tipData.current);
      }
      setTipOn(false);
      scheduleTipShow(key);
    }

    function scheduleHide() {
      clearTimers();
      tipTimer.current = setTimeout(function () {
        setTipOn(false);
        tipClear.current = setTimeout(function () {
          setTip(null);
          setActive(null);
          tipData.current = null;
          tipClear.current = null;
        }, 200);
      }, 400);
    }

    function cancelHide() {
      clearTimers();
      if (tipData.current) setTipOn(true);
    }

    function leaveNode(key) {
      if (!hasTip(key)) { setActive(null); return; }
      scheduleHide();
    }

    function hideNow() {
      clearTimers();
      setTipOn(false);
      setTip(null);
      setActive(null);
      tipData.current = null;
    }

    function beginBand(e, band) {
      e.preventDefault();
      e.stopPropagation();
      var key = 'band' + band;
      if (hasTip(key)) pauseTip(key);
      else hideNow();
      setActive(key);
      if (e.altKey) {
        dragRef.current = {
          kind: 'q',
          band: band,
          startY: e.clientY,
          startQ: bandValue(store.state, band, 'Q')
        };
        store.dragging = ['band' + band + 'Q'];
      } else {
        dragRef.current = { kind: 'band', band: band };
        store.dragging = pinBand(band);
      }
      try { svgRef.current.setPointerCapture(e.pointerId); } catch (error) {}
    }

    function beginCut(e) {
      e.preventDefault();
      e.stopPropagation();
      pauseTip('cut');
      setActive('cut');
      dragRef.current = { kind: 'cut' };
      store.dragging = ['lowCutFreq'];
      try { svgRef.current.setPointerCapture(e.pointerId); } catch (error) {}
    }

    function onMove(e) {
      var drag = dragRef.current;
      if (!drag || !svgRef.current) return;
      var rect = svgRef.current.getBoundingClientRect();
      if (rect.width < 1 || rect.height < 1) return;
      var vx = (e.clientX - rect.left) / rect.width * GW;
      var vy = (e.clientY - rect.top) / rect.height * GH;
      var f = clamp(xToFreq(vx), 20, 20000);
      if (drag.kind === 'q') {
        var span = 9.9 - 0.4;
        var next = drag.startQ + (drag.startY - e.clientY) / 140 * span;
        setParam('band' + drag.band + 'Q', Math.round(clamp(next, 0.4, 9.9) * 10) / 10);
        pauseTip('band' + drag.band);
      } else if (drag.kind === 'band') {
        setParam('band' + drag.band + 'Freq', Math.round(f));
        setParam('band' + drag.band + 'Gain', Math.round(clamp(yToDb(vy), -20, 20) * 10) / 10);
        pauseTip('band' + drag.band);
      } else {
        setParam('lowCutFreq', Math.round(clamp(f, 20, 500)));
        pauseTip('cut');
      }
    }

    function end(e) {
      if (!dragRef.current) return;
      dragRef.current = null;
      store.dragging = null;
      try { svgRef.current.releasePointerCapture(e.pointerId); } catch (error) {}
    }

    function wheelQ(e, band) {
      e.stopPropagation();
      var raw = e.deltaY * (e.deltaMode === 1 ? 16 : e.deltaMode === 2 ? 100 : 1);
      raw = clamp(raw, -25, 25);
      var delta = -raw * 0.004;
      if (wheelAccum.current * delta < 0) wheelAccum.current = 0;
      wheelAccum.current += delta;
      if (Math.abs(wheelAccum.current) < 0.1) return;
      var steps = wheelAccum.current > 0
        ? Math.floor(wheelAccum.current / 0.1 + 1e-6)
        : Math.ceil(wheelAccum.current / 0.1 - 1e-6);
      wheelAccum.current -= steps * 0.1;
      var key = 'band' + band + 'Q';
      var value = clamp(bandValue(store.state, band, 'Q') + steps * 0.1, 0.4, 9.9);
      setParam(key, value);
      if (value <= 0.4 || value >= 9.9) wheelAccum.current = 0;
      pauseTip('band' + band);
    }

    var children = [];
    var i;

    [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000].forEach(function (f) {
      children.push(h('line', {
        key: 'gx' + f,
        x1: freqToX(f), y1: PAD_T, x2: freqToX(f), y2: GH - PAD_B,
        stroke: 'rgba(255,255,255,' + (f === 1000 ? '.075' : '.04') + ')'
      }));
    });

    [-12, 0, 12].forEach(function (db) {
      children.push(h('line', {
        key: 'gy' + db,
        x1: PAD_L, y1: dbToY(db), x2: GW - PAD_R, y2: dbToY(db),
        stroke: 'rgba(255,255,255,' + (db === 0 ? '.13' : '.04') + ')'
      }));
    });

    [20, 100, 1000, 10000].forEach(function (f) {
      children.push(h('text', {
        key: 'lx' + f,
        x: freqToX(f), y: GH - 4,
        fill: '#5c5c66', fontSize: 7, textAnchor: 'middle'
      }, f >= 1000 ? (f / 1000) + 'k' : String(f)));
    });

    var mainPoints = [];
    var zeroPoints = [];
    for (i = 0; i <= 220; i += 1) {
      var f = 20 * Math.pow(1000, i / 220);
      var x = freqToX(f);
      mainPoints.push(x.toFixed(1) + ',' + dbToY(clamp(responseDb(state, f), -24, 24)).toFixed(1));
      zeroPoints.push(x.toFixed(1) + ',' + dbToY(0).toFixed(1));
    }

    children.push(h('polygon', {
      key: 'fill',
      points: mainPoints.concat(zeroPoints.reverse()).join(' '),
      fill: 'rgba(255,255,255,.045)'
    }));

    if (state.enabled) {
      [1, 2, 3].forEach(function (band) {
        var pts = [];
        for (var k = 0; k <= 160; k += 1) {
          var ff = 20 * Math.pow(1000, k / 160);
          var mm = bandMagnitude(band, state, ff);
          pts.push(freqToX(ff).toFixed(1) + ',' + dbToY(clamp(20 * Math.log(mm) / Math.LN10, -24, 24)).toFixed(1));
        }
        children.push(h('polyline', {
          key: 'bc' + band,
          points: pts.join(' '),
          fill: 'none',
          stroke: BAND_COLORS[band],
          strokeOpacity: 0.28,
          strokeWidth: 1
        }));
      });
    }

    children.push(h('polyline', {
      key: 'curve',
      points: mainPoints.join(' '),
      fill: 'none',
      stroke: '#e8e8f2',
      strokeOpacity: state.enabled ? 0.95 : 0.35,
      strokeWidth: 1.7,
      strokeLinecap: 'round',
      strokeLinejoin: 'round'
    }));

    if (state.lowCutEnabled) {
      var lcX = freqToX(state.lowCutFreq);
      children.push(h('line', {
        key: 'lcline',
        x1: lcX, y1: PAD_T, x2: lcX, y2: GH - PAD_B,
        stroke: COLORS.cut, strokeOpacity: 0.5, strokeDasharray: '3 3'
      }));
    }

    var lcFreq = state.lowCutFreq;
    var lcLabel = 'LC  ' + fmtFreq(lcFreq);
    var lcHalf = lcLabel.length * 4.15 / 2;
    var lcCx = clamp(freqToX(lcFreq), lcHalf + 4, GW - lcHalf - 4);
    var lcLabelY = GH - PAD_B - 17;
    var placedLabels = [{
      x1: lcCx - lcHalf - 2,
      x2: lcCx + lcHalf + 2,
      y1: lcLabelY - 9,
      y2: lcLabelY + 3
    }];

    [1, 2, 3].forEach(function (band) {
      var gain = bandValue(state, band, 'Gain');
      var freq = bandValue(state, band, 'Freq');
      var q = bandValue(state, band, 'Q');
      var cx = freqToX(freq);
      var cy = dbToY(gain);

      var lines = [fmtFreq(freq), 'Q ' + q.toFixed(1), fmtGain(gain)];
      var labelHalf = 0;
      lines.forEach(function (line) {
        labelHalf = Math.max(labelHalf, line.length * 4.15 / 2);
      });
      var labelCx = clamp(cx, labelHalf + 4, GW - labelHalf - 4);
      var offsets = [7.5, 16, 24.5];
      var blockH = 27;

      var yMin = Infinity;
      var yMax = -Infinity;
      for (var sample = 0; sample <= 10; sample += 1) {
        var lx = labelCx - labelHalf - 2 + (sample / 10) * (labelHalf * 2 + 4);
        var lf = clamp(xToFreq(lx), 20, 20000);
        var ly = dbToY(clamp(responseDb(state, lf), -24, 24));
        if (ly < yMin) yMin = ly;
        if (ly > yMax) yMax = ly;
      }

      var candidates = [
        { top: cy - 10 - blockH, above: true },
        { top: cy + 11, above: false },
        { top: yMin - 4 - blockH, above: true },
        { top: yMax + 4, above: false }
      ];

      var chosen = null;
      for (var ci = 0; ci < candidates.length; ci += 1) {
        var cand = candidates[ci];
        var bottom = cand.top + blockH;
        if (cand.top < 2 || bottom > GH - 2) continue;
        if (cand.above && bottom > yMin - 2) continue;
        if (!cand.above && cand.top < yMax + 2) continue;
        var rect = {
          x1: labelCx - labelHalf - 2,
          x2: labelCx + labelHalf + 2,
          y1: cand.top,
          y2: bottom
        };
        var clash = false;
        for (var pi = 0; pi < placedLabels.length; pi += 1) {
          var other = placedLabels[pi];
          if (!(rect.x2 < other.x1 || rect.x1 > other.x2 || rect.y2 < other.y1 || rect.y1 > other.y2)) {
            clash = true;
            break;
          }
        }
        if (clash) continue;
        chosen = rect;
        break;
      }

      if (!chosen) {
        var fallbackTop = clamp(cy - 10 - blockH, 2, GH - 2 - blockH);
        chosen = {
          x1: labelCx - labelHalf - 2,
          x2: labelCx + labelHalf + 2,
          y1: fallbackTop,
          y2: fallbackTop + blockH
        };
      }
      placedLabels.push(chosen);

      lines.forEach(function (line, idx) {
        children.push(h('text', {
          key: 'nlt' + band + idx,
          x: labelCx,
          y: chosen.y1 + offsets[idx],
          fill: '#64646e',
          fontSize: 7.5,
          fontWeight: 700,
          letterSpacing: 0.2,
          textAnchor: 'middle',
          pointerEvents: 'none'
        }, line));
      });

      if (active === 'band' + band) {
        children.push(h('circle', {
          key: 'ring' + band,
          cx: cx,
          cy: cy,
          r: 9,
          fill: BAND_COLORS[band],
          fillOpacity: 0.12,
          stroke: BAND_COLORS[band],
          strokeOpacity: 0.65,
          strokeWidth: 1.4,
          pointerEvents: 'none'
        }));
      }

      children.push(h('circle', {
        key: 'n' + band,
        cx: cx,
        cy: cy,
        r: 5,
        fill: BAND_COLORS[band],
        stroke: '#000000',
        strokeWidth: 1.4,
        pointerEvents: 'none'
      }));

      children.push(h('circle', {
        key: 'hit' + band,
        cx: cx,
        cy: cy,
        r: 17,
        fill: '#000000',
        fillOpacity: 0,
        pointerEvents: 'all',
        onPointerDown: function (e) { beginBand(e, band); },
        onPointerEnter: function () {
          var key = 'band' + band;
          if (hasTip(key)) { showTip(key, cx, cy); setActive(key); }
          else { hideNow(); setActive(key); }
        },
        onPointerLeave: function () { leaveNode('band' + band); },
        onWheel: function (e) { wheelQ(e, band); },
        onDoubleClick: function () { setParam('band' + band + 'Gain', 0); }
      }));
    });

    var lcX = freqToX(lcFreq);
    var lcY = GH - PAD_B - 3;

    if (active === 'cut') {
      children.push(h('circle', {
        key: 'lcring',
        cx: lcX,
        cy: lcY,
        r: 10,
        fill: COLORS.cut,
        fillOpacity: 0.12,
        stroke: COLORS.cut,
        strokeOpacity: 0.65,
        strokeWidth: 1.4,
        pointerEvents: 'none'
      }));
    }

    children.push(h('circle', {
      key: 'lcnode',
      cx: lcX,
      cy: lcY,
      r: 4,
      fill: state.lowCutEnabled ? COLORS.cut : '#2a2a30',
      stroke: COLORS.cut,
      strokeOpacity: state.lowCutEnabled ? 1 : 0.5,
      strokeWidth: 1.2,
      pointerEvents: 'none'
    }));

    children.push(h('circle', {
      key: 'lchit',
      cx: lcX,
      cy: lcY,
      r: 17,
      fill: '#000000',
      fillOpacity: 0,
      pointerEvents: 'all',
      onPointerDown: beginCut,
      onPointerEnter: function () { showTip('cut', lcX, lcY); setActive('cut'); },
      onPointerLeave: function () { leaveNode('cut'); },
      onDoubleClick: function () { setParam('lowCutFreq', 80); }
    }));

    children.push(h('text', {
      key: 'lclt',
      x: lcCx,
      y: lcLabelY,
      fill: '#64646e',
      fontSize: 7.5,
      fontWeight: 700,
      letterSpacing: 0.2,
      textAnchor: 'middle',
      pointerEvents: 'none'
    }, lcLabel));

    var tipEl = null;
    if (tip) {
      var isCut = tip.key === 'cut';
      var band = isCut ? 0 : Number(tip.key.slice(4));
      var color = isCut ? COLORS.cut : BAND_COLORS[band];
      var current = isCut ? state.lowCutSlope : state['band' + band + 'Type'];
      var items;
      if (isCut) {
        items = [{ key: 'lc', text: 'LC', kind: null, value: 'lc', toggle: true }];
        items = items.concat(SLOPES.map(function (label, idx) {
          return { key: label, text: label, kind: null, value: idx };
        }));
      } else {
        items = (TYPE_ICONS[band] || []).map(function (kind, idx) {
          return { key: kind, text: null, kind: kind, value: idx };
        });
      }
      tipEl = h('div', {
        className: 'band-tip' + (tipOn ? ' show' : ''),
        style: { left: tip.left + 'px', top: tip.top + 'px' },
        onPointerEnter: cancelHide,
        onPointerLeave: scheduleHide
      },
        h('div', { className: 'tip-grid' },
          items.map(function (item) {
            var isOn = isCut && item.toggle ? state.lowCutEnabled : current === item.value;
            var itemColor = isCut && item.toggle ? COLORS.red : color;
            return h('button', {
              key: item.key,
              className: 'tip-chip' + (isOn ? ' on' : ''),
              'aria-label': isCut
                ? (item.toggle ? 'Low Cut' : item.text + ' dB/oct')
                : (BAND_TYPES[band] || [])[item.value],
              style: isOn
                ? { background: itemColor, color: '#000000' }
                : { color: itemColor },
              onClick: function () {
                if (isCut && item.toggle) {
                  var value = !store.state.lowCutEnabled;
                  store.setValue('lowCutEnabled', value);
                  send({ action: 'lowcut', enabled: value });
                } else {
                  setParam(isCut ? 'lowCutSlope' : 'band' + band + 'Type', item.value);
                }
              }
            }, item.kind ? h(TypeIcon, { kind: item.kind }) : item.text);
          })
        )
      );
    }

    return h('div', { className: 'graph' },
      h('svg', {
        ref: svgRef,
        viewBox: '0 0 ' + GW + ' ' + GH,
        preserveAspectRatio: 'none',
        onPointerMove: onMove,
        onPointerUp: end,
        onPointerCancel: end
      }, children),
      tipEl
    );
  }

  // --- Header / app --------------------------------------------------------

  function Header(props) {
    var state = props.state;
    var on = state.enabled;
    return h('div', { className: 'header' },
      h('button', {
        className: 'switch' + (on ? ' on' : ''),
        role: 'switch',
        'aria-checked': on ? 'true' : 'false',
        title: on ? 'Bypass' : 'Enable',
        onPointerDown: function (e) { e.stopPropagation(); },
        onClick: function () {
          var value = !on;
          store.setValue('enabled', value);
          send({ action: 'power', enabled: value });
        }
      }, h('span', { className: 'knob' })),
      h('div', { className: 'drag' },
        h('div', { className: 'title' }, state.name)
      ),
      h('button', {
        className: 'close',
        title: isWebRemote ? 'Back to remote' : 'Close',
        onPointerDown: function (e) { e.stopPropagation(); },
        onClick: function () { send({ action: 'close' }); }
      }, isWebRemote ? 'BACK' : 'CLOSE')
    );
  }


  function formatFreq(value) {
    if (value >= 1000) {
      var k = value / 1000;
      return (k >= 10 ? k.toFixed(1) : k.toFixed(2)).replace(/\.0+$/, '').replace(/(\.\d)0$/, '$1') + ' kHz';
    }
    return Math.round(value) + ' Hz';
  }

  function BandCard(props) {
    var state = props.state;
    var band = props.band;
    var key = 'band' + band;
    var color = BAND_COLORS[band];
    var types = BAND_TYPES[band] || [];
    var type = state[key + 'Type'];
    return h('article', { className: 'band-card band-' + band },
      h('div', { className: 'band-head' },
        h('span', { className: 'band-dot' }),
        h('span', { className: 'band-title' }, BAND_NAMES[band]),
        types.length
          ? h('select', {
              className: 'band-select',
              value: type,
              onChange: function (e) { setParam(key + 'Type', Number(e.target.value)); }
            }, types.map(function (label, idx) {
              return h('option', { key: label, value: idx }, label);
            }))
          : h('span', { className: 'band-fixed' }, 'Bell')
      ),
      h('label', { className: 'band-control' },
        h('span', null, 'Freq'),
        h('input', {
          type: 'range', min: 20, max: 20000, step: 1, value: state[key + 'Freq'],
          style: { accentColor: color },
          onChange: function (e) { setParam(key + 'Freq', Number(e.target.value)); }
        }),
        h('span', { className: 'band-value' }, formatFreq(state[key + 'Freq']))
      ),
      h('label', { className: 'band-control' },
        h('span', null, 'Gain'),
        h('input', {
          type: 'range', min: -20, max: 20, step: 0.1, value: state[key + 'Gain'],
          style: { accentColor: color },
          onChange: function (e) { setParam(key + 'Gain', Number(e.target.value)); }
        }),
        h('span', { className: 'band-value' }, (state[key + 'Gain'] > 0 ? '+' : '') + state[key + 'Gain'].toFixed(1) + ' dB')
      ),
      h('label', { className: 'band-control' },
        h('span', null, 'Q'),
        h('input', {
          type: 'range', min: 0.4, max: 9.9, step: 0.1, value: state[key + 'Q'],
          style: { accentColor: color },
          onChange: function (e) { setParam(key + 'Q', Number(e.target.value)); }
        }),
        h('span', { className: 'band-value' }, state[key + 'Q'].toFixed(1))
      )
    );
  }

  function LowCutCard(props) {
    var state = props.state;
    var on = state.lowCutEnabled;
    return h('article', { className: 'band-card band-cut' },
      h('div', { className: 'band-head' },
        h('span', { className: 'band-dot' }),
        h('span', { className: 'band-title' }, 'LOW CUT'),
        h('select', {
          className: 'band-select',
          value: state.lowCutSlope,
          onChange: function (e) { setParam('lowCutSlope', Number(e.target.value)); }
        }, SLOPES.map(function (label, idx) {
          return h('option', { key: label, value: idx }, label + ' dB/oct');
        }))
      ),
      h('label', { className: 'band-control' },
        h('span', null, 'Freq'),
        h('input', {
          type: 'range', min: 20, max: 500, step: 1, value: state.lowCutFreq,
          style: { accentColor: COLORS.cut },
          onChange: function (e) { setParam('lowCutFreq', Number(e.target.value)); }
        }),
        h('span', { className: 'band-value' }, formatFreq(state.lowCutFreq))
      ),
      h('button', {
        className: 'band-power' + (on ? ' on' : ''),
        type: 'button',
        'aria-pressed': on ? 'true' : 'false',
        onClick: function () {
          var value = !store.state.lowCutEnabled;
          store.setValue('lowCutEnabled', value);
          send({ action: 'lowcut', enabled: value });
        }
      }, on ? 'ON' : 'OFF')
    );
  }

  function BandPanels(props) {
    return h('div', { className: 'bands' },
      [1, 2, 3].map(function (band) {
        return h(BandCard, { key: band, band: band, state: props.state });
      }),
      h(LowCutCard, { key: 'cut', state: props.state })
    );
  }

  function App() {
    var state = useSyncExternalStore(store.subscribe, store.getSnapshot);
    return h('div', { className: 'app' },
      h(Header, { state: state }),
      h(Graph, { state: state }),
      isWebRemote ? h(BandPanels, { state: state }) : null
    );
  }

  ReactDOM.createRoot(document.getElementById('root')).render(h(App));
  send({ action: 'ready' });
})();
