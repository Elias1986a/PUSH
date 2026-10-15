(function () {
  var topic = document.getElementById('support-topic');
  var subject = document.getElementById('support-subject');
  var hint = document.getElementById('support-hint');
  var hints = {
    'Refund': 'Use the email you bought with, so we can find your order.\u00a0 No reason needed.',
    'Question': 'If something isn\'t working, say which PUSHTYPE version you have (Settings ▸ General) and your macOS version.',
    'Feature idea': 'What would you use it for?\u00a0 A sentence about that helps more than anything.'
  };
  function sync() {
    subject.value = 'PUSHTYPE ' + topic.value.toLowerCase();
    hint.textContent = hints[topic.value];
  }
  topic.addEventListener('change', sync);
  document.querySelectorAll('[data-topic]').forEach(function (a) {
    a.addEventListener('click', function () { topic.value = a.getAttribute('data-topic'); sync(); setTimeout(function () { document.getElementById('support-message').focus({ preventScroll: true }); }, 400); });
  });
  sync();
})();
