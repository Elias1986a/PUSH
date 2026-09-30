// Light/dark theme. Loaded in <head> so the saved or system theme is applied
// before the page paints. The toggle button is wired once the DOM is ready.
(function () {
  var root = document.documentElement;
  var saved = null;
  try { saved = localStorage.getItem('push-theme'); } catch (e) {}
  var system = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  root.setAttribute('data-theme', saved === 'dark' || saved === 'light' ? saved : system);

  function sync(btn) {
    var dark = root.getAttribute('data-theme') === 'dark';
    btn.setAttribute('aria-pressed', String(dark));
    btn.setAttribute('aria-label', dark ? 'Switch to light mode' : 'Switch to dark mode');
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
