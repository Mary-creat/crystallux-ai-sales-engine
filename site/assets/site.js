/* Crystallux public site — minimal shared JS (header mobile toggle + active nav marking) */
(function () {
  // Mobile nav toggle
  var burger = document.querySelector('.clx-burger');
  var nav    = document.querySelector('.clx-nav');
  if (burger && nav) {
    burger.addEventListener('click', function () { nav.classList.toggle('open'); });
  }
  // Mark active nav item based on current path
  var path = window.location.pathname.replace(/\/$/, '') || '/index.html';
  var leaf = path.split('/').pop() || 'index.html';
  document.querySelectorAll('.clx-nav a').forEach(function (a) {
    var href = a.getAttribute('href') || '';
    var ahrefLeaf = href.split('/').pop();
    if (ahrefLeaf === leaf || (leaf === 'index.html' && ahrefLeaf === 'index.html')) a.classList.add('active');
  });
})();
