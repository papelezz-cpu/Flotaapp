// ── FLOTA / CAMIONES ──────────────────────────────────

let allCamiones = [];

async function renderCamiones(filtroTipo = '', filtroOrigen = '') {
  const grid  = document.getElementById('truck-grid');
  const stats = document.getElementById('stats-row');
  const count = document.getElementById('count-label');

  // #6 — Skeleton loader
  grid.innerHTML = skeletonGrid(6);

  let query = sb.from('camiones').select('*').eq('aprobacion', 'aprobada').order('id');
  if (filtroTipo)   query = query.eq('tipo', filtroTipo);
  if (filtroOrigen) query = query.eq('origen', filtroOrigen);
  const { data, error } = await query;
  if (error) {
    grid.innerHTML = `<div class="empty-state"><div class="icon">❌</div>Error al cargar datos.</div>`;
    return;
  }

  const ownerIds = [...new Set(data.map(c => c.propietario_id).filter(Boolean))];
  let ownerMap = {};
  if (ownerIds.length) {
    const { data: perfiles } = await sb.from('perfiles').select('user_id, nombre').in('user_id', ownerIds);
    (perfiles || []).forEach(p => { ownerMap[p.user_id] = p.nombre; });
  }

  allCamiones = data.map(c => ({ ...c, empresaNombre: ownerMap[c.propietario_id] || '—' }));

  const disp = data.filter(c => c.estado === 'disponible').length;
  const ocup = data.filter(c => c.estado === 'ocupado').length;
  const mant = data.filter(c => c.estado === 'mantenimiento').length;

  stats.innerHTML = `
    <div class="stat-card"><div class="stat-num green">${disp}</div><div class="stat-label">Disponibles</div></div>
    <div class="stat-card"><div class="stat-num amber">${ocup}</div><div class="stat-label">En servicio</div></div>
    <div class="stat-card"><div class="stat-num red">${mant}</div><div class="stat-label">Mantenimiento</div></div>
    <div class="stat-card"><div class="stat-num" style="color:var(--accent-bright)">${data.length}</div><div class="stat-label">Total unidades</div></div>
  `;
  count.textContent = `— ${disp} de ${data.length}`;

  if (data.length === 0) {
    grid.innerHTML = `<div class="empty-state"><div class="icon">🔍</div>No se encontraron unidades.</div>`;
    return;
  }

  // #1 — XSS: usar esc() en todos los campos de usuario
  grid.innerHTML = allCamiones.map(c => {
    const badgeClass = c.estado === 'disponible' ? 'badge-avail' : c.estado === 'ocupado' ? 'badge-busy' : 'badge-maint';
    const label      = c.estado === 'disponible' ? '✓ Disponible' : c.estado === 'ocupado' ? '⏳ En servicio' : '🔧 Mantenimiento';
    const disabled   = c.estado !== 'disponible' ? 'disabled' : '';
    const stars      = c.calificacion ? renderStars(c.calificacion) : '';

    return `
      <div class="truck-card">
        <div class="truck-header">
          <div>
            <div class="truck-id">${esc(c.id)}</div>
            <div class="truck-type">${esc(c.tipo)}</div>
            <div class="truck-empresa">🏢 ${esc(c.empresaNombre)}</div>
            ${stars ? `<div class="truck-stars">${stars}</div>` : ''}
          </div>
          <div class="badge ${badgeClass}">${label}</div>
        </div>
        <div class="truck-img-area">${esc(c.emoji)}</div>
        <div class="truck-specs">
          <div class="spec-item"><div class="spec-label">Capacidad</div><div class="spec-value">${esc(String(c.capacidad))} ton</div></div>
          <div class="spec-item"><div class="spec-label">Tipo</div><div class="spec-value">${esc(c.tipo)}</div></div>
          <div class="spec-item"><div class="spec-label">Operador</div><div class="spec-value">${esc(c.operador)}</div></div>
          <div class="spec-item"><div class="spec-label">Puerto / Origen</div><div class="spec-value">${esc(c.origen || '—')}</div></div>
        </div>
        ${formatPrecio(c.precio_dia) ? `<div class="truck-precio">${esc(formatPrecio(c.precio_dia))}</div>` : ''}
        <div class="truck-footer">
          <button class="btn-detail" onclick="openDetail('${esc(c.id)}')">Ver detalle</button>
          <button class="btn-reservar" ${disabled} onclick="openReserva('${esc(c.id)}')">Agendar</button>
        </div>
      </div>`;
  }).join('');
}

function renderStars(rating) {
  const full  = Math.floor(rating);
  const empty = 5 - full;
  return '<span class="stars">' +
    '★'.repeat(full) + '<span class="stars-empty">' + '★'.repeat(empty) + '</span>' +
    ` <span class="stars-num">${rating}</span>` +
    '</span>';
}

function filtrarCamiones() {
  renderCamiones(
    document.getElementById('filtro-tipo').value,
    document.getElementById('filtro-origen').value
  );
}

function openDetail(id) {
  const c = allCamiones.find(x => x.id === id);
  if (!c) return;
  alert(`📋 Detalle — ${c.id}\n\nEmpresa: ${c.empresaNombre}\nTipo: ${c.tipo}\nCapacidad: ${c.capacidad} ton\nOperador: ${c.operador}\nEstado: ${c.estado}`);
}
