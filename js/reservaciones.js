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

  body.innerHTML = data.map(r => `
    <div class="reserv-row">
      <div class="reserv-id">${r.unidad}</div>
      <div>${r.cliente}</div>
      <div>${r.fecha_ini}</div>
      <div>${r.fecha_fin}</div>
      <div><span class="badge badge-avail">${r.estado}</span></div>
    </div>`).join('');
}
