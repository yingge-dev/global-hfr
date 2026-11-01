/* ============================================================
   真·全局高刷 · WebUI
   Author: 颖哥
   ============================================================ */
(function () {
  'use strict';

  var ENGINE = '/data/adb/modules/global_hfr/hfr.sh';
  var STD_RATES = [60, 90, 120, 144, 165, 185];
  var C = 2 * Math.PI * 96;
  var state = null;
  var demo = false;
  var busy = false;
  var cbSeq = 0;
  var toastTimer = null;
  var pollTimer = null;
  var shownHz = 0;
  var firstPaint = true;
  var lastInteract = 0;
  var THEME_KEY = 'hfr_theme_v1';
  var themeMode = 'auto';

  var $ = function (sel, root) { return (root || document).querySelector(sel); };
  var $$ = function (sel, root) {
    return Array.prototype.slice.call((root || document).querySelectorAll(sel));
  };

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function hasApi() {
    return !!(window.ksu && typeof window.ksu.exec === 'function');
  }

  function exec(cmd) {
    return new Promise(function (resolve) {
      if (!hasApi()) { resolve({ errno: 127, stdout: '', stderr: 'no-bridge' }); return; }
      var name = '__hfr_cb_' + (++cbSeq);
      var finished = false;
      window[name] = function (errno, stdout, stderr) {
        finished = true;
        try { delete window[name]; } catch (e) {}
        resolve({ errno: errno, stdout: stdout || '', stderr: stderr || '' });
      };
      try {
        window.ksu.exec(cmd, '{}', name);
      } catch (e) {
        finished = true;
        resolve({ errno: -1, stdout: '', stderr: String(e) });
      }
      setTimeout(function () {
        if (finished) return;
        try { delete window[name]; } catch (e) {}
        resolve({ errno: -2, stdout: '', stderr: 'timeout' });
      }, 15000);
    });
  }

  function parseJson(text) {
    if (!text) return null;
    var i = text.indexOf('{');
    var j = text.lastIndexOf('}');
    if (i < 0 || j <= i) return null;
    try { return JSON.parse(text.slice(i, j + 1)); } catch (e) { return null; }
  }

  function run(args) {
    return exec('sh ' + ENGINE + ' ' + args + ' 2>&1').then(function (r) {
      return { raw: r, json: parseJson(r.stdout) };
    });
  }

  /* ---------------- 演示数据（浏览器预览） ---------------- */
  var DEMO = {
    ok: 1,
    ts: Math.floor(Date.now() / 1000),
    version: 'v2.0.0',
    versionCode: 20000,
    device: {
      brand: 'OnePlus', model: 'PJZ110', market: 'OnePlus 13',
      rom: 'ColorOS 15.0.1', android: '15', sdk: 35,
      soc: 'Snapdragon 8 Elite', platform: 'qualcomm', family: 'oplus'
    },
    panel: {
      max: 165,
      nativeMax: 165,
      modes: [
        { id: 1, w: 1440, h: 3168, hz: 60 },
        { id: 2, w: 1440, h: 3168, hz: 90 },
        { id: 3, w: 1440, h: 3168, hz: 120 },
        { id: 4, w: 1440, h: 3168, hz: 144 },
        { id: 5, w: 1440, h: 3168, hz: 165 }
      ]
    },
    config: {
      profile: 'dynamic', fixed_hz: 0, dyn_min: 60, dyn_max: 165,
      dyn_engine: 'auto', dyn_idle_ms: 3000,
      touch: 1, touch_level: 'standard', deep_lock: 1, overlay: 0,
      daemon: 1, auto_boot: 1, oplus_props: 0
    },
    live: { current: 60, target: 165, verified: 1, method: '原生动态 60-165Hz', engine: 'native', updated: Math.floor(Date.now() / 1000), restart_required: 0 },
    touch: {
      enabled: 1, level: 'standard', applied: 3,
      nodes: [
        { name: 'touchboost', path: '/sys/module/msm_performance/parameters/touchboost', exists: 1, ok: 1 },
        { name: 'input_boost', path: '/sys/module/cpu_boost/parameters/input_boost_enabled', exists: 1, ok: 0 },
        { name: 'adreno_idler', path: '/sys/module/adreno_idler/parameters/adreno_idler_active', exists: 1, ok: 1 },
        { name: 'x_gpu_gov', path: '/sys/class/kgsl/kgsl-3d0/devfreq/governor', exists: 1, ok: 0 },
        { name: 'mtk_fpsgo', path: '/sys/kernel/fpsgo/common/force_onoff', exists: 0, ok: 0 },
        { name: 'renice', path: 'touch HAL', exists: 1, ok: 1 }
      ]
    }
  };

  /* ---------------- 基础渲染 ---------------- */
  function toast(msg, kind) {
    var el = $('#toast');
    el.textContent = msg;
    el.className = 'toast on' + (kind ? ' ' + kind : '');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { el.className = 'toast'; }, 2600);
  }

  function buildTicks() {
    var g = $('#ticks');
    var NS = 'http://www.w3.org/2000/svg';
    var n = 48;
    for (var i = 0; i < n; i++) {
      var a = (-90 + i * (360 / n)) * Math.PI / 180;
      var major = i % 6 === 0;
      var r1 = 106;
      var r2 = major ? 114 : 110;
      var ln = document.createElementNS(NS, 'line');
      ln.setAttribute('x1', (120 + Math.cos(a) * r1).toFixed(2));
      ln.setAttribute('y1', (120 + Math.sin(a) * r1).toFixed(2));
      ln.setAttribute('x2', (120 + Math.cos(a) * r2).toFixed(2));
      ln.setAttribute('y2', (120 + Math.sin(a) * r2).toFixed(2));
      if (major) ln.setAttribute('class', 'major');
      g.appendChild(ln);
    }
  }

  function animateHz(target) {
    var el = $('#curHz');
    var from = shownHz || 0;
    var to = Number(target) || 0;
    if (!to) { el.textContent = '--'; shownHz = 0; return; }
    var start = (window.performance && performance.now) ? performance.now() : Date.now();
    var dur = 620;
    function tick(now) {
      var t = Math.min(1, (now - start) / dur);
      var e = 1 - Math.pow(1 - t, 3);
      var v = Math.round(from + (to - from) * e);
      el.textContent = String(v);
      if (t < 1) requestAnimationFrame(tick); else shownHz = to;
    }
    requestAnimationFrame(tick);
  }

  function paintGauge(hz, max, profile) {
    var ring = $('#ring');
    var pct = max > 0 ? Math.min(1, Math.max(0, (Number(hz) || 0) / max)) : 0;
    if (profile === 'off') pct = 0;
    ring.style.strokeDashoffset = (C * (1 - pct)).toFixed(2);
    var box = ring.ownerSVGElement;
    box.classList.toggle('dim', profile === 'off');
    var ticks = $('#ticks').children;
    var n = ticks.length;
    for (var i = 0; i < n; i++) {
      ticks[i].classList.toggle('hot', pct > 0 && (i + 1) / n <= pct + 0.004);
    }
  }

  function rateList(data) {
    var modes = (data.panel && data.panel.modes) || [];
    var seen = {};
    var out = [];
    modes.forEach(function (m) {
      var hz = Math.round(Number(m.hz) || 0);
      if (hz > 0 && !seen[hz]) { seen[hz] = 1; out.push(hz); }
    });
    out.sort(function (a, b) { return a - b; });
    return out;
  }

  function nearest(list, want) {
    if (!list.length) return want;
    var best = list[0];
    var bd = Math.abs(best - want);
    list.forEach(function (v) {
      var d = Math.abs(v - want);
      if (d < bd) { bd = d; best = v; }
    });
    return best;
  }

  function supported(list, hz) {
    for (var i = 0; i < list.length; i++) {
      if (Math.abs(list[i] - hz) <= 2) return true;
    }
    return false;
  }

  /* ---------------- 主题（Glass） ---------------- */
  function isDarkNow(mode) {
    if (mode === 'dark') return true;
    if (mode === 'light') return false;
    try { return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches; } catch (e) { return false; }
  }

  function paintThemeMeta(mode) {
    var meta = $('#themeColor');
    if (meta) meta.setAttribute('content', isDarkNow(mode) ? '#08090e' : '#eef3fa');
  }

  function applyTheme(mode) {
    themeMode = (mode === 'light' || mode === 'dark') ? mode : 'auto';
    var root = document.documentElement;
    if (themeMode === 'auto') root.removeAttribute('data-theme');
    else root.setAttribute('data-theme', themeMode);
    try { localStorage.setItem(THEME_KEY, themeMode); } catch (e) {}
    $$('#themeSeg button').forEach(function (b) {
      b.classList.toggle('on', b.getAttribute('data-theme') === themeMode);
    });
    paintThemeMeta(themeMode);
  }

  /* ---------------- 主渲染 ---------------- */
  function render() {
    if (!state) return;
    var d = state.device || {};
    var p = state.panel || {};
    var c = state.config || {};
    var l = state.live || {};
    var t = state.touch || {};
    var max = Math.round(Number(p.max) || 0);
    var cur = Math.round(Number(l.current) || 0);
    var target = Math.round(Number(l.target) || 0);
    var profile = c.profile || 'off';
    var verified = Number(l.verified) === 1;

    var vt = $('#verText');
    if (vt) vt.textContent = state.version || 'v2.0.0';
    $('#aboutVer').textContent = state.version || 'v2.0.0';
    $('#devName').textContent = demo ? '预览模式' : (d.market || d.model || '未知设备');
    var dot = $('#devDot');
    dot.className = 'dot' + (demo ? '' : (verified ? ' on' : ' err'));

    var liveDot = $('#liveDot');
    var liveLabel = $('#liveLabel');
    var dynLive = profile === 'dynamic';
    liveDot.className = 'pulse' + (demo ? ' warn' : (verified ? '' : ' bad'));
    liveLabel.textContent = demo ? '浏览器预览 · 未连接模块' :
      (Number(l.restart_required) === 1 ? '已连接 · 需重启后生效' :
        (dynLive ? ('已连接 · ' + (l.engine === 'adaptive' ? '自适应动态' : '原生动态')) :
          (verified ? '已连接 · 锁定已核验' : '已连接 · 等待核验')));

    if (firstPaint) {
      $('#curHz').textContent = cur ? String(cur) : '--';
      shownHz = cur;
      firstPaint = false;
    } else {
      animateHz(cur);
    }
    paintGauge(cur, max, profile);

    var tag = $('#curTag');
    if (profile === 'dynamic') {
      tag.textContent = l.engine === 'adaptive' ? '自适应' : '原生动态';
      tag.className = 'hz-tag';
    }
    else if (profile === 'off') { tag.textContent = '系统调度'; tag.className = 'hz-tag'; }
    else if (verified) { tag.textContent = '已锁定'; tag.className = 'hz-tag ok'; }
    else { tag.textContent = '待核验'; tag.className = 'hz-tag warn'; }

    $('#statMax').textContent = max ? max + ' Hz' : '--';
    $('#statTarget').textContent = target ? target + ' Hz' : '--';
    $('#statVerify').textContent = dynLive ? (l.engine === 'adaptive' ? '自适应调度' : '原生调度') :
      (verified ? '已核验' : (profile === 'off' ? '已交还' : '未核验'));
    $('#methodLine').textContent = l.method || '—';

    renderPresets(c, max);
    renderRates(c, max, rateList(state));
    renderDynamic(c, max, rateList(state));
    renderTouch(t, c);
    renderSettings(d, c);
  }

  function renderPresets(c, max) {
    var fixed = Number(c.fixed_hz) || 0;
    var active = c.profile === 'dynamic' ? 'dynamic' :
      (c.profile === 'off' ? 'off' : ((fixed === 0 || Math.abs(fixed - max) <= 2) ? 'max' : ''));
    $$('#presets .preset').forEach(function (b) {
      b.classList.toggle('on', b.getAttribute('data-preset') === active);
    });
  }

  function renderRates(c, max, avail) {
    var box = $('#rates');
    var fixed = Number(c.fixed_hz) || 0;
    var currentFixed = c.profile === 'fixed' ? (fixed || max) : 0;
    var list = [];
    STD_RATES.concat(avail).forEach(function (v) {
      v = Math.round(v);
      if (v > 0 && list.indexOf(v) < 0) list.push(v);
    });
    list.sort(function (a, b) { return a - b; });
    if (max > 0) {
      list = list.filter(function (v) { return v <= max + 2 || STD_RATES.indexOf(v) >= 0; });
    }
    var html = list.map(function (hz) {
      var ok = supported(avail, hz);
      var on = currentFixed > 0 && Math.abs(currentFixed - hz) <= 2;
      var oc = ok && hz > 120 ? '<span class="oc">OC</span>' : '';
      return '<button class="rate' + (on ? ' on' : '') + (ok ? '' : ' off') + '" type="button" data-hz="' + hz + '"' +
        (ok ? '' : ' aria-disabled="true"') + '>' + oc + '<b>' + hz + '</b><i>HZ</i></button>';
    }).join('');
    box.innerHTML = html;

    var hint = $('#ratesHint');
    if (!avail.length) {
      hint.innerHTML = '未扫描到显示档位。请到「设置 → 重新扫描显示档位」，或重启后再试。';
    } else if (max > 120) {
      hint.innerHTML = '已检测到 <b>' + max + 'Hz</b> 档位（含超频）。锁定后请观察屏幕稳定性与耗电。';
    } else {
      hint.innerHTML = '面板原生最高 <b>' + max + 'Hz</b>；144 / 165 / 185Hz 需要机型或超频 DTBO 支持，未检测到时不可选。';
    }
  }

  function renderDynamic(c, max, avail) {
    var minEl = $('#dynMin');
    var maxEl = $('#dynMax');
    var l = (state && state.live) || {};
    var panelMax = max || (avail.length ? avail[avail.length - 1] : 120);
    var nativeMax = Number((state && state.panel && state.panel.nativeMax) || 0) || panelMax;
    var mins = [10, 30, 48, 60].concat(avail).filter(function (v, i, a) {
      return v <= panelMax && a.indexOf(v) === i;
    }).sort(function (a, b) { return a - b; });
    var maxs = avail.length ? avail.filter(function (v) { return v <= panelMax + 2; }) : [60, 90, 120];
    if (maxs.indexOf(panelMax) < 0) maxs.push(panelMax);
    maxs.sort(function (a, b) { return a - b; });

    minEl.innerHTML = mins.map(function (v) {
      return '<option value="' + v + '">' + v + ' Hz' + (v <= 30 ? ' · LTPO' : '') + '</option>';
    }).join('');
    maxEl.innerHTML = maxs.map(function (v) {
      return '<option value="' + v + '">' + v + ' Hz</option>';
    }).join('');

    var wantMin = Number(c.dyn_min) || 60;
    var wantMax = Number(c.dyn_max) || panelMax;
    minEl.value = String(nearest(mins, wantMin));
    maxEl.value = String(nearest(maxs, wantMax));

    var lo = Number(minEl.value);
    var hi = Number(maxEl.value);
    if (hi <= lo) { hi = maxs[maxs.length - 1]; maxEl.value = String(hi); }

    var floor = mins[0];
    var span = Math.max(1, panelMax - floor);
    $('#dynFill').style.left = (((lo - floor) / span) * 100).toFixed(1) + '%';
    $('#dynFill').style.width = (Math.max(6, ((hi - lo) / span) * 100)).toFixed(1) + '%';
    $('#dynLabel').textContent = lo + ' – ' + hi + ' Hz';

    var pairs = [];
    var seen = {};
    function addPair(a, b) {
      a = Math.round(Number(a)); b = Math.round(Number(b));
      if (!a || !b || b <= a || b > panelMax + 2 || a < floor) return;
      var key = a + '-' + b;
      if (seen[key]) return;
      seen[key] = 1;
      pairs.push([a, b]);
    }
    addPair(60, panelMax);
    addPair(60, 120);
    addPair(60, 144);
    addPair(60, 165);
    addPair(120, panelMax);
    addPair(120, 165);
    addPair(90, panelMax);
    addPair(30, 120);
    pairs.sort(function (a, b) { return (a[1] - b[1]) || (a[0] - b[0]); });
    if (!pairs.length) pairs = [[Math.min(60, floor), panelMax]];

    $('#dynPresets').innerHTML = pairs.map(function (pr) {
      var on = c.profile === 'dynamic' && Number(c.dyn_min) === pr[0] && Number(c.dyn_max) === pr[1];
      return '<button type="button" data-lo="' + pr[0] + '" data-hi="' + pr[1] + '" class="' + (on ? 'on' : '') + '">' +
        pr[0] + '–' + pr[1] + 'Hz</button>';
    }).join('');

    var eng = c.dyn_engine || 'auto';
    $$('#dynEngineSeg button').forEach(function (b) {
      b.classList.toggle('on', b.getAttribute('data-engine') === eng);
    });
    var idleEl = $('#dynIdle');
    var idleVal = String(Number(c.dyn_idle_ms) || 3000);
    var hasIdle = false;
    Array.prototype.forEach.call(idleEl.options, function (o) { if (o.value === idleVal) hasIdle = true; });
    if (!hasIdle) {
      var o = document.createElement('option');
      o.value = idleVal; o.textContent = (Number(idleVal) / 1000).toFixed(1) + ' 秒';
      idleEl.appendChild(o);
    }
    idleEl.value = idleVal;
    var hint = '';
    if (eng === 'auto') {
      hint = l.engine === 'adaptive' ? ('当前：自适应（可绕过系统 ' + nativeMax + 'Hz 上限）') :
        ('当前：原生（系统上限 ' + nativeMax + 'Hz）');
    } else if (eng === 'native') {
      hint = '系统内容调度，最高 ' + nativeMax + 'Hz';
      if (nativeMax < panelMax) hint += ' · 面板 ' + panelMax + 'Hz，超出请用自适应';
    } else {
      hint = '触控驱动，最高 ' + panelMax + 'Hz，静止 ' + (Number(idleVal) / 1000).toFixed(0) + ' 秒降到下限';
    }
    $('#dynEngineHint').textContent = hint;
  }

  function touchLabel(name) {
    var map = {
      touchboost: '高通触控 boost',
      touchboost_alt: '高通触控 boost · 兼容',
      input_boost: 'CPU 输入加速',
      adreno_idler: 'Adreno 空闲降频',
      mtk_fpsgo: 'MTK FPSGO 帧率加速',
      x_gpu_gov: 'GPU 频率策略',
      x_sched_boost: '调度器 boost',
      renice: '触控 HAL 优先级'
    };
    return map[name] || name;
  }

  function inferVerified() {
    if (!state || !state.live) return;
    var l = state.live;
    var cfg = state.config || {};
    if (cfg.profile === 'dynamic') {
      l.verified = (l.engine === 'native' || l.engine === 'adaptive') ? 1 : 0;
      return;
    }
    var t = Number(l.target) || 0;
    var c = Number(l.current) || 0;
    if (t > 0 && Math.abs(c - t) <= 2 && Number(l.verified) !== 1) l.verified = 1;
  }

  function renderTouch(t, c) {
    var on = Number(c.touch) === 1;
    var lvl = c.touch_level || 'standard';
    var nodes = t.nodes || [];
    var applied = Number(t.applied) || 0;

    $('#touchSwitch').checked = on;
    $('#touchSwitch2').checked = on;
    $$('#touchLevelSeg button, #touchLevelSeg2 button').forEach(function (b) {
      b.classList.toggle('on', b.getAttribute('data-level') === lvl);
    });

    $('#touchSummary').textContent = on ?
      ('已启用 · ' + applied + ' 项生效 · ' + (lvl === 'esports' ? '电竞' : '标准')) :
      '已关闭 · 未写入内核节点';
    $('#touchHeroState').textContent = on ?
      ('运行中 · ' + (lvl === 'esports' ? '电竞模式（高耗电）' : '标准模式')) : '已关闭';

    var body = nodes.map(function (n) {
      var cls = n.exists ? (n.ok ? 'ok' : '') : 'miss';
      var stateText = n.exists ? (n.ok ? '已生效' : '未生效') : '未检测到';
      return '<li>' +
        '<span class="n-dot ' + cls + '"></span>' +
        '<div class="n-body"><div class="n-name">' + esc(touchLabel(n.name)) + '</div>' +
        '<div class="n-path">' + esc(n.path) + '</div></div>' +
        '<span class="n-state ' + (n.ok ? 'ok' : '') + '">' + stateText + '</span>' +
        '</li>';
    }).join('');
    $('#nodes').innerHTML = body || '<li><span class="n-dot miss"></span><div class="n-body"><div class="n-name">未检测到可写节点</div><div class="n-path">当前内核未暴露常用触控 boost 接口</div></div></li>';
    $('#touchCount').textContent = applied + ' 项生效';
  }

  function platformText(p) {
    if (p === 'qualcomm') return '高通骁龙';
    if (p === 'mediatek') return '联发科天玑';
    return p || '未知';
  }

  function renderSettings(d, c) {
    $('#swDeep').checked = Number(c.deep_lock) === 1;
    $('#swOverlay').checked = Number(c.overlay) === 1;
    $('#swBoot').checked = Number(c.auto_boot) === 1;
    $('#swDaemon').checked = Number(c.daemon) === 1;
    $('#swOplus').checked = Number(c.oplus_props) === 1;

    var brand = String(d.brand || '').toLowerCase();
    var isOplus = /oppo|oneplus|realme|oplus/.test(brand);
    $('#rowOplus').hidden = !isOplus;

    var modes = rateList(state);
    var res = '';
    var bestPx = 0;
    (state.panel && state.panel.modes || []).forEach(function (m) {
      var px = (Number(m.w) || 0) * (Number(m.h) || 0);
      if (px > bestPx) { bestPx = px; res = m.w + ' × ' + m.h; }
    });
    var platform = platformText(d.platform);
    var rows = [
      ['品牌', d.brand || '--'],
      ['机型', (d.market || '') + (d.model && d.model !== d.market ? ' · ' + d.model : '')],
      ['系统', (d.rom || '--') + ' / Android ' + (d.android || '--')],
      ['芯片', d.soc || '--'],
      ['平台', platform],
      ['分辨率', res || '--'],
      ['档位', modes.length ? modes.join(' / ') + ' Hz' : '未扫描'],
      ['系统上限', ((state.panel && state.panel.nativeMax) || '--') + ' Hz'],
      ['引擎', state.version || '--']
    ];
    $('#deviceKv').innerHTML = rows.map(function (r) {
      return '<div><span>' + esc(r[0]) + '</span><b>' + esc(r[1]) + '</b></div>';
    }).join('');
  }

  function renderError(raw) {
    var msg = (raw && (raw.stderr || raw.stdout)) || '';
    $('#curHz').textContent = '--';
    $('#curTag').textContent = '未连接';
    $('#curTag').className = 'hz-tag warn';
    $('#liveLabel').textContent = '模块引擎未响应';
    $('#liveDot').className = 'pulse bad';
    $('#devName').textContent = '未连接';
    $('#devDot').className = 'dot err';
    $('#methodLine').textContent = msg ? msg.slice(0, 90) : ('找不到 ' + ENGINE);
    $('#statMax').textContent = '--';
    $('#statTarget').textContent = '--';
    $('#statVerify').textContent = '--';
    $('#rates').innerHTML = '<div class="skel"></div><div class="skel"></div><div class="skel"></div><div class="skel"></div>';
    $('#ratesHint').textContent = '请确认模块已安装并重启，且 WebUI 具备 Root 权限。';
    paintGauge(0, 120, 'off');
  }

  /* ---------------- 更新检查 ---------------- */
  var UPDATE_URLS = [
    'https://raw.githubusercontent.com/yingge-dev/global-hfr/main/update.json',
    'https://cdn.jsdelivr.net/gh/yingge-dev/global-hfr@main/update.json'
  ];
  var CHANGELOG_URLS = [
    'https://raw.githubusercontent.com/yingge-dev/global-hfr/main/CHANGELOG.md',
    'https://cdn.jsdelivr.net/gh/yingge-dev/global-hfr@main/CHANGELOG.md'
  ];
  var updateInfo = null;
  var updateChecked = false;

  function fetchJson(url) {
    return fetch(url, { cache: 'no-store' }).then(function (r) {
      if (!r.ok) throw new Error('http ' + r.status);
      return r.json();
    });
  }

  function fetchText(url) {
    return fetch(url, { cache: 'no-store' }).then(function (r) {
      if (!r.ok) throw new Error('http ' + r.status);
      return r.text();
    });
  }

  function fetchAny(urls, i, text) {
    i = i || 0;
    if (i >= urls.length) return Promise.reject(new Error('no url'));
    var fn = text ? fetchText : fetchJson;
    return fn(urls[i]).catch(function () { return fetchAny(urls, i + 1, text); });
  }

  function isUrl(v) { return /^https?:\/\//.test(String(v || '')); }

  function updateNote(j) {
    if (isUrl(j && j.changelog)) return '查看 ' + (j.version || '') + ' 更新内容';
    var t = String((j && (j.changelog || j.note)) || '').replace(/\r/g, '');
    t = t.split('\n').filter(function (s) { return s.trim(); })[0] || '点此查看更新内容';
    return t.replace(/^[-*#\s]+/, '').slice(0, 60);
  }

  function renderUpdateBar(j) {
    if (!j) return;
    $('#updateVer').textContent = j.version || '';
    $('#updateNote').textContent = updateNote(j);
    $('#updateBar').hidden = false;
    $('#changelogHint').textContent = '发现新版本 ' + (j.version || '');
  }

  function changelogSection(text, version) {
    var key = String(version || '').replace(/^v/, '');
    var parts = String(text || '').split(/^##\s+/m);
    for (var i = 1; i < parts.length; i++) {
      var head = parts[i].replace(/^v/, '');
      if (head.slice(0, key.length) === key) return '## ' + parts[i];
    }
    return text;
  }

  function showChangelog(j) {
    j = j || updateInfo;
    if (!j) { toast('暂无更新信息，请先检查更新', 'err'); return; }
    var link = isUrl(j.changelog) ? j.changelog : '';
    var dl = '';
    if (isUrl(j.zipUrl)) {
      dl += '<a class="btn" href="' + esc(j.zipUrl) + '" target="_blank" rel="noopener">下载 ' + esc(j.version || '') + '</a>';
    }
    if (link) {
      dl += '<a class="btn ghost" href="' + esc(link) + '" target="_blank" rel="noopener">GitHub 发布页</a>';
    }
    dl = '<div class="sheet-actions">' + dl + '</div>';

    function paint(text) {
      var body = esc(text || '本次更新内容请查看 GitHub 发布页。').replace(/\n/g, '<br>');
      openSheet(
        '<h3>发现新版本 ' + esc(j.version || '') + '</h3>' +
        '<p class="sub">当前 ' + esc((state && state.version) || '') + ' · 更新内容</p>' +
        '<div class="changelog">' + body + '</div>' + dl
      );
    }

    if (link) {
      openSheet('<h3>发现新版本 ' + esc(j.version || '') + '</h3><p class="sub">正在获取更新日志…</p>');
      fetchAny(CHANGELOG_URLS, 0, true).then(function (t) {
        paint(changelogSection(t, j.version));
      }).catch(function () { paint(''); });
    } else {
      paint(j.changelog || j.note || '');
    }
  }

  function checkUpdate(force) {
    if (!hasApi()) {
      if (force) toast('预览模式无法检查更新', 'err');
      return;
    }
    if (!force && updateChecked) return;
    updateChecked = true;
    if (force) $('#changelogHint').textContent = '正在检查 GitHub…';
    fetchAny(UPDATE_URLS).then(function (j) {
      if (!j || !j.versionCode) throw new Error('bad json');
      if (Number(j.versionCode) > Number((state && state.versionCode) || 0)) {
        updateInfo = j;
        renderUpdateBar(j);
        if (force) showChangelog(j);
      } else {
        if (force) toast('已是最新版本 ' + ((state && state.version) || ''), 'ok');
        $('#changelogHint').textContent = '已是最新版本 ' + ((state && state.version) || '');
      }
    }).catch(function () {
      if (force) {
        toast('检查更新失败，请检查网络', 'err');
        $('#changelogHint').textContent = '检查更新失败';
      }
    });
  }

  /* ---------------- 数据刷新 ---------------- */
  async function refresh(opts) {
    opts = opts || {};
    if (!hasApi()) {
      state = DEMO;
      demo = true;
      render();
      return;
    }
    if (!opts.silent) $('#btnRefresh').classList.add('spin');
    try {
      var r = await run('status');
      if (r.json && r.json.ok) {
        demo = false;
        state = r.json;
        inferVerified();
        render();
        if (!updateChecked && !demo) setTimeout(function () { checkUpdate(false); }, 800);
      } else if (!state) {
        renderError(r.raw);
      }
    } finally {
      $('#btnRefresh').classList.remove('spin');
    }
  }

  function setBusy(v) {
    busy = v;
    $('#btnRefresh').classList.toggle('spin', v);
  }

  function guard() {
    if (demo) { toast('预览模式：请在 KernelSU / APatch 的 WebUI 中操作', 'err'); return true; }
    if (busy) { toast('正在执行，请稍候'); return true; }
    return false;
  }

  async function writePairs(pairs, okMsg) {
    for (var i = 0; i < pairs.length; i++) {
      var r = await run('set ' + pairs[i][0] + ' ' + pairs[i][1]);
      if (!r.json || !r.json.ok) {
        toast('参数写入失败：' + pairs[i][0], 'err');
        return false;
      }
    }
    return true;
  }

  async function applyPairs(pairs, okMsg) {
    if (guard()) return;
    setBusy(true);
    try {
      if (!await writePairs(pairs, okMsg)) return;
      var a = await run('apply');
      if (!a.json) { toast('应用失败，请查看运行日志', 'err'); return; }
      await refresh({ silent: true });
      var tail = a.json.verified ? ' · 已核验' : ' · 待核验';
      toast(okMsg + tail, a.json.verified ? 'ok' : '');
    } finally {
      setBusy(false);
    }
  }

  function optimisticSwitch(kind, value) {
    if (!state) return;
    var cfg = state.config || (state.config = {});
    var live = state.live || (state.live = {});
    if (kind === 'fixed') {
      var hz = Number(value) || 0;
      var max = Number((state.panel || {}).max) || 0;
      cfg.profile = 'fixed';
      cfg.fixed_hz = hz;
      live.target = hz || max;
      live.current = live.target;
      live.verified = 0;
      live.method = '切换中…';
    } else if (kind === 'dynamic') {
      cfg.profile = 'dynamic';
      cfg.dyn_min = Number(value.lo);
      cfg.dyn_max = Number(value.hi);
      live.target = Number(value.hi);
      live.current = live.target;
      live.verified = 0;
      live.method = '切换中…';
    } else if (kind === 'off') {
      cfg.profile = 'off';
      live.target = 0;
      live.verified = 0;
      live.method = '切换中…';
    } else if (kind === 'touch') {
      cfg.touch = Number(value);
    } else if (kind === 'level') {
      cfg.touch_level = value;
      cfg.touch = 1;
    }
    render();
  }

  function applyResult(j) {
    if (!j || !state) return;
    var c = state.config || (state.config = {});
    if (j.profile) c.profile = j.profile;
    if (c.profile === 'fixed' && Number(j.target) > 0) c.fixed_hz = Number(j.target);
    if (c.profile === 'dynamic' && j.engine === 'native' && Number(j.target) > 0) c.dyn_max = Number(j.target);
    var live = state.live || (state.live = {});
    live.current = Number(j.current) || 0;
    live.target = Number(j.target) || 0;
    live.verified = Number(j.verified) || 0;
    live.method = j.method || '';
    live.engine = j.engine || live.engine || '';
    live.restart_required = Number(j.restart_required) || 0;
    live.updated = Math.floor(Date.now() / 1000);
    if (state.touch) state.touch.applied = Number(j.touch_applied) || 0;
    render();
  }

  async function applySwitch(args, okMsg, kind, value) {
    if (guard()) return;
    if (kind) optimisticSwitch(kind, value);
    setBusy(true);
    try {
      var r = await run('switch ' + args);
      if (!r.json || !r.json.ok) {
        toast('切换失败，请查看日志', 'err');
        await refresh({ silent: true });
        return;
      }
      applyResult(r.json);
      var tail = r.json.engine === 'adaptive' ? ' · 自适应' :
        (r.json.engine === 'native' ? ' · 原生' : (r.json.verified ? ' · 已核验' : ' · 待核验'));
      toast(okMsg + tail, r.json.verified ? 'ok' : '');
      if (Number(r.json.restart_required) === 1) setTimeout(askReboot, 500);
      setTimeout(function () { refresh({ silent: true }); }, 600);
    } finally {
      setBusy(false);
    }
  }

  /* ---------------- 交互绑定 ---------------- */
  function currentEngine() {
    var b = $('#dynEngineSeg button.on');
    return b ? b.getAttribute('data-engine') : 'auto';
  }

  function bind() {
    ['pointerdown', 'change'].forEach(function (evt) {
      document.addEventListener(evt, function () { lastInteract = Date.now(); }, true);
    });
    $('#btnRefresh').addEventListener('click', function () { refresh(); });
    $('#updateBar').addEventListener('click', function () { showChangelog(updateInfo); });
    $('#btnChangelog').addEventListener('click', function () { checkUpdate(true); });

    $('#presets').addEventListener('click', function (e) {
      var btn = e.target.closest('.preset');
      if (!btn) return;
      var kind = btn.getAttribute('data-preset');
      if (kind === 'max') {
        applySwitch('fixed 0', '已切换为全局最高', 'fixed', 0);
      } else if (kind === 'off') {
        applySwitch('off', '已交还系统调度', 'off');
      } else {
        var lo = $('#dynMin').value;
        var hi = $('#dynMax').value;
        if (Number(hi) <= Number(lo)) { toast('上限需大于下限', 'err'); return; }
        applySwitch('dynamic ' + lo + ' ' + hi + ' ' + currentEngine(), '动态区间已应用', 'dynamic', { lo: lo, hi: hi });
      }
    });

    $('#rates').addEventListener('click', function (e) {
      var btn = e.target.closest('.rate');
      if (!btn) return;
      var hz = btn.getAttribute('data-hz');
      if (btn.classList.contains('off')) {
        toast(hz + 'Hz 档位未检测到，需要机型或超频 DTBO 支持', 'err');
        return;
      }
      if (btn.classList.contains('on')) { toast('已经是 ' + hz + 'Hz'); return; }
      applySwitch('fixed ' + hz, '已锁定 ' + hz + 'Hz', 'fixed', hz);
    });

    $('#dynMin').addEventListener('change', syncDynBar);
    $('#dynMax').addEventListener('change', syncDynBar);

    $('#dynPresets').addEventListener('click', function (e) {
      var btn = e.target.closest('button');
      if (!btn) return;
      var lo = btn.getAttribute('data-lo');
      var hi = btn.getAttribute('data-hi');
      $('#dynMin').value = lo;
      $('#dynMax').value = hi;
      syncDynBar();
      applySwitch('dynamic ' + lo + ' ' + hi + ' ' + currentEngine(), '动态区间已应用', 'dynamic', { lo: lo, hi: hi });
    });

    $('#btnApplyDyn').addEventListener('click', function () {
      var lo = $('#dynMin').value;
      var hi = $('#dynMax').value;
      if (Number(hi) <= Number(lo)) { toast('上限需大于下限', 'err'); return; }
      applySwitch('dynamic ' + lo + ' ' + hi + ' ' + currentEngine(), '动态区间已应用', 'dynamic', { lo: lo, hi: hi });
    });

    $('#dynEngineSeg').addEventListener('click', function (e) {
      var btn = e.target.closest('button');
      if (!btn) return;
      var eng = btn.getAttribute('data-engine');
      $$('#dynEngineSeg button').forEach(function (b) { b.classList.toggle('on', b === btn); });
      var lo = $('#dynMin').value;
      var hi = $('#dynMax').value;
      if (Number(hi) <= Number(lo)) { toast('上限需大于下限', 'err'); return; }
      applySwitch('dynamic ' + lo + ' ' + hi + ' ' + eng, '动态实现已切换', 'dynamic', { lo: lo, hi: hi });
    });

    $('#dynIdle').addEventListener('change', function () {
      applyPairs([['dyn_idle_ms', this.value]], '静止降频时间已更新');
    });

    ['touchSwitch', 'touchSwitch2'].forEach(function (id) {
      $('#' + id).addEventListener('change', function () {
        var on = this.checked;
        applySwitch('touch ' + (on ? '1' : '0'), on ? '触控加速已开启' : '触控加速已关闭', 'touch', on ? 1 : 0);
      });
    });

    $$('#touchLevelSeg button, #touchLevelSeg2 button').forEach(function (b) {
      b.addEventListener('click', function () {
        var lvl = b.getAttribute('data-level');
        applySwitch('touch 1 ' + lvl, lvl === 'esports' ? '已切换电竞触控' : '已切换标准触控', 'level', lvl);
      });
    });

    $('#swDeep').addEventListener('change', function () {
      applyPairs([['deep_lock', this.checked ? '1' : '0']], this.checked ? '深度锁帧已开启' : '深度锁帧已关闭');
    });
    $('#swOverlay').addEventListener('change', function () {
      applyPairs([['overlay', this.checked ? '1' : '0']], this.checked ? '帧率浮窗已开启' : '帧率浮窗已关闭');
    });
    $('#swBoot').addEventListener('change', function () {
      applyPairs([['auto_boot', this.checked ? '1' : '0']], this.checked ? '开机自动应用已开启' : '开机自动应用已关闭');
    });
    $('#swDaemon').addEventListener('change', function () {
      var on = this.checked;
      applyPairs([['daemon', on ? '1' : '0']], on ? '后台守护已开启（重启后生效）' : '后台守护已关闭');
    });
    $('#swOplus').addEventListener('change', function () {
      applyPairs([['oplus_props', this.checked ? '1' : '0']], this.checked ? 'OPPO 兼容模式已开启，重启后生效' : 'OPPO 兼容模式已关闭，重启后生效');
    });

    $('#btnScan').addEventListener('click', async function () {
      if (guard()) return;
      setBusy(true);
      try {
        var r = await run('scan');
        if (r.json && r.json.ok) {
          var c = (state && state.config) || {};
          if (c.profile === 'fixed') await run('apply');
          await refresh({ silent: true });
          toast('扫描完成，共 ' + r.json.count + ' 个档位', 'ok');
        } else {
          toast('扫描失败，请查看日志', 'err');
        }
      } finally { setBusy(false); }
    });

    $('#btnLog').addEventListener('click', async function () {
      if (demo) { toast('预览模式无运行日志', 'err'); return; }
      var r = await run('log 120');
      var text = (r.raw && r.raw.stdout) || '暂无日志';
      openSheet('<h3>运行日志</h3><p class="sub">' + (text.split('\n').length) + ' 行 · 最近记录</p><pre>' + esc(text) + '</pre>');
    });

    $('#btnRestore').addEventListener('click', function () {
      openSheet(
        '<h3>恢复系统默认？</h3>' +
        '<p class="sub">将还原刷新率设置、触控节点与底层锁定。完成后需重新选择档位。</p>' +
        '<div class="sheet-actions">' +
        '<button class="btn" type="button" data-close>取消</button>' +
        '<button class="btn danger" type="button" id="doRestore">确认恢复</button>' +
        '</div>'
      );
    });

    $('#devPill').addEventListener('click', function () {
      if (!state) return;
      var d = state.device || {};
      var rows = [
        ['品牌', d.brand], ['机型', d.market], ['型号', d.model],
        ['系统', d.rom], ['Android', d.android], ['SDK', d.sdk],
        ['芯片', d.soc], ['平台', platformText(d.platform)]
      ];
      openSheet('<h3>设备信息</h3><p class="sub">模块按机型自动选择刷新率档位与触控节点</p><div class="rows">' +
        rows.map(function (r) {
          return '<div><span>' + esc(r[0]) + '</span><b>' + esc(r[1] || '--') + '</b></div>';
        }).join('') + '</div>');
    });

    $('#tabbar').addEventListener('click', function (e) {
      var btn = e.target.closest('.tab');
      if (!btn) return;
      var tab = btn.getAttribute('data-tab');
      $$('.tab').forEach(function (t) { t.classList.toggle('on', t === btn); });
      $$('.page').forEach(function (p) { p.classList.toggle('on', p.id === 'page-' + tab); });
      var ind = $('#tabInd');
      ind.className = 'ind' + (tab === 'touch' ? ' t1' : (tab === 'set' ? ' t2' : ''));
      window.scrollTo({ top: 0, behavior: 'smooth' });
    });

    $('#scrim').addEventListener('click', closeSheet);
    $('#sheet').addEventListener('click', function (e) {
      if (e.target.closest('[data-close]')) closeSheet();
      if (e.target.id === 'doRestore') {
        closeSheet();
        (async function () {
          if (guard()) return;
          setBusy(true);
          try {
            var r = await run('restore');
            await refresh({ silent: true });
            toast(r.json && r.json.ok ? '已恢复系统默认' : '恢复失败，请查看日志', r.json && r.json.ok ? 'ok' : 'err');
          } finally { setBusy(false); }
        })();
      }
      if (e.target.id === 'doReboot') {
        closeSheet();
        toast('正在重启设备…', 'ok');
        exec('sh ' + ENGINE + ' reboot 2>&1');
      }
    });

    $('#themeSeg').addEventListener('click', function (e) {
      var b = e.target.closest('button');
      if (!b) return;
      applyTheme(b.getAttribute('data-theme'));
    });

    document.addEventListener('visibilitychange', function () {
      if (document.visibilityState === 'visible' && hasApi()) refresh({ silent: true });
    });
  }

  function syncDynBar() {
    var minEl = $('#dynMin');
    var maxEl = $('#dynMax');
    var lo = Number(minEl.value);
    var hi = Number(maxEl.value);
    var opts = Array.prototype.map.call(minEl.options, function (o) { return Number(o.value); });
    var floor = Math.min.apply(null, opts);
    var top = Math.max.apply(null, Array.prototype.map.call(maxEl.options, function (o) { return Number(o.value); }));
    var span = Math.max(1, top - floor);
    if (hi <= lo) {
      hi = Math.min(top, lo + 30);
      maxEl.value = String(hi);
    }
    $('#dynFill').style.left = (((lo - floor) / span) * 100).toFixed(1) + '%';
    $('#dynFill').style.width = (Math.max(6, ((hi - lo) / span) * 100)).toFixed(1) + '%';
    $('#dynLabel').textContent = lo + ' – ' + hi + ' Hz';
    $$('#dynPresets button').forEach(function (b) {
      b.classList.toggle('on', Number(b.getAttribute('data-lo')) === lo && Number(b.getAttribute('data-hi')) === hi);
    });
  }

  function openSheet(html) {
    $('#sheetBody').innerHTML = '<button class="sheet-x" type="button" data-close aria-label="关闭">×</button>' + html;
    $('#sheet').classList.add('on');
    $('#scrim').classList.add('on');
  }

  function closeSheet() {
    $('#sheet').classList.remove('on');
    $('#scrim').classList.remove('on');
  }

  function askReboot() {
    openSheet(
      '<h3>需要重启一次</h3>' +
      '<p class="sub">系统底层锁帧标记需要重启才能释放，重启后「原生动态」才会真正接管。自适应模式无需重启。</p>' +
      '<div class="sheet-actions">' +
      '<button class="btn" type="button" data-close>稍后</button>' +
      '<button class="btn danger" type="button" id="doReboot">立即重启</button>' +
      '</div>'
    );
  }

  function startPoll() {
    if (pollTimer) clearInterval(pollTimer);
    pollTimer = setInterval(function () {
      if (!hasApi() || busy) return;
      if (document.visibilityState !== 'visible') return;
      if ($('#sheet').classList.contains('on')) return;
      if (Date.now() - lastInteract < 12000) return;
      refresh({ silent: true });
    }, 6000);
  }

  function init() {
    var savedTheme = 'auto';
    try { savedTheme = localStorage.getItem(THEME_KEY) || 'auto'; } catch (e) {}
    try {
      var qTheme = new URLSearchParams(location.search).get('theme');
      if (qTheme === 'light' || qTheme === 'dark') savedTheme = qTheme;
    } catch (e) {}
    applyTheme(savedTheme);
    if (window.matchMedia) {
      try {
        window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function () {
          if (themeMode === 'auto') paintThemeMeta('auto');
        });
      } catch (e) {}
    }
    buildTicks();
    bind();
    if (!hasApi()) {
      state = DEMO;
      demo = true;
      render();
    } else {
      refresh();
    }
    var h = String(location.hash || '').replace('#', '');
    if (h === 'touch' || h === 'set') {
      var btn = document.querySelector('.tab[data-tab="' + h + '"]');
      if (btn) btn.click();
    }
    startPoll();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
