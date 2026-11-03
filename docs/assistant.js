(function () {
  'use strict';
  var fab = document.getElementById('assistantFab');
  var panel = document.getElementById('assistantPanel');
  var close = document.getElementById('assistantClose');
  var msgs = document.getElementById('assistantMsgs');
  var quick = document.getElementById('assistantQuick');
  var form = document.getElementById('assistantForm');
  var input = document.getElementById('assistantInput');
  if (!fab || !panel || !msgs) return;

  var started = false;
  var issueUrl = 'https://github.com/yingge-dev/global-hfr/issues/new?template=bug_report.yml';
  var home = 'https://yingge-dev.github.io/global-hfr/';

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function add(text, who) {
    var d = document.createElement('div');
    d.className = 'assistant-msg ' + (who === 'user' ? 'user' : 'bot');
    if (who === 'user') d.textContent = text;
    else d.innerHTML = text;
    msgs.appendChild(d);
    msgs.scrollTop = msgs.scrollHeight;
  }

  var rules = [
    {
      keys: ['安装', '刷入', 'magisk', 'kernelsu', 'ksu', 'apatch', '怎么用'],
      a: '在 Magisk / KernelSU / APatch 里刷入 zip，重启一次；然后从模块的「打开」进入 WebUI。第一次建议先用「动态刷新」，不要直接锁最高。详细步骤看 <a href="' + home + '#install" target="_blank" rel="noopener">安装说明</a>。'
    },
    {
      keys: ['锁不住', '系统默认', '固定', '切换', '不生效', '120'],
      a: '先到 WebUI → 设置 → 兼容性自检，确认「面板最高 / 系统原生上限 / 支持速率」。如果底层锁回读失败，v2.2.4 起会继续走 DisplayManager / Settings；仍不行请把自检截图和运行日志发到 <a href="' + issueUrl + '" target="_blank" rel="noopener">GitHub Issue</a>。'
    },
    {
      keys: ['掉60', '掉 60', '抖音', 'b站', '哔哩', '视频', '掉帧'],
      a: '这是应用自己向系统请求了 60Hz。v2.2.4 起固定档每 2 秒检查一次，掉下去会重新锁定；如果仍然频繁掉，请说明机型、应用和固定档位，并发运行日志。'
    },
    {
      keys: ['30', '下限', 'ltpo', '30hz'],
      a: '30Hz 只有面板真的上报了 30Hz 才会出现；没上报就不显示，避免写无效档位。可以在「兼容性自检」里看「支持速率」。'
    },
    {
      keys: ['360', '档位', '假的', '面板最高', '144', '165', '185'],
      a: 'Xiaomi 17 Pro 这类 120Hz 面板出现 360Hz 属于异常/虚拟档位；v2.2.5 已过滤 240Hz 以上的异常值，360 不再显示也不能锁定。'
    },
    {
      keys: ['触控', '节点', '只有一项', '1项', 'boost', '采样'],
      a: '模块只写真实存在且写入成功的节点，不会补假节点。只有 1 项生效说明这台机器的内核只暴露了 1 个可用入口（常见是触控 HAL 优先级），不是漏写。'
    },
    {
      keys: ['反馈', 'bug', '问题', '报错', '提交'],
      a: '直接发 <a href="' + issueUrl + '" target="_blank" rel="noopener">GitHub Issue</a>，带上机型、ROM、模块版本、复现步骤、兼容性自检和运行日志。所有回复都会在 Issue 里公开进行。'
    },
    {
      keys: ['支持', '机型', '其他品牌', 'oppo', '一加', 'realme', '小米', '红米', 'mix'],
      a: '模块按能力检测，不按机型写死：小米走底层锁，其他系统优先 DisplayManager / Settings。具体能用到什么程度，以那台机器的「兼容性自检」为准；不支持的档位不会假装支持。'
    },
    {
      keys: ['下载', '更新', '版本', '最新'],
      a: '下载和更新日志都在 <a href="' + home + '#install" target="_blank" rel="noopener">项目主页</a>；模块内「检查更新」会读取 GitHub 的 update.json。'
    },
    {
      keys: ['自检', '检测', '日志'],
      a: 'WebUI → 设置 → 兼容性自检 / 运行日志。自检看接口和面板能力，日志看最近 120 行执行记录；反馈时两个都带上最有用。'
    }
  ];

  function reply(text) {
    var q = String(text || '').toLowerCase();
    for (var i = 0; i < rules.length; i++) {
      var keys = rules[i].keys;
      for (var j = 0; j < keys.length; j++) {
        if (q.indexOf(keys[j].toLowerCase()) >= 0) return rules[i].a;
      }
    }
    return '我目前只内置了安装、锁不住、掉 60、30Hz、异常档位、触控和反馈这些规则。更具体的问题请发 <a href="' + issueUrl + '" target="_blank" rel="noopener">GitHub Issue</a>，附上机型、自检和日志，我会按真实信息排查。';
  }

  function greet() {
    if (started) return;
    started = true;
    add('你好，我是高刷助手。可以先问我：怎么安装、锁不住、掉 60、30Hz、触控节点、怎么反馈。', 'bot');
  }

  function open(show) {
    panel.hidden = show === false ? true : !panel.hidden ? true : false;
    if (!panel.hidden) {
      greet();
      setTimeout(function () { try { input.focus(); } catch (e) {} }, 80);
    }
  }

  fab.addEventListener('click', function () { open(); });
  if (close) close.addEventListener('click', function () { panel.hidden = true; });
  if (quick) quick.addEventListener('click', function (e) {
    var b = e.target.closest('button[data-q]');
    if (!b) return;
    var q = b.getAttribute('data-q');
    add(q, 'user');
    add(reply(q), 'bot');
  });
  if (form) form.addEventListener('submit', function (e) {
    e.preventDefault();
    var q = String(input.value || '').trim();
    if (!q) return;
    input.value = '';
    add(q, 'user');
    add(reply(q), 'bot');
  });
})();
