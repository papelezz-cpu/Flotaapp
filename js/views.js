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

  if (v === 'home')               renderHome();
  if (v === 'cliente')            renderCatalogo();
  if (v === 'reservaciones')      renderReserv();
  if (v === 'admin')              renderAdmin();
  if (v === 'pendientes')         renderAprobaciones();
  if (v === 'pedidos')            renderPedidos();
  if (v === 'usuarios')           renderUsuarios();
  if (v === 'reportes')           renderReportes();
  if (v === 'mis-stats')          renderMisStats();
  if (v === 'historial-reservas') renderHistorialReservas();
  if (v === 'vigencias')         renderVigencias();
}

function toggleMenu() {
  document.getElementById('btn-hamburger')?.classList.toggle('open');
  document.querySelector('.nav-tabs')?.classList.toggle('open');
  document.getElementById('menu-backdrop')?.classList.toggle('open');
}

// ── ÍCONOS DE LÍNEA (inline SVG, sin dependencias) ────
function _hcIcon(name) {
  const P = {
    truck:          '<path d="M14 18V6a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2v11a1 1 0 0 0 1 1h2"/><path d="M15 18H9"/><path d="M19 18h2a1 1 0 0 0 1-1v-3.65a1 1 0 0 0-.22-.624l-3.48-4.35A1 1 0 0 0 17.52 8H14"/><circle cx="17" cy="18" r="2"/><circle cx="7" cy="18" r="2"/>',
    clipboardList:  '<rect width="8" height="4" x="8" y="2" rx="1" ry="1"/><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/><path d="M12 11h4"/><path d="M12 16h4"/><path d="M8 11h.01"/><path d="M8 16h.01"/>',
    building:       '<path d="M6 22V4a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v18Z"/><path d="M6 12H4a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2h2"/><path d="M18 9h2a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-2"/><path d="M10 6h4"/><path d="M10 10h4"/><path d="M10 14h4"/><path d="M10 18h4"/>',
    calendarCheck:  '<path d="M8 2v4"/><path d="M16 2v4"/><rect width="18" height="18" x="3" y="4" rx="2"/><path d="M3 10h18"/><path d="m9 16 2 2 4-4"/>',
    users:          '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
    hardHat:        '<path d="M2 18a1 1 0 0 0 1 1h18a1 1 0 0 0 1-1v-2a1 1 0 0 0-1-1H3a1 1 0 0 0-1 1Z"/><path d="M10 10V5a1 1 0 0 1 1-1h2a1 1 0 0 1 1 1v5"/><path d="M4 15v-3a6 6 0 0 1 6-6"/><path d="M14 6a6 6 0 0 1 6 6v3"/>',
    calendarClock:  '<path d="M21 7.5V6a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h3.5"/><path d="M16 2v4"/><path d="M8 2v4"/><path d="M3 10h5"/><path d="M17.5 17.5 16 16.3V14"/><circle cx="16" cy="16" r="6"/>',
    trendingUp:     '<polyline points="22 7 13.5 15.5 8.5 10.5 2 17"/><polyline points="16 7 22 7 22 13"/>',
    badgeCheck:     '<path d="M3.85 8.62a4 4 0 0 1 4.78-4.77 4 4 0 0 1 6.74 0 4 4 0 0 1 4.78 4.78 4 4 0 0 1 0 6.74 4 4 0 0 1-4.77 4.78 4 4 0 0 1-6.75 0 4 4 0 0 1-4.78-4.77 4 4 0 0 1 0-6.76Z"/><path d="m9 12 2 2 4-4"/>',
    barChart:       '<path d="M3 3v18h18"/><path d="M18 17V9"/><path d="M13 17V5"/><path d="M8 17v-3"/>',
    archive:        '<rect width="20" height="5" x="2" y="3" rx="1"/><path d="M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8"/><path d="M10 12h4"/>',
  };
  const inner = P[name] || P.clipboardList;
  return `<svg viewBox="0 0 24 24" width="26" height="26" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${inner}</svg>`;
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
      { i:'truck',         bg:'hc-blue',   t:'Solicitar servicio',     d:'Transporte, custodia y más',      fn:`_pedidosMode='solicitar';showView('pedidos',null)` },
      { i:'clipboardList', bg:'hc-slate',  t:'Mis solicitudes',         d:'Revisa el estado de tus pedidos', fn:`_pedidosMode='lista';showView('pedidos',null)` },
      { i:'building',      bg:'hc-teal',   t:'Catálogo',                d:'Empresas verificadas',            fn:`showView('cliente',null)` },
      { i:'calendarCheck', bg:'hc-purple', t:'Reservaciones',           d:'Tus reservas activas',            fn:`showView('reservaciones',null)` },
    ],
    admin: [
      { i:'clipboardList', bg:'hc-blue',   t:'Solicitudes',   d:'Ofertas y pedidos activos',        fn:`showView('pedidos',null)` },
      { i:'calendarCheck', bg:'hc-purple', t:'Reservaciones', d:'Viajes y servicios activos',       fn:`showView('reservaciones',null)` },
      { i:'truck',         bg:'hc-slate',  t:'Mis unidades',  d:'Gestiona tu flota de camiones',    fn:`_irAdmin('camion')` },
      { i:'hardHat',       bg:'hc-amber',  t:'Operadores',    d:'Personal de conducción',           fn:`_irAdmin('operador')` },
      { i:'calendarClock', bg:'hc-red',    t:'Vigencias',     d:'Documentos por vencer o vencidos', fn:`showView('vigencias',null)`, badge:'home-vig-badge' },
      { i:'trendingUp',    bg:'hc-purple', t:'Mi desempeño',  d:'Estadísticas personales',          fn:`showView('mis-stats',null)` },
    ],
    superadmin: [
      { i:'badgeCheck',    bg:'hc-red',    t:'Por aprobar',   d:'Solicitudes y recursos pendientes', fn:`showView('pendientes',null)`, badge:'home-apr-badge' },
      { i:'users',         bg:'hc-blue',   t:'Usuarios',      d:'Gestión de cuentas',               fn:`showView('usuarios',null)` },
      { i:'clipboardList', bg:'hc-slate',  t:'Solicitudes',   d:'Pedidos en el sistema',            fn:`showView('pedidos',null)` },
      { i:'barChart',      bg:'hc-amber',  t:'Reportes',      d:'Métricas y estadísticas',          fn:`showView('reportes',null)` },
      { i:'building',      bg:'hc-teal',   t:'Catálogo',      d:'Directorio de proveedores',        fn:`showView('cliente',null)` },
      { i:'calendarClock', bg:'hc-red',    t:'Vigencias',     d:'Documentos vencidos o por vencer', fn:`showView('vigencias',null)`, badge:'home-vig-badge' },
      { i:'calendarCheck', bg:'hc-purple', t:'Reservaciones', d:'Reservas activas',                 fn:`showView('reservaciones',null)` },
      { i:'archive',       bg:'hc-orange', t:'Historial',     d:'Reservaciones archivadas',         fn:`showView('historial-reservas',null)` },
    ],
  };

  const cards = C[currentUser?.rol] || [];
  grid.innerHTML = cards.map(c => `
    <div class="home-card ${c.bg}" onclick="${c.fn}">
      <div class="hc-icon">${_hcIcon(c.i)}</div>
      <div class="hc-title">${c.t}</div>
      <div class="hc-desc">${c.d}</div>
      ${c.badge ? `<div class="hc-badge" id="${c.badge}"></div>` : ''}
    </div>`).join('');

  if (currentUser?.rol === 'superadmin') _loadAprBadge();
  if (['admin','superadmin'].includes(currentUser?.rol)) actualizarBadgeVigencias();
}

function _navTab(view) {
  return document.querySelector(`.nav-tab[onclick*="'${view}'"]`) || null;
}

function _irAdmin(tab) {
  showView('admin', null);
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
    sb.from('pedidos'   ).select('id',{count:'exact',head:true}).eq('estado','pendiente_revision'),
    sb.from('pedidos'   ).select('id',{count:'exact',head:true}).eq('estado','pendiente_acuerdo'),
    sb.from('perfiles'  ).select('user_id',{count:'exact',head:true}).eq('aprobacion_cuenta','pendiente'),
    sb.from('perfiles'  ).select('user_id',{count:'exact',head:true}).eq('perfil_docs_pendiente',true),
  ]);
  const total = counts.reduce((s,r) => s + (r.count||0), 0);
  if (total > 0) {
    badge.textContent = total > 99 ? '99+' : total;
    badge.style.display = 'inline-block';
  } else {
    badge.style.display = 'none';
  }
}

// ── ESTADÍSTICAS PROPIAS (admin) ──────────────────────

async function renderMisStats() {
  const el = document.getElementById('mis-stats-content');
  if (!el || !currentUser.id) return;
  el.innerHTML = `<div class="empty-state"><div class="icon">⏳</div>Calculando tus métricas…</div>`;

  const [
    { data: ofertas },
    { data: reservas },
    { data: cals },
  ] = await Promise.all([
    sb.from('ofertas').select('id, estado, created_at').eq('admin_id', currentUser.id),
    sb.from('reservaciones').select('id, precio_acordado, estado, created_at')
      .eq('propietario_id', currentUser.id),
    sb.from('calificaciones').select('rating').eq('admin_id', currentUser.id),
  ]);

  const totalOfertas   = ofertas?.length || 0;
  const aceptadas      = (ofertas || []).filter(o => o.estado === 'aceptada').length;
  const tasa           = totalOfertas ? Math.round((aceptadas / totalOfertas) * 100) : 0;
  const totalReservas  = reservas?.length || 0;
  const completadas    = (reservas || []).filter(r => r.estado === 'Completada').length;
  const ingresoTotal   = (reservas || []).reduce((s, r) => s + (Number(r.precio_acordado) || 0), 0);
  const avgRating      = cals?.length ? (cals.reduce((s, c) => s + c.rating, 0) / cals.length).toFixed(1) : '—';

  // Ingresos por mes (últimos 6)
  const mesesMap = {};
  const hoy = new Date();
  for (let i = 5; i >= 0; i--) {
    const d = new Date(hoy.getFullYear(), hoy.getMonth() - i, 1);
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
    mesesMap[key] = { label: d.toLocaleString('es-MX', { month: 'short', year: '2-digit' }), ingreso: 0 };
  }
  (reservas || []).forEach(r => {
    const key = r.created_at?.substring(0, 7);
    if (key && mesesMap[key]) mesesMap[key].ingreso += Number(r.precio_acordado) || 0;
  });
  const meses   = Object.values(mesesMap);
  const maxIng  = Math.max(...meses.map(m => m.ingreso), 1);
  const barChart = meses.map(m => {
    const pct = Math.round((m.ingreso / maxIng) * 100);
    return `<div class="rep-bar-col">
      <div class="rep-bar-wrap"><div class="rep-bar-fill" style="height:${pct}%"></div></div>
      <div class="rep-bar-val" style="font-size:0.6rem">$${(m.ingreso/1000).toFixed(0)}k</div>
      <div class="rep-bar-label">${m.label}</div></div>`;
  }).join('');

  el.innerHTML = `
    <div class="rep-cards">
      <div class="rep-kpi-card"><div class="rep-kpi-val">${totalOfertas}</div><div class="rep-kpi-label">Ofertas enviadas</div></div>
      <div class="rep-kpi-card"><div class="rep-kpi-val green">${aceptadas}</div><div class="rep-kpi-label">Aceptadas</div></div>
      <div class="rep-kpi-card"><div class="rep-kpi-val">${tasa}%</div><div class="rep-kpi-label">Tasa de cierre</div></div>
      <div class="rep-kpi-card"><div class="rep-kpi-val">${totalReservas}</div><div class="rep-kpi-label">Reservaciones</div></div>
      <div class="rep-kpi-card"><div class="rep-kpi-val green">${completadas}</div><div class="rep-kpi-label">Completadas</div></div>
      <div class="rep-kpi-card"><div class="rep-kpi-val green">$${ingresoTotal.toLocaleString('es-MX')}</div><div class="rep-kpi-label">Ingreso total (MXN)</div></div>
      <div class="rep-kpi-card"><div class="rep-kpi-val amber">${avgRating} ⭐</div><div class="rep-kpi-label">Calificación promedio</div></div>
    </div>
    <div class="rep-section" style="margin-top:20px">
      <div class="rep-section-title">💰 Ingresos por mes</div>
      <div class="rep-bar-chart">${barChart}</div>
    </div>`;
}
