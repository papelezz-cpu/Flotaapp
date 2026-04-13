// ── RESERVACIONES ─────────────────────────────────────

async function renderReserv() {
  const body = document.getElementById('reserv-body');
  body.innerHTML = `<div class="empty-state"><div class="icon">⏳</div>Cargando...</div>`;

  const { data, error } = await sb.from('reservaciones')
    .select('*')
    .order('created_at', { ascending: false });

  if (error) {
    body.innerHTML = `<div class="empty-state"><div class="icon">❌</div>Error al cargar.</div>`;
    return;
  }
  if (!data.length) {
    body.innerHTML = `<div class="empty-state"><div class="icon">📋</div>No hay reservaciones registradas.</div>`;
    return;
  }

  // Obtener propietarios de los camiones involucrados
  const unidades = [...new Set(data.map(r => r.unidad))];
  const { data: camiones } = await sb.from('camiones')
    .select('id, propietario_id')
    .in('id', unidades);

  const ownerIds = [...new Set((camiones || []).map(c => c.propietario_id).filter(Boolean))];
  let ownerMap = {};
  if (ownerIds.length) {
    const { data: perfiles } = await sb.from('perfiles')
      .select('user_id, nombre')
      .in('user_id', ownerIds);
    (perfiles || []).forEach(p => { ownerMap[p.user_id] = p.nombre; });
  }

  // Mapa unidad → empresa
  const empresaMap = {};
  (camiones || []).forEach(c => {
    empresaMap[c.id] = ownerMap[c.propietario_id] || '—';
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
