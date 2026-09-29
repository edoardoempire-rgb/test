const CACHE = "wallet-skins-v8";

self.addEventListener("install", event => event.waitUntil(
  caches.open(CACHE).then(cache => cache.addAll([
    "/",
    "/index.html",
    "/callback.html",
    "/styles.css",
    "/result.css",
    "/app.js",
    "/callback.js",
    "/skins/aurora.png",
    "/skins/ember.png",
    "/skins/tide.png",
    "/skins/mono.png"
  ]))
));

self.addEventListener("activate", event => event.waitUntil(
  caches.keys().then(keys => Promise.all(keys.filter(key => key !== CACHE).map(key => caches.delete(key))))
));

self.addEventListener("fetch", event => {
  if (event.request.method === "GET" && !new URL(event.request.url).pathname.startsWith("/v1/")) {
    event.respondWith(fetch(event.request).catch(() => caches.match(event.request)));
  }
});
