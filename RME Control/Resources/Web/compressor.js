(function () {
  'use strict';

  var h = React.createElement;
  var isWebRemote = window.location.protocol === 'http:' || window.location.protocol === 'https:';
  var useRef = React.useRef;
  var useState = React.useState;
  var useEffect = React.useEffect;
  var useSyncExternalStore = React.useSyncExternalStore;

  var COLORS = {
    threshold: '#ff9f0a',
    ratio: '#ff375f',
    attack: '#64d2ff',
    release: '#bf5af2',
    gain: '#30d158',
    reduction: '#5e5ce6'
  };

  var PARAMS = [
    { key: 'threshold', label: 'THRESH', unit: 'dB', min: -60, max: 0, step: 0.1, neutral: 0, digits: 1, color: COLORS.threshold },
    { key: 'ratio', label: 'RATIO', unit: ':1', min: 1, max: 10, step: 0.1, neutral: 1, digits: 1, color: COLORS.ratio },
    { key: 'attack', label: 'ATTACK', unit: 'ms', min: 0, max: 200, step: 1, neutral: 0, digits: 0, color: COLORS.attack },
    { key: 'release', label: 'RELEASE', unit: 'ms', min: 100, max: 999, step: 1, neutral: 200, digits: 0, color: COLORS.release },
    { key: 'gain', label: 'GAIN', unit: 'dB', min: -30, max: 30, step: 0.1, neutral: 0, digits: 1, color: COLORS.gain }
  ];

  var PARAM_BY_KEY = {};
  PARAMS.forEach(function (p) { PARAM_BY_KEY[p.key] = p; });

  var PRESET_GROUPS = [
    {
      name: 'Vocals',
      presets: [
        { id: 'clean', name: 'Clean', values: { threshold: -18, ratio: 2.5, attack: 15, release: 150, gain: 2 } },
        { id: 'male', name: 'Male', values: { threshold: -20, ratio: 3.5, attack: 10, release: 180, gain: 3 } },
        { id: 'female', name: 'Female', values: { threshold: -22, ratio: 3, attack: 8, release: 140, gain: 2.5 } },
        { id: 'rap', name: 'Rap', values: { threshold: -24, ratio: 5, attack: 5, release: 120, gain: 4 } },
        { id: 'speech', name: 'Speech', values: { threshold: -20, ratio: 4, attack: 6, release: 200, gain: 3 } },
        { id: 'soft', name: 'Soft', values: { threshold: -16, ratio: 2, attack: 25, release: 260, gain: 1.5 } },
        { id: 'loud', name: 'Loud', values: { threshold: -26, ratio: 7, attack: 3, release: 100, gain: 2 } }
      ]
    },
    {
      name: 'Guitar',
      presets: [
        { id: 'guitar-electric', name: 'Electric', values: { threshold: -22, ratio: 4, attack: 8, release: 120, gain: 3 } },
        { id: 'guitar-acoustic', name: 'Acoustic', values: { threshold: -20, ratio: 2.5, attack: 20, release: 200, gain: 2 } }
      ]
    },
    {
      name: 'Bass',
      presets: [
        { id: 'bass', name: 'Bass Guitar', values: { threshold: -24, ratio: 4, attack: 20, release: 250, gain: 4 } }
      ]
    },
    {
      name: 'Keys',
      presets: [
        { id: 'keys-piano', name: 'Piano', values: { threshold: -20, ratio: 3, attack: 15, release: 250, gain: 2 } },
        { id: 'keys-synth', name: 'Synth', values: { threshold: -26, ratio: 4, attack: 5, release: 150, gain: 3 } }
      ]
    },
    {
      name: 'Drums',
      presets: [
        { id: 'drums', name: 'Drums', values: { threshold: -18, ratio: 5, attack: 15, release: 100, gain: 3 } }
      ]
    },
    {
      name: 'Film',
      outputsOnly: true,
      presets: [
        { id: 'cinema', name: 'Cinema', values: { threshold: -18, ratio: 4, attack: 5, release: 300, gain: 3 } }
      ]
    }
  ];

  function visibleGroups() {
    return PRESET_GROUPS.filter(function (group) {
      return !group.outputsOnly || store.state.isOutput;
    });
  }

  function visiblePresets() {
    var out = [];
    visibleGroups().forEach(function (group) {
      group.presets.forEach(function (preset) { out.push(preset); });
    });
    return out;
  }

  var initialState = {
    name: 'INPUT',
    isOutput: false,
    enabled: false,
    params: { threshold: 0, ratio: 1, attack: 0, release: 200, gain: 0 },
    level: -100,
    reduction: 0,
    output: -100
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
    emit: function () { store.listeners.forEach(function (fn) { fn(); }); },
    setParam: function (key, value) {
      var params = Object.assign({}, store.state.params);
      params[key] = value;
      store.state = Object.assign({}, store.state, { params: params });
      store.emit();
    },
    applyPreset: function (values) {
      store.state = Object.assign({}, store.state, {
        params: Object.assign({}, store.state.params, values)
      });
      store.emit();
    },
    update: function (patch) {
      if (!patch) return;
      var params = store.state.params;
      if (patch.params) {
        params = Object.assign({}, params, patch.params);
        if (store.dragging && patch.params[store.dragging] !== undefined) {
          params[store.dragging] = store.state.params[store.dragging];
        }
      }
      store.state = Object.assign({}, store.state, patch, { params: params });
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
    var p = PARAM_BY_KEY[key];
    if (!p) return;
    var v = clamp(value, p.min, p.max);
    v = p.step >= 1 ? Math.round(v) : Math.round(v * 10) / 10;
    store.setParam(key, v);
    send({ action: 'param', name: key, value: v });
  }

  function formatValue(key, value) {
    var p = PARAM_BY_KEY[key];
    var s = p.digits === 0 ? String(Math.round(value)) : value.toFixed(p.digits);
    if (key === 'gain' && value > 0) s = '+' + s;
    return s;
  }

  function formatDB(value) {
    return value <= -99.9 ? '-∞' : (value > 0 ? '+' : '') + value.toFixed(1);
  }

  function levelColor(value) {
    if (value > -6) return '#ff453a';
    if (value > -18) return '#ffd60a';
    return '#30d158';
  }

  // --- SVG helpers ---------------------------------------------------------

  function polar(cx, cy, r, deg) {
    var a = (deg - 90) * Math.PI / 180;
    return [cx + r * Math.cos(a), cy + r * Math.sin(a)];
  }

  function arcPath(cx, cy, r, a0, a1) {
    if (Math.abs(a1 - a0) < 0.01) a1 = a0 + 0.01;
    var p0 = polar(cx, cy, r, a0);
    var p1 = polar(cx, cy, r, a1);
    var large = Math.abs(a1 - a0) > 180 ? 1 : 0;
    var sweep = a1 > a0 ? 1 : 0;
    return 'M ' + p0[0].toFixed(2) + ' ' + p0[1].toFixed(2) +
      ' A ' + r + ' ' + r + ' 0 ' + large + ' ' + sweep + ' ' +
      p1[0].toFixed(2) + ' ' + p1[1].toFixed(2);
  }

  // --- Components ----------------------------------------------------------

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
          store.update({ enabled: value });
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

  function VerticalMeter(props) {
    return h('div', { className: 'vmeter' },
      h('div', { className: 'vlab' }, props.label),
      h('div', { className: 'bar' + (props.fromTop ? ' top' : '') },
        h('div', {
          className: 'fill',
          style: {
            height: clamp(props.pct, 0, 1) * 100 + '%',
            background: props.color
          }
        })
      ),
      h('div', { className: 'vval' }, formatDB(props.db))
    );
  }

  function MeterRail(props) {
    var state = props.state;
    return h('div', { className: 'rail' },
      h(VerticalMeter, { label: 'IN', db: state.level, pct: (state.level + 60) / 60, color: levelColor(state.level) }),
      h(VerticalMeter, { label: 'GR', db: -state.reduction, pct: state.reduction / 30, color: COLORS.reduction, fromTop: true }),
      h(VerticalMeter, { label: 'OUT', db: state.output, pct: (state.output + 60) / 60, color: levelColor(state.output) })
    );
  }

  function TransferCurve(props) {
    var state = props.state;
    var W = 356, H = 82;
    var padL = 7, padR = 7, padT = 7, padB = 7;
    var x0 = padL, x1 = W - padR, y0 = H - padB, y1 = padT;
    var dbToX = function (db) { return x0 + ((db + 60) / 60) * (x1 - x0); };
    var dbToY = function (db) { return y0 + ((clamp(db, -60, 0) + 60) / 60) * (y1 - y0); };

    var threshold = state.params.threshold;
    var ratio = Math.max(1, state.params.ratio);
    var gain = state.params.gain;

    var compressed = function (db) {
      if (state.enabled && db > threshold && ratio > 1) {
        return threshold + (db - threshold) / ratio + gain;
      }
      return db + gain;
    };

    var curvePoints = [];
    var identityPoints = [];
    var i;
    for (i = -60; i <= 0; i += 1) {
      curvePoints.push(dbToX(i).toFixed(1) + ',' + dbToY(compressed(i)).toFixed(1));
      identityPoints.push(dbToX(i).toFixed(1) + ',' + dbToY(i + gain).toFixed(1));
    }

    var children = [];
    [-40, -20].forEach(function (db) {
      children.push(h('line', {
        key: 'gx' + db, x1: dbToX(db), y1: padT, x2: dbToX(db), y2: H - padB,
        stroke: 'rgba(255,255,255,.04)'
      }));
      children.push(h('line', {
        key: 'gy' + db, x1: padL, y1: dbToY(db), x2: W - padR, y2: dbToY(db),
        stroke: 'rgba(255,255,255,.04)'
      }));
    });

    children.push(h('line', {
      key: 'threshold', x1: dbToX(threshold), y1: padT, x2: dbToX(threshold), y2: H - padB,
      stroke: 'rgba(255,159,10,.45)', strokeDasharray: '3 3'
    }));

    children.push(h('polyline', {
      key: 'identity', points: identityPoints.join(' '), fill: 'none',
      stroke: 'rgba(255,255,255,.12)', strokeWidth: 1, strokeDasharray: '3 3'
    }));

    if (state.enabled && ratio > 1 && threshold < 0) {
      var top = [];
      var bottom = [];
      for (var db = threshold; db <= 0; db += 1) {
        top.push(dbToX(db).toFixed(1) + ',' + dbToY(compressed(db)).toFixed(1));
        bottom.push(dbToX(db).toFixed(1) + ',' + dbToY(db + gain).toFixed(1));
      }
      children.push(h('polygon', {
        key: 'area', points: top.concat(bottom.reverse()).join(' '),
        fill: 'rgba(94,92,230,.14)'
      }));
    }

    children.push(h('polyline', {
      key: 'curve', points: curvePoints.join(' '), fill: 'none', stroke: COLORS.attack,
      strokeWidth: 1.6, strokeLinecap: 'round', strokeLinejoin: 'round'
    }));

    if (state.level > -99.9) {
      var dotIn = clamp(state.level, -60, 0);
      var dotX = dbToX(dotIn);
      var dotY = dbToY(compressed(dotIn));
      children.push(h('circle', { key: 'dot', cx: dotX, cy: dotY, r: 2.6, fill: '#ffffff' }));
    }

    return h('div', { className: 'curve' },
      h('svg', { viewBox: '0 0 ' + W + ' ' + H, preserveAspectRatio: 'none' }, children)
    );
  }

  function Knob(props) {
    var param = props.param;
    var value = props.value;
    var start = useRef(null);

    var progress = clamp((value - param.min) / (param.max - param.min), 0, 1);
    var angle = -135 + 270 * progress;
    var cx = 24, cy = 24, r = 19;
    var inner = polar(cx, cy, 6, angle);
    var outer = polar(cx, cy, 15, angle);

    function endDrag() {
      start.current = null;
      store.dragging = null;
    }

    return h('div', { className: 'knob' },
      h('div', {
        className: 'svgwrap',
        onPointerDown: function (e) {
          e.preventDefault();
          e.stopPropagation();
          start.current = { y: e.clientY, v: value };
          store.dragging = param.key;
          try { e.currentTarget.setPointerCapture(e.pointerId); } catch (error) {}
        },
        onPointerMove: function (e) {
          var s = start.current;
          if (!s) return;
          var span = param.max - param.min;
          var delta = -(e.clientY - s.y) / 150 * span;
          setParam(param.key, s.v + delta);
        },
        onPointerUp: function (e) {
          endDrag();
          try { e.currentTarget.releasePointerCapture(e.pointerId); } catch (error) {}
        },
        onPointerCancel: endDrag,
        onDoubleClick: function () { setParam(param.key, param.neutral); }
      },
        h('svg', { width: 48, height: 48, viewBox: '0 0 48 48' },
          h('path', {
            d: arcPath(cx, cy, r, -135, 135), fill: 'none',
            stroke: 'rgba(255,255,255,.09)', strokeWidth: 2, strokeLinecap: 'round'
          }),
          h('path', {
            d: arcPath(cx, cy, r, -135, angle), fill: 'none',
            stroke: param.color, strokeWidth: 2.5, strokeLinecap: 'round'
          }),
          h('line', {
            x1: inner[0], y1: inner[1], x2: outer[0], y2: outer[1],
            stroke: param.color, strokeWidth: 1.8, strokeLinecap: 'round'
          })
        )
      ),
      h('div', { className: 'kval', style: { color: param.color } }, formatValue(param.key, value)),
      h('div', { className: 'klab' }, param.label)
    );
  }

  function activePreset(params) {
    var list = visiblePresets();
    for (var i = 0; i < list.length; i += 1) {
      var preset = list[i];
      var match = true;
      var keys = Object.keys(preset.values);
      for (var j = 0; j < keys.length; j += 1) {
        if (Math.abs(params[keys[j]] - preset.values[keys[j]]) > 0.001) {
          match = false;
          break;
        }
      }
      if (match) return preset.id;
    }
    return null;
  }

  function applyPresetValues(values) {
    var turnOn = !store.state.enabled;
    store.applyPreset(values);
    if (turnOn) {
      store.update({ enabled: true });
      send({ action: 'power', enabled: true });
    }
    Object.keys(values).forEach(function (key) {
      send({ action: 'param', name: key, value: values[key] });
    });
  }

  function PresetSelect(props) {
    var active = activePreset(props.params);
    var openState = useState(false);
    var open = openState[0];
    var setOpen = openState[1];
    var rootRef = useRef(null);

    useEffect(function () {
      if (!open) return;
      function onPointerDown(e) {
        if (rootRef.current && !rootRef.current.contains(e.target)) setOpen(false);
      }
      function onKeyDown(e) {
        if (e.key === 'Escape') setOpen(false);
      }
      document.addEventListener('pointerdown', onPointerDown, true);
      document.addEventListener('keydown', onKeyDown);
      return function () {
        document.removeEventListener('pointerdown', onPointerDown, true);
        document.removeEventListener('keydown', onKeyDown);
      };
    }, [open]);

    var current = 'Custom';
    var list = visiblePresets();
    for (var i = 0; i < list.length; i += 1) {
      if (list[i].id === active) {
        current = list[i].name;
        break;
      }
    }

    return h('div', { className: 'preset-row' },
      h('span', { className: 'preset-label' }, 'PRESET'),
      h('div', { className: 'dropdown', ref: rootRef },
        h('button', {
          className: 'dd-btn' + (open ? ' open' : ''),
          onPointerDown: function (e) { e.stopPropagation(); },
          onClick: function () { setOpen(!open); }
        },
          h('span', { className: 'dd-current' }, current),
          h('svg', {
            className: 'dd-caret',
            width: 9,
            height: 9,
            viewBox: '0 0 24 24',
            fill: 'none',
            stroke: 'currentColor',
            strokeWidth: 3,
            strokeLinecap: 'round',
            strokeLinejoin: 'round'
          }, h('path', { d: 'M6 9l6 6 6-6' }))
        ),
        open ? h('div', { className: 'dd-menu' },
          h('button', {
            className: 'dd-item' + (active ? '' : ' active'),
            onPointerDown: function (e) { e.stopPropagation(); },
            onClick: function () { setOpen(false); }
          }, 'Custom'),
          visibleGroups().map(function (group) {
            return h('div', { key: group.name, className: 'dd-group' },
              h('div', { className: 'dd-group-name' }, group.name),
              group.presets.map(function (preset) {
                return h('button', {
                  key: preset.id,
                  className: 'dd-item' + (active === preset.id ? ' active' : ''),
                  onPointerDown: function (e) { e.stopPropagation(); },
                  onClick: function () {
                    applyPresetValues(preset.values);
                    setOpen(false);
                  }
                }, preset.name);
              })
            );
          })
        ) : null
      )
    );
  }

  function App() {
    var state = useSyncExternalStore(store.subscribe, store.getSnapshot);
    return h('div', { className: 'app' },
      h(Header, { state: state }),
      h('div', { className: 'body' },
        h('div', { className: 'main' },
          h(TransferCurve, { state: state }),
          h('div', { className: 'knobs' },
            PARAMS.map(function (param) {
              return h(Knob, { key: param.key, param: param, value: state.params[param.key] });
            })
          ),
          h(PresetSelect, { params: state.params })
        ),
        h(MeterRail, { state: state })
      )
    );
  }

  ReactDOM.createRoot(document.getElementById('root')).render(h(App));
  send({ action: 'ready' });
})();
