(function () {
  'use strict';

  /* GitHub 仓库：部署到 <user>.github.io/<repo>/ 时自动识别，否则用下面的占位符 */
  var REPO = 'yingge-dev/global-hfr';
  try {
    var host = location.hostname;
    var seg = location.pathname.split('/').filter(Boolean);
    if (/\.github\.io$/i.test(host) && seg.length) {
      REPO = host.split('.')[0] + '/' + seg[0];
    }
  } catch (e) {}
  Array.prototype.forEach.call(document.querySelectorAll('[data-repo]'), function (a) {
    a.href = 'https://github.com/' + REPO;
  });

  /* 主题 */
  var root = document.documentElement;
  var btn = document.getElementById('themeBtn');
  var meta = document.getElementById('themeColor');
  function systemDark() {
    try { return window.matchMedia('(prefers-color-scheme: dark)').matches; } catch (e) { return false; }
  }
  function effective() {
    var t = root.getAttribute('data-theme');
    if (t === 'light' || t === 'dark') return t;
    return systemDark() ? 'dark' : 'light';
  }
  function paintMeta() {
    if (meta) meta.setAttribute('content', effective() === 'dark' ? '#07080d' : '#eef3fa');
  }
  function setTheme(t) {
    if (t === 'auto') root.removeAttribute('data-theme');
    else root.setAttribute('data-theme', t);
    try { localStorage.setItem('ghfr-theme', t); } catch (e) {}
    paintMeta();
  }
  if (btn) {
    btn.addEventListener('click', function () {
      setTheme(effective() === 'dark' ? 'light' : 'dark');
    });
  }
  try {
    var qTheme = new URLSearchParams(location.search).get('theme');
    if (qTheme === 'light' || qTheme === 'dark') setTheme(qTheme);
  } catch (e) {}
  paintMeta();
  try {
    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function () {
      if (!root.getAttribute('data-theme')) paintMeta();
    });
  } catch (e) {}

  /* 滚动显现 */
  var items = document.querySelectorAll('.reveal');
  if ('IntersectionObserver' in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) { en.target.classList.add('in'); io.unobserve(en.target); }
      });
    }, { threshold: 0.12 });
    Array.prototype.forEach.call(items, function (el) { io.observe(el); });
  } else {
    Array.prototype.forEach.call(items, function (el) { el.classList.add('in'); });
  }

  /* 截图灯箱 */
  var box = document.getElementById('lightbox');
  var big = box ? box.querySelector('img') : null;
  function close() {
    if (!box) return;
    box.classList.remove('on');
    box.setAttribute('aria-hidden', 'true');
  }
  Array.prototype.forEach.call(document.querySelectorAll('.shot'), function (a) {
    a.addEventListener('click', function (e) {
      if (!box || !big) return;
      e.preventDefault();
      big.src = a.getAttribute('href');
      big.alt = a.querySelector('img') ? a.querySelector('img').alt : '';
      box.classList.add('on');
      box.setAttribute('aria-hidden', 'false');
    });
  });
  if (box) {
    box.addEventListener('click', function (e) {
      if (e.target === box || e.target.tagName === 'BUTTON') close();
    });
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') close();
    });
  }
})();
