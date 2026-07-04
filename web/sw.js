// CountDownTodo PWA Service Worker
// Handles offline caching and update lifecycle.

const CACHE_VERSION = 'v7';
const CACHE_NAME = `countdowntodo-${CACHE_VERSION}`;
const OFFLINE_URL = './offline.html';
const BOOTSTRAP_URL = './flutter_bootstrap.js?v=20260701e';

// App shell files to pre-cache on install.
// Flutter build output is hashed, so we only cache the unhashed entry points;
// hashed assets (main.dart.js, flutter.js, assets/*, fonts/*) are cached at
// runtime on first fetch.
const PRE_CACHE_URLS = [
  './',
  './index.html',
  OFFLINE_URL,
  BOOTSTRAP_URL,
  './sqflite_sw.js',
  './sqlite3.wasm',
  './favicon.png',
  './icons/Icon-180.png',
  './icons/Icon-192.png',
  './icons/Icon-512.png',
  './icons/Icon-maskable-192.png',
  './icons/Icon-maskable-512.png',
  './manifest.json',
];

const STATIC_EXTENSIONS = [
  '.css',
  '.js',
  '.mjs',
  '.wasm',
  '.json',
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.svg',
  '.ico',
  '.otf',
  '.ttf',
  '.woff',
  '.woff2',
  '.bin',
];

function isSameOrigin(url) {
  return url.origin === self.location.origin;
}

function isStaticAsset(url) {
  return STATIC_EXTENSIONS.some((ext) => url.pathname.endsWith(ext)) ||
    url.pathname.includes('/assets/') ||
    url.pathname.includes('/canvaskit/');
}

async function cacheShell() {
  const cache = await caches.open(CACHE_NAME);
  await Promise.all(
    PRE_CACHE_URLS.map(async (url) => {
      try {
        await cache.add(new Request(url, { cache: 'reload' }));
      } catch (err) {
        console.warn('[SW] Pre-cache skipped:', url, err);
      }
    })
  );
}

// ── Install ─────────────────────────────────────────────────
self.addEventListener('install', (event) => {
  event.waitUntil(cacheShell());
});

// ── Activate ────────────────────────────────────────────────
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((key) => key !== CACHE_NAME)
          .map((key) => caches.delete(key))
      )
    )
  );
  self.clients.claim();
});

// ── Fetch ───────────────────────────────────────────────────
self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);

  // Only handle GET requests.
  if (request.method !== 'GET') return;

  // Skip cross-origin requests (API calls, CDN, etc.) — let them pass through.
  if (!isSameOrigin(url)) return;

  // Range requests are used by media and should not be served from this cache.
  if (request.headers.has('range')) return;

  // Navigation requests: network-first, fallback to cached index.html.
  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request)
        .then((response) => {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put('./index.html', clone);
          });
          return response;
        })
        .catch(async () =>
          (await caches.match('./index.html')) ||
          (await caches.match(OFFLINE_URL)) ||
          Response.error()
        )
    );
    return;
  }

  if (!isStaticAsset(url)) return;

  // Same-origin static assets: cache-first, populate and refresh on fetch.
  event.respondWith(
    caches.match(request).then((cached) => {
      const fetchAndCache = fetch(request).then((response) => {
        if (response && response.status === 200) {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(request, clone));
        }
        return response;
      });

      return cached || fetchAndCache;
    }).catch(() => caches.match(request))
  );
});

// ── Messages ───────────────────────────────────────────────
self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});

// ── Notifications ──────────────────────────────────────────
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const targetUrl = event.notification.data && event.notification.data.url
    ? event.notification.data.url
    : './';

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then((clientList) => {
        for (const client of clientList) {
          if ('focus' in client && new URL(client.url).origin === self.location.origin) {
            return client.focus();
          }
        }
        if (self.clients.openWindow) {
          return self.clients.openWindow(targetUrl);
        }
        return undefined;
      })
  );
});
