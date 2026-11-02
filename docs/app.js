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

  /* 版本提示：update.json 比本页新时，顶部横幅自动切换 */
  (function () {
    var SITE_VERSION = 'v2.2.1';
    var SITE_CODE = 20201;
    var bar = document.getElementById('releaseBar');
    if (!bar) return;
    fetch('update.json', { cache: 'no-store' }).then(function (r) {
      if (!r.ok) throw new Error('http');
      return r.json();
    }).then(function (j) {
      if (!j || !j.versionCode || Number(j.versionCode) <= SITE_CODE) return;
      var t = document.getElementById('releaseTitle');
      var d = document.getElementById('releaseDesc');
      var a = bar.querySelector('a');
      if (t) t.textContent = '发现新版本 ' + j.version;
      if (d) d.textContent = '项目主页当前 ' + SITE_VERSION + '，新版本已发布';
      if (a) a.href = j.changelog || '#changelog';
    }).catch(function () {});
  })();

  /* GitHub Release 下载次数：优先读同源 downloads.json 快照，再用 API 刷新 */
  (function () {
    var el = document.getElementById('dlTotal');
    if (!el) return;
    var KEY = 'hfr_dl_total_v2';
    var cached = null;
    try { cached = JSON.parse(localStorage.getItem(KEY) || 'null'); } catch (e) {}
    var stat = document.getElementById('dlStat');
    function paint(n) {
      var txt;
      try { txt = Number(n || 0).toLocaleString('zh-CN'); }
      catch (e) { txt = String(n || 0); }
      el.textContent = txt;
      if (stat) stat.textContent = txt;
    }
    if (cached && cached.total != null) paint(cached.total);

    // 同源快照：即使 api.github.com 被限流/不可达，页面也有数字
    fetch('downloads.json?ts=' + Date.now(), { cache: 'no-store' })
      .then(function (r) { if (!r.ok) throw new Error('http ' + r.status); return r.json(); })
      .then(function (snap) {
        if (snap && snap.total != null) paint(snap.total);
      })
      .catch(function () {});

    if (cached && cached.total != null && Date.now() - cached.ts < 600000) return;

    fetch('https://api.github.com/repos/yingge-dev/global-hfr/releases?per_page=100', { cache: 'no-store' })
      .then(function (r) { if (!r.ok) throw new Error('http ' + r.status); return r.json(); })
      .then(function (list) {
        var total = 0;
        (list || []).forEach(function (rel) {
          if (rel.draft) return;
          (rel.assets || []).forEach(function (a) {
            if (a.name === 'global-hfr.zip') total += Number(a.download_count) || 0;
          });
        });
        try { localStorage.setItem(KEY, JSON.stringify({ ts: Date.now(), total: total })); } catch (e) {}
        paint(total);
      })
      .catch(function () {});
  })();

})();
