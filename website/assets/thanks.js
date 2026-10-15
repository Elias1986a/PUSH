(function () {
  // The order number and session token in the address are what unlock the
  // key: read them, then take them out of the address bar and history. The
  // tab keeps them so a reload still works. No third-party script runs here.
  var query = new URLSearchParams(location.search);
  var id = query.get('checkout_id');
  var session = query.get('customer_session_token') || '';
  try {
    if (id) sessionStorage.setItem('purchase', JSON.stringify({ id: id, session: session }));
    else { var kept = JSON.parse(sessionStorage.getItem('purchase') || 'null'); if (kept) { id = kept.id; session = kept.session; } }
  } catch (e) {}
  if (location.search) history.replaceState(null, '', location.pathname);
  var tries = 0;
  // Only if the lookup can't be done: the receipt email has everything.
  function fallback() {
    document.getElementById('thanks-lede').textContent = 'Polar has emailed you a receipt with your download and license key.';
    document.getElementById('manual').hidden = false;
  }
  if (!id) return fallback();
  function show(data) {
    document.getElementById('thanks-lede').textContent = data.kind === 'extra'
      ? (data.added === 1 ? 'That\'s one more Mac on your license.' : 'That adds ' + data.added + ' Macs to your license.')
        + ' It now covers ' + data.macs + '.\u00a0 Install and activate it on the new Mac.'
      : 'Two clicks and you\'re talking.\u00a0 Polar has also emailed you a receipt with your download and license key.';
    // What this key covers: one Mac for a single, more once things are added.
    document.getElementById('macs-note').textContent = data.macs === 1
      ? 'This key covers 1 Mac.\u00a0 Each extra Mac is $12, and the $35 license adds 3 more (buy with the same email).'
      : 'This license covers ' + data.macs + ' Macs, and each extra Mac is $12.';
    document.getElementById('quick').hidden = false;
    var dl = document.getElementById('download-btn');
    if (data.download) {
      dl.href = data.download.url;
      document.getElementById('download-meta').textContent = data.download.name + ' · ' + data.download.size;
    } else {
      dl.replaceWith(document.createTextNode('Use the link in Polar\'s email.'));
    }
    document.getElementById('activate-btn').href = 'pushtype://activate?key=' + encodeURIComponent(data.key);
    document.getElementById('key-text').textContent = data.key;
    document.getElementById('copy-btn').addEventListener('click', function (e) {
      navigator.clipboard.writeText(data.key).then(function () { e.target.textContent = 'Copied'; });
    });
  }
  function load() {
    fetch('/api/purchase?checkout_id=' + encodeURIComponent(id) + '&customer_session_token=' + encodeURIComponent(session))
      .then(function (r) { return r.json().then(function (body) { return { status: r.status, body: body }; }); })
      .then(function (res) {
        if (res.status === 200 && res.body.key) return show(res.body);
        // Polar can take a few seconds to finish the order after payment.
        if (res.status === 409 && ++tries < 8) return setTimeout(load, 2000);
        fallback();
      })
      .catch(fallback);
  }
  load();
})();
