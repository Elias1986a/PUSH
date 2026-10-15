// Light/dark theme. Loaded in <head> so the saved or system theme is applied
// before the page paints. The toggle button is wired once the DOM is ready.
(function () {
  var root = document.documentElement;
  var saved = null;
  try { saved = localStorage.getItem('push-theme'); } catch (e) {}
  var system = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  root.setAttribute('data-theme', saved === 'dark' || saved === 'light' ? saved : system);

  // A fixed name with a pressed state: "Dark mode, pressed" reads right,
  // while a label that flipped with the state read as its own opposite.
  function sync(btn) {
    btn.setAttribute('aria-pressed', String(root.getAttribute('data-theme') === 'dark'));
    btn.setAttribute('aria-label', 'Dark mode');
  }

  // With no saved choice, follow the system when it switches.
  if (window.matchMedia) {
    var query = window.matchMedia('(prefers-color-scheme: dark)');
    var follow = function (e) {
      var chosen = null;
      try { chosen = localStorage.getItem('push-theme'); } catch (err) {}
      if (chosen) return;
      root.setAttribute('data-theme', e.matches ? 'dark' : 'light');
      var btn = document.getElementById('theme-toggle');
      if (btn) sync(btn);
    };
    if (query.addEventListener) query.addEventListener('change', follow);
  }

  document.addEventListener('DOMContentLoaded', function () {
    var btn = document.getElementById('theme-toggle');
    if (!btn) return;
    sync(btn);
    btn.addEventListener('click', function () {
      var next = root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
      root.setAttribute('data-theme', next);
      try { localStorage.setItem('push-theme', next); } catch (e) {}
      sync(btn);
    });
  });
})();
