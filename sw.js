// ── SERVICE WORKER — PortGo ────────────────────────────
const CACHE      = 'portgo-v153';
const DATA_CACHE = 'portgo-data-v1';

const SHELL = [
  '/',
  '/index.html',
  '/app.html',
  '/privacidad.html',
  '/terminos.html',
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
  '/js/expedientes.js',
  '/js/mapa.js',
  '/js/plantillas.js',
  '/js/aprobaciones.js',
  '/js/admin.js',
  '/js/usuarios.js',
  '/js/verificacion.js',
  '/js/privacidad.js',
  '/js/preferencias.js',
  '/js/cobros.js',
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

  // ── Supabase REST (data): network-first, caché solo como respaldo ──
  // Antes era stale-while-revalidate: siempre devolvía la respuesta vieja
  // guardada y actualizaba el caché para la SIGUIENTE vez, así que la app
  // nunca mostraba datos frescos hasta la carga después de esa — pedidos,
  // notificaciones, etc. se veían "un paso atrás" y solo un refresh (o dos)
  // los ponía al día. Ahora se intenta la red primero; el caché solo se usa
  // si de verdad no hay conexión.
  if (isSupabaseRest) {
    e.respondWith(
      fetch(e.request.clone()).then(res => {
        if (res.ok) {
          caches.open(DATA_CACHE).then(cache => cache.put(e.request.clone(), res.clone()));
        }
        return res;
      }).catch(async () => {
        const cached = await caches.match(e.request);
        return cached || new Response('[]', {
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
