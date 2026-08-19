// ── RESERVACIONES ─────────────────────────────────────

// Filtro de estado de la vista de reservaciones. Por defecto "Activa": al
// entrar desde el cuadro del home se ven primero las activas; los demás
// estados se ven con las pills.
let _reservFiltro = 'Activa';

// Ids de reservación con el panel de acciones secundarias abierto. Se guarda
// aparte del DOM porque renderReserv() se vuelve a llamar seguido (realtime,
// notificaciones) y sin esto cada refresh cerraría lo que el usuario acababa
// de abrir.
const _reservAbiertas = new Set();

function toggleReservDetalle(id) {
  const panel  = document.getElementById(`reserv-detalle-${id}`);
  const toggle = document.getElementById(`reserv-toggle-${id}`);
  if (!panel || !toggle) return;
  const abrir = !panel.classList.contains('open');
  panel.classList.toggle('open', abrir);
  toggle.classList.toggle('open', abrir);
  toggle.setAttribute('aria-expanded', abrir ? 'true' : 'false');
  if (abrir) _reservAbiertas.add(id); else _reservAbiertas.delete(id);
}

const _RESERV_FILTRO_LABEL = {
  Activa: 'activas', Pendiente: 'pendientes', PorAprobar: 'por aprobar', Completada: 'completadas',
  Cancelada: 'canceladas', CancelacionSolicitada: 'con cancelación en revisión', PorCobrar: 'por cobrar', Vencido: 'con pago vencido', todas: '',
};

// Texto legible del estado (la DB guarda 'PorAprobar' sin espacio)
const _ESTADO_LABEL = { PorAprobar: 'Por aprobar', CancelacionSolicitada: 'Cancelación en revisión' };
const _estadoLabel = estado => _ESTADO_LABEL[estado] || estado;

function _aplicaFiltroReserva(rows) {
  if (_reservFiltro === 'todas') return rows;
  if (_reservFiltro === 'Cancelada') return rows.filter(r => r.estado === 'Cancelada' || r.estado === 'Rechazada');
  // Filtros de cobro: se apoyan en el estado derivado (ver js/cobros.js)
  if (_reservFiltro === 'PorCobrar') return rows.filter(r => estadoCobro(r)?.clave === 'por_cobrar');
  if (_reservFiltro === 'Vencido')   return rows.filter(r => estadoCobro(r)?.clave === 'vencido');
  return rows.filter(r => r.estado === _reservFiltro);
}

function filtrarReservas(est) {
  _reservFiltro = est;
  document.querySelectorAll('#reserv-filtros-bar .ped-filtro-pill').forEach(el =>
    el.classList.toggle('active', el.dataset.rest === est));
  renderReserv();
}

async function renderReserv() {
  const body   = document.getElementById('reserv-body');
  const header = document.getElementById('reserv-header');
  body.innerHTML = skeletonRows(4);

  // Sincronizar las pills con el filtro activo (p. ej. al llegar desde el home)
  document.querySelectorAll('#reserv-filtros-bar .ped-filtro-pill').forEach(el =>
    el.classList.toggle('active', el.dataset.rest === _reservFiltro));

  // Sin sesión
  if (!currentUser.id) {
    body.innerHTML = `<div class="empty-state"><div class="icon">🔒</div>Inicia sesión para ver tus reservaciones.</div>`;
    return;
  }

  // ── VISTA CLIENTE (solo sus propias reservas, solo lectura) ──
  if (currentUser.rol === 'cliente') {
    header.innerHTML = `<div>Unidad</div><div>Empresa</div><div>Inicio</div><div>Fin</div><div>Estado</div>`;
    header.classList.add('cli');

    const { data: _allCli, error } = await sb.from('reservaciones')
      .select('*')
      .eq('cliente_email', currentUser.email)
      .order('created_at', { ascending: false });

    if (error) { body.innerHTML = `<div class="empty-state"><div class="icon">❌</div>Error al cargar.</div>`; return; }
    const data = _aplicaFiltroReserva(_allCli || []);
    if (!data.length) {
      const lbl = _RESERV_FILTRO_LABEL[_reservFiltro] || '';
      body.innerHTML = `<div class="empty-state"><div class="icon">📋</div>No tienes reservaciones${lbl ? ' ' + lbl : ''}.</div>`;
      return;
    }

    // Obtener empresa según tipo de recurso
    const camionIds   = data.filter(r => !r.recurso_tipo || r.recurso_tipo === 'camion').map(r => r.unidad).filter(Boolean);
    const custodioIds = data.filter(r => r.recurso_tipo === 'custodio').map(r => r.unidad).filter(Boolean);
    const patioIds    = data.filter(r => r.recurso_tipo === 'patio').map(r => r.unidad).filter(Boolean);

    const empresaMap = {};
    const recursoNombreMap = {};
    const ownerIdMap = {};  // recurso id → propietario_id (para chat)

    // Recopilar propietario_ids de cada tipo, luego query perfiles por separado
    const propIdMap = {};  // recurso_id → propietario_id

    const fetches = [];
    if (camionIds.length) fetches.push(
      sb.from('camiones').select('id, propietario_id').in('id', camionIds)
        .then(({ data: d }) => (d || []).forEach(c => { propIdMap[c.id] = c.propietario_id; }))
    );
    if (custodioIds.length) fetches.push(
      sb.from('custodios').select('id, nombre, propietario_id').in('id', custodioIds)
        .then(({ data: d }) => (d || []).forEach(c => {
          propIdMap[c.id] = c.propietario_id;
          recursoNombreMap[c.id] = `👮 ${c.nombre}`;
        }))
    );
    if (patioIds.length) fetches.push(
      sb.from('patios').select('id, nombre, propietario_id').in('id', patioIds)
        .then(({ data: d }) => (d || []).forEach(p => {
          propIdMap[p.id] = p.propietario_id;
          recursoNombreMap[p.id] = `🏭 ${p.nombre}`;
        }))
    );
    await Promise.all(fetches);

    // Query directa a perfiles por user_id (evita problemas de RLS con joins)
    const uniquePropIds = [...new Set(Object.values(propIdMap).filter(Boolean))];
    if (uniquePropIds.length) {
      const { data: perfs } = await sb.from('perfiles').select('user_id, nombre').in('user_id', uniquePropIds);
      const perfMap = {};
      (perfs || []).forEach(p => { perfMap[p.user_id] = p.nombre; });
      Object.entries(propIdMap).forEach(([recursoId, propId]) => {
        empresaMap[recursoId] = perfMap[propId] || '—';
        ownerIdMap[recursoId] = propId;
      });
    }

    // Los expedientes documentales de todas las filas, en una sola consulta.
    if (typeof cargarExpedientes === 'function') await cargarExpedientes(data);

    body.innerHTML = data.map(r => {
      const badgeCls = r.estado === 'Pendiente'   ? 'badge-busy'
                     : r.estado === 'Activa'      ? 'badge-avail'
                     : r.estado === 'PorAprobar'  ? 'badge-acuerdo-rev'
                     : r.estado === 'CancelacionSolicitada' ? 'badge-revision'
                     : r.estado === 'Completada'  ? 'badge-completado'
                     : 'badge-maint';
      const trackBtn = r.estado === 'Activa'
        ? `<button class="btn-edit" onclick="openTracking('${r.id}')" style="font-size:0.7rem">📍 ${esc(r.tracking_estado || 'Confirmado')}</button>`
        : '';
      // El GPS solo se muestra una vez que el viaje realmente arrancó (mismo
      // punto en que ya se exige tener chofer asignado) — antes de eso el
      // link no sirve de nada.
      const primerPasoKey = (typeof _getEstados === 'function' ? _getEstados(r.recurso_tipo)[0]?.key : 'Confirmado') || 'Confirmado';
      const gpsBtnCli = (r.estado === 'Activa' && r.gps_link && r.tracking_estado && r.tracking_estado !== primerPasoKey)
        ? `<a href="${esc(r.gps_link)}" target="_blank" class="btn-edit" style="font-size:0.7rem">📍 Ver ubicación en vivo</a>`
        : '';
      // Cancelar un acuerdo ya aprobado no es unilateral: se solicita y el
      // superadmin decide (ver solicitarCancelacion).
      const cancelBtn = r.estado === 'Activa'
        ? `<button class="btn-cancelar-reserva" style="font-size:0.7rem" onclick="solicitarCancelacion('${r.id}')">Solicitar cancelación</button>`
        : r.estado === 'CancelacionSolicitada'
          ? `<span style="font-size:0.7rem;color:var(--text-muted)">⏳ Cancelación en revisión</span>`
          : '';
      // El servicio se cierra cuando cliente Y empresa marcan completado (cada
      // quien sube su propia evidencia) y el superadmin aprueba la revisión.
      const miEvidenciaCli = r.evidencias_cliente?.length || 0;
      const completarBtn = r.estado === 'Activa'
        ? `<button class="btn-completar-reserva" style="font-size:0.7rem" onclick="abrirEvidencias('${r.id}','evidencias_cliente')">✓ Marcar completado</button>`
        : r.estado === 'PorAprobar'
          ? (miEvidenciaCli
              ? `<span style="font-size:0.7rem;color:var(--text-muted)">⏳ Esperando aprobación</span>`
              : `<button class="btn-completar-reserva" style="font-size:0.7rem" onclick="abrirEvidencias('${r.id}','evidencias_cliente')">📎 Subir mi evidencia</button>`)
          : '';
      const unidadLabel = recursoNombreMap[r.unidad] || esc(r.unidad) || '—';
      const propId = ownerIdMap[r.unidad] || r.propietario_id || '';
      const calBtn = (r.estado === 'Completada' && !r.calificado && propId)
        ? `<button class="btn-calificar" onclick="openCalificar('${r.id}','${propId}','${escJs(empresaMap[r.unidad]||'')}')">⭐ Calificar</button>`
        : '';
      // El cliente ve su estado de cobro: pagado, por cobrar o vencido.
      const pagoLbl = cobroBadgeHTML(r);
      const precioLbl = r.precio_acordado
        ? `<span style="font-size:0.7rem;color:var(--text-muted)">$${Number(r.precio_acordado).toLocaleString('es-MX')} MXN</span>`
        : '';
      const pagarBtn = (r.estado === 'Activa' && !r.pagado)
        ? `<button class="btn-prox" disabled title="Pagos en línea — próximamente">💳 Pagar <span class="prox-badge">Prox.</span></button>`
        : '';
      // Carta Porte / documentos de carga y maniobra: subida libre, sin
      // checklist, disponible en cuanto hay match (la reservación existe).
      const numDocsCarga = r.documentos_carga?.length || 0;
      const cartaPorteBtn = `<button class="btn-edit" style="font-size:0.7rem" onclick="abrirDocumentosCarga('${r.id}')">📄 ${numDocsCarga ? `Documentos (${numDocsCarga})` : 'Carta Porte / documentos'}</button>`;
      const expedientePills = typeof expedienteBotonesHTML === 'function' ? expedienteBotonesHTML(r, true) : '';
      const abierta = _reservAbiertas.has(r.id);
      const grupo = (label, html) => html ? `
        <div class="reserv-detail-group">
          <span class="reserv-detail-group-label">${label}</span>
          <div class="reserv-detail-group-btns">${html}</div>
        </div>` : '';
      return `
      <div class="reserv-item">
      <div class="reserv-row reserv-row-cli">
        <div class="reserv-id">${unidadLabel}</div>
        <div class="reserv-empresa">${esc(empresaMap[r.unidad] || '—')}</div>
        <div>${fmtFecha(r.fecha_ini)}</div>
        <div>${fmtFecha(r.fecha_fin)}</div>
        <div style="display:flex;gap:5px;align-items:center;flex-wrap:wrap">
          <span class="badge ${badgeCls}">${esc(_estadoLabel(r.estado))}</span>
          ${trackBtn}
          ${pagoLbl}
          <button id="reserv-toggle-${r.id}" class="reserv-toggle${abierta ? ' open' : ''}" aria-expanded="${abierta}" title="Más acciones" onclick="toggleReservDetalle('${r.id}')">▾</button>
        </div>
      </div>
      <div id="reserv-detalle-${r.id}" class="reserv-detail${abierta ? ' open' : ''}">
        ${grupo('Operación', gpsBtnCli)}
        ${grupo('Documentos', cartaPorteBtn + expedientePills)}
        ${grupo('Pago', precioLbl + pagarBtn)}
        ${grupo('Avisos', r.estado === 'Activa' ? `<button class="btn-edit" onclick="abrirReportarCambio('${r.id}')" title="Avisar a la empresa que algo cambió o hay un problema">⚠ Reportar cambio o problema</button>` : '')}
        ${grupo('Cierre', completarBtn + calBtn + cancelBtn)}
      </div>
      </div>`;
    }).join('');
    return;
  }

  // ── VISTA ADMIN / SUPERADMIN ──
  header.innerHTML = `<div>Unidad</div><div>Empresa</div><div>Cliente</div><div>Inicio</div><div>Fin</div><div>Estado</div>`;
  header.classList.remove('cli');

  let reservQuery = sb.from('reservaciones')
    .select('*')
    .order('created_at', { ascending: false });

  if (currentUser.rol !== 'superadmin') {
    reservQuery = reservQuery.eq('propietario_id', currentUser.id);
  }

  const { data: _allAdm, error } = await reservQuery;
  if (error) { body.innerHTML = `<div class="empty-state"><div class="icon">❌</div>Error al cargar.</div>`; return; }
  const data = _aplicaFiltroReserva(_allAdm || []);
  if (!data.length) {
    const lbl = _RESERV_FILTRO_LABEL[_reservFiltro] || '';
    body.innerHTML = `<div class="empty-state"><div class="icon">📋</div>No hay reservaciones${lbl ? ' ' + lbl : ''}.</div>`;
    return;
  }

  // Construir mapa de empresa y etiqueta por tipo de recurso
  const camionIds   = [...new Set(data.filter(r => !r.recurso_tipo || r.recurso_tipo === 'camion').map(r => r.unidad).filter(Boolean))];
  const custodioIds = [...new Set(data.filter(r => r.recurso_tipo === 'custodio').map(r => r.unidad).filter(Boolean))];
  const patioIds    = [...new Set(data.filter(r => r.recurso_tipo === 'patio').map(r => r.unidad).filter(Boolean))];

  const empresaMap      = {};
  const ownerMap        = {};
  const recursoLabelMap = {};
  const propIdMap2      = {};  // recurso_id → propietario_id

  const fetches = [];
  if (camionIds.length) fetches.push(
    sb.from('camiones').select('id, propietario_id').in('id', camionIds)
      .then(({ data: d }) => (d || []).forEach(c => {
        propIdMap2[c.id] = c.propietario_id;
        ownerMap[c.id]   = c.propietario_id;
      }))
  );
  if (custodioIds.length) fetches.push(
    sb.from('custodios').select('id, nombre, propietario_id').in('id', custodioIds)
      .then(({ data: d }) => (d || []).forEach(c => {
        propIdMap2[c.id]      = c.propietario_id;
        ownerMap[c.id]        = c.propietario_id;
        recursoLabelMap[c.id] = `👮 ${c.nombre}`;
      }))
  );
  if (patioIds.length) fetches.push(
    sb.from('patios').select('id, nombre, propietario_id').in('id', patioIds)
      .then(({ data: d }) => (d || []).forEach(p => {
        propIdMap2[p.id]      = p.propietario_id;
        ownerMap[p.id]        = p.propietario_id;
        recursoLabelMap[p.id] = `🏭 ${p.nombre}`;
      }))
  );
  await Promise.all(fetches);

  // Query directa a perfiles
  const uniquePropIds2 = [...new Set(Object.values(propIdMap2).filter(Boolean))];
  if (uniquePropIds2.length) {
    const { data: perfs } = await sb.from('perfiles').select('user_id, nombre').in('user_id', uniquePropIds2);
    const perfMap2 = {};
    (perfs || []).forEach(p => { perfMap2[p.user_id] = p.nombre; });
    Object.entries(propIdMap2).forEach(([recursoId, propId]) => {
      empresaMap[recursoId] = perfMap2[propId] || '—';
    });
  }

  // Los expedientes documentales de todas las filas, en una sola consulta.
  // renderReserv tiene DOS rutas de render —cliente y empresa/superadmin— y
  // las dos necesitan esto: si solo se carga en una, la otra ve el botón de
  // "Solicitar documentación" para siempre porque nunca se entera de que el
  // expediente ya existe.
  if (typeof cargarExpedientes === 'function') await cargarExpedientes(data);

  body.innerHTML = data.map(r => {
    const esCancelada = r.estado === 'Cancelada';
    const esRechazada = r.estado === 'Rechazada';
    const esPendiente = r.estado === 'Pendiente';
    const esActiva    = r.estado === 'Activa';
    const inactiva    = esCancelada || esRechazada;

    const esCompletada  = r.estado === 'Completada';
    const esPorAprobar  = r.estado === 'PorAprobar';
    const badgeCls = r.estado === 'CancelacionSolicitada' ? 'badge-revision'
                   : esPendiente   ? 'badge-busy'
                   : esActiva      ? 'badge-avail'
                   : esPorAprobar  ? 'badge-acuerdo-rev'
                   : esCompletada  ? 'badge-acordado'
                   : 'badge-maint';

    const esDueno = currentUser.rol === 'superadmin' || ownerMap[r.unidad] === currentUser.id || r.propietario_id === currentUser.id;

    // Fila compacta: solo lo decisivo a simple vista. Todo lo demás
    // (chofer, unidad, GPS, documentos, cierre) vive en el panel expandible
    // — ver toggleReservDetalle. Pendiente se deja tal cual: son solo 2
    // botones y ambos son la decisión que importa, no hay nada que ocultar.
    let primaria = '';
    const gruposDetalle = [];
    const grupo = (label, html) => { if (html) gruposDetalle.push({ label, html }); };

    if (esDueno && esPendiente) {
      primaria = `
        <button class="btn-aceptar-reserva"  onclick="aceptarReserva('${r.id}','${escJs(r.unidad)}','${r.recurso_tipo||'camion'}')">✓ Aceptar</button>
        <button class="btn-rechazar-reserva" onclick="rechazarReserva('${r.id}','${escJs(r.unidad)}')">✕ Rechazar</button>`;
    } else if (esDueno && esActiva) {
      const trackStep = r.tracking_estado || 'Confirmado';
      // El chofer ya no es obligatorio al ofertar: se asigna aquí, en
      // cualquier momento mientras el viaje sigue Activo. El tracking no
      // deja avanzar del primer paso sin uno asignado (ver tracking.js) —
      // por eso, si falta, se marca en la fila y no solo adentro del panel.
      const esCamion = r.recurso_tipo === 'camion' || !r.recurso_tipo;
      const choferFalta = esCamion && !r.operador_nombre;
      const choferBtn = esCamion
        ? `<button class="btn-edit" onclick="abrirAsignarChofer('${r.id}')" title="${r.operador_nombre ? 'Cambiar chofer' : 'Asignar chofer antes de iniciar el viaje'}">👷 ${r.operador_nombre ? esc(r.operador_nombre) : 'Asignar chofer'}</button>`
        : '';
      // El link se puede guardar en cualquier momento; el cliente solo lo ve
      // una vez que el tracking avanzó del primer paso (ver vista cliente).
      const gpsBtn = `<button class="btn-edit" onclick="abrirGpsLink('${r.id}')" title="Link de GPS temporal">🛰️ GPS${r.gps_link ? ' ✓' : ''}</button>`;
      const numDocsCargaDueno = r.documentos_carga?.length || 0;
      const docsCargaBtnDueno = `<button class="btn-edit" onclick="abrirDocumentosCarga('${r.id}')" title="Ver Carta Porte y documentos que subió el cliente">📄 ${numDocsCargaDueno ? `Documentos (${numDocsCargaDueno})` : 'Documentos del cliente'}</button>`;
      const expedientePillsActiva = typeof expedienteBotonesHTML === 'function'
        ? expedienteBotonesHTML(r, r.cliente_user_id === currentUser.id) : '';

      primaria = `
        <button class="btn-edit" onclick="openTracking('${r.id}')" title="Ver seguimiento">📍 ${esc(trackStep)}</button>
        ${choferFalta ? `<span class="reserv-warn-chip" title="Bloquea avanzar el seguimiento">⚠ Sin chofer</span>` : ''}`;
      grupo('Operación', choferBtn + `<button class="btn-edit" onclick="abrirCambiarUnidad('${r.id}')" title="Reasignar a otra unidad (p. ej. si se descompuso)">🔧 Cambiar unidad</button>` + gpsBtn);
      grupo('Documentos', docsCargaBtnDueno + expedientePillsActiva);
      // Avisos al cliente sin necesidad de chat: un aviso puntual (campana +
      // correo) en vez de un mensaje libre.
      grupo('Avisos', `<button class="btn-edit" onclick="confirmarLugarHora('${r.id}')" title="Pedirle al cliente que confirme lugar y hora">📍 Confirmar lugar y hora</button>` +
        `<button class="btn-edit" onclick="avisarRetraso('${r.id}')" title="Avisar que el transporte va a llegar tarde">⏰ Avisar retraso</button>`);
      grupo('Cierre', `<button class="btn-completar-reserva" onclick="abrirEvidencias('${r.id}','evidencias')">✓ Completar</button>` +
        `<button class="btn-cancelar-reserva" onclick="cancelarReserva('${r.id}','${escJs(r.unidad)}')">Cancelar</button>`);
    } else if (esDueno && esPorAprobar) {
      // El servicio se cierra cuando cliente Y empresa marcan completado (cada
      // quien sube su propia evidencia); el superadmin aprueba la revisión.
      const miEvidencia = r.evidencias?.length || 0;
      primaria = miEvidencia
        ? `<span style="font-size:0.72rem;color:var(--text-muted)">⏳ Esperando aprobación del superadmin</span>`
        : `<button class="btn-completar-reserva" style="font-size:0.72rem" onclick="abrirEvidencias('${r.id}','evidencias')">📎 Subir mi evidencia</button>`;
      const expedientePillsAprobar = typeof expedienteBotonesHTML === 'function'
        ? expedienteBotonesHTML(r, r.cliente_user_id === currentUser.id) : '';
      grupo('Documentos', expedientePillsAprobar);
    } else if (esDueno && esCompletada) {
      const diasPasados = r.completado_en
        ? Math.floor((new Date() - new Date(r.completado_en)) / 86400000) : 99;
      const numEv = r.evidencias?.length || 0;
      const evBtnLabel = numEv > 0 ? `📎 Evidencias (${numEv})` : '📎 Subir evidencias';
      const evBtn = diasPasados <= 5 || numEv > 0
        ? `<button class="btn-edit" style="font-size:0.72rem" onclick="abrirEvidencias('${r.id}','evidencias')">${evBtnLabel}</button>`
        : '';
      // Cobro: quien recibe el dinero (la empresa) o el superadmin lo registra.
      const cobroBtn = r.pagado
        ? `<button class="btn-edit" style="font-size:0.72rem" title="Revertir el cobro registrado" onclick="revertirPago('${r.id}')">↩ Revertir cobro</button>`
        : `<button class="btn-edit" style="font-size:0.72rem;color:var(--amber);border-color:rgba(245,158,11,0.4)" onclick="abrirRegistrarPago('${r.id}')">💰 Registrar pago</button>`;
      primaria = cobroBadgeHTML(r);
      grupo('Cierre', cobroBtn + evBtn);
    }

    const unidadLabel = recursoLabelMap[r.unidad] || esc(r.unidad) || '—';
    // Eliminar (mover a histórico) — solo superadmin. No es una acción de
    // todos los días: va al panel, no a la fila.
    if (currentUser.rol === 'superadmin') {
      grupo('Superadmin', `<button class="btn-edit btn-rechazar" style="font-size:0.72rem" onclick="eliminarReserva('${r.id}')">🗑 Eliminar</button>`);
    }

    const abierta = _reservAbiertas.has(r.id);
    const detalleHTML = gruposDetalle.map(g => `
        <div class="reserv-detail-group">
          <span class="reserv-detail-group-label">${g.label}</span>
          <div class="reserv-detail-group-btns">${g.html}</div>
        </div>`).join('');

    return `
    <div class="reserv-item">
    <div class="reserv-row ${inactiva ? 'reserv-cancelada' : ''}">
      <div class="reserv-id">${unidadLabel}</div>
      <div class="reserv-empresa">${esc(empresaMap[r.unidad] || '—')}</div>
      <div>${esc(r.cliente)}</div>
      <div>${fmtFecha(r.fecha_ini)}</div>
      <div>${fmtFecha(r.fecha_fin)}</div>
      <div style="display:flex;gap:5px;align-items:center;flex-wrap:wrap">
        <span class="badge ${badgeCls}">${esc(_estadoLabel(r.estado))}</span>
        ${primaria}
        ${detalleHTML ? `<button id="reserv-toggle-${r.id}" class="reserv-toggle${abierta ? ' open' : ''}" aria-expanded="${abierta}" title="Más acciones" onclick="toggleReservDetalle('${r.id}')">▾</button>` : ''}
      </div>
    </div>
    ${detalleHTML ? `<div id="reserv-detalle-${r.id}" class="reserv-detail${abierta ? ' open' : ''}">${detalleHTML}</div>` : ''}
    </div>`;
  }).join('');
}

// ── ACCIONES ───────────────────────────────────────────

let _reservaActiva = false; // guard anti-double-click

async function aceptarReserva(reservaId, unidad, recurso_tipo) {
  if (_reservaActiva) return;
  _reservaActiva = true;
  // Obtener datos antes de actualizar para el email
  const { data: r } = await sb.from('reservaciones').select('*').eq('id', reservaId).single();
  const tipoFinal = recurso_tipo || r?.recurso_tipo || 'camion';
  await sb.from('reservaciones').update({ estado: 'Activa' }).eq('id', reservaId);

  // Notificar al cliente que su reservación fue aceptada
  if (r?.cliente_user_id) {
    await sb.from('notificaciones').insert({
      user_id: r.cliente_user_id,
      tipo:    'reserva_aceptada',
      titulo:  '✓ Reservación confirmada',
      mensaje: `${currentUser.nombre} confirmó tu servicio de ${r?.descripcion ? '' : ''}. Revisa tus reservaciones para más detalles.`,
      leido:   false,
    });
  }

  // Marcar recurso como ocupado solo si ya inició y es un camión
  const fechaIni = r?.fecha_ini ? r.fecha_ini.split('T')[0] : null;
  if (tipoFinal === 'camion' && fechaIni && fechaIni <= today()) {
    await sb.from('camiones').update({ estado: 'ocupado' }).eq('id', unidad);
  } else if (tipoFinal === 'custodio' && fechaIni && fechaIni <= today()) {
    await sb.from('custodios').update({ estado: 'ocupado' }).eq('id', unidad);
  } else if (tipoFinal === 'patio' && fechaIni && fechaIni <= today()) {
    await sb.from('patios').update({ estado: 'ocupado' }).eq('id', unidad);
  }

  // Email al cliente: reserva aceptada (con CC al superadmin)
  _enviarEmail('reserva_aceptada', {
    clienteEmail:  r?.cliente_email,
    clienteNombre: r?.cliente,
    camion: unidad,
    empresa: currentUser.nombre,
    fecha_ini: r?.fecha_ini,
    fecha_fin: r?.fecha_fin
  });

  _reservaActiva = false;
  await renderReserv();
  await loadNotificaciones();
  const recursoLabel = tipoFinal === 'custodio' ? 'custodio' : tipoFinal === 'patio' ? 'patio' : 'camión';
  const toastMsg = fechaIni && fechaIni <= today()
    ? `✓ Reserva aceptada — ${recursoLabel} marcado como en servicio`
    : `✓ Reserva aceptada — el ${recursoLabel} quedará en servicio a partir del ` + fmtFecha(fechaIni);
  showToast(toastMsg);
}

function rechazarReserva(reservaId, unidad) {
  if (_reservaActiva) return;
  showConfirm('¿Rechazar esta solicitud de reserva?', async () => {
  _reservaActiva = true;
  const { data: r } = await sb.from('reservaciones').select('*').eq('id', reservaId).single();
  await sb.from('reservaciones').update({ estado: 'Rechazada' }).eq('id', reservaId);

  // Email al cliente: rechazada (con CC al superadmin)
  _enviarEmail('reserva_rechazada', {
    clienteEmail:  r?.cliente_email,
    clienteNombre: r?.cliente,
    camion: unidad,
    fecha_ini: r?.fecha_ini,
    fecha_fin: r?.fecha_fin
  });

  _reservaActiva = false;
  await renderReserv();
  await loadNotificaciones();
  showToast('Solicitud rechazada');
  }, { danger: true, confirmLabel: 'Rechazar' });
}

function cancelarReserva(reservaId, unidad) {
  if (_reservaActiva) return;
  showConfirm('¿Cancelar esta reserva? El recurso volverá a estar disponible y la solicitud se reabrirá para nuevas ofertas.', async () => {
    _reservaActiva = true;
    const { data: rv } = await sb.from('reservaciones').select('*').eq('id', reservaId).single();
    const tipoFinal = rv?.recurso_tipo || 'camion';

    // Cancelar la reserva
    await sb.from('reservaciones').update({ estado: 'Cancelada' }).eq('id', reservaId);

    // Liberar el recurso
    if (unidad) {
      const tabla = tipoFinal === 'custodio' ? 'custodios' : tipoFinal === 'patio' ? 'patios' : 'camiones';
      await sb.from(tabla).update({ estado: 'disponible' }).eq('id', unidad);
    }

    // Regresar el pedido a abierto para que puedan ofertar de nuevo
    if (rv?.pedido_id) {
      const { error: errPedido } = await sb.from('pedidos').update({
        estado:              'abierto',
        oferta_pendiente_id: null,
      }).eq('id', rv.pedido_id);
      if (errPedido) {
        _reservaActiva = false;
        showToast('La reserva se canceló, pero la solicitud no se pudo reabrir: ' + errPedido.message, 'error');
        await renderReserv();
        return;
      }

      // La oferta que ya estaba aceptada (la de quien canceló el viaje) queda
      // bloqueada para volver a ofertar en esta misma solicitud — canceló un
      // acuerdo ya cerrado, no es lo mismo que una oferta simplemente rechazada.
      await sb.from('ofertas')
        .update({ estado: 'rechazada', permite_reoferta: false })
        .eq('pedido_id', rv.pedido_id)
        .eq('estado', 'aceptada');

      // Las demás ofertas que seguían activas (de otras empresas) también se
      // invalidan para el ciclo de negociación anterior, pero sí podrán
      // volver a ofertar en la solicitud reabierta.
      await sb.from('ofertas')
        .update({ estado: 'rechazada' })
        .eq('pedido_id', rv.pedido_id)
        .in('estado', ['enviada', 'contra_oferta']);
    }

    // Notificar al cliente
    if (rv?.cliente_user_id) {
      await sb.from('notificaciones').insert({
        user_id: rv.cliente_user_id,
        tipo:    'reserva_cancelada',
        titulo:  'Reserva cancelada',
        mensaje: `Tu reserva fue cancelada por el proveedor. Tu solicitud está abierta de nuevo para recibir ofertas.`,
        leido:   false,
      });
    }

    // Notificar a superadmin — un acuerdo ya aprobado se cayó, debe saberlo
    const { data: supers } = await sb.from('perfiles').select('user_id').eq('rol', 'superadmin');
    if (supers?.length) {
      await sb.from('notificaciones').insert(supers.map(a => ({
        user_id: a.user_id,
        tipo:    'reserva_cancelada_admin',
        titulo:  'Un acuerdo aprobado se canceló',
        mensaje: `${esc(currentUser.nombre)} canceló la reserva con ${esc(rv?.cliente || 'un cliente')} después de que el acuerdo ya había sido aprobado. La solicitud volvió a estar abierta.`,
        leido:   false,
      })));
    }

    _reservaActiva = false;
    await renderReserv();
    showToast('Reserva cancelada — solicitud reabierta para nuevas ofertas');
  }, { danger: true, confirmLabel: 'Sí, cancelar' });
}

// ── ELIMINAR RESERVA (superadmin) → mover a histórico ──
function eliminarReserva(reservaId) {
  showConfirm('¿Archivar esta reservación? Se moverá al historial y desaparecerá de la lista activa.', async () => {

  // 1. Obtener la reservación completa
  const { data: r, error: fetchErr } = await sb.from('reservaciones').select('*').eq('id', reservaId).single();
  if (fetchErr || !r) { showToast('Error al obtener la reservación'); return; }

    // 2. Insertar en histórico
    const { error: insertErr } = await sb.from('reservaciones_historico').insert({
      id:              r.id,
      unidad:          r.unidad,
      recurso_tipo:    r.recurso_tipo,
      cliente:         r.cliente,
      cliente_email:   r.cliente_email,
      cliente_user_id: r.cliente_user_id,
      empresa:         r.empresa || null,
      fecha_ini:       r.fecha_ini,
      fecha_fin:       r.fecha_fin,
      descripcion:     r.descripcion,
      estado:          r.estado,
      tracking_estado: r.tracking_estado,
      created_at:      r.created_at,
      archivado_por:   currentUser.id,
      archivado_at:    new Date().toISOString(),
    });
    if (insertErr) { showToast('Error al archivar: ' + (insertErr.message || '')); return; }

    // 3. Eliminar de la tabla activa
    const { error: delErr } = await sb.from('reservaciones').delete().eq('id', reservaId);
    if (delErr) { showToast('Error al eliminar: ' + (delErr.message || '')); return; }

    await renderReserv();
    showToast('✓ Reservación archivada en el historial');
  });
}

// ── GPS TEMPORAL (empresa guarda, cliente ve al iniciar) ──
// La empresa puede guardar el link en cualquier momento mientras la reserva
// está Activa; el cliente solo lo ve una vez que el tracking avanzó del
// primer paso (ver el botón en la vista cliente de renderReserv).

async function abrirGpsLink(reservaId) {
  const { data: r } = await sb.from('reservaciones').select('gps_link').eq('id', reservaId).single();
  document.getElementById('gps-reserva-id').value = reservaId;
  document.getElementById('gps-link-input').value = r?.gps_link || '';
  document.getElementById('modal-gps-link').classList.add('open');
}

function cerrarGpsLink() {
  document.getElementById('modal-gps-link').classList.remove('open');
}

async function guardarGpsLink() {
  const reservaId = document.getElementById('gps-reserva-id').value;
  const link = document.getElementById('gps-link-input')?.value?.trim() || null;
  const { error } = await sb.from('reservaciones').update({ gps_link: link }).eq('id', reservaId);
  if (error) { showToast('No se pudo guardar: ' + error.message, 'error'); return; }
  cerrarGpsLink();
  await renderReserv();
  showToast(link ? '✓ Link de GPS guardado' : 'Link de GPS quitado');
}

// ── DOCUMENTOS DE CARGA (sube el cliente, ve la empresa) ──
// Carta Porte, documentos de maniobra, etc. — subida libre, sin checklist
// (a diferencia de los expedientes de puerto/vacíos). Disponible en cuanto
// hay match, sin importar el estado de la reservación. Solo el cliente
// sube (policy de storage + guard_reservacion_update); la empresa solo ve.

async function abrirDocumentosCarga(reservaId) {
  const { data: r } = await sb.from('reservaciones').select('documentos_carga, cliente_user_id').eq('id', reservaId).single();
  const soyCliente = r?.cliente_user_id === currentUser.id;

  document.getElementById('dc-reserva-id').value = reservaId;
  document.getElementById('dc-files').value = '';
  document.getElementById('dc-lista-actual').innerHTML = '<span style="color:var(--text-muted);font-size:0.82rem">Cargando…</span>';

  const subirWrap = document.getElementById('dc-subir-wrap');
  if (subirWrap) subirWrap.style.display = soyCliente ? '' : 'none';
  const btnSubir = document.getElementById('dc-btn-subir');
  if (btnSubir) btnSubir.style.display = soyCliente ? '' : 'none';
  const btnSolicitar = document.getElementById('dc-btn-solicitar');
  if (btnSolicitar) btnSolicitar.style.display = soyCliente ? 'none' : '';
  const titulo = document.getElementById('dc-titulo');
  if (titulo) titulo.textContent = soyCliente ? '📄 Carta Porte / documentos de carga' : '📄 Documentos de carga del cliente';

  document.getElementById('modal-documentos-carga').classList.add('open');

  const existentes = r?.documentos_carga || [];
  const listaEl = document.getElementById('dc-lista-actual');
  if (existentes.length) {
    const enlaces = await Promise.all(existentes.map(async (e) => {
      const { data } = await sb.storage.from('unidades').createSignedUrl(e, 3600);
      return data?.signedUrl || null;
    }));
    listaEl.innerHTML = enlaces.map((url, i) => url
      ? `<a href="${esc(url)}" target="_blank" class="btn-edit" style="font-size:0.75rem">📄 Documento ${i + 1}</a>`
      : `<span style="font-size:0.75rem;color:var(--text-muted)">📄 Documento ${i + 1} (no disponible)</span>`
    ).join('');
  } else {
    listaEl.innerHTML = '<span style="font-size:0.78rem;color:var(--text-muted)">Sin documentos aún</span>';
  }
}

function cerrarDocumentosCarga() {
  document.getElementById('modal-documentos-carga').classList.remove('open');
}

// La empresa pide la Carta Porte / documentos de carga sin necesidad de
// chat: un aviso puntual (campana + correo) en vez de un mensaje libre.
function solicitarDocumentosCarga() {
  const reservaId = document.getElementById('dc-reserva-id').value;
  if (!reservaId) return;
  showConfirm('¿Solicitar al cliente la Carta Porte y documentos de carga? Le llegará aviso por campana y correo.', async () => {
    const { data: r } = await sb.from('reservaciones')
      .select('cliente_user_id, unidad').eq('id', reservaId).single();
    if (!r?.cliente_user_id) { showToast('No se pudo solicitar', 'error'); return; }

    const mensaje = `${esc(currentUser.nombre)} necesita la Carta Porte y/o documentos de carga para el servicio "${esc(r.unidad || '')}". Súbelos desde Reservaciones.`;
    const { error } = await sb.from('notificaciones').insert({
      user_id: r.cliente_user_id,
      tipo:    'documentos_carga_solicitados',
      titulo:  '📄 Documentos de carga solicitados',
      mensaje,
      leido:   false,
    });
    if (error) { showToast('No se pudo solicitar: ' + error.message, 'error'); return; }

    _notificarEmail({
      tipo: 'resolucion', destinoIds: [r.cliente_user_id],
      titulo: 'Documentos de carga solicitados', mensaje, aprobado: true,
    });

    showToast('✓ Solicitud enviada al cliente');
  });
}

// La empresa le pide al cliente que confirme lugar y hora — un aviso, no
// una conversación. Si el pedido ya trae detalles capturados al aceptar la
// oferta los usa; si no, cae a origen/fecha del pedido.
function confirmarLugarHora(reservaId) {
  showConfirm('¿Pedirle al cliente que confirme el lugar y la hora? Le llegará aviso por campana y correo.', async () => {
    const { data: r } = await sb.from('reservaciones')
      .select('cliente_user_id, unidad, pedido_id').eq('id', reservaId).single();
    if (!r?.cliente_user_id) { showToast('No se pudo enviar', 'error'); return; }

    let lugar = null, hora = null;
    if (r.pedido_id) {
      const { data: p } = await sb.from('pedidos')
        .select('detalles_lugar, detalles_hora, origen, fecha_ini').eq('id', r.pedido_id).maybeSingle();
      lugar = p?.detalles_lugar || p?.origen || null;
      hora  = p?.detalles_hora  || (p?.fecha_ini ? fmtFecha(p.fecha_ini) : null);
    }
    const detalle = [lugar ? `lugar: ${lugar}` : null, hora ? `hora: ${hora}` : null].filter(Boolean).join(', ');
    const mensaje = `${esc(currentUser.nombre)} quiere confirmar contigo${detalle ? ` — ${esc(detalle)}` : ''} para el servicio "${esc(r.unidad || '')}". Si algo cambió, repórtalo desde Reservaciones.`;

    const { error } = await sb.from('notificaciones').insert({
      user_id: r.cliente_user_id,
      tipo:    'confirmar_lugar_hora',
      titulo:  '📍 Confirma lugar y hora',
      mensaje,
      leido:   false,
    });
    if (error) { showToast('No se pudo enviar: ' + error.message, 'error'); return; }

    _notificarEmail({
      tipo: 'resolucion', destinoIds: [r.cliente_user_id],
      titulo: 'Confirma lugar y hora', mensaje, aprobado: true,
    });
    showToast('✓ Aviso enviado al cliente');
  });
}

// Aviso de retraso — el detalle (cuánto tiempo, por qué) es opcional, se
// puede mandar solo el aviso sin nada más si no hace falta explicar.
function avisarRetraso(reservaId) {
  _abrirRechazarNota(
    '⏰ Avisar retraso',
    'Detalle (opcional) — cuánto tiempo o el motivo:',
    async nota => {
      const { data: r } = await sb.from('reservaciones')
        .select('cliente_user_id, unidad').eq('id', reservaId).single();
      if (!r?.cliente_user_id) { showToast('No se pudo enviar', 'error'); return; }

      const mensaje = `El transporte de tu servicio "${esc(r.unidad || '')}" va a llegar tarde.${nota ? ` ${esc(nota)}` : ''}`;
      const { error } = await sb.from('notificaciones').insert({
        user_id: r.cliente_user_id,
        tipo:    'aviso_retraso',
        titulo:  '⏰ Aviso de retraso',
        mensaje,
        leido:   false,
      });
      if (error) { showToast('No se pudo enviar: ' + error.message, 'error'); return; }

      _notificarEmail({
        tipo: 'resolucion', destinoIds: [r.cliente_user_id],
        titulo: 'Aviso de retraso', mensaje, aprobado: false,
      });
      showToast('✓ Aviso de retraso enviado');
    },
    { confirmLabel: '⏰ Enviar aviso', danger: false }
  );
}

// ── ACTUALIZAR LUGAR/HORA O REPORTAR PROBLEMA (cliente → empresa + superadmin) ──
// El lugar/hora se editan de verdad (se guardan en el pedido, la empresa ve
// el dato real); los otros motivos son alertas fijas, sin textarea, porque
// no hay un campo concreto que editar para "hay un problema con la carga".
const _RC_MOTIVOS = {
  carga: '📦 El cliente reporta un problema con la carga o los documentos.',
  otro:  '⚠ El cliente reporta un problema urgente y pide que lo contacten.',
};

async function abrirReportarCambio(reservaId) {
  document.getElementById('rc-reserva-id').value = reservaId;
  document.getElementById('rc-pedido-id').value = '';
  document.getElementById('rc-lugar').value = '';
  document.getElementById('rc-hora').value = '';
  document.getElementById('modal-reportar-cambio').classList.add('open');

  const { data: r } = await sb.from('reservaciones').select('pedido_id').eq('id', reservaId).single();
  if (!r?.pedido_id) return;
  document.getElementById('rc-pedido-id').value = r.pedido_id;

  const { data: p } = await sb.from('pedidos')
    .select('detalles_lugar, detalles_hora, origen').eq('id', r.pedido_id).maybeSingle();
  document.getElementById('rc-lugar').value = p?.detalles_lugar || p?.origen || '';
  document.getElementById('rc-hora').value  = p?.detalles_hora || '';
}
function cerrarReportarCambio() {
  document.getElementById('modal-reportar-cambio').classList.remove('open');
}

// Le avisa a la empresa (dueña de la reservación) y a todo superadmin —
// mismo destinatario para el cambio de lugar/hora y para los reportes fijos.
async function _notificarCambioReserva(reservaId, titulo, mensaje) {
  const { data: r } = await sb.from('reservaciones')
    .select('propietario_id').eq('id', reservaId).single();
  if (!r?.propietario_id) { showToast('No se pudo enviar', 'error'); return false; }

  const { data: supers } = await sb.from('perfiles').select('user_id').eq('rol', 'superadmin');
  const destinatarios = [r.propietario_id, ...((supers || []).map(s => s.user_id))];

  const { error } = await sb.from('notificaciones').insert(destinatarios.map(uid => ({
    user_id: uid, tipo: 'cambio_reportado', titulo, mensaje, leido: false,
  })));
  if (error) { showToast('No se pudo enviar: ' + error.message, 'error'); return false; }

  _notificarEmail({ tipo: 'resolucion', destinoIds: destinatarios, titulo, mensaje, aprobado: false });
  return true;
}

async function _guardarCambioLugarHora() {
  const reservaId = document.getElementById('rc-reserva-id').value;
  const pedidoId  = document.getElementById('rc-pedido-id').value;
  const lugar = document.getElementById('rc-lugar')?.value?.trim() || '';
  const hora  = document.getElementById('rc-hora')?.value?.trim() || '';
  if (!reservaId || !pedidoId) return;
  if (!lugar && !hora) { showToast('Indica el lugar y/o la hora', 'error'); return; }

  const { error } = await sb.from('pedidos')
    .update({ detalles_lugar: lugar || null, detalles_hora: hora || null }).eq('id', pedidoId);
  if (error) { showToast('No se pudo guardar: ' + error.message, 'error'); return; }

  const detalle = [lugar ? `lugar: ${lugar}` : null, hora ? `hora: ${hora}` : null].filter(Boolean).join(', ');
  const mensaje = `✏️ El cliente actualizó el viaje — ${esc(detalle)}.`;
  const ok = await _notificarCambioReserva(reservaId, '✏️ El cliente actualizó lugar/hora', mensaje);
  if (!ok) return;

  cerrarReportarCambio();
  await renderReserv();
  showToast('✓ Guardado y avisado a la empresa');
}

// El motivo ya viene fijo (no hay que elegirlo a mano), pero el detalle de
// qué pasó exactamente sí se puede agregar — opcional, mismo modal de nota
// que ya usa el resto del sitio para esto.
function _enviarReporteCambio(motivoClave) {
  const reservaId = document.getElementById('rc-reserva-id').value;
  const texto = _RC_MOTIVOS[motivoClave];
  if (!reservaId || !texto) return;
  cerrarReportarCambio();

  _abrirRechazarNota(
    '⚠ Reportar problema',
    'Detalle (opcional) — qué pasó exactamente:',
    async nota => {
      const { data: r } = await sb.from('reservaciones')
        .select('unidad, cliente').eq('id', reservaId).single();
      const mensaje = `${texto}${nota ? ` ${esc(nota)}` : ''} Servicio "${esc(r?.unidad || '')}" — ${esc(r?.cliente || 'cliente')}.`;
      const ok = await _notificarCambioReserva(reservaId, '⚠ Cliente reporta un problema', mensaje);
      if (!ok) return;
      showToast('✓ Reporte enviado a la empresa y al superadmin');
    },
    { confirmLabel: '⚠ Enviar reporte', danger: false }
  );
}

async function subirDocumentosCarga() {
  const reservaId = document.getElementById('dc-reserva-id').value;
  const files = Array.from(document.getElementById('dc-files')?.files || []);
  if (!files.length) { showToast('Selecciona al menos un archivo', 'error'); return; }

  const { data: r } = await sb.from('reservaciones').select('documentos_carga').eq('id', reservaId).single();
  const existentes = r?.documentos_carga || [];
  if (existentes.length + files.length > 8) {
    showToast(`Máximo 8 documentos. Ya tienes ${existentes.length}.`, 'error'); return;
  }

  const nuevosPaths = [];
  for (const f of files) {
    const ext  = f.name.split('.').pop();
    const path = `${currentUser.id}/documentos-carga/${reservaId}/${Date.now()}_${Math.random().toString(36).slice(2)}.${ext}`;
    const { error: upErr } = await sb.storage.from('unidades').upload(path, f);
    if (upErr) { showToast('Error al subir: ' + upErr.message, 'error'); return; }
    nuevosPaths.push(path);
  }

  const { error } = await sb.from('reservaciones')
    .update({ documentos_carga: [...existentes, ...nuevosPaths] }).eq('id', reservaId);
  if (error) { showToast('No se pudo guardar: ' + error.message, 'error'); return; }

  cerrarDocumentosCarga();
  await renderReserv();
  showToast(`✓ ${nuevosPaths.length} documento${nuevosPaths.length !== 1 ? 's' : ''} subido${nuevosPaths.length !== 1 ? 's' : ''}`);
}

// ── ASIGNAR CHOFER (empresa, reserva activa) ──────────
// El chofer ya no es obligatorio al ofertar: se puede asignar en cualquier
// momento mientras el viaje sigue Activo, y tracking.js bloquea avanzar del
// primer paso sin uno (ver avanzarTracking).

async function abrirAsignarChofer(reservaId) {
  const { data: r } = await sb.from('reservaciones')
    .select('operador_id, pedido_id').eq('id', reservaId).single();
  if (!r) { showToast('No se encontró la reserva', 'error'); return; }

  let esCargaPeligrosa = false;
  if (r.pedido_id) {
    const { data: ped } = await sb.from('pedidos').select('carga_peligrosa').eq('id', r.pedido_id).maybeSingle();
    esCargaPeligrosa = !!ped?.carga_peligrosa;
  }

  const { data: opsRaw } = await sb.from('operadores')
    .select('id, nombre, primer_apellido, fecha_vencimiento_licencia_peligrosa')
    .eq('propietario_id', currentUser.id).eq('aprobacion', 'aprobada');
  const hoy = today();
  const ops = esCargaPeligrosa
    ? (opsRaw || []).filter(o => o.fecha_vencimiento_licencia_peligrosa && o.fecha_vencimiento_licencia_peligrosa >= hoy)
    : (opsRaw || []);

  const sel = document.getElementById('ac-operador');
  sel.innerHTML = ops.length
    ? '<option value="">— Selecciona un chofer —</option>' + ops.map(o =>
        `<option value="${esc(o.id)}">${esc(`${o.nombre} ${o.primer_apellido || ''}`.trim())}</option>`).join('')
    : esCargaPeligrosa
      ? '<option value="">Sin choferes con licencia HAZMAT vigente</option>'
      : '<option value="">Sin operadores registrados</option>';
  if (r.operador_id) sel.value = r.operador_id;

  document.getElementById('ac-reserva-id').value = reservaId;
  const aviso = document.getElementById('ac-aviso-hazmat');
  if (aviso) aviso.style.display = esCargaPeligrosa ? '' : 'none';
  document.getElementById('modal-asignar-chofer').classList.add('open');
}

function cerrarAsignarChofer() {
  document.getElementById('modal-asignar-chofer').classList.remove('open');
}

async function confirmarAsignarChofer() {
  const reservaId = document.getElementById('ac-reserva-id').value;
  const sel = document.getElementById('ac-operador');
  const operadorId = sel?.value;
  const operadorNombre = sel?.options[sel.selectedIndex]?.textContent?.trim() || null;
  if (!operadorId) { showToast('Selecciona un chofer', 'error'); return; }

  const { error } = await sb.from('reservaciones').update({
    operador_id:     operadorId,
    operador_nombre: operadorNombre,
  }).eq('id', reservaId);
  if (error) { showToast('No se pudo asignar: ' + error.message, 'error'); return; }

  cerrarAsignarChofer();
  await renderReserv();
  showToast('✓ Chofer asignado');
}

// ── CAMBIAR UNIDAD (empresa, reserva activa) ──────────
// Para cuando la unidad asignada se descompone o no puede seguir el
// servicio: la empresa reasigna a otra unidad propia disponible del mismo
// tipo, con motivo obligatorio (lo exige guard_reservacion_update en DB).

async function abrirCambiarUnidad(reservaId) {
  const { data: r } = await sb.from('reservaciones')
    .select('unidad, recurso_tipo').eq('id', reservaId).single();
  if (!r) { showToast('No se encontró la reserva', 'error'); return; }

  const tabla = r.recurso_tipo === 'custodio' ? 'custodios'
    : r.recurso_tipo === 'patio' ? 'patios'
    : r.recurso_tipo === 'lavado' ? 'lavados' : 'camiones';

  const { data: opciones } = await sb.from(tabla)
    .select('id, tipo, nombre')
    .eq('propietario_id', currentUser.id)
    .eq('aprobacion', 'aprobada')
    .eq('estado', 'disponible')
    .neq('id', r.unidad || '');

  const sel = document.getElementById('cu-unidad-nueva');
  sel.innerHTML = opciones?.length
    ? '<option value="">Selecciona…</option>' + opciones.map(o =>
        `<option value="${esc(o.id)}">${esc(o.id)}${o.tipo ? ' — ' + esc(o.tipo) : ''}${o.nombre ? ' — ' + esc(o.nombre) : ''}</option>`).join('')
    : '<option value="">No tienes otra unidad disponible del mismo tipo</option>';

  document.getElementById('cu-reserva-id').value     = reservaId;
  document.getElementById('cu-tabla').value          = tabla;
  document.getElementById('cu-unidad-actual').value  = r.unidad || '';
  document.getElementById('cu-unidad-actual-label').textContent = r.unidad || '—';
  document.getElementById('cu-motivo').value = '';
  document.getElementById('modal-cambiar-unidad').classList.add('open');
}

function cerrarCambiarUnidad() {
  document.getElementById('modal-cambiar-unidad').classList.remove('open');
}

async function confirmarCambiarUnidad() {
  const reservaId   = document.getElementById('cu-reserva-id').value;
  const tabla       = document.getElementById('cu-tabla').value;
  const unidadVieja = document.getElementById('cu-unidad-actual').value;
  const unidadNueva = document.getElementById('cu-unidad-nueva').value;
  const motivo      = document.getElementById('cu-motivo').value.trim();

  if (!unidadNueva) { showToast('Selecciona la nueva unidad', 'error'); return; }
  if (!motivo) { showToast('Indica el motivo del cambio', 'error'); return; }

  const { error } = await sb.from('reservaciones').update({
    unidad: unidadNueva,
    motivo_cambio_unidad: motivo,
  }).eq('id', reservaId);
  if (error) { showToast('No se pudo cambiar la unidad: ' + (error.message || ''), 'error'); return; }

  if (unidadVieja) await sb.from(tabla).update({ estado: 'disponible' }).eq('id', unidadVieja);
  await sb.from(tabla).update({ estado: 'ocupado' }).eq('id', unidadNueva);

  const { data: r } = await sb.from('reservaciones').select('cliente_user_id, cliente').eq('id', reservaId).single();
  const notifs = [];
  if (r?.cliente_user_id) notifs.push({
    user_id: r.cliente_user_id, tipo: 'unidad_cambiada', titulo: '🔧 Se cambió la unidad de tu servicio',
    mensaje: `La empresa cambió la unidad asignada de "${unidadVieja}" a "${unidadNueva}". Motivo: ${motivo}`, leido: false,
  });
  const { data: supers } = await sb.from('perfiles').select('user_id').eq('rol', 'superadmin');
  (supers || []).forEach(s => notifs.push({
    user_id: s.user_id, tipo: 'unidad_cambiada', titulo: '🔧 Cambio de unidad en un servicio activo',
    mensaje: `${esc(currentUser.nombre || 'Una empresa')} cambió la unidad de "${unidadVieja}" a "${unidadNueva}" en el servicio de ${esc(r?.cliente || 'un cliente')}. Motivo: ${motivo}`,
    leido: false,
  }));
  if (notifs.length) await sb.from('notificaciones').insert(notifs);

  cerrarCambiarUnidad();
  await renderReserv();
  showToast('✓ Unidad cambiada');
}

// ── COMPLETAR SERVICIO (cliente y empresa, con aprobación del superadmin) ──
//
// Ni cliente ni empresa cierran el servicio directamente: cada quien marca
// su lado como completado subiendo su propia evidencia (evidencias = empresa,
// evidencias_cliente = cliente). En cuanto el primero lo hace, la reserva
// pasa a 'PorAprobar' y el superadmin revisa ambas evidencias antes de
// aprobar (-> 'Completada', cierra el pedido) o rechazar (-> 'Activa').

async function abrirEvidencias(reservaId, campo = 'evidencias') {
  const { data: r } = await sb.from('reservaciones')
    .select('estado, tracking_estado, recurso_tipo, completado_en, evidencias, evidencias_cliente, cliente_user_id, propietario_id, cliente, pedido_id')
    .eq('id', reservaId).single();
  if (!r) { showToast('No se encontró la reserva', 'error'); return; }

  const modo = r.estado === 'Activa' ? 'solicitar' : 'agregar';

  // Solo la empresa, y solo al solicitar el cierre, debe haber avanzado el
  // seguimiento hasta el último paso.
  if (campo === 'evidencias' && modo === 'solicitar') {
    const estados   = _getEstados(r.recurso_tipo);
    const estadoFin = estados[estados.length - 1];
    const actual    = r.tracking_estado || estados[0].key;
    if (actual !== estadoFin.key) {
      showToast(`Primero avanza el seguimiento 📍 hasta "${estadoFin.label}". Estado actual: "${esc(actual)}".`, 'error');
      return;
    }
  }

  const campoInput = document.getElementById('ev-campo');
  if (!campoInput) {
    // El HTML del modal está desactualizado en este navegador (falta el
    // campo nuevo) — avisar en vez de fallar en silencio.
    showToast('Tu app está desactualizada. Recarga la página (Ctrl+Shift+R) e inténtalo de nuevo.', 'error');
    return;
  }
  document.getElementById('ev-reserva-id').value = reservaId;
  campoInput.value = campo;
  document.getElementById('ev-files').value = '';
  document.getElementById('ev-lista-actual').innerHTML = '<span style="color:var(--text-muted);font-size:0.82rem">Cargando…</span>';
  document.getElementById('modal-evidencias').classList.add('open');

  const tituloEl = document.getElementById('ev-titulo');
  const btnEl    = document.getElementById('btn-subir-evidencias');
  if (tituloEl) tituloEl.textContent = modo === 'solicitar' ? '✓ Marcar servicio completado' : '📎 Evidencias del servicio';
  if (btnEl)    btnEl.textContent    = modo === 'solicitar' ? '✓ Confirmar y enviar a revisión' : '📤 Subir evidencias';

  const infoEl = document.getElementById('ev-plazo-info');
  if (modo === 'solicitar') {
    if (infoEl) infoEl.textContent = 'Sube al menos una foto como evidencia. La otra parte también deberá subir la suya antes de que el superadmin apruebe el cierre.';
  } else {
    const hoy = new Date();
    const fechaComp = r.completado_en ? new Date(r.completado_en) : hoy;
    const diasRestantes = 5 - Math.floor((hoy - fechaComp) / 86400000);
    if (infoEl) infoEl.textContent = diasRestantes > 0
      ? `Tienes ${diasRestantes} día${diasRestantes !== 1 ? 's' : ''} para subir evidencias (máx. 5 archivos en total).`
      : 'El plazo de 5 días para subir evidencias ha vencido.';
    const fileInput = document.getElementById('ev-files');
    if (fileInput) fileInput.disabled = diasRestantes <= 0;
  }

  // El bucket es privado: se guardan paths y se firman URLs al momento de ver.
  // Entradas legadas con URL completa se muestran tal cual.
  const existentes = r[campo] || [];
  const listaEl = document.getElementById('ev-lista-actual');
  if (existentes.length) {
    const enlaces = await Promise.all(existentes.map(async (e) => {
      if (String(e).startsWith('http')) return e;
      const { data } = await sb.storage.from('unidades').createSignedUrl(e, 3600);
      return data?.signedUrl || null;
    }));
    listaEl.innerHTML = enlaces.map((url, i) => url
      ? `<a href="${esc(url)}" target="_blank" class="btn-edit" style="font-size:0.75rem">📎 Evidencia ${i + 1}</a>`
      : `<span style="font-size:0.75rem;color:var(--text-muted)">📎 Evidencia ${i + 1} (no disponible)</span>`
    ).join('');
  } else {
    listaEl.innerHTML = '<span style="font-size:0.78rem;color:var(--text-muted)">Sin evidencias aún</span>';
  }
}

function cerrarEvidencias() {
  document.getElementById('modal-evidencias').classList.remove('open');
}

async function subirEvidencias() {
  const reservaId = document.getElementById('ev-reserva-id').value;
  const campo     = document.getElementById('ev-campo')?.value || 'evidencias';
  const files     = Array.from(document.getElementById('ev-files')?.files || []);
  if (!files.length) { showToast('Selecciona al menos un archivo', 'error'); return; }

  const { data: r } = await sb.from('reservaciones')
    .select('estado, completado_en, evidencias, evidencias_cliente, cliente_user_id, propietario_id, cliente, unidad, recurso_tipo, pedido_id')
    .eq('id', reservaId).single();
  if (!r) { showToast('No se encontró la reserva', 'error'); return; }

  const solicitando = r.estado === 'Activa';

  // Verificar plazo (5 días) — solo aplica cuando ya se solicitó el cierre.
  if (!solicitando) {
    const diasPasados = r.completado_en
      ? Math.floor((new Date() - new Date(r.completado_en)) / 86400000)
      : 0;
    if (diasPasados > 5) { showToast('El plazo de 5 días para subir evidencias ha vencido.', 'error'); return; }
  }

  const existentes = r[campo] || [];
  if (existentes.length + files.length > 5) {
    showToast(`Solo puedes tener 5 evidencias. Ya tienes ${existentes.length}.`, 'error'); return;
  }

  // Se guarda el path (no una URL pública): el bucket es privado y los
  // enlaces se firman al verlos en abrirEvidencias().
  const nuevosPaths = [];
  for (const f of files) {
    const ext  = f.name.split('.').pop();
    const path = `${currentUser.id}/evidencias/${reservaId}/${Date.now()}_${Math.random().toString(36).slice(2)}.${ext}`;
    const { error: upErr } = await sb.storage.from('unidades').upload(path, f);
    if (upErr) { showToast('Error al subir: ' + upErr.message, 'error'); return; }
    nuevosPaths.push(path);
  }

  const payload = { [campo]: [...existentes, ...nuevosPaths] };
  const actor = campo === 'evidencias_cliente' ? 'cliente' : 'empresa';
  if (solicitando) {
    payload.estado = 'PorAprobar';
    payload.finalizacion_solicitada_por = actor;
    if (!r.completado_en) payload.completado_en = new Date().toISOString();
  }

  const { error } = await sb.from('reservaciones').update(payload).eq('id', reservaId);
  if (error) { showToast('Error al guardar: ' + error.message, 'error'); return; }

  if (solicitando) {
    // Notificar a la otra parte para que suba su propia evidencia
    const otroId = actor === 'cliente' ? r.propietario_id : r.cliente_user_id;
    if (otroId) {
      await sb.from('notificaciones').insert({
        user_id: otroId,
        tipo:    'finalizacion_solicitada',
        titulo:  '📎 Confirma la finalización del servicio',
        mensaje: `${actor === 'cliente' ? 'El cliente' : 'La empresa'} marcó el servicio como completado. Sube tu propia evidencia para enviarlo a revisión del superadmin.`,
        leido:   false,
      });
    }
    // Notificar a superadmins para que lo revisen
    const { data: supers } = await sb.from('perfiles').select('user_id').eq('rol', 'superadmin');
    if (supers?.length) {
      await sb.from('notificaciones').insert(supers.map(a => ({
        user_id: a.user_id,
        tipo:    'revision_finalizacion',
        titulo:  '🏁 Finalización de servicio por revisar',
        mensaje: `${esc(r.cliente || 'Un cliente')} tiene un servicio marcado como completado, pendiente de tu aprobación.`,
        leido:   false,
      })));
    }
  } else if (!existentes.length) {
    // La otra parte ya había solicitado el cierre; esta es la primera vez que
    // ESTE lado sube su evidencia — avisar a superadmins que ya están ambas.
    const { data: supers } = await sb.from('perfiles').select('user_id').eq('rol', 'superadmin');
    if (supers?.length) {
      await sb.from('notificaciones').insert(supers.map(a => ({
        user_id: a.user_id,
        tipo:    'revision_finalizacion',
        titulo:  '🏁 Ya están ambas evidencias',
        mensaje: `${esc(r.cliente || 'Un cliente')} y la empresa ya subieron su evidencia de cierre. Puedes revisarla y aprobarla.`,
        leido:   false,
      })));
    }
  }

  cerrarEvidencias();
  await renderReserv();
  showToast(solicitando
    ? '✓ Enviado a revisión del superadmin'
    : `✓ ${nuevosPaths.length} evidencia${nuevosPaths.length !== 1 ? 's' : ''} subida${nuevosPaths.length !== 1 ? 's' : ''}`);
}

// ── CALIFICAR SERVICIO (cliente) ───────────────────────

let _calReservaId = null;
let _calAdminId   = null;
let _calRating    = 5;

function openCalificar(reservaId, adminId, adminNombre) {
  _calReservaId = reservaId;
  _calAdminId   = adminId;
  _calRating    = 5;
  document.getElementById('cal-reservacion-id').value = reservaId;
  document.getElementById('cal-admin-id').value       = adminId;
  document.getElementById('cal-subtitulo').textContent = adminNombre ? `Califica a ${adminNombre}` : '';
  seleccionarEstrella(5);
  document.getElementById('cal-comentario').value = '';
  document.getElementById('modal-calificar').classList.add('open');
}

function closeCalificar() {
  document.getElementById('modal-calificar').classList.remove('open');
  _calReservaId = null;
  _calAdminId   = null;
}

function seleccionarEstrella(val) {
  _calRating = val;
  const labels = ['', 'Malo', 'Regular', 'Bueno', 'Muy bueno', 'Excelente'];
  document.querySelectorAll('#cal-stars .star').forEach((el, i) => {
    el.classList.toggle('star-on', i < val);
  });
  const lbl = document.getElementById('cal-rating-label');
  if (lbl) lbl.textContent = labels[val] || '';
}

async function enviarCalificacion() {
  if (!_calReservaId || !_calAdminId) return;
  const comentario = document.getElementById('cal-comentario')?.value?.trim() || null;
  const { error } = await sb.from('calificaciones').insert({
    reservacion_id: _calReservaId,
    admin_id:       _calAdminId,
    cliente_id:     currentUser.id,
    rating:         _calRating,
    comentario,
  });
  if (error) { showToast('Error al enviar calificación'); return; }
  await sb.from('reservaciones').update({ calificado: true }).eq('id', _calReservaId);

  // Notificar al proveedor de la nueva calificación
  await sb.from('notificaciones').insert({
    user_id: _calAdminId,
    tipo:    'nueva_calificacion',
    titulo:  '⭐ Nueva calificación recibida',
    mensaje: `${currentUser.nombre || 'Un cliente'} te calificó con ${_calRating} estrella${_calRating !== 1 ? 's' : ''}${comentario ? ': "' + comentario.slice(0, 80) + (comentario.length > 80 ? '…' : '') + '"' : ''}.`,
    leido:   false,
  });

  closeCalificar();
  await renderReserv();
  showToast('⭐ ¡Gracias por tu calificación!');
}

// El registro de cobros vive en js/cobros.js (abrirRegistrarPago /
// revertirPago), que además captura forma de pago y referencia.

// ── SOLICITUD DE CANCELACIÓN (cliente) ─────────────────
// El acuerdo ya fue aprobado y la empresa comprometió una unidad, así que el
// cliente no cancela por su cuenta: lo solicita con un motivo y el superadmin
// resuelve. La empresa se entera de inmediato, porque puede tener un camión
// ya en camino.
let _cancelReservaId = null;

function solicitarCancelacion(reservaId) {
  _cancelReservaId = reservaId;
  document.getElementById('sc-motivo').value = '';
  document.getElementById('sc-detalle').value = '';
  document.getElementById('modal-solicitar-cancelacion').classList.add('open');
}

function cerrarSolicitarCancelacion() {
  document.getElementById('modal-solicitar-cancelacion').classList.remove('open');
  _cancelReservaId = null;
}

async function confirmarSolicitudCancelacion() {
  if (!_cancelReservaId) return;
  const motivo  = document.getElementById('sc-motivo').value;
  const detalle = document.getElementById('sc-detalle').value.trim();
  if (!motivo) { showToast('Selecciona el motivo de la cancelación.', 'error'); return; }

  const { data: r } = await sb.from('reservaciones')
    .select('tracking_estado, propietario_id, unidad, cliente')
    .eq('id', _cancelReservaId).single();

  const { error } = await sb.from('reservaciones').update({
    estado:                      'CancelacionSolicitada',
    cancelacion_solicitada_en:   new Date().toISOString(),
    cancelacion_solicitada_por:  currentUser.id,
    cancelacion_motivo:          motivo,
    cancelacion_detalle:         detalle || null,
    // Se congela el punto del viaje: no es lo mismo cancelar antes de salir
    // que con la carga en tránsito.
    cancelacion_tracking_estado: r?.tracking_estado || 'Confirmado',
  }).eq('id', _cancelReservaId);

  cerrarSolicitarCancelacion();
  if (error) { showToast('No se pudo enviar la solicitud: ' + error.message, 'error'); return; }

  // Avisar a la empresa YA (puede detener la unidad) y al superadmin, que decide.
  const notifs = [];
  if (r?.propietario_id) notifs.push({
    user_id: r.propietario_id,
    tipo:    'cancelacion_solicitada',
    titulo:  '⚠ El cliente pidió cancelar un servicio',
    mensaje: `${esc(currentUser.nombre || 'El cliente')} solicitó cancelar el servicio de ${esc(r.unidad || 'la unidad')}. Motivo: ${esc(motivo)}. Está en revisión — no continúes hasta que se resuelva.`,
    leido:   false,
  });
  const { data: supers } = await sb.from('perfiles').select('user_id').eq('rol', 'superadmin');
  (supers || []).forEach(s => notifs.push({
    user_id: s.user_id,
    tipo:    'cancelacion_solicitada',
    titulo:  'Cancelación por revisar',
    mensaje: `${esc(currentUser.nombre || 'Un cliente')} solicitó cancelar un servicio activo (${esc(r?.tracking_estado || 'Confirmado')}). Motivo: ${esc(motivo)}.`,
    leido:   false,
  }));
  if (notifs.length) await sb.from('notificaciones').insert(notifs);

  showToast('✓ Solicitud enviada — te avisaremos cuando se resuelva');
  await renderReserv();
  await loadNotificaciones();
}

// ── HISTORIAL DE RESERVACIONES ARCHIVADAS (superadmin) ─

async function renderHistorialReservas() {
  const el = document.getElementById('historial-reservas-content');
  if (!el) return;
  el.innerHTML = `<div class="empty-state"><div class="icon">⏳</div>Cargando historial…</div>`;

  const { data, error } = await sb.from('reservaciones_historico')
    .select('*')
    .order('created_at', { ascending: false })
    .limit(100);

  if (error) { el.innerHTML = `<div class="empty-state"><div class="icon">❌</div>Error al cargar historial.</div>`; return; }
  if (!data?.length) { el.innerHTML = `<div class="empty-state"><div class="icon">🗃</div>No hay reservaciones archivadas.</div>`; return; }

  el.innerHTML = `
    <table class="rep-table" style="width:100%">
      <thead>
        <tr>
          <th>Unidad</th><th>Cliente</th><th>Empresa</th><th>Inicio</th><th>Fin</th>
          <th>Estado</th><th>Archivado</th>
        </tr>
      </thead>
      <tbody>
        ${data.map(r => `
        <tr>
          <td>${esc(r.unidad || '—')}</td>
          <td>${esc(r.cliente || '—')}</td>
          <td>${esc(r.empresa || '—')}</td>
          <td>${fmtFecha(r.fecha_ini)}</td>
          <td>${fmtFecha(r.fecha_fin)}</td>
          <td><span class="badge badge-maint">${esc(r.estado || '—')}</span></td>
          <td style="font-size:0.75rem;color:var(--text-muted)">${r.created_at ? new Date(r.created_at).toLocaleDateString('es-MX') : '—'}</td>
        </tr>`).join('')}
      </tbody>
    </table>`;
}

// Helper: envía email via edge function (fire-and-forget)
async function _enviarEmail(tipo, payload) {
  try {
    const session = (await sb.auth.getSession()).data.session;
    const fnBase  = typeof FN_URL !== 'undefined'
      ? FN_URL.replace('gestionar-usuario', 'enviar-notificacion') : null;
    if (!fnBase || !session?.access_token || !payload.clienteEmail) return;
    fetch(fnBase, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${session.access_token}` },
      body: JSON.stringify({ tipo, ...payload })
    });
  } catch (_) { /* silencioso */ }
}
