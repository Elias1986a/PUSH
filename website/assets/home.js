(function () {
  var btn = document.getElementById('cali-toggle');
  var off = document.getElementById('cali-off');
  var on = document.getElementById('cali-on');
  var label = document.getElementById('cali-label');
  btn.addEventListener('click', function () {
    var isOn = btn.getAttribute('aria-checked') !== 'true';
    btn.setAttribute('aria-checked', String(isOn));
    off.hidden = isOn;
    on.hidden = !isOn;
    label.textContent = 'California mode: ' + (isOn ? 'ON' : 'OFF');
  });
})();

// The demo videos play only while on screen, and not at all for people who
// asked for reduced motion (the controls still let them play one). With
// preload="none" a visit no longer downloads all three (about 7 MB) up front.
(function () {
  var videos = document.querySelectorAll('video[data-autoplay]');
  var still = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (still || !('IntersectionObserver' in window)) return;
  var seen = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) {
      if (e.isIntersecting) { var p = e.target.play(); if (p && p.catch) p.catch(function () {}); }
      else e.target.pause();
    });
  }, { threshold: 0.25 });
  videos.forEach(function (v) { seen.observe(v); });
})();
