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

  /* Slow drift: the product trails the page as it scrolls away. */
  if (stage && !window.matchMedia('(prefers-reduced-transparency: reduce)').matches) {
    var drift = false;
    function onDrift() {
      if (drift) return;
      drift = true;
      requestAnimationFrame(function () {
        drift = false;
        var y = Math.min(window.scrollY, 700);
        var offset = Math.max(-40, y * -0.06);
        stage.style.transform = offset === 0 ? '' : 'translate3d(0,' + offset.toFixed(1) + 'px,0)';
      });
    }
    onDrift();
    window.addEventListener('scroll', onDrift, { passive: true });
  }
})();
