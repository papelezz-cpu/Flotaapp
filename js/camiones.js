// ── FLOTA / CAMIONES ──────────────────────────────────

let allCamiones = [];
let currentRecursoTipo = 'camion'; // 'camion' | 'custodio' | 'patio'

const RECURSO_FILTRO_OPTS = {
  camion:   [['','Todos los tipos'],['Torton','Torton'],['Rabón','Rabón'],['Full','Full'],['Plataforma','Plataforma']],
  custodio: [['','Todos los tipos'],['Armado','Armado'],['Sin arma','Sin arma'],['Motorizado','Motorizado'],['K9','K9'],['Supervisión remota','Supervisión remota']],
  patio:    [['','Todos los tipos'],['Techado','Techado'],['Abierto','Abierto'],['Refrigerado','Refrigerado'],['Especializado','Especializado'],['Bodega','Bodega']],
};

const RECURSO_LABELS = {
  camion:   { filtro: 'Tipo de camión',    titulo: '🚛 Camiones disponibles' },
  custodio: { filtro: 'Tipo de custodio',  titulo: '👮 Custodios disponibles' },
  patio:    { filtro: 'Tipo de patio',     titulo: '🏭 Patios disponibles' },
};

function cambiarTipoRecurso(tipo) {
  currentRecursoTipo = tipo;

  ['camion','custodio','patio'].forEach(t => {
    document.getElementById(`tab-${t}`)?.classList.toggle('active', t === tipo);
  });

  const meta = RECURSO_LABELS[tipo];
  const lbl  = document.getElementById('filtro-tipo-label');
  const sel  = document.getElementById('filtro-tipo');
  if (lbl) lbl.textContent = meta.filtro;
  if (sel) sel.innerHTML   = (RECURSO_FILTRO_OPTS[tipo] || []).map(([v,t]) =>
    `<option value="${v}">${t}</option>`).join('');

  const title = document.getElementById('recursos-titulo');
  if (title) title.innerHTML = `${meta.titulo} <span id="count-label"></span>`;

  // Show/hide dates row (only relevant for camiones)
  const datesRow = document.getElementById('search-dates-row');
  if (datesRow) datesRow.style.display = tipo === 'camion' ? '' : 'none';

  filtrarRecursos();
}

function filtrarRecursos() {
  const tipo     = document.getElementById('filtro-tipo').value;
  const fechaIni = document.getElementById('fecha-inicio').value;
  const fechaFin = document.getElementById('fecha-fin').value;
  if (currentRecursoTipo === 'custodio') renderCustodios(tipo);
  else if (currentRecursoTipo === 'patio') renderPatios(tipo);
  else renderCamiones(tipo, fechaIni, fechaFin);
}

async function renderCamiones(filtroTipo = '', fechaIni = '', fechaFin = '') {
  const grid  = document.getElementById('truck-grid');
  const stats = document.getElementById('stats-row');

  grid.innerHTML = skeletonGrid(6);

  let query = sb.from('camiones').select('*').eq('aprobacion', 'aprobada').order('id');
  if (filtroTipo) query = query.eq('tipo', filtroTipo);
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

  // ── Filtro por fechas: buscar qué camiones tienen reservas que se traslapan ──
  let busyIds = new Set();
  const buscarPorFecha = fechaIni && fechaFin;
  if (buscarPorFecha) {
    const { data: reservas } = await sb.from('reservaciones')
      .select('unidad')
      .in('estado', ['Activa', 'Pendiente'])
      .lte('fecha_ini', fechaFin)   // la reserva empieza antes del fin buscado
      .gte('fecha_fin', fechaIni);  // la reserva termina después del inicio buscado
    (reservas || []).forEach(r => busyIds.add(r.unidad));
  }

  // ── Stats (basados en estado real del camión, no en fechas) ──
  const disp = data.filter(c => c.estado === 'disponible').length;
  const ocup = data.filter(c => c.estado === 'ocupado').length;
  const mant = data.filter(c => c.estado === 'mantenimiento').length;

  stats.innerHTML = `
    <div class="stat-card"><div class="stat-num green">${disp}</div><div class="stat-label">Disponibles</div></div>
    <div class="stat-card"><div class="stat-num amber">${ocup}</div><div class="stat-label">En servicio</div></div>
    <div class="stat-card"><div class="stat-num red">${mant}</div><div class="stat-label">Mantenimiento</div></div>
    <div class="stat-card"><div class="stat-num" style="color:var(--accent-bright)">${data.length}</div><div class="stat-label">Total unidades</div></div>
  `;

  const disponibles = buscarPorFecha
    ? allCamiones.filter(c => c.estado !== 'mantenimiento' && !busyIds.has(c.id)).length
    : disp;
  const countEl = document.getElementById('count-label');
  if (countEl) countEl.textContent = buscarPorFecha
    ? `— ${disponibles} disponibles para esas fechas`
    : `— ${disp} de ${data.length}`;

  if (data.length === 0) {
    grid.innerHTML = `<div class="empty-state"><div class="icon">🔍</div>No se encontraron unidades.</div>`;
    return;
  }

  grid.innerHTML = allCamiones.map(c => {
    // Si se buscó por fechas, el badge refleja disponibilidad para esas fechas
    let estadoEfectivo = c.estado;
    if (buscarPorFecha && c.estado !== 'mantenimiento') {
      estadoEfectivo = busyIds.has(c.id) ? 'ocupado' : 'disponible';
    }

    const badgeClass = estadoEfectivo === 'disponible' ? 'badge-avail'
                     : estadoEfectivo === 'ocupado'    ? 'badge-busy'
                     : 'badge-maint';
    const label      = estadoEfectivo === 'disponible' ? '✓ Disponible'
                     : estadoEfectivo === 'ocupado'    ? '⏳ En servicio'
                     : '🔧 Mantenimiento';
    const disabled   = estadoEfectivo !== 'disponible' ? 'disabled' : '';
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
          <div class="spec-item"><div class="spec-label">Unidad</div><div class="spec-value">${esc(c.id)}</div></div>
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

// Alias de compatibilidad
function filtrarCamiones() { filtrarRecursos(); }

// openDetail() está definido en detalle.js
