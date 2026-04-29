// ── NAVEGACIÓN ENTRE VISTAS ───────────────────────────

function showView(v, btn) {
  document.querySelectorAll('.view').forEach(el => el.classList.remove('active'));
  document.querySelectorAll('.nav-tab').forEach(el => el.classList.remove('active'));

  document.getElementById('view-' + v)?.classList.add('active');
  if (btn) btn.classList.add('active');

  // Cerrar menú hamburguesa al navegar
  document.getElementById('btn-hamburger')?.classList.remove('open');
  document.querySelector('.nav-tabs')?.classList.remove('open');
  document.getElementById('menu-backdrop')?.classList.remove('open');

  if (v === 'home')          renderHome();
  if (v === 'cliente')       renderCatalogo();
  if (v === 'reservaciones') renderReserv();
  if (v === 'admin')         renderAdmin();
  if (v === 'pendientes')    renderAprobaciones();
  if (v === 'pedidos')       renderPedidos();
  if (v === 'usuarios')      renderUsuarios();
}

function toggleMenu() {
  document.getElementById('btn-hamburger').classList.toggle('open');
  document.querySelector('.nav-tabs').classList.toggle('open');
  document.getElementById('menu-backdrop').classList.toggle('open');
}

// ── HOME PAGE ─────────────────────────────────────────

function renderHome() {
  const el = document.getElementById('home-greeting');
  if (el && currentUser?.nombre) {
    const h = new Date().getHours();
    const saludo = h < 12 ? 'Buenos días' : h < 19 ? 'Buenas tardes' : 'Buenas noches';
    el.textContent = `${saludo}, ${currentUser.nombre.split(' ')[0]} 👋`;
  }
  const grid = document.getElementById('home-grid');
  if (!grid) return;

  const C = {
    cliente: [
      { e:'🚛', bg:'hc-blue',   t:'Solicitar servicio',     d:'Transporte, custodia y más',      fn:`showView('pedidos',_navTab('pedidos'))` },
      { e:'📋', bg:'hc-slate',  t:'Mis solicitudes',         d:'Revisa el estado de tus pedidos', fn:`showView('pedidos',_navTab('pedidos'))` },
      { e:'📚', bg:'hc-teal',   t:'Catálogo',                d:'Empresas verificadas',            fn:`showView('cliente',_navTab('cliente'))` },
      { e:'🗓️', bg:'hc-purple', t:'Reservaciones',           d:'Tus reservas activas',            fn:`showView('reservaciones',_navTab('reservaciones'))` },
    ],
    admin: [
      { e:'📋', bg:'hc-blue',   t:'Solicitudes',   d:'Ofertas y pedidos activos',        fn:`showView('pedidos',_navTab('pedidos'))` },
      { e:'🚛', bg:'hc-slate',  t:'Mis unidades',  d:'Gestiona tu flota de camiones',    fn:`_irAdmin('camion')` },
      { e:'👷', bg:'hc-amber',  t:'Operadores',    d:'Personal de conducción',           fn:`_irAdmin('operador')` },
      { e:'👮', bg:'hc-teal',   t:'Custodios',     d:'Servicios de seguridad',           fn:`_irAdmin('custodio')` },
      { e:'🏭', bg:'hc-orange', t:'Patios',        d:'Almacenamiento y estacionamiento', fn:`_irAdmin('patio')` },
      { e:'🚿', bg:'hc-green',  t:'Lavados',       d:'Limpieza vehicular',               fn:`_irAdmin('lavado')` },
    ],
    superadmin: [
      { e:'✅', bg:'hc-red',    t:'Por aprobar',   d:'Solicitudes y recursos pendientes', fn:`showView('pendientes',_navTab('pendientes'))`, badge:'home-apr-badge' },
      { e:'👥', bg:'hc-blue',   t:'Usuarios',      d:'Gestión de cuentas',               fn:`showView('usuarios',_navTab('usuarios'))` },
      { e:'📋', bg:'hc-slate',  t:'Solicitudes',   d:'Pedidos en el sistema',            fn:`showView('pedidos',_navTab('pedidos'))` },
      { e:'📚', bg:'hc-teal',   t:'Catálogo',      d:'Directorio de proveedores',        fn:`showView('cliente',_navTab('cliente'))` },
      { e:'🗓️', bg:'hc-purple', t:'Reservaciones', d:'Reservas activas',                 fn:`showView('reservaciones',_navTab('reservaciones'))` },
    ],
  };

  const cards = C[currentUser?.rol] || [];
  grid.innerHTML = cards.map(c => `
    <div class="home-card ${c.bg}" onclick="${c.fn}">
      <div class="hc-bg-emoji">${c.e}</div>
      <div class="hc-icon">${c.e}</div>
      <div class="hc-title">${c.t}</div>
      <div class="hc-desc">${c.d}</div>
      ${c.badge ? `<div class="hc-badge" id="${c.badge}"></div>` : ''}
    </div>`).join('');

  if (currentUser?.rol === 'superadmin') _loadAprBadge();
}

function _navTab(view) {
  return document.querySelector(`.nav-tab[onclick*="'${view}'"]`) || null;
}

function _irAdmin(tab) {
  showView('admin', _navTab('admin'));
  setTimeout(() => cambiarAdminTab(tab), 150);
}

async function _loadAprBadge() {
  const badge = document.getElementById('home-apr-badge');
  if (!badge) return;
  const counts = await Promise.all([
    sb.from('camiones'  ).select('id',{count:'exact',head:true}).eq('aprobacion','pendiente'),
    sb.from('operadores').select('id',{count:'exact',head:true}).eq('aprobacion','pendiente'),
    sb.from('custodios' ).select('id',{count:'exact',head:true}).eq('aprobacion','pendiente'),
    sb.from('patios'    ).select('id',{count:'exact',head:true}).eq('aprobacion','pendiente'),
    sb.from('lavados'   ).select('id',{count:'exact',head:true}).eq('aprobacion','pendiente'),
  ]);
  const total = counts.reduce((s,r) => s + (r.count||0), 0);
  if (total > 0) {
    badge.textContent = `${total} pendiente${total > 1 ? 's' : ''}`;
    badge.style.display = 'inline-block';
  }
}
