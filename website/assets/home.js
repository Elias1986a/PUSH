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

// The hero video autoplays, except for people who asked for reduced motion:
// they get the poster and the controls instead.  Wider screens play the 16:9
// cut, so they get its poster.
(function () {
  var hero = document.getElementById('hero-video');
  if (!hero || !window.matchMedia) return;
  if (window.matchMedia('(min-width: 768px)').matches) hero.poster = 'assets/video/hero.jpg';
  if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  hero.autoplay = false;
  hero.pause();
  hero.controls = true;
})();

// Sound on or off without going full screen: a button on every video that
// has a soundtrack (data-sound; the TYPE demo has none).  Turning one on
// turns the others off and starts it if it was paused.
(function () {
  var ON = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M11 5 6 9H3v6h3l5 4z" fill="currentColor"/><path d="M15.5 8.5a5 5 0 0 1 0 7M18.5 5.5a9 9 0 0 1 0 13"/></svg>';
  var OFF = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M11 5 6 9H3v6h3l5 4z" fill="currentColor"/><path d="m16 9 6 6M22 9l-6 6"/></svg>';
  var videos = Array.prototype.slice.call(document.querySelectorAll('video[data-sound]'));
  videos.forEach(function (v) {
    var frame = document.createElement('div');
    frame.className = 'video-frame';
    v.parentNode.insertBefore(frame, v);
    frame.appendChild(v);
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'sound-btn';
    frame.appendChild(btn);
    function show() {
      var on = !v.muted;
      btn.innerHTML = on ? ON : OFF;
      btn.setAttribute('aria-label', on ? 'Turn sound off' : 'Turn sound on');
      btn.setAttribute('aria-pressed', String(on));
    }
    btn.addEventListener('click', function () {
      if (v.muted) {
        videos.forEach(function (o) { if (o !== v) o.muted = true; });
        v.muted = false;
        if (v.paused) { var p = v.play(); if (p && p.catch) p.catch(function () {}); }
      } else {
        v.muted = true;
      }
    });
    v.addEventListener('volumechange', show);  // also when the native controls mute it
    show();
  });
})();
