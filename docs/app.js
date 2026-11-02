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

  /* 下载总数 = GitHub Release 下载 + 网页下载实时计数（Abacus） */
  (function () {
    var el = document.getElementById('dlTotal');
    if (!el) return;
    var stat = document.getElementById('dlStat');
    var GH_KEY = 'hfr_dl_gh_v3';
    var ghTotal = 0;
    var pageTotal = 0;
    var PAGE_BASE = 'https://abacus.jasoncameron.dev';
    var PAGE_PATH = '/yingge-dev/global-hfr-page-downloads-v1';

    function paint() {
      var total = ghTotal + pageTotal;
      var txt;
      try { txt = Number(total || 0).toLocaleString('zh-CN'); }
      catch (e) { txt = String(total || 0); }
      el.textContent = txt;
      if (stat) stat.textContent = txt;
    }

    function setGh(n) {
      ghTotal = Number(n) || 0;
      paint();
    }

    function setPage(n) {
      pageTotal = Math.max(pageTotal, Number(n) || 0);
      paint();
    }

    function pageGet() {
      fetch(PAGE_BASE + '/get' + PAGE_PATH, { cache: 'no-store' })
        .then(function (r) { return r.json(); })
        .then(function (j) { if (j && j.value != null) setPage(j.value); })
        .catch(function () {});
    }

    function pageHit() {
      fetch(PAGE_BASE + '/hit' + PAGE_PATH, { cache: 'no-store', keepalive: true })
        .then(function (r) { return r.json(); })
        .then(function (j) { if (j && j.value != null) setPage(j.value); })
        .catch(function () {});
    }

    // 点击下载时计数；不阻止浏览器下载
    function onDownload(e) {
      var t = e.target;
      var a = t && t.closest ? t.closest('a[data-dl]') : null;
      if (a) pageHit();
    }
    document.addEventListener('click', onDownload, true);
    document.addEventListener('auxclick', onDownload, true);

    pageGet();
    setInterval(function () {
      if (document.visibilityState !== 'hidden') pageGet();
    }, 5000);

    var cached = null;
    try { cached = JSON.parse(localStorage.getItem(GH_KEY) || 'null'); } catch (e) {}
    if (cached && cached.total != null) setGh(cached.total);

    // 同源快照：api.github.com 不可达时也有 GitHub 下载数
    fetch('downloads.json?ts=' + Date.now(), { cache: 'no-store' })
      .then(function (r) { if (!r.ok) throw new Error('http ' + r.status); return r.json(); })
      .then(function (snap) { if (snap && snap.total != null) setGh(snap.total); })
      .catch(function () {});

    if (cached && cached.total != null && Date.now() - cached.ts < 600000) return;

    fetch('https://api.github.com/repos/yingge-dev/global-hfr/releases?per_page=100', { cache: 'no-store' })
      .then(function (r) { if (!r.ok) throw new Error('http ' + r.status); return r.json(); })
      .then(function (list) {
        var total = 0;
        (list || []).forEach(function (rel) {
          if (rel.draft) return;
          (rel.assets || []).forEach(function (a) {
            if (a.name === 'global-hfr.zip' || a.name === 'zhen-quanju-gaoshu.zip') total += Number(a.download_count) || 0;
          });
        });
        try { localStorage.setItem(GH_KEY, JSON.stringify({ ts: Date.now(), total: total })); } catch (e) {}
        setGh(total);
      })
      .catch(function () {});
  })();
})();

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('sw.js').catch(function () {});
}

/* ---------- background music ---------- */
(function () {
  var audio = document.getElementById('musicAudio');
  var btn = document.getElementById('musicBtn');
  var panel = document.getElementById('musicPanel');
  var close = document.getElementById('musicClose');
  var toggle = document.getElementById('musicToggle');
  var next = document.getElementById('musicNext');
  var prev = document.getElementById('musicPrev');
  var title = document.getElementById('musicTitle');
  var stateEl = document.getElementById('musicState');
  var idxEl = document.getElementById('musicIdx');
  if (!audio || !btn) return;

  var tracks = [
    { title: '唐人恋曲 (DJ版)', artist: 'DJ大圣', src: 'assets/music/tangren-lianqu-dj.mp3' },
    { title: '红尘客栈 (DJ版)', artist: 'DJ冷冰冰', src: 'assets/music/hongchen-kz-dj.mp3' }
  ];
  var idx = 0;
  var needsGesture = false;
  var started = false;
  var interacted = false;
  var mutedAuto = false;

  audio.volume = 0.32;
  audio.preload = 'auto';
  audio.setAttribute('playsinline', '');

  function setState(txt) {
    if (stateEl) stateEl.textContent = txt;
    btn.classList.toggle('playing', !audio.paused);
    if (toggle) toggle.classList.toggle('playing', !audio.paused);
  }

  function load(i, play) {
    idx = (i + tracks.length) % tracks.length;
    var t = tracks[idx];
    audio.src = t.src;
    audio.load();
    if (title) title.textContent = t.title;
    if (idxEl) idxEl.textContent = (idx + 1) + ' / ' + tracks.length;
    if (next) next.disabled = tracks.length < 2;
    if (prev) prev.disabled = tracks.length < 2;
    if (stateEl) stateEl.textContent = t.artist || '背景音乐';
    if (play) startAudible();
    else setState('已暂停');
  }

  function startAudible() {
    audio.muted = false;
    var p = audio.play();
    if (p && p.then) {
      p.then(function () {
        needsGesture = false;
        mutedAuto = false;
        setState('正在播放');
      }).catch(function () {
        needsGesture = true;
        setState('点击播放');
      });
    }
  }

  function unmuteAndPlay() {
    var wasMuted = audio.muted || mutedAuto;
    audio.muted = false;
    if (wasMuted) {
      try { audio.currentTime = 0; } catch (e) {}
    }
    startAudible();
  }

  function tryAutoplay() {
    var p = audio.play();
    if (!p || !p.then) return;
    p.then(function () {
      started = true;
      setState('正在播放');
    }).catch(function () {
      // 有声音自动播放被拦截时，先静音播放，把音频缓冲起来；第一次点击再瞬间开声
      audio.muted = true;
      var q = audio.play();
      if (q && q.then) {
        q.then(function () {
          started = true;
          mutedAuto = true;
          needsGesture = true;
          setState('点击开启声音');
          if (interacted) unmuteAndPlay();
        }).catch(function () {
          needsGesture = true;
          setState('点击播放');
        });
      } else {
        needsGesture = true;
        setState('点击播放');
      }
    });
  }

  function togglePanel(show) {
    if (!panel) return;
    panel.hidden = show === false ? true : panel.hidden ? false : true;
    if (!panel.hidden) {
      if (audio.muted || mutedAuto) unmuteAndPlay();
      else if (audio.paused) startAudible();
    }
  }

  audio.addEventListener('play', function () {
    started = true;
    btn.classList.toggle('playing', true);
    if (toggle) toggle.classList.toggle('playing', true);
  });
  audio.addEventListener('pause', function () {
    if (started) setState(audio.muted ? '点击开启声音' : '已暂停');
  });
  audio.addEventListener('ended', function () { load(idx + 1, true); });
  audio.addEventListener('error', function () { setState('音频加载失败'); });

  btn.addEventListener('click', function () { togglePanel(); });
  if (close) close.addEventListener('click', function () { panel.hidden = true; });
  if (toggle) toggle.addEventListener('click', function () {
    if (audio.muted || mutedAuto) unmuteAndPlay();
    else if (audio.paused) startAudible();
    else audio.pause();
  });
  if (next) next.addEventListener('click', function () { load(idx + 1, true); });
  if (prev) prev.addEventListener('click', function () { load(idx - 1, true); });

  // 第一次点击页面任意位置：如果有声音自动播放被拦截，立即开声并从 0 开始
  document.addEventListener('pointerdown', function () {
    interacted = true;
    if (needsGesture || audio.muted || mutedAuto) unmuteAndPlay();
  }, true);

  load(0, false);
  tryAutoplay();
})();
