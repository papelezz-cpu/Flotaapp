// ── SERVICE WORKER — PortGo ────────────────────────────
const CACHE      = 'portgo-v191';
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
  '/css/detalle.css',
  '/css/theme.css',
  '/js/utils.js',
  '/js/config.js',
  '/js/auth.js',
  '/js/theme.js',
  '/js/views.js',
  '/js/detalle.js',
  '/js/notificaciones.js',
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

  // Solo GET. La Cache API no admite otros métodos: un cache.put() con un POST
  // lanza "Request method POST is unsupported", y caches.match() sobre un POST
  // no acierta nunca. Dejar pasar el registro, el login y cualquier escritura
  // directamente a la red evita ese ruido en la consola y en la pestaña Red.
  if (e.request.method !== 'GET') return;

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
          // El clon se saca AQUÍ, no dentro del then() de caches.open().
          // caches.open() es asíncrono: para cuando resolvía, el `return res`
          // de abajo ya había entregado la respuesta al navegador y el cuerpo
          // estaba consumido, así que el clone lanzaba
          //   TypeError: Response body is already used
          // y la entrada nunca llegaba al caché. Clonar antes es gratis:
          // clone() no lee el cuerpo, solo abre una segunda vía para leerlo.
          const copia = res.clone();
          caches.open(DATA_CACHE).then(cache => cache.put(e.request.clone(), copia));
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
          const copia = res.clone();          // antes de devolver: ver el comentario de arriba
          caches.open(CACHE).then(c => c.put(e.request, copia));
        }
        return res;
      }).catch(() =>
        // ignoreSearch: la lista SHELL precarga '/js/pedidos.js' pero la pagina
        // pide '/js/pedidos.js?v=72', y la Cache API compara la URL COMPLETA,
        // query incluida. Sin esto el precacheo no respondia jamas: se
        // descargaban 33 ficheros en cada instalacion que no se servian nunca,
        // y sin conexion la app no arrancaba en la primera visita — solo
        // funcionaba offline quien ya la hubiera cargado online, porque
        // entonces este mismo network-first ya habia guardado la URL con su ?v=.
        caches.match(e.request, { ignoreSearch: true }))
    );
    return;
  }

  // ── Images and other static assets: cache-first ───────────
  e.respondWith(
    caches.match(e.request).then(cached =>
      cached || fetch(e.request).then(res => {
        if (res.ok) {
          const copia = res.clone();          // antes de devolver: ver el comentario de arriba
          caches.open(CACHE).then(c => c.put(e.request, copia));
        }
        return res;
      })
    )
  );
});
