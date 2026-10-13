// Offline cache for Restock. The page is fetched network-first so updates land on the next open;
// the OCR engine files are cached once and served from cache.
const CACHE = 'restock-v3';
const ENGINE = ['vendor/tesseract.min.js', 'vendor/worker.min.js', 'vendor/tesseract-core-simd-lstm.wasm.js', 'vendor/tesseract-core-simd-lstm.wasm', 'vendor/eng.traineddata.gz'];
const SHELL = ['index.html', 'manifest.webmanifest', 'icon-180.png', 'icon-192.png'];
self.addEventListener('install', e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll([...SHELL, ...ENGINE])).then(() => self.skipWaiting())); });
self.addEventListener('activate', e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (url.origin !== location.origin) return;
  const path = url.pathname;
  if (path.endsWith('/') || path.endsWith('index.html')) {
    e.respondWith(fetch(e.request).then(r => { const copy = r.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)); return r; }).catch(() => caches.match(e.request)));
  } else {
    e.respondWith(caches.match(e.request).then(hit => hit || fetch(e.request).then(r => { if (r.ok && /vendor\/|icon-|manifest/.test(path)) { const copy = r.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)); } return r; })));
  }
});
