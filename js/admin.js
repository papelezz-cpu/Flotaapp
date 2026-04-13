// ── PANEL DE ADMINISTRACIÓN ───────────────────────────

async function renderAdmin() {
  const list = document.getElementById('admin-list');
  list.innerHTML = `<div class="empty-state"><div class="icon">⏳</div>Cargando...</div>`;

  const { data, error } = await sb.from('camiones').select('*').order('id');
  if (error) {
    list.innerHTML = `<div class="empty-state"><div class="icon">❌</div>Error.</div>`;
    return;
  }
  allCamiones = data;

  list.innerHTML = data.map(c => {
    const badgeClass = c.estado === 'disponible' ? 'badge-avail' : c.estado === 'ocupado' ? 'badge-busy' : 'badge-maint';
    return `
      <div class="truck-list-item">
        <div class="truck-list-item-info">
          <div class="truck-list-item-name">${c.emoji} ${c.id} — ${c.tipo}</div>
          <div class="truck-list-item-sub">
            ${c.operador} · ${c.capacidad} ton ·
            <span class="badge ${badgeClass}" style="font-size:0.68rem">${c.estado}</span>
          </div>
        </div>
        <button class="btn-edit" onclick="toggleEstado('${c.id}','${c.estado}')">Cambiar estado</button>
      </div>`;
  }).join('');
}

async function toggleEstado(id, estadoActual) {
  const opts = ['disponible', 'ocupado', 'mantenimiento'];
  const next = opts[(opts.indexOf(estadoActual) + 1) % opts.length];
  await sb.from('camiones').update({ estado: next }).eq('id', id);
  await renderAdmin();
  showToast(`Estado de ${id} cambiado a: ${next}`);
}

async function agregarCamion() {
  const id     = document.getElementById('admin-id').value.trim();
  const tipo   = document.getElementById('admin-tipo').value;
  const cap    = parseInt(document.getElementById('admin-cap').value) || 0;
  const op     = document.getElementById('admin-op').value.trim();
  const estado = document.getElementById('admin-estado').value;

  if (!id || !op || !cap) { alert('Completa todos los campos.'); return; }

  const emojis = { 'Torton': '🚛', 'Rabón': '🚚', 'Full': '🚛', 'Plataforma': '🏗️' };
  const { error } = await sb.from('camiones').insert({
    id, tipo, capacidad: cap, operador: op, estado,
    emoji: emojis[tipo] || '🚛'
  });
  if (error) { alert('Error: ' + (error.message || 'No se pudo agregar.')); return; }

  document.getElementById('admin-id').value  = '';
  document.getElementById('admin-op').value  = '';
  document.getElementById('admin-cap').value = '';
  await renderAdmin();
  showToast(`✓ Unidad ${id} agregada`);
}
