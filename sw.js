// ============================================================================
// SERVICE WORKER (sw.js) - Gjør at mobil-appen fungerer 100 % uten internett!
// ============================================================================

const CACHE_NAVN = "gwent-score-cache-v1";
const FILER_SOM_SKAL_LAGRast = [
    "./",
    "./index.html",
    "./gwent-mobile.html",
    "./style.css",
    "./script.js",
    "./manifest.json",
    "./icon-192.png",
    "./icon-512.png"
];

self.addEventListener("install", (event) => {
    event.waitUntil(
        caches.open(CACHE_NAVN).then((cache) => {
            return cache.addAll(FILER_SOM_SKAL_LAGRast);
        })
    );
    self.skipWaiting();
});

self.addEventListener("activate", (event) => {
    event.waitUntil(
        caches.keys().then((keyList) => {
            return Promise.all(
                keyList.map((key) => {
                    if (key !== CACHE_NAVN) {
                        return caches.delete(key);
                    }
                })
            );
        })
    );
    self.clients.claim();
});

self.addEventListener("fetch", (event) => {
    event.respondWith(
        caches.match(event.request).then((response) => {
            return response || fetch(event.request);
        })
    );
});
