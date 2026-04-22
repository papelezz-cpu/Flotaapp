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
    .select('user_id, nombre')
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
  ] = await Promise.all([
    sb.from('camiones' ).select('id, tipo, estado, propietario_id').eq('aprobacion','aprobada').in('propietario_id', ids),
    sb.from('custodios').select('id, tipo, estado, propietario_id').eq('aprobacion','aprobada').in('propietario_id', ids),
    sb.from('patios'   ).select('id, tipo, estado, propietario_id').eq('aprobacion','aprobada').in('propietario_id', ids),
    sb.from('lavados'  ).select('id, tipos_vehiculo, tipos_lavado, estado, propietario_id').eq('aprobacion','aprobada').in('propietario_id', ids),
  ]);

  const empresas = perfiles.map(p => ({
    ...p,
    camiones:  (camiones  || []).filter(r => r.propietario_id === p.user_id),
    custodios: (custodios || []).filter(r => r.propietario_id === p.user_id),
    patios:    (patios    || []).filter(r => r.propietario_id === p.user_id),
    lavados:   (lavados   || []).filter(r => r.propietario_id === p.user_id),
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

  // statusTxt eliminado — la disponibilidad se muestra en cada bloque de servicio

  const SERV_ICONS = { camion:'🚛', custodio:'👮', patio:'🏭', lavado:'🚿' };
  const iconBadges = servicios.map(s =>
    `<span class="emp-icon-badge" title="${s}">${SERV_ICONS[s]}</span>`
  ).join('');

  let bloques = '';
  if (e.camiones.length)  bloques += _bloqueEstandar ('camion',   '🚛', 'Camiones',  e.camiones);
  if (e.custodios.length) bloques += _bloqueEstandar ('custodio', '👮', 'Custodia',  e.custodios);
  if (e.patios.length)    bloques += _bloqueEstandar ('patio',    '🏭', 'Patios',    e.patios);
  if (e.lavados.length)   bloques += _bloqueLavado   (e.lavados);

  return `
    <div class="empresa-card" data-servicios="${servicios.join(' ')}">
      <div class="empresa-card-top">
        <div class="empresa-avatar" style="--av-color:${color}">${inicial}</div>
        <div class="empresa-header-info">
          <div class="empresa-nombre">${esc(e.nombre)}</div>
          <div class="empresa-serv-icons">${iconBadges}</div>
        </div>
      </div>
      <div class="empresa-recursos-list">${bloques}</div>
      ${currentUser.rol === 'cliente' || !currentUser.id ? `
      <div class="empresa-card-footer">
        <button class="btn-emp-solicitar" onclick="openNuevoPedido()">📋 Publicar solicitud</button>
      </div>` : ''}
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

// ─── Filtro: muestra empresas y bloques del tipo activo ─
function filtrarEmpresas(tipo) {
  document.querySelectorAll('.cat-pill').forEach(p =>
    p.classList.toggle('active', p.dataset.filter === tipo)
  );

  document.querySelectorAll('.empresa-card').forEach(card => {
    const tieneServicio = card.dataset.servicios?.includes(tipo);
    card.style.display = tieneServicio ? '' : 'none';

    if (tieneServicio) {
      // Mostrar SOLO el bloque del tipo activo, ocultar los demás
      card.querySelectorAll('.emp-rec-bloque').forEach(bloque => {
        bloque.style.display = bloque.dataset.tipo === tipo ? '' : 'none';
      });
    }
  });
}
