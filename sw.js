// ── SERVICE WORKER — PortGo ────────────────────────────
const CACHE = 'portgo-v8';
const SHELL = [
  '/',
  '/index.html',
  '/manifest.json',
  '/icon.svg',
  '/icon-light.svg',
  '/css/base.css',
  '/css/layout.css',
  '/css/components.css',
  '/css/login.css',
  '/css/theme.css',
  '/js/utils.js',
  '/js/config.js',
  '/js/auth.js',
  '/js/theme.js',
  '/js/views.js',
  '/js/camiones.js',
  '/js/recursos.js',
  '/js/reservaciones.js',
  '/js/modal.js',
  '/js/pedidos.js',
  '/js/admin.js',
  '/js/usuarios.js',
  '/js/chat.js',
  '/js/catalogo.js',
  '/js/main.js'
];

// Instalar: cachear app shell
self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting())
  );
});

// Activar: limpiar caches viejos
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

// Fetch: network-first para JS/CSS (siempre frescos), cache-first para imágenes
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);

  // Supabase y CDN siempre desde red
  if (url.hostname !== location.hostname) return;

  const esScript = url.pathname.endsWith('.js') || url.pathname.endsWith('.css') || url.pathname.endsWith('.html');

  if (esScript) {
    // Network-first: si falla la red, usar cache como fallback
    e.respondWith(
      fetch(e.request).then(res => {
        if (res.ok) {
          const clone = res.clone();
          caches.open(CACHE).then(c => c.put(e.request, clone));
        }
        return res;
      }).catch(() => caches.match(e.request))
    );
  } else {
    // Imágenes y otros assets: cache-first
    e.respondWith(
      caches.match(e.request).then(cached => cached || fetch(e.request).then(res => {
        if (res.ok) {
          const clone = res.clone();
          caches.open(CACHE).then(c => c.put(e.request, clone));
        }
        return res;
      }))
    );
  }
});
