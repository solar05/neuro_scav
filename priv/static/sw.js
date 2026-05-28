const CACHE_NAME = 'scavgen-v1';

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
  '/images/gnome.png',
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
        keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))
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

  // Статика (assets, шрифты, изображения, звуки) — Cache-First
  if (
    url.pathname.startsWith('/assets/') ||
    url.pathname.startsWith('/fonts/') ||
    url.pathname.startsWith('/images/') ||
    url.pathname.startsWith('/sounds/')
  ) {
    event.respondWith(
      caches.match(event.request).then(
        (cached) => cached || fetch(event.request).then((response) => {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
          return response;
        })
      )
    );
    return;
  }

  // HTML-страницы — Network-First с fallback на offline
  event.respondWith(
    fetch(event.request)
      .then((response) => {
        const clone = response.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
        return response;
      })
      .catch(() =>
        caches.match(event.request).then(
          (cached) => cached || caches.match('/offline.html')
        )
      )
  );
});
