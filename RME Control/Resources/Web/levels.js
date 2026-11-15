(function () {
  'use strict';

  var h = React.createElement;
  var useState = React.useState;
  var useEffect = React.useEffect;
  var useSyncExternalStore = React.useSyncExternalStore;

  var initialState = { inputs: [] };

  var store = {
    state: initialState,
    listeners: new Set(),
    subscribe: function (fn) {
      store.listeners.add(fn);
      return function () { store.listeners.delete(fn); };
    },
    getSnapshot: function () { return store.state; },
    emit: function () { store.listeners.forEach(function (fn) { fn(); }); },
    update: function (patch) {
      if (!patch) return;
      store.state = Object.assign({}, store.state, patch);
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
      }
    } catch (error) {}
  }

  function clamp(value, lo, hi) { return Math.min(hi, Math.max(lo, value)); }

  function levelColor(value) {
    if (value > -6) return '#ff453a';
    if (value > -18) return '#ffd60a';
    return '#30d158';
  }

  function levelText(level) {
    return level <= -99.9 ? '-\u221E' : level.toFixed(1);
  }

  function LevelRow(props) {
    var input = props.input;
    var level = input.level;
    var pct = clamp((level + 60) / 60, 0, 1) * 100;
    return h('div', { className: 'row' },
      h('div', { className: 'name' + (input.phantom ? ' on' : '') }, input.name),
      h('div', { className: 'bar' },
        h('div', { className: 'fill', style: { width: pct + '%', background: levelColor(level) } })
      ),
      h('div', { className: 'val' + (level >= 0 ? ' clip' : '') }, levelText(level))
    );
  }

  function App() {
    var state = useSyncExternalStore(store.subscribe, store.getSnapshot);
    var menuState = useState(null);
    var menu = menuState[0];
    var setMenu = menuState[1];
    var inputs = state.inputs || [];

    useEffect(function () {
      var root = document.documentElement;
      if (state.nameWidth) root.style.setProperty('--name-w', state.nameWidth + 'px');
      if (state.valueWidth) root.style.setProperty('--value-w', state.valueWidth + 'px');
      if (state.meterWidth) root.style.setProperty('--meter-w', state.meterWidth + 'px');
    }, [state.nameWidth, state.valueWidth, state.meterWidth]);

    useEffect(function () {
      function hide() { setMenu(null); }
      function onKey(event) { if (event.key === 'Escape') setMenu(null); }
      window.addEventListener('mousedown', hide);
      window.addEventListener('keydown', onKey);
      window.addEventListener('blur', hide);
      return function () {
        window.removeEventListener('mousedown', hide);
        window.removeEventListener('keydown', onKey);
        window.removeEventListener('blur', hide);
      };
    }, []);

    useEffect(function () {
      if (!menu) return undefined;
      var timer = setTimeout(function () { setMenu(null); }, 4000);
      return function () { clearTimeout(timer); };
    }, [menu]);

    function onContextMenu(event) {
      event.preventDefault();
      setMenu({
        x: clamp(event.clientX - 4, 4, Math.max(4, window.innerWidth - 54)),
        y: clamp(event.clientY - 9, 4, Math.max(4, window.innerHeight - 26))
      });
    }

    return h('div', { className: 'app', onContextMenu: onContextMenu },
      h('div', { className: 'rows' }, inputs.map(function (input, index) {
        return h(LevelRow, { key: index, input: input });
      })),
      menu && h('button', {
        className: 'close',
        style: { left: menu.x + 'px', top: menu.y + 'px' },
        onMouseDown: function (event) { event.stopPropagation(); },
        onClick: function (event) {
          event.stopPropagation();
          setMenu(null);
          send({ action: 'close' });
        }
      }, 'CLOSE')
    );
  }

  ReactDOM.createRoot(document.getElementById('root')).render(h(App));
})();
