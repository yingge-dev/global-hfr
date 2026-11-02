/* 统计直接访问中文 zip 的下载；页面按钮点击由 app.js 计数（链接带 src=page） */
const HIT = 'https://abacus.jasoncameron.dev/hit/yingge-dev/global-hfr-page-downloads-v1';

self.addEventListener('install', function () { self.skipWaiting(); });
self.addEventListener('activate', function (e) { e.waitUntil(self.clients.claim()); });

self.addEventListener('fetch', function (e) {
  if (e.request.method !== 'GET') return;
  var u;
  try { u = new URL(e.request.url); } catch (err) { return; }
  if (u.origin !== self.location.origin) return;
  if (!/\/assets\/.*\.zip$/.test(u.pathname)) return;
  // 页面按钮已经由 app.js 计数，避免一次点击加两次
  if (u.searchParams.has('src')) return;
  e.waitUntil(fetch(HIT, { cache: 'no-store' }).catch(function () {}));
});
