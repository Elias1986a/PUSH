// Meta Pixel (ads measurement). A file rather than Meta's inline snippet: the
// CSP allows no inline scripts. Not on the thank-you page, whose address holds
// the order number; the pixel sends Meta the full URL. Skipped when the
// browser sends Global Privacy Control, the CCPA opt-out the privacy policy
// promises to honor.
(function () {
  if (navigator.globalPrivacyControl) return;
  !function(f,b,e,v,n,t,s)
  {if(f.fbq)return;n=f.fbq=function(){n.callMethod?
  n.callMethod.apply(n,arguments):n.queue.push(arguments)};
  if(!f._fbq)f._fbq=n;n.push=n;n.loaded=!0;n.version='2.0';
  n.queue=[];t=b.createElement(e);t.async=!0;
  t.src=v;s=b.getElementsByTagName(e)[0];
  s.parentNode.insertBefore(t,s)}(window, document,'script',
  'https://connect.facebook.net/en_US/fbevents.js');
  fbq('init', '1108475398808388');
  fbq('track', 'PageView');
})();
