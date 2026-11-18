// RME Control — motion layer.
// Reveals are opt-in: without this file the page is simply static.

(function () {
  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
  var fine = window.matchMedia('(hover: hover) and (pointer: fine)');

  /* Nav: a denser material once the page has moved under it. */
  var nav = document.querySelector('.nav');
  var ticking = false;
  function onScroll() {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(function () {
      ticking = false;
      nav.classList.toggle('is-scrolled', window.scrollY > 8);
    });
  }
  if (nav) {
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });

    // On phones the bar slides away while reading and comes back on an upward scroll.
    var lastY = window.scrollY;
    var barTicking = false;
    function onBarScroll() {
      if (barTicking) return;
      barTicking = true;
      requestAnimationFrame(function () {
        barTicking = false;
        var y = window.scrollY;
        var down = y > lastY + 4;
        var up = y < lastY - 4;
        if (y < 80) {
          nav.classList.remove('is-hidden');
        } else if (down && !nav.classList.contains('is-open')) {
          nav.classList.add('is-hidden');
        } else if (up) {
          nav.classList.remove('is-hidden');
        }
        lastY = y;
      });
    }
    window.addEventListener('scroll', onBarScroll, { passive: true });

    // Burger: opens the sheet, closes it on a link tap or on resize.
    var burger = nav.querySelector('.nav__burger');
    function closeMenu() {
      nav.classList.remove('is-open');
      if (burger) burger.setAttribute('aria-expanded', 'false');
    }
    if (burger) {
      burger.addEventListener('click', function () {
        var open = nav.classList.toggle('is-open');
        burger.setAttribute('aria-expanded', open ? 'true' : 'false');
        if (open) nav.classList.remove('is-hidden');
      });
    }
    nav.querySelectorAll('.nav__links a').forEach(function (link) {
      link.addEventListener('click', closeMenu);
    });
    window.addEventListener('resize', function () {
      if (window.innerWidth > 860) closeMenu();
    });
  }

  /* Reveal: each block rises into place once it is on screen. */
  var items = document.querySelectorAll('[data-reveal]');
  if (items.length) {
    if (!('IntersectionObserver' in window) || reduced.matches) {
      items.forEach(function (el) { el.classList.add('is-in'); });
    } else {
      var io = new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) return;
          entry.target.classList.add('is-in');
          io.unobserve(entry.target);
        });
      }, { rootMargin: '0px 0px -12% 0px', threshold: 0.15 });

      items.forEach(function (el) { io.observe(el); });

      // Safety: anything still hidden after a few seconds is shown.
      window.setTimeout(function () {
        items.forEach(function (el) { el.classList.add('is-in'); });
      }, 4000);
    }
  }

  /* Commands: one tap puts the line on the clipboard, so nobody retypes it. */
  document.querySelectorAll('.cmd-block').forEach(function (block) {
    var cmd = block.querySelector('.cmd');
    var btn = block.querySelector('[data-copy-command]');
    if (!cmd || !btn) return;

    var label = btn.querySelector('[data-i18n]') || btn;
    var timer = null;

    function word(key, fallback) {
      var i18n = window.rmeI18n;
      var value = i18n ? i18n.t(key) : '';
      return value || fallback;
    }

    function paint(copied) {
      btn.classList.toggle('is-copied', copied);
      label.textContent = copied ? word('install.cmd.copied', 'Copied') : word('install.cmd.copy', 'Copy');
    }

    // Older browsers and plain http need the selection path: the Clipboard API
    // only exists in a secure context.
    function copyBySelection() {
      var selection = window.getSelection();
      var range = document.createRange();
      range.selectNodeContents(cmd);
      selection.removeAllRanges();
      selection.addRange(range);
      var ok = false;
      try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
      selection.removeAllRanges();
      return ok;
    }

    function settle(ok) {
      if (!ok) return;
      paint(true);
      window.clearTimeout(timer);
      timer = window.setTimeout(function () { paint(false); }, 1800);
    }

    btn.addEventListener('click', function () {
      var text = cmd.textContent;
      if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(text).then(
          function () { settle(true); },
          function () { settle(copyBySelection()); }
        );
      } else {
        settle(copyBySelection());
      }
    });
  });

  if (reduced.matches) return;

  /* The product leans towards the pointer, then settles back on its own. */
  var stage = document.querySelector('.hero__stage');
  var tilt = document.querySelector('.hero__tilt');
  if (stage && tilt && fine.matches) {
    var target = { x: 0, y: 0 };
    var current = { x: 0, y: 0 };
    var raf = null;

    function frame() {
      current.x += (target.x - current.x) * 0.12;
      current.y += (target.y - current.y) * 0.12;
      var settled = Math.abs(target.x - current.x) < 0.002 && Math.abs(target.y - current.y) < 0.002;

      if (settled) {
        current.x = target.x;
        current.y = target.y;
        tilt.style.transform = '';
      } else {
        tilt.style.transform =
          'perspective(1000px) rotateY(' + (current.x * 3.2).toFixed(2) + 'deg) ' +
          'rotateX(' + (-current.y * 2.4).toFixed(2) + 'deg) ' +
          'translate3d(' + (current.x * 4).toFixed(2) + 'px,' + (current.y * 4).toFixed(2) + 'px,0)';
      }
      raf = settled ? null : requestAnimationFrame(frame);
    }

    stage.addEventListener('pointermove', function (event) {
      var rect = stage.getBoundingClientRect();
      target.x = ((event.clientX - rect.left) / rect.width - 0.5) * 2;
      target.y = ((event.clientY - rect.top) / rect.height - 0.5) * 2;
      if (!raf) raf = requestAnimationFrame(frame);
    });

    stage.addEventListener('pointerleave', function () {
      target.x = 0;
      target.y = 0;
      if (!raf) raf = requestAnimationFrame(frame);
    });
  }

})();
