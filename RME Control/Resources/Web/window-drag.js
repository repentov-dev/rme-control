// Перетаскивание безрамочного окна за любое пустое место страницы.
// Курсор не меняется: нативный drag handle не используется, окно двигает Swift.
(function () {
  'use strict';

  var INTERACTIVE = 'button, .switch, .close, .svgwrap, .graph, .tip-chip, .dd-btn, .dd-menu, .dropdown, input, select, textarea';

  var dragging = false;
  var pending = false;

  function send(message) {
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.rme) {
        window.webkit.messageHandlers.rme.postMessage(message);
      }
    } catch (error) {}
  }

  function onMove() {
    if (pending) return;
    pending = true;
    requestAnimationFrame(function () {
      pending = false;
      if (dragging) send({ action: 'drag' });
    });
  }

  function stop() {
    if (!dragging) return;
    dragging = false;
    document.removeEventListener('pointermove', onMove);
    send({ action: 'dragEnd' });
  }

  document.addEventListener('pointerdown', function (event) {
    if (event.button !== 0) return;
    var target = event.target;
    if (target && target.closest && target.closest(INTERACTIVE)) return;
    dragging = true;
    pending = false;
    send({ action: 'dragStart' });
    document.addEventListener('pointermove', onMove);
  });

  document.addEventListener('pointerup', stop);
  document.addEventListener('pointercancel', stop);
  window.addEventListener('blur', stop);

  // Правый клик по окну не должен открывать системное меню WebKit («Reload» и т.п.).
  // Обработчики страницы (например, CLOSE в панели уровней) продолжают работать.
  window.addEventListener('contextmenu', function (event) {
    event.preventDefault();
  }, true);
})();
