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

    const unidades = [...new Set(data.map(r => r.unidad))];
    const { data: camiones } = await sb.from('camiones')
      .select('id, propietario:perfiles(nombre)').in('id', unidades);
    const empresaMap = {};
    (camiones || []).forEach(c => { empresaMap[c.id] = c.propietario?.nombre || '—'; });

    body.innerHTML = data.map(r => {
      const badgeCls = r.estado === 'Pendiente'  ? 'badge-busy'
                     : r.estado === 'Activa'     ? 'badge-avail'
                     : 'badge-maint';
      return `
      <div class="reserv-row reserv-row-cli">
        <div class="reserv-id">${esc(r.unidad)}</div>
        <div class="reserv-empresa">${esc(empresaMap[r.unidad] || '—')}</div>
        <div>${fmtFecha(r.fecha_ini)}</div>
        <div>${fmtFecha(r.fecha_fin)}</div>
        <div><span class="badge ${badgeCls}">${esc(r.estado)}</span></div>
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
    const { data: misCamiones } = await sb.from('camiones')
      .select('id').eq('propietario_id', currentUser.id);
    if (!misCamiones?.length) {
      body.innerHTML = `<div class="empty-state"><div class="icon">🚛</div>No tienes unidades registradas.</div>`;
      return;
    }
    reservQuery = reservQuery.in('unidad', misCamiones.map(c => c.id));
  }

  const { data, error } = await reservQuery;
  if (error) { body.innerHTML = `<div class="empty-state"><div class="icon">❌</div>Error al cargar.</div>`; return; }
  if (!data.length) { body.innerHTML = `<div class="empty-state"><div class="icon">📋</div>No hay reservaciones registradas.</div>`; return; }

  const unidades = [...new Set(data.map(r => r.unidad))];
  const { data: camiones } = await sb.from('camiones')
    .select('id, propietario_id, propietario:perfiles(nombre)').in('id', unidades);
  const empresaMap = {};
  const ownerMap  = {};
  (camiones || []).forEach(c => {
    empresaMap[c.id] = c.propietario?.nombre || '—';
    ownerMap[c.id]   = c.propietario_id;
  });

  body.innerHTML = data.map(r => {
    const esCancelada = r.estado === 'Cancelada';
    const esRechazada = r.estado === 'Rechazada';
    const esPendiente = r.estado === 'Pendiente';
    const esActiva    = r.estado === 'Activa';
    const inactiva    = esCancelada || esRechazada;

    const badgeCls = esPendiente ? 'badge-busy'
                   : esActiva    ? 'badge-avail'
                   : 'badge-maint';

    const esDueno = currentUser.rol === 'superadmin' || ownerMap[r.unidad] === currentUser.id;
    let acciones = '';
    if (esDueno && esPendiente) {
      acciones = `
        <button class="btn-aceptar-reserva"  onclick="aceptarReserva('${r.id}','${esc(r.unidad)}')">✓ Aceptar</button>
        <button class="btn-rechazar-reserva" onclick="rechazarReserva('${r.id}','${esc(r.unidad)}')">✕ Rechazar</button>`;
    } else if (esDueno && esActiva) {
      acciones = `<button class="btn-cancelar-reserva" onclick="cancelarReserva('${r.id}','${esc(r.unidad)}')">Cancelar</button>`;
    }

    return `
    <div class="reserv-row ${inactiva ? 'reserv-cancelada' : ''}">
      <div class="reserv-id">${esc(r.unidad)}</div>
      <div class="reserv-empresa">${esc(empresaMap[r.unidad] || '—')}</div>
      <div>${esc(r.cliente)}</div>
      <div>${fmtFecha(r.fecha_ini)}</div>
      <div>${fmtFecha(r.fecha_fin)}</div>
      <div style="display:flex;gap:5px;align-items:center;flex-wrap:wrap">
        <span class="badge ${badgeCls}">${esc(r.estado)}</span>
        ${acciones}
      </div>
    </div>`;
  }).join('');
}

// ── ACCIONES ───────────────────────────────────────────

async function aceptarReserva(reservaId, unidad) {
  // Obtener datos antes de actualizar para el email
  const { data: r } = await sb.from('reservaciones').select('*').eq('id', reservaId).single();
  await sb.from('reservaciones').update({ estado: 'Activa' }).eq('id', reservaId);
  await sb.from('camiones').update({ estado: 'ocupado' }).eq('id', unidad);

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
  showToast('✓ Reserva aceptada — camión marcado como en servicio');
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
  if (!confirm('¿Cancelar esta reserva? El camión volverá a estar disponible.')) return;
  await sb.from('reservaciones').update({ estado: 'Cancelada' }).eq('id', reservaId);
  await sb.from('camiones').update({ estado: 'disponible' }).eq('id', unidad);
  await renderReserv();
  showToast('Reserva cancelada — camión disponible de nuevo');
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
