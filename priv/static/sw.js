const NEXTGEN_CACHE = "nextgen-summit-liveview-v3-auth";
const STATIC_ASSETS = [
  "/manifest.webmanifest",
  "/images/favicon.png",
  "/images/logo.png"
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(NEXTGEN_CACHE)
      .then((cache) => cache.addAll(STATIC_ASSETS))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(keys.filter((key) => key !== NEXTGEN_CACHE).map((key) => caches.delete(key)))
      )
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;

  if (event.request.mode === "navigate") {
    event.respondWith(
      fetch(event.request).catch(
        () =>
          new Response(
            "<!doctype html><title>NextGen Summit</title><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><main style=\"font-family: system-ui, sans-serif; padding: 32px; line-height: 1.5;\"><h1>You're offline</h1><p>Reconnect to refresh the event app.</p></main>",
            { headers: { "Content-Type": "text/html; charset=utf-8" } }
          )
      )
    );
    return;
  }

  const url = new URL(event.request.url);

  if (url.origin === self.location.origin && STATIC_ASSETS.includes(url.pathname)) {
    event.respondWith(caches.match(event.request).then((cached) => cached || fetch(event.request)));
  }
});
