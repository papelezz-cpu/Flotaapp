// ── RESERVACIONES ─────────────────────────────────────

async function renderReserv() {
  const body   = document.getElementById('reserv-body');
  const header = document.getElementById('reserv-header');
  body.innerHTML = skeletonRows(4);

  // Sin sesión
  if (!currentUser.id) {
    body.innerHTML = `<div class="empty-state"><div class="icon">🔒</div>Inicia sesión para ver tus reservaciones.</div>`;
    return;
  }

  // ── VISTA CLIENTE (solo sus propias reservas, solo lectura) ──
  if (currentUser.rol === 'cliente') {
    header.innerHTML = `<div>Unidad</div><div>Empresa</div><div>Inicio</div><div>Fin</div><div>Estado</div>`;
    header.classList.add('cli');

    const { data, error } = await sb.from('reservaciones')
      .select('*')
      .eq('cliente_email', currentUser.email)
      .order('created_at', { ascending: false });

    if (error) { body.innerHTML = `<div class="empty-state"><div class="icon">❌</div>Error al cargar.</div>`; return; }
    if (!data?.length) { body.innerHTML = `<div class="empty-state"><div class="icon">📋</div>Aún no tienes reservaciones.</div>`; return; }

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

    body.innerHTML = data.map(r => {
      const badgeCls = r.estado === 'Pendiente'   ? 'badge-busy'
                     : r.estado === 'Activa'      ? 'badge-avail'
                     : r.estado === 'Completada'  ? 'badge-completado'
                     : 'badge-maint';
      const trackBtn = r.estado === 'Activa'
        ? `<button class="btn-edit" onclick="openTracking('${r.id}')" style="font-size:0.7rem">📍 ${esc(r.tracking_estado || 'Confirmado')}</button>`
        : '';
      const unidadLabel = recursoNombreMap[r.unidad] || esc(r.unidad) || '—';
      const propId = ownerIdMap[r.unidad] || r.propietario_id || '';
      const chatBtn = propId
        ? `<button class="btn-chat-hilo" onclick="openChatReserva('${r.id}','${propId}','${esc(empresaMap[r.unidad]||'')}')">💬</button>`
        : '';
      const calBtn = (r.estado === 'Completada' && !r.calificado && propId)
        ? `<button class="btn-calificar" onclick="openCalificar('${r.id}','${propId}','${esc(empresaMap[r.unidad]||'')}')">⭐ Calificar</button>`
        : '';
      return `
      <div class="reserv-row reserv-row-cli">
        <div class="reserv-id">${unidadLabel}</div>
        <div class="reserv-empresa">${esc(empresaMap[r.unidad] || '—')}</div>
        <div>${fmtFecha(r.fecha_ini)}</div>
        <div>${fmtFecha(r.fecha_fin)}</div>
        <div style="display:flex;gap:5px;align-items:center;flex-wrap:wrap">
          <span class="badge ${badgeCls}">${esc(r.estado)}</span>
          ${trackBtn}
          ${chatBtn}
          ${calBtn}
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
    // Obtener IDs de todos los recursos propios (camiones + custodios + patios)
    const [{ data: misCamiones }, { data: misCustodios }, { data: misPatios }] = await Promise.all([
      sb.from('camiones').select('id').eq('propietario_id', currentUser.id),
      sb.from('custodios').select('id').eq('propietario_id', currentUser.id),
      sb.from('patios').select('id').eq('propietario_id', currentUser.id),
    ]);
    const misIds = [
      ...(misCamiones  || []).map(c => c.id),
      ...(misCustodios || []).map(c => c.id),
      ...(misPatios    || []).map(p => p.id),
    ];
    if (!misIds.length) {
      body.innerHTML = `<div class="empty-state"><div class="icon">🚛</div>No tienes recursos registrados.</div>`;
      return;
    }
    reservQuery = reservQuery.in('unidad', misIds);
  }

  const { data, error } = await reservQuery;
  if (error) { body.innerHTML = `<div class="empty-state"><div class="icon">❌</div>Error al cargar.</div>`; return; }
  if (!data.length) { body.innerHTML = `<div class="empty-state"><div class="icon">📋</div>No hay reservaciones registradas.</div>`; return; }

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

  body.innerHTML = data.map(r => {
    const esCancelada = r.estado === 'Cancelada';
    const esRechazada = r.estado === 'Rechazada';
    const esPendiente = r.estado === 'Pendiente';
    const esActiva    = r.estado === 'Activa';
    const inactiva    = esCancelada || esRechazada;

    const esCompletada = r.estado === 'Completada';
    const badgeCls = esPendiente  ? 'badge-busy'
                   : esActiva     ? 'badge-avail'
                   : esCompletada ? 'badge-acordado'
                   : 'badge-maint';

    const esDueno = currentUser.rol === 'superadmin' || ownerMap[r.unidad] === currentUser.id || r.propietario_id === currentUser.id;
    let acciones = '';
    if (esDueno && esPendiente) {
      acciones = `
        <button class="btn-aceptar-reserva"  onclick="aceptarReserva('${r.id}','${esc(r.unidad)}','${r.recurso_tipo||'camion'}')">✓ Aceptar</button>
        <button class="btn-rechazar-reserva" onclick="rechazarReserva('${r.id}','${esc(r.unidad)}')">✕ Rechazar</button>`;
    } else if (esDueno && esActiva) {
      const trackStep = r.tracking_estado || 'Confirmado';
      acciones = `
        <button class="btn-edit" onclick="openTracking('${r.id}')" title="Ver seguimiento">📍 ${esc(trackStep)}</button>
        <button class="btn-completar-reserva" onclick="marcarCompletado('${r.id}')">✓ Completar</button>
        <button class="btn-cancelar-reserva" onclick="cancelarReserva('${r.id}','${esc(r.unidad)}')">Cancelar</button>`;
    }

    const unidadLabel = recursoLabelMap[r.unidad] || esc(r.unidad) || '—';
    // Chat con el cliente (solo si hay cliente_user_id y la reserva está activa/pendiente)
    const chatBtn = (esDueno && r.cliente_user_id && !inactiva)
      ? `<button class="btn-chat-hilo" onclick="openChatReserva('${r.id}','${r.cliente_user_id}','${esc(r.cliente||'')}')">💬</button>`
      : '';
    // Eliminar (mover a histórico) — solo superadmin
    const elimBtn = currentUser.rol === 'superadmin'
      ? `<button class="btn-edit btn-rechazar" style="font-size:0.72rem" onclick="eliminarReserva('${r.id}')">🗑</button>`
      : '';
    return `
    <div class="reserv-row ${inactiva ? 'reserv-cancelada' : ''}">
      <div class="reserv-id">${unidadLabel}</div>
      <div class="reserv-empresa">${esc(empresaMap[r.unidad] || '—')}</div>
      <div>${esc(r.cliente)}</div>
      <div>${fmtFecha(r.fecha_ini)}</div>
      <div>${fmtFecha(r.fecha_fin)}</div>
      <div style="display:flex;gap:5px;align-items:center;flex-wrap:wrap">
        <span class="badge ${badgeCls}">${esc(r.estado)}</span>
        ${acciones}
        ${chatBtn}
        ${elimBtn}
      </div>
    </div>`;
  }).join('');
}

// ── ACCIONES ───────────────────────────────────────────

async function aceptarReserva(reservaId, unidad, recurso_tipo) {
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

  await renderReserv();
  await loadNotificaciones();
  const recursoLabel = tipoFinal === 'custodio' ? 'custodio' : tipoFinal === 'patio' ? 'patio' : 'camión';
  const toastMsg = fechaIni && fechaIni <= today()
    ? `✓ Reserva aceptada — ${recursoLabel} marcado como en servicio`
    : `✓ Reserva aceptada — el ${recursoLabel} quedará en servicio a partir del ` + fmtFecha(fechaIni);
  showToast(toastMsg);
}

async function rechazarReserva(reservaId, unidad) {
  if (!confirm('¿Rechazar esta solicitud?')) return;
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

  await renderReserv();
  await loadNotificaciones();
  showToast('Solicitud rechazada');
}

async function cancelarReserva(reservaId, unidad) {
  if (!confirm('¿Cancelar esta reserva? El recurso volverá a estar disponible.')) return;
  const { data: r } = await sb.from('reservaciones').select('recurso_tipo').eq('id', reservaId).single();
  const tipoFinal = r?.recurso_tipo || 'camion';
  await sb.from('reservaciones').update({ estado: 'Cancelada' }).eq('id', reservaId);
  if (unidad) {
    const tabla = tipoFinal === 'custodio' ? 'custodios' : tipoFinal === 'patio' ? 'patios' : 'camiones';
    await sb.from(tabla).update({ estado: 'disponible' }).eq('id', unidad);
  }
  await renderReserv();
  showToast('Reserva cancelada — recurso disponible de nuevo');
}

// ── ELIMINAR RESERVA (superadmin) → mover a histórico ──
async function eliminarReserva(reservaId) {
  if (!confirm('¿Archivar esta reservación? Se moverá al historial y desaparecerá de la lista activa.')) return;

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
  });
  if (insertErr) { showToast('Error al archivar: ' + (insertErr.message || '')); return; }

  // 3. Eliminar de la tabla activa
  const { error: delErr } = await sb.from('reservaciones').delete().eq('id', reservaId);
  if (delErr) { showToast('Error al eliminar: ' + (delErr.message || '')); return; }

  await renderReserv();
  showToast('✓ Reservación archivada en el historial');
}

// ── COMPLETAR SERVICIO (admin) ─────────────────────────

async function marcarCompletado(reservaId) {
  if (!confirm('¿Marcar este servicio como completado? El cliente podrá calificarlo.')) return;
  const { data: r } = await sb.from('reservaciones').select('unidad, recurso_tipo').eq('id', reservaId).single();
  await sb.from('reservaciones').update({
    estado:       'Completada',
    completado_en: new Date().toISOString(),
  }).eq('id', reservaId);

  // Liberar recurso
  if (r?.unidad) {
    const tabla = r.recurso_tipo === 'custodio' ? 'custodios' : r.recurso_tipo === 'patio' ? 'patios' : 'camiones';
    await sb.from(tabla).update({ estado: 'disponible' }).eq('id', r.unidad);
  }
  await renderReserv();
  showToast('✓ Servicio marcado como completado');
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
