// ── CATÁLOGO DE EMPRESAS ───────────────────────────────
// Directorio de proveedores. Al filtrar por tipo de servicio,
// cada tarjeta muestra SOLO el bloque de ese servicio.

const _AVATAR_COLORS = [
  '#4e8ef7','#22c55e','#8b5cf6','#06b6d4',
  '#f59e0b','#ec4899','#14b8a6','#f97316',
];

function _avatarColor(str) {
  let h = 0;
  for (let i = 0; i < str.length; i++) h = str.charCodeAt(i) + ((h << 5) - h);
  return _AVATAR_COLORS[Math.abs(h) % _AVATAR_COLORS.length];
}

// ─── Render principal ───────────────────────────────────
async function renderCatalogo() {
  const grid = document.getElementById('empresa-grid');
  if (!grid) return;
  grid.innerHTML = skeletonGrid(3);

  const { data: perfiles } = await sb.from('perfiles')
    .select('user_id, nombre, rfc, razon_social, anos_operacion, num_unidades, seguro_rc, seguro_carga, permiso_sct, descripcion, telefono, fecha_vencimiento_permiso_sct, fecha_vencimiento_seguro_rc, fecha_vencimiento_seguro_carga, verificado')
    .eq('rol', 'admin')
    .order('nombre');

  if (!perfiles?.length) {
    grid.innerHTML = `<div class="empty-state"><div class="icon">🏢</div>Aún no hay proveedores registrados.</div>`;
    return;
  }

  const ids = perfiles.map(p => p.user_id);

  // Todos los recursos aprobados en paralelo
  const [
    { data: camiones  },
    { data: custodios },
    { data: patios    },
    { data: lavados   },
    { data: califs    },
  ] = await Promise.all([
    sb.from('camiones'      ).select('id, tipo, estado, propietario_id').eq('aprobacion','aprobada').in('propietario_id', ids),
    sb.from('custodios'     ).select('id, tipo, estado, propietario_id').eq('aprobacion','aprobada').in('propietario_id', ids),
    sb.from('patios'        ).select('id, tipo, estado, propietario_id').eq('aprobacion','aprobada').in('propietario_id', ids),
    sb.from('lavados'       ).select('id, tipos_vehiculo, tipos_lavado, estado, propietario_id').eq('aprobacion','aprobada').in('propietario_id', ids),
    sb.from('calificaciones').select('admin_id, rating, comentario, created_at').in('admin_id', ids).order('created_at', { ascending: false }),
  ]);

  // Agrupar calificaciones por empresa
  const califMap = {};
  (califs || []).forEach(c => {
    if (!califMap[c.admin_id]) califMap[c.admin_id] = [];
    califMap[c.admin_id].push(c);
  });

  const empresas = perfiles.map(p => ({
    ...p,
    camiones:  (camiones  || []).filter(r => r.propietario_id === p.user_id),
    custodios: (custodios || []).filter(r => r.propietario_id === p.user_id),
    patios:    (patios    || []).filter(r => r.propietario_id === p.user_id),
    lavados:   (lavados   || []).filter(r => r.propietario_id === p.user_id),
    califs:    califMap[p.user_id] || [],
  })).filter(e =>
    e.camiones.length + e.custodios.length + e.patios.length + e.lavados.length > 0
  );

  if (!empresas.length) {
    grid.innerHTML = `<div class="empty-state"><div class="icon">🏢</div>Los proveedores aún no tienen recursos aprobados.</div>`;
    return;
  }

  // Ordenar: más disponibilidad primero
  empresas.sort((a, b) => {
    const disp = e => [...e.camiones, ...e.custodios, ...e.patios, ...e.lavados]
      .filter(r => r.estado === 'disponible').length;
    return disp(b) - disp(a);
  });

  grid.innerHTML = empresas.map(e => _empresaCardHTML(e)).join('');

  // Aplicar filtro activo (primer pill por defecto)
  const activo = document.querySelector('.cat-pill.active')?.dataset?.filter || 'camion';
  filtrarEmpresas(activo);
}

// ─── Tarjeta de empresa ─────────────────────────────────
function _empresaCardHTML(e) {
  const color   = _avatarColor(e.nombre);
  const inicial = (e.nombre || '?')[0].toUpperCase();

  const servicios = [
    e.camiones.length  ? 'camion'   : null,
    e.custodios.length ? 'custodio' : null,
    e.patios.length    ? 'patio'    : null,
    e.lavados.length   ? 'lavado'   : null,
  ].filter(Boolean);

  const SERV_ICONS = { camion:'🚛', custodio:'👮', patio:'🏭', lavado:'🚿' };
  const iconBadges = servicios.map(s =>
    `<span class="emp-icon-badge" title="${s}">${SERV_ICONS[s]}</span>`
  ).join('');

  // Rating promedio
  const numCal = e.califs.length;
  const avg    = numCal ? (e.califs.reduce((s, c) => s + c.rating, 0) / numCal) : 0;
  const avgStr = avg.toFixed(1);
  const stars  = numCal
    ? `<div class="emp-rating">
         <span class="emp-stars">${'★'.repeat(Math.round(avg))}${'☆'.repeat(5 - Math.round(avg))}</span>
         <span class="emp-rating-num">${avgStr}</span>
         <button class="emp-btn-resenas" onclick="openVerCalificaciones('${e.user_id}','${esc(e.nombre)}')">
           Ver ${numCal} reseña${numCal !== 1 ? 's' : ''}
         </button>
       </div>`
    : `<div class="emp-rating emp-sin-rating">Sin reseñas aún</div>`;

  let bloques = '';
  if (e.camiones.length)  bloques += _bloqueEstandar ('camion',   '🚛', 'Camiones',  e.camiones);
  if (e.custodios.length) bloques += _bloqueEstandar ('custodio', '👮', 'Custodia',  e.custodios);
  if (e.patios.length)    bloques += _bloqueEstandar ('patio',    '🏭', 'Patios',    e.patios);
  if (e.lavados.length)   bloques += _bloqueLavado   (e.lavados);

  // Docs vigentes badge: every claimed doc has a non-expired date
  const hoy      = new Date().toISOString().slice(0, 10);
  const claimed  = [
    e.permiso_sct  ? e.fecha_vencimiento_permiso_sct  : undefined,
    e.seguro_rc    ? e.fecha_vencimiento_seguro_rc    : undefined,
    e.seguro_carga ? e.fecha_vencimiento_seguro_carga : undefined,
  ].filter(v => v !== undefined);
  const docsAlDia = claimed.length > 0 && claimed.every(f => f && f >= hoy);

  const chips = [];
  if (e.razon_social)    chips.push(`🏢 ${esc(e.razon_social)}`);
  if (e.rfc)             chips.push(`RFC: ${esc(e.rfc)}`);
  if (e.anos_operacion)  chips.push(`${e.anos_operacion} años`);
  if (e.permiso_sct)     chips.push('SCT ✓');
  if (e.seguro_rc)       chips.push('Seg. RC ✓');
  if (e.seguro_carga)    chips.push('Seg. Carga ✓');
  if (docsAlDia)         chips.push('✅ Docs al día');
  const infoChips = chips.length
    ? `<div class="emp-info-chips">${chips.map(c => `<span class="emp-info-chip">${c}</span>`).join('')}</div>`
    : '';

  const verBadge = e.verificado
    ? `<span style="display:inline-block;font-size:0.7rem;font-weight:700;background:rgba(34,197,94,0.15);color:#16a34a;border:1px solid rgba(34,197,94,0.4);border-radius:10px;padding:1px 8px;margin-left:6px;vertical-align:middle">✓ Verificado</span>`
    : '';

  return `
    <div class="empresa-card" data-servicios="${servicios.join(' ')}">
      <div class="empresa-card-top">
        <div class="empresa-avatar" style="--av-color:${color}">${inicial}</div>
        <div class="empresa-header-info">
          <div class="empresa-nombre">${esc(e.nombre)}${verBadge}</div>
          <div class="empresa-serv-icons">${iconBadges}</div>
        </div>
      </div>
      ${infoChips}
      ${e.descripcion ? `<div class="emp-desc">${esc(e.descripcion)}</div>` : ''}
      ${stars}
      <div class="empresa-recursos-list">${bloques}</div>
      <div class="empresa-card-footer">
        ${currentUser.rol === 'cliente' || !currentUser.id
          ? `<button class="btn-emp-solicitar" onclick="openNuevoPedido()">📋 Publicar solicitud</button>`
          : ''}
        ${e.telefono || e.descripcion || e.rfc
          ? `<button class="btn-emp-perfil" onclick="abrirPerfilEmpresaCat('${e.user_id}','${esc(e.nombre)}')">Ver empresa</button>`
          : ''}
      </div>
    </div>`;
}

// ─── Bloque genérico (camiones / custodios / patios) ────
function _bloqueEstandar(tipo, icon, titulo, recursos) {
  const disp  = recursos.filter(r => r.estado === 'disponible').length;
  const total = recursos.length;
  const tipos = [...new Set(recursos.map(r => r.tipo))].filter(Boolean);
  const pct   = Math.round((disp / total) * 100);
  const col   = disp === 0 ? 'var(--amber)' : disp === total ? 'var(--green)' : 'var(--accent)';

  return `
    <div class="emp-rec-bloque" data-tipo="${tipo}">
      <div class="emp-rec-top">
        <span class="emp-rec-icon">${icon}</span>
        <span class="emp-rec-titulo">${titulo}</span>
        <span class="emp-rec-count" style="color:${col}">${disp}/${total}</span>
      </div>
      <div class="emp-avail-bar"><div class="emp-avail-fill" style="width:${pct}%;background:${col}"></div></div>
      ${tipos.length ? `<div class="emp-rec-tipos">${tipos.map(t => `<span class="cargo-chip cargo-chip-sm">${esc(t)}</span>`).join('')}</div>` : ''}
    </div>`;
}

// ─── Bloque especial: lavado ────────────────────────────
function _bloqueLavado(lavados) {
  const disp  = lavados.filter(r => r.estado === 'disponible').length;
  const total = lavados.length;
  const pct   = Math.round((disp / total) * 100);
  const col   = disp === 0 ? 'var(--amber)' : disp === total ? 'var(--green)' : 'var(--accent)';

  // Qué vehículos lavan (unión de todos los servicios)
  const vehiculos = [...new Set(lavados.flatMap(l => l.tipos_vehiculo || []))];
  // Qué tipos de lavado ofrecen
  const tiposLav  = [...new Set(lavados.flatMap(l => l.tipos_lavado  || []))];

  const chips = (arr, cls) => arr.map(t => `<span class="cargo-chip cargo-chip-sm ${cls}">${esc(t)}</span>`).join('');

  return `
    <div class="emp-rec-bloque" data-tipo="lavado">
      <div class="emp-rec-top">
        <span class="emp-rec-icon">🚿</span>
        <span class="emp-rec-titulo">Lavado</span>
        <span class="emp-rec-count" style="color:${col}">${disp}/${total}</span>
      </div>
      <div class="emp-avail-bar"><div class="emp-avail-fill" style="width:${pct}%;background:${col}"></div></div>
      ${vehiculos.length ? `
        <div class="emp-lav-label">Lavan:</div>
        <div class="emp-rec-tipos">${chips(vehiculos, '')}</div>` : ''}
      ${tiposLav.length ? `
        <div class="emp-lav-label" style="margin-top:6px">Servicios:</div>
        <div class="emp-rec-tipos">${chips(tiposLav, 'chip-lav')}</div>` : ''}
    </div>`;
}

// ─── Modal: ver calificaciones de una empresa ───────────

async function openVerCalificaciones(adminId, adminNombre) {
  document.getElementById('vcal-titulo').textContent = `⭐ Reseñas de ${adminNombre}`;
  document.getElementById('vcal-resumen').innerHTML  = '<span style="color:var(--text-muted);font-size:0.85rem">Cargando…</span>';
  document.getElementById('vcal-lista').innerHTML    = '';
  document.getElementById('modal-ver-calificaciones').classList.add('open');

  const { data: cals } = await sb.from('calificaciones')
    .select('rating, comentario, created_at, cliente_id')
    .eq('admin_id', adminId)
    .order('created_at', { ascending: false });

  if (!cals?.length) {
    document.getElementById('vcal-resumen').innerHTML = '';
    document.getElementById('vcal-lista').innerHTML =
      '<div style="color:var(--text-muted);font-size:0.88rem;text-align:center;padding:20px">Sin reseñas todavía</div>';
    return;
  }

  const avg    = cals.reduce((s, c) => s + c.rating, 0) / cals.length;
  const avgStr = avg.toFixed(1);
  document.getElementById('vcal-resumen').innerHTML = `
    <div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap">
      <span style="font-size:1.6rem;font-weight:700;color:var(--accent)">${avgStr}</span>
      <span style="color:#f59e0b;font-size:1.2rem">${'★'.repeat(Math.round(avg))}${'☆'.repeat(5 - Math.round(avg))}</span>
      <span style="color:var(--text-muted);font-size:0.85rem">${cals.length} reseña${cals.length !== 1 ? 's' : ''}</span>
    </div>`;

  const labels = ['', 'Malo', 'Regular', 'Bueno', 'Muy bueno', 'Excelente'];
  document.getElementById('vcal-lista').innerHTML = cals.map(c => `
    <div class="vcal-item">
      <div class="vcal-item-top">
        <span class="vcal-stars">${'★'.repeat(c.rating)}${'☆'.repeat(5 - c.rating)}</span>
        <span class="vcal-label">${labels[c.rating] || ''}</span>
        <span class="vcal-fecha">${fmtFecha((c.created_at||'').substring(0,10))}</span>
      </div>
      ${c.comentario ? `<div class="vcal-comentario">"${esc(c.comentario)}"</div>` : ''}
    </div>`).join('');
}

function cerrarVerCalificaciones() {
  document.getElementById('modal-ver-calificaciones').classList.remove('open');
}

// ─── Modal perfil de empresa (desde catálogo) ──────────
let _catPerfilesCache = {};

async function abrirPerfilEmpresaCat(adminId, adminNombre) {
  document.getElementById('epc-titulo').textContent = adminNombre;
  document.getElementById('epc-body').innerHTML =
    '<div style="text-align:center;padding:24px;color:var(--text-muted)">Cargando…</div>';
  document.getElementById('modal-emp-cat').classList.add('open');

  const [{ data: p }, { data: cals }] = await Promise.all([
    sb.from('perfiles')
      .select('rfc, razon_social, anos_operacion, num_unidades, seguro_rc, seguro_carga, permiso_sct, descripcion, telefono, fecha_vencimiento_permiso_sct, fecha_vencimiento_seguro_rc, fecha_vencimiento_seguro_carga')
      .eq('user_id', adminId).single(),
    sb.from('calificaciones').select('rating, comentario, created_at').eq('admin_id', adminId).order('created_at', { ascending: false }).limit(5),
  ]);

  const avg = cals?.length ? (cals.reduce((s, c) => s + c.rating, 0) / cals.length).toFixed(1) : null;

  const hoyEpc = new Date().toISOString().slice(0, 10);
  const _fmtDoc = (fecha) => {
    if (!fecha) return '<span style="color:var(--text-muted)">Sin fecha registrada</span>';
    const vencido = fecha < hoyEpc;
    return `<span style="color:${vencido ? 'var(--danger)' : 'inherit'}">${fmtFecha(fecha)}${vencido ? ' ⛔' : ' ✓'}</span>`;
  };

  const rows = [
    p?.razon_social  && ['🏢', 'Razón social',        esc(p.razon_social)],
    p?.rfc           && ['📄', 'RFC',                  esc(p.rfc)],
    p?.telefono      && ['📞', 'Teléfono',              esc(p.telefono)],
    p?.permiso_sct   && ['📋', 'Permiso SCT',          `${esc(p.permiso_sct)} — Vence: ${_fmtDoc(p.fecha_vencimiento_permiso_sct)}`],
    p?.anos_operacion && ['⏱️', 'Años de operación',   `${p.anos_operacion} años`],
    p?.num_unidades  && ['🚛', 'Unidades en flota',    `${p.num_unidades}`],
    p?.seguro_rc     && ['🛡️', 'Seguro RC',            _fmtDoc(p.fecha_vencimiento_seguro_rc)],
    p?.seguro_carga  && ['📦', 'Seguro de carga',      _fmtDoc(p.fecha_vencimiento_seguro_carga)],
  ].filter(Boolean);

  const recientes = (cals || []).slice(0, 3).map(c => `
    <div class="vcal-item">
      <div class="vcal-item-top">
        <span class="vcal-stars">${'★'.repeat(c.rating)}${'☆'.repeat(5 - c.rating)}</span>
        <span class="vcal-fecha">${fmtFecha((c.created_at||'').substring(0,10))}</span>
      </div>
      ${c.comentario ? `<div class="vcal-comentario">"${esc(c.comentario)}"</div>` : ''}
    </div>`).join('');

  document.getElementById('epc-body').innerHTML = `
    ${p?.descripcion ? `<p class="emp-desc" style="margin-bottom:16px">${esc(p.descripcion)}</p>` : ''}
    ${rows.length ? `
    <div class="epc-rows">
      ${rows.map(([icon, label, val]) => `
        <div class="epc-row">
          <span class="epc-row-icon">${icon}</span>
          <span class="epc-row-label">${label}</span>
          <span class="epc-row-val">${val}</span>
        </div>`).join('')}
    </div>` : ''}
    ${avg ? `
    <div style="margin-top:16px">
      <div class="section-title" style="font-size:0.85rem;margin-bottom:8px">Calificación: ${avg} ⭐</div>
      ${recientes}
    </div>` : ''}`;
}

function cerrarPerfilEmpresaCat() {
  document.getElementById('modal-emp-cat').classList.remove('open');
}

// ─── Filtro: muestra empresas y bloques del tipo activo ─
function filtrarEmpresas(tipo) {
  document.querySelectorAll('.cat-pill').forEach(p =>
    p.classList.toggle('active', p.dataset.filter === tipo)
  );
  const q = (document.getElementById('cat-search')?.value || '').toLowerCase().trim();
  _aplicarFiltrosCat(tipo, q);
}

function buscarEmpresas(query) {
  const tipo = document.querySelector('.cat-pill.active')?.dataset?.filter || 'camion';
  _aplicarFiltrosCat(tipo, query.toLowerCase().trim());
}

function _aplicarFiltrosCat(tipo, q) {
  document.querySelectorAll('.empresa-card').forEach(card => {
    const tieneServicio = card.dataset.servicios?.includes(tipo);
    const nombre = card.querySelector('.empresa-nombre')?.textContent?.toLowerCase() || '';
    const matchQ = !q || nombre.includes(q);
    card.style.display = tieneServicio && matchQ ? '' : 'none';

    if (tieneServicio) {
      card.querySelectorAll('.emp-rec-bloque').forEach(bloque => {
        bloque.style.display = bloque.dataset.tipo === tipo ? '' : 'none';
      });
    }
  });
}
