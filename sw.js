// ── SERVICE WORKER — PortGo ────────────────────────────
const CACHE      = 'portgo-v59';
const DATA_CACHE = 'portgo-data-v1';

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
  '/js/aprobaciones.js',
  '/js/admin.js',
  '/js/usuarios.js',
  '/js/reportes.js',
  '/js/chat.js',
  '/js/catalogo.js',
  '/js/operadores.js',
  '/js/tracking.js',
  '/js/vigencias.js',
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
      Promise.all(keys.filter(k => k !== CACHE && k !== DATA_CACHE).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

// Fetch handler
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  const isSameOrigin = url.hostname === location.hostname;
  const isSupabaseRest = url.hostname.endsWith('supabase.co') &&
                         url.pathname.startsWith('/rest/v1/') &&
                         e.request.method === 'GET';
  const isSupabaseEdge = url.hostname.endsWith('supabase.co') &&
                         url.pathname.startsWith('/functions/');

  // ── Supabase Edge Functions: always network, never cache ──
  if (isSupabaseEdge) return;

  // ── Supabase REST (data): stale-while-revalidate ──────────
  if (isSupabaseRest) {
    e.respondWith(
      caches.open(DATA_CACHE).then(async cache => {
        const cached = await cache.match(e.request);

        const networkFetch = fetch(e.request.clone()).then(res => {
          if (res.ok) cache.put(e.request.clone(), res.clone());
          return res;
        }).catch(() => null);

        if (cached) {
          // Return cached immediately, update in background
          networkFetch.catch(() => {});
          return cached;
        }

        // No cache yet: wait for network, fallback to empty array when offline
        const networkRes = await networkFetch;
        return networkRes ?? new Response('[]', {
          status: 200,
          headers: { 'Content-Type': 'application/json', 'X-From-Cache': 'offline' }
        });
      })
    );
    return;
  }

  // ── Other Supabase calls (realtime, auth): always network ──
  if (!isSameOrigin) return;

  // ── App JS/CSS/HTML: network-first, fallback to cache ─────
  const isAsset = /\.(js|css|html)$/.test(url.pathname) || url.pathname === '/';
  if (isAsset) {
    e.respondWith(
      fetch(e.request).then(res => {
        if (res.ok) {
          caches.open(CACHE).then(c => c.put(e.request, res.clone()));
        }
        return res;
      }).catch(() => caches.match(e.request))
    );
    return;
  }

  // ── Images and other static assets: cache-first ───────────
  e.respondWith(
    caches.match(e.request).then(cached =>
      cached || fetch(e.request).then(res => {
        if (res.ok) caches.open(CACHE).then(c => c.put(e.request, res.clone()));
        return res;
      })
    )
  );
});
