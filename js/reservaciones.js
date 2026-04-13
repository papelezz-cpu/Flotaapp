// ── RESERVACIONES ─────────────────────────────────────

async function renderReserv() {
  const body = document.getElementById('reserv-body');
  body.innerHTML = `<div class="empty-state"><div class="icon">⏳</div>Cargando...</div>`;

  // Admin solo ve reservaciones de sus propios camiones
  let reservQuery = sb.from('reservaciones')
    .select('*')
    .order('created_at', { ascending: false });

  if (currentUser.rol !== 'superadmin') {
    const { data: misCamiones } = await sb.from('camiones')
      .select('id')
      .eq('propietario_id', currentUser.id);

    if (!misCamiones || !misCamiones.length) {
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

  // Obtener empresa (propietario) usando el mismo join que funciona en admin.js
  const unidades = [...new Set(data.map(r => r.unidad))];
  const { data: camiones } = await sb.from('camiones')
    .select('id, propietario:perfiles(nombre)')
    .in('id', unidades);

  const empresaMap = {};
  (camiones || []).forEach(c => {
    empresaMap[c.id] = c.propietario?.nombre || '—';
  });

  body.innerHTML = data.map(r => `
    <div class="reserv-row">
      <div class="reserv-id">${r.unidad}</div>
      <div class="reserv-empresa">${empresaMap[r.unidad] || '—'}</div>
      <div>${r.cliente}</div>
      <div>${r.fecha_ini}</div>
      <div>${r.fecha_fin}</div>
      <div><span class="badge badge-avail">${r.estado}</span></div>
    </div>`).join('');
}
