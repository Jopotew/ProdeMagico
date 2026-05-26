const CACHE = "prode-shell-v1";

const APP_SHELL = [
  "/assets/css/app.css",
  "/assets/js/app.js",
  "/images/logo.svg",
  "/manifest.json",
];

self.addEventListener("install", (e) => {
  e.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll(APP_SHELL))
  );
  self.skipWaiting();
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener("fetch", (e) => {
  const url = new URL(e.request.url);

  // Never intercept LiveView websocket or SSE connections
  if (url.pathname.startsWith("/live") || url.pathname.startsWith("/phoenix")) {
    return;
  }

  // Cache-first for static assets; network-first for everything else
  if (url.pathname.startsWith("/assets/") || url.pathname.startsWith("/images/")) {
    e.respondWith(
      caches.match(e.request).then((cached) => cached || fetch(e.request))
    );
  }
});
