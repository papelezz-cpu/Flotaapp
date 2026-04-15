// ── CUSTODIOS Y PATIOS ─────────────────────────────────

const CUSTODIO_TIPOS = ['Armado','Sin arma','Motorizado','K9','Supervisión remota'];
const PATIO_TIPOS    = ['Techado','Abierto','Refrigerado','Especializado','Bodega'];

const CUSTODIO_EMOJI = {
  'Armado':             '🔫',
  'Sin arma':           '👮',
  'Motorizado':         '🏍️',
  'K9':                 '🐕',
  'Supervisión remota': '📹',
};

const PATIO_EMOJI = {
  'Techado':       '🏭',
  'Abierto':       '🏗️',
  'Refrigerado':   '❄️',
  'Especializado': '⚙️',
  'Bodega':        '📦',
};

// ── CUSTODIOS ──────────────────────────────────────────

async function renderCustodios(filtroTipo = '') {
  const grid  = document.getElementById('truck-grid');
  const stats = document.getElementById('stats-row');
  const count = document.getElementById('count-label');

  grid.innerHTML = skeletonGrid(4);

  let query = sb.from('custodios').select('*').eq('aprobacion', 'aprobada').order('id');
  if (filtroTipo) query = query.eq('tipo', filtroTipo);
  const { data, error } = await query;
  if (error) {
    grid.innerHTML = `<div class="empty-state"><div class="icon">❌</div>Error al cargar custodios.</div>`;
    return;
  }

  const ownerIds = [...new Set((data || []).map(c => c.propietario_id).filter(Boolean))];
  let ownerMap = {};
  if (ownerIds.length) {
    const { data: perfiles } = await sb.from('perfiles').select('user_id, nombre').in('user_id', ownerIds);
    (perfiles || []).forEach(p => { ownerMap[p.user_id] = p.nombre; });
  }
  const custodios = (data || []).map(c => ({ ...c, empresaNombre: ownerMap[c.propietario_id] || '—' }));

  const disp = custodios.filter(c => c.estado === 'disponible').length;
  const ocup = custodios.filter(c => c.estado === 'ocupado').length;
  const nod  = custodios.filter(c => c.estado === 'no_disponible').length;

  stats.innerHTML = `
    <div class="stat-card"><div class="stat-num green">${disp}</div><div class="stat-label">Disponibles</div></div>
    <div class="stat-card"><div class="stat-num amber">${ocup}</div><div class="stat-label">En servicio</div></div>
    <div class="stat-card"><div class="stat-num red">${nod}</div><div class="stat-label">No disponibles</div></div>
    <div class="stat-card"><div class="stat-num" style="color:var(--accent-bright)">${custodios.length}</div><div class="stat-label">Total</div></div>`;
  count.textContent = `— ${disp} de ${custodios.length}`;

  if (!custodios.length) {
    grid.innerHTML = `<div class="empty-state"><div class="icon">👮</div>No se encontraron custodios.</div>`;
    return;
  }

  grid.innerHTML = custodios.map(c => {
    const badgeClass = c.estado === 'disponible' ? 'badge-avail' : c.estado === 'ocupado' ? 'badge-busy' : 'badge-maint';
    const label      = c.estado === 'disponible' ? '✓ Disponible' : c.estado === 'ocupado' ? '⏳ En servicio' : '✕ No disponible';
    const disabled   = c.estado !== 'disponible' ? 'disabled' : '';
    const emoji      = CUSTODIO_EMOJI[c.tipo] || '👮';
    const certs      = (c.certificaciones || []).map(cert => `<span class="cargo-chip">${esc(cert)}</span>`).join('');
    const precio     = c.precio_dia ? `<div class="truck-precio">$${Number(c.precio_dia).toLocaleString('es-MX')} MXN / día</div>` : '';
    return `
      <div class="truck-card">
        <div class="truck-header">
          <div>
            <div class="truck-id">${esc(c.id)}</div>
            <div class="truck-type">${emoji} ${esc(c.tipo)}</div>
            <div class="truck-empresa">🏢 ${esc(c.empresaNombre)}</div>
          </div>
          <div class="badge ${badgeClass}">${label}</div>
        </div>
        <div class="truck-img-area" style="font-size:2.8rem">${emoji}</div>
        <div class="truck-specs">
          <div class="spec-item"><div class="spec-label">Nombre</div><div class="spec-value">${esc(c.nombre)}</div></div>
          <div class="spec-item"><div class="spec-label">Disponibilidad</div><div class="spec-value">${esc(c.disponibilidad || '—')}</div></div>
        </div>
        ${c.descripcion ? `<div class="recurso-desc">${esc(c.descripcion)}</div>` : ''}
        ${certs ? `<div class="recurso-chips">${certs}</div>` : ''}
        ${precio}
        <div class="truck-footer">
          ${currentUser.rol === 'cliente' || !currentUser.id
            ? `<button class="btn-reservar" onclick="openNuevoPedido()" title="Publica una solicitud y los proveedores te harán ofertas">📋 Solicitar</button>`
            : `<button class="btn-reservar" ${disabled} onclick="openReservaRecurso('custodio','${esc(c.id)}','${esc(c.nombre)}','${c.propietario_id||''}')">Reservar</button>`
          }
        </div>
      </div>`;
  }).join('');
}

// ── PATIOS ─────────────────────────────────────────────

async function renderPatios(filtroTipo = '') {
  const grid  = document.getElementById('truck-grid');
  const stats = document.getElementById('stats-row');
  const count = document.getElementById('count-label');

  grid.innerHTML = skeletonGrid(4);

  let query = sb.from('patios').select('*').eq('aprobacion', 'aprobada').order('id');
  if (filtroTipo) query = query.eq('tipo', filtroTipo);
  const { data, error } = await query;
  if (error) {
    grid.innerHTML = `<div class="empty-state"><div class="icon">❌</div>Error al cargar patios.</div>`;
    return;
  }

  const ownerIds = [...new Set((data || []).map(p => p.propietario_id).filter(Boolean))];
  let ownerMap = {};
  if (ownerIds.length) {
    const { data: perfiles } = await sb.from('perfiles').select('user_id, nombre').in('user_id', ownerIds);
    (perfiles || []).forEach(p => { ownerMap[p.user_id] = p.nombre; });
  }
  const patios = (data || []).map(p => ({ ...p, empresaNombre: ownerMap[p.propietario_id] || '—' }));

  const disp = patios.filter(p => p.estado === 'disponible').length;
  const ocup = patios.filter(p => p.estado === 'ocupado').length;
  const mant = patios.filter(p => p.estado === 'mantenimiento').length;

  stats.innerHTML = `
    <div class="stat-card"><div class="stat-num green">${disp}</div><div class="stat-label">Disponibles</div></div>
    <div class="stat-card"><div class="stat-num amber">${ocup}</div><div class="stat-label">Ocupados</div></div>
    <div class="stat-card"><div class="stat-num red">${mant}</div><div class="stat-label">Mantenimiento</div></div>
    <div class="stat-card"><div class="stat-num" style="color:var(--accent-bright)">${patios.length}</div><div class="stat-label">Total</div></div>`;
  count.textContent = `— ${disp} de ${patios.length}`;

  if (!patios.length) {
    grid.innerHTML = `<div class="empty-state"><div class="icon">🏭</div>No se encontraron patios.</div>`;
    return;
  }

  grid.innerHTML = patios.map(p => {
    const badgeClass = p.estado === 'disponible' ? 'badge-avail' : p.estado === 'ocupado' ? 'badge-busy' : 'badge-maint';
    const label      = p.estado === 'disponible' ? '✓ Disponible' : p.estado === 'ocupado' ? '⏳ Ocupado' : '🔧 Mantenimiento';
    const disabled   = p.estado !== 'disponible' ? 'disabled' : '';
    const emoji      = PATIO_EMOJI[p.tipo] || '🏭';
    const svcs       = (p.servicios || []).map(s => `<span class="cargo-chip">${esc(s)}</span>`).join('');
    const precio     = p.precio_dia ? `<div class="truck-precio">$${Number(p.precio_dia).toLocaleString('es-MX')} MXN / día</div>` : '';
    return `
      <div class="truck-card">
        <div class="truck-header">
          <div>
            <div class="truck-id">${esc(p.id)}</div>
            <div class="truck-type">${emoji} ${esc(p.tipo)}</div>
            <div class="truck-empresa">🏢 ${esc(p.empresaNombre)}</div>
          </div>
          <div class="badge ${badgeClass}">${label}</div>
        </div>
        <div class="truck-img-area" style="font-size:2.8rem">${emoji}</div>
        <div class="truck-specs">
          <div class="spec-item"><div class="spec-label">Nombre</div><div class="spec-value">${esc(p.nombre)}</div></div>
          <div class="spec-item"><div class="spec-label">Tipo</div><div class="spec-value">${esc(p.tipo)}</div></div>
          ${p.area_m2 ? `<div class="spec-item"><div class="spec-label">Área</div><div class="spec-value">${Number(p.area_m2).toLocaleString('es-MX')} m²</div></div>` : ''}
          ${p.capacidad_vehiculos ? `<div class="spec-item"><div class="spec-label">Cap. vehículos</div><div class="spec-value">${p.capacidad_vehiculos} uds.</div></div>` : ''}
        </div>
        ${p.ubicacion ? `<div class="recurso-desc">📍 ${esc(p.ubicacion)}</div>` : ''}
        ${svcs ? `<div class="recurso-chips">${svcs}</div>` : ''}
        ${precio}
        <div class="truck-footer">
          ${currentUser.rol === 'cliente' || !currentUser.id
            ? `<button class="btn-reservar" onclick="openNuevoPedido()" title="Publica una solicitud y los proveedores te harán ofertas">📋 Solicitar</button>`
            : `<button class="btn-reservar" ${disabled} onclick="openReservaRecurso('patio','${esc(p.id)}','${esc(p.nombre)}','${p.propietario_id||''}')">Reservar</button>`
          }
        </div>
      </div>`;
  }).join('');
}

// openReservaRecurso() está definido en modal.js
