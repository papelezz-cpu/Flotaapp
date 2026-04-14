// ── RESERVACIONES ─────────────────────────────────────

async function renderReserv() {
  const body = document.getElementById('reserv-body');
  body.innerHTML = skeletonRows(4);

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
  if (error) {
    body.innerHTML = `<div class="empty-state"><div class="icon">❌</div>Error al cargar.</div>`;
    return;
  }
  if (!data.length) {
    body.innerHTML = `<div class="empty-state"><div class="icon">📋</div>No hay reservaciones registradas.</div>`;
    return;
  }

  const unidades = [...new Set(data.map(r => r.unidad))];
  const { data: camiones } = await sb.from('camiones')
    .select('id, propietario_id, propietario:perfiles(nombre)').in('id', unidades);
  const empresaMap = {};
  const ownerMap  = {};
  (camiones || []).forEach(c => {
    empresaMap[c.id] = c.propietario?.nombre || '—';
    ownerMap[c.id]   = c.propietario_id;
  });

  const canManage = ['admin', 'superadmin'].includes(currentUser.rol);

  body.innerHTML = data.map(r => {
    const esCancelada  = r.estado === 'Cancelada';
    const esRechazada  = r.estado === 'Rechazada';
    const esPendiente  = r.estado === 'Pendiente';
    const esActiva     = r.estado === 'Activa';
    const inactiva     = esCancelada || esRechazada;

    const badgeCls = esPendiente ? 'badge-busy'
                   : esActiva    ? 'badge-avail'
                   : 'badge-maint';

    // El dueño del camión (o superadmin) puede aceptar/rechazar/cancelar
    const esDueno = currentUser.rol === 'superadmin' || ownerMap[r.unidad] === currentUser.id;

    let acciones = '';
    if (canManage && esDueno && esPendiente) {
      acciones = `
        <button class="btn-aceptar-reserva" onclick="aceptarReserva('${r.id}','${esc(r.unidad)}')">✓ Aceptar</button>
        <button class="btn-rechazar-reserva" onclick="rechazarReserva('${r.id}')">✕ Rechazar</button>`;
    } else if (canManage && esDueno && esActiva) {
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

// Aceptar reserva → estado Activa + camión ocupado
async function aceptarReserva(reservaId, unidad) {
  await sb.from('reservaciones').update({ estado: 'Activa' }).eq('id', reservaId);
  await sb.from('camiones').update({ estado: 'ocupado' }).eq('id', unidad);
  await renderReserv();
  await loadNotificaciones();
  showToast('✓ Reserva aceptada — camión marcado como en servicio');
}

// Rechazar reserva
async function rechazarReserva(reservaId) {
  if (!confirm('¿Rechazar esta solicitud?')) return;
  await sb.from('reservaciones').update({ estado: 'Rechazada' }).eq('id', reservaId);
  await renderReserv();
  await loadNotificaciones();
  showToast('Solicitud rechazada');
}

// Cancelar reserva activa
async function cancelarReserva(reservaId, unidad) {
  if (!confirm('¿Cancelar esta reserva? El camión volverá a estar disponible.')) return;
  await sb.from('reservaciones').update({ estado: 'Cancelada' }).eq('id', reservaId);
  await sb.from('camiones').update({ estado: 'disponible' }).eq('id', unidad);
  await renderReserv();
  showToast('Reserva cancelada — camión disponible de nuevo');
}
