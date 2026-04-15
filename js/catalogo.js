// ── CATÁLOGO DE EMPRESAS ───────────────────────────────
// Directorio de proveedores agrupado por empresa, con
// disponibilidad en tiempo real por tipo de recurso.

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

  // 1. Empresas (admins con perfil)
  const { data: perfiles } = await sb.from('perfiles')
    .select('user_id, nombre')
    .eq('rol', 'admin')
    .order('nombre');

  if (!perfiles?.length) {
    grid.innerHTML = `<div class="empty-state"><div class="icon">🏢</div>Aún no hay proveedores registrados.</div>`;
    return;
  }

  const ids = perfiles.map(p => p.user_id);

  // 2. Recursos aprobados en paralelo
  const [{ data: camiones }, { data: custodios }, { data: patios }] = await Promise.all([
    sb.from('camiones').select('id, tipo, estado, propietario_id').eq('aprobacion', 'aprobada').in('propietario_id', ids),
    sb.from('custodios').select('id, tipo, estado, propietario_id').eq('aprobacion', 'aprobada').in('propietario_id', ids),
    sb.from('patios').select('id, tipo, estado, propietario_id').eq('aprobacion', 'aprobada').in('propietario_id', ids),
  ]);

  // 3. Agrupar por empresa
  const empresas = perfiles.map(p => ({
    ...p,
    camiones:  (camiones  || []).filter(r => r.propietario_id === p.user_id),
    custodios: (custodios || []).filter(r => r.propietario_id === p.user_id),
    patios:    (patios    || []).filter(r => r.propietario_id === p.user_id),
  })).filter(e => e.camiones.length + e.custodios.length + e.patios.length > 0);

  if (!empresas.length) {
    grid.innerHTML = `<div class="empty-state"><div class="icon">🏢</div>Los proveedores registrados aún no tienen recursos aprobados.</div>`;
    return;
  }

  // 4. Ordenar: primero los que tienen disponibilidad
  empresas.sort((a, b) => {
    const dispA = [...a.camiones, ...a.custodios, ...a.patios].filter(r => r.estado === 'disponible').length;
    const dispB = [...b.camiones, ...b.custodios, ...b.patios].filter(r => r.estado === 'disponible').length;
    return dispB - dispA;
  });

  grid.innerHTML = empresas.map(e => _empresaCardHTML(e)).join('');

  // Reaplicar filtro activo
  const activo = document.querySelector('.cat-pill.active')?.dataset?.filter || 'todos';
  filtrarEmpresas(activo);
}

// ─── HTML de tarjeta de empresa ─────────────────────────
function _empresaCardHTML(e) {
  const color   = _avatarColor(e.nombre);
  const inicial = (e.nombre || '?')[0].toUpperCase();

  const servicios = [
    e.camiones.length  ? 'camion'   : null,
    e.custodios.length ? 'custodio' : null,
    e.patios.length    ? 'patio'    : null,
  ].filter(Boolean);

  // Total disponibles de todos los recursos
  const totalDisp = [
    ...e.camiones, ...e.custodios, ...e.patios
  ].filter(r => r.estado === 'disponible').length;

  const globalStatus = totalDisp > 0
    ? `<span class="emp-status emp-status-ok">● ${totalDisp} recurso${totalDisp !== 1 ? 's' : ''} disponible${totalDisp !== 1 ? 's' : ''}</span>`
    : `<span class="emp-status emp-status-busy">◐ Sin disponibilidad hoy</span>`;

  let bloques = '';
  if (e.camiones.length)  bloques += _recursoBloque('🚛', 'Camiones',  e.camiones);
  if (e.custodios.length) bloques += _recursoBloque('👮', 'Custodia',  e.custodios);
  if (e.patios.length)    bloques += _recursoBloque('🏭', 'Patios',    e.patios);

  return `
    <div class="empresa-card" data-servicios="${servicios.join(' ')}">
      <div class="empresa-card-top">
        <div class="empresa-avatar" style="--av-color:${color}">
          <span>${inicial}</span>
        </div>
        <div class="empresa-header-info">
          <div class="empresa-nombre">${esc(e.nombre)}</div>
          ${globalStatus}
          <div class="empresa-serv-icons">
            ${e.camiones.length  ? `<span class="emp-icon-badge" title="Camiones">🚛</span>`  : ''}
            ${e.custodios.length ? `<span class="emp-icon-badge" title="Custodia">👮</span>` : ''}
            ${e.patios.length    ? `<span class="emp-icon-badge" title="Patios">🏭</span>`    : ''}
          </div>
        </div>
      </div>

      <div class="empresa-recursos-list">
        ${bloques}
      </div>

      <div class="empresa-card-footer">
        <button class="btn-emp-solicitar" onclick="openNuevoPedido()">
          📋 Publicar solicitud
        </button>
      </div>
    </div>`;
}

function _recursoBloque(icon, titulo, recursos) {
  const disp  = recursos.filter(r => r.estado === 'disponible').length;
  const total = recursos.length;
  const tipos = [...new Set(recursos.map(r => r.tipo))].filter(Boolean);
  const pct   = Math.round((disp / total) * 100);

  const barColor = disp === 0 ? 'var(--amber)' : disp === total ? 'var(--green)' : 'var(--accent)';

  const tiposHTML = tipos.map(t => `<span class="cargo-chip cargo-chip-sm">${esc(t)}</span>`).join('');

  return `
    <div class="emp-rec-bloque">
      <div class="emp-rec-top">
        <span class="emp-rec-icon">${icon}</span>
        <span class="emp-rec-titulo">${titulo}</span>
        <span class="emp-rec-count" style="color:${barColor}">${disp}/${total}</span>
      </div>
      <div class="emp-avail-bar">
        <div class="emp-avail-fill" style="width:${pct}%;background:${barColor}"></div>
      </div>
      ${tiposHTML ? `<div class="emp-rec-tipos">${tiposHTML}</div>` : ''}
    </div>`;
}

// ─── Filtro client-side por tipo de servicio ────────────
function filtrarEmpresas(tipo) {
  document.querySelectorAll('.cat-pill').forEach(p =>
    p.classList.toggle('active', p.dataset.filter === tipo)
  );
  document.querySelectorAll('.empresa-card').forEach(card => {
    const ok = tipo === 'todos' || card.dataset.servicios?.includes(tipo);
    card.style.display = ok ? '' : 'none';
  });
}
