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
}

function toggleMenu() {
  document.getElementById('btn-hamburger')?.classList.toggle('open');
  document.querySelector('.nav-tabs')?.classList.toggle('open');
  document.getElementById('menu-backdrop')?.classList.toggle('open');
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
      { e:'🚛', bg:'hc-blue',   t:'Solicitar servicio',     d:'Transporte, custodia y más',      fn:`_pedidosMode='solicitar';showView('pedidos',null)` },
      { e:'📋', bg:'hc-slate',  t:'Mis solicitudes',         d:'Revisa el estado de tus pedidos', fn:`_pedidosMode='lista';showView('pedidos',null)` },
      { e:'📚', bg:'hc-teal',   t:'Catálogo',                d:'Empresas verificadas',            fn:`showView('cliente',null)` },
      { e:'🗓️', bg:'hc-purple', t:'Reservaciones',           d:'Tus reservas activas',            fn:`showView('reservaciones',null)` },
    ],
    admin: [
      { e:'📋', bg:'hc-blue',   t:'Solicitudes',   d:'Ofertas y pedidos activos',        fn:`showView('pedidos',null)` },
      { e:'🚛', bg:'hc-slate',  t:'Mis unidades',  d:'Gestiona tu flota de camiones',    fn:`_irAdmin('camion')` },
      { e:'👷', bg:'hc-amber',  t:'Operadores',    d:'Personal de conducción',           fn:`_irAdmin('operador')` },
      { e:'👮', bg:'hc-teal',   t:'Custodios',     d:'Servicios de seguridad',           fn:`_irAdmin('custodio')` },
      { e:'🏭', bg:'hc-orange', t:'Patios',        d:'Almacenamiento y estacionamiento', fn:`_irAdmin('patio')` },
      { e:'🚿', bg:'hc-green',  t:'Lavados',       d:'Limpieza vehicular',               fn:`_irAdmin('lavado')` },
      { e:'📈', bg:'hc-purple', t:'Mi desempeño',  d:'Estadísticas personales',          fn:`showView('mis-stats',null)` },
    ],
    superadmin: [
      { e:'✅', bg:'hc-red',    t:'Por aprobar',   d:'Solicitudes y recursos pendientes', fn:`showView('pendientes',null)`, badge:'home-apr-badge' },
      { e:'👥', bg:'hc-blue',   t:'Usuarios',      d:'Gestión de cuentas',               fn:`showView('usuarios',null)` },
      { e:'📋', bg:'hc-slate',  t:'Solicitudes',   d:'Pedidos en el sistema',            fn:`showView('pedidos',null)` },
      { e:'📊', bg:'hc-amber',  t:'Reportes',      d:'Métricas y estadísticas',          fn:`showView('reportes',null)` },
      { e:'📚', bg:'hc-teal',   t:'Catálogo',      d:'Directorio de proveedores',        fn:`showView('cliente',null)` },
      { e:'🗓️', bg:'hc-purple', t:'Reservaciones', d:'Reservas activas',                 fn:`showView('reservaciones',null)` },
      { e:'🗃',  bg:'hc-orange', t:'Historial',     d:'Reservaciones archivadas',         fn:`showView('historial-reservas',null)` },
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
    sb.from('perfiles'  ).select('user_id',{count:'exact',head:true}).eq('aprobacion_cuenta','pendiente'),
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
