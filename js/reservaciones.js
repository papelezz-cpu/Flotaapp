// ── RESERVACIONES ─────────────────────────────────────

async function renderReserv() {
  const body = document.getElementById('reserv-body');
  // #6 — Skeleton loader
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
    .select('id, propietario:perfiles(nombre)').in('id', unidades);
  const empresaMap = {};
  (camiones || []).forEach(c => { empresaMap[c.id] = c.propietario?.nombre || '—'; });

  // #1 XSS + #8 cancelar reserva
  const canCancel = ['admin','superadmin'].includes(currentUser.rol);
  body.innerHTML = data.map(r => {
    const esCancelada = r.estado === 'Cancelada';
    const badgeCls = esCancelada ? 'badge-maint' : 'badge-avail';
    return `
    <div class="reserv-row ${esCancelada ? 'reserv-cancelada' : ''}">
      <div class="reserv-id">${esc(r.unidad)}</div>
      <div class="reserv-empresa">${esc(empresaMap[r.unidad] || '—')}</div>
      <div>${esc(r.cliente)}</div>
      <div>${fmtFecha(r.fecha_ini)}</div>
      <div>${fmtFecha(r.fecha_fin)}</div>
      <div style="display:flex;gap:6px;align-items:center">
        <span class="badge ${badgeCls}">${esc(r.estado)}</span>
        ${canCancel && !esCancelada ? `<button class="btn-cancelar-reserva" onclick="cancelarReserva('${r.id}','${esc(r.unidad)}')">✕</button>` : ''}
      </div>
    </div>`;
  }).join('');
}

// #8 — Cancelar reserva
async function cancelarReserva(reservaId, unidad) {
  if (!confirm('¿Cancelar esta reserva? El camión volverá a estar disponible.')) return;
  await sb.from('reservaciones').update({ estado: 'Cancelada' }).eq('id', reservaId);
  await sb.from('camiones').update({ estado: 'disponible' }).eq('id', unidad);
  await renderReserv();
  showToast('Reserva cancelada — camión disponible de nuevo');
}
