const CACHE_VERSION = 'v6';
const CACHE_NAME = `scavgen-${CACHE_VERSION}`;

const PRECACHE_URLS = [
  '/',
  '/offline.html',
  '/site.webmanifest',
  '/favicon.ico',
  '/favicon-32x32.png',
  '/favicon-16x16.png',
  '/apple-touch-icon.png',
  '/android-chrome-192x192.png',
  '/android-chrome-512x512.png',
  '/images/gnome.webp',
  '/images/back.png',
  '/images/old_back.webp',
  '/sounds/gnome_sound.mp3'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(PRECACHE_URLS))
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((key) => key.startsWith('scavgen-') && key !== CACHE_NAME)
          .map((key) => caches.delete(key))
      )
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // Пропускаем: LiveView WebSocket, Phoenix live reload, API, метрики
  if (
    url.pathname.startsWith('/live') ||
    url.pathname.startsWith('/phoenix') ||
    url.pathname.startsWith('/api') ||
    url.pathname.startsWith('/metrics') ||
    event.request.method !== 'GET'
  ) {
    return;
  }

  // Cache-First только для того, что не устаревает: файлы с хэшем в имени
  // (phx.digest в prod: app-<md5>.css) и изображения/звуки. В dev /assets/app.css
  // без хэша — он идёт Network-First ниже, иначе SW навсегда отдаёт старый CSS
  const fingerprinted = /-[0-9a-f]{32}\.\w+$/.test(url.pathname);
  if (
    fingerprinted ||
    url.pathname.startsWith('/images/') ||
    url.pathname.startsWith('/sounds/')
  ) {
    event.respondWith(
      caches.match(event.request).then(
        (cached) => cached || fetch(event.request).then((response) => {
          if (response.ok) {
            const clone = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
          }
          return response;
        })
      )
    );
    return;
  }

  // HTML-страницы и статика без хэша — Network-First с fallback на кеш, затем offline.html.
  // В кеш — только основные страницы (один сегмент пути, без query): ссылки /share/…,
  // комнаты /battle/<id>, отряды /raid?team=… у каждого свои, кеш копил бы их без конца
  const page = url.search === '' && /^\/[a-z_]*$/.test(url.pathname);
  event.respondWith(
    fetch(event.request)
      .then((response) => {
        if (response.ok && page) {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
        }
        return response;
      })
      .catch(() =>
        caches.match(event.request).then(
          (cached) => cached || caches.match('/offline.html')
        )
      )
  );
});
