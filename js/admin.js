// ── PANEL DE ADMINISTRACIÓN ───────────────────────────

async function renderAdmin() {
  const list = document.getElementById('admin-list');
  list.innerHTML = `<div class="empty-state"><div class="icon">⏳</div>Cargando...</div>`;

  let query = sb.from('camiones')
    .select('*, propietario:perfiles(nombre)')
    .eq('aprobacion', 'aprobada')
    .order('id');

  if (currentUser.rol !== 'superadmin') {
    query = query.eq('propietario_id', currentUser.id);
  }

  const { data, error } = await query;
  if (error) {
    list.innerHTML = `<div class="empty-state"><div class="icon">❌</div>Error.</div>`;
    return;
  }
  allCamiones = data;

  if (!data.length) {
    list.innerHTML = `<div class="empty-state"><div class="icon">🚛</div>No tienes unidades aprobadas.</div>`;
  } else {
    list.innerHTML = data.map(c => {
      const badgeClass = c.estado === 'disponible' ? 'badge-avail' : c.estado === 'ocupado' ? 'badge-busy' : 'badge-maint';
      const empresa    = c.propietario?.nombre || '—';
      return `
        <div class="truck-list-item">
          <div class="truck-list-item-info">
            <div class="truck-list-item-name">${c.emoji} ${c.id} — ${c.tipo}</div>
            <div class="truck-list-item-sub">
              ${c.operador} · ${c.capacidad} ton ·
              <span class="badge ${badgeClass}" style="font-size:0.68rem">${c.estado}</span>
              ${currentUser.rol === 'superadmin' ? `· <em style="color:var(--text-muted)">${empresa}</em>` : ''}
            </div>
          </div>
          <div style="display:flex;gap:6px">
            <button class="btn-edit" onclick="toggleEstado('${c.id}','${c.estado}')">Cambiar estado</button>
            <button class="btn-edit btn-rechazar" onclick="eliminarUnidad('${c.id}')">🗑</button>
          </div>
        </div>`;
    }).join('');
  }

  renderPendientes();
  if (currentUser.rol !== 'superadmin') renderMisPendientes();
}

// Muestra las unidades pendientes del propio admin (no superadmin)
async function renderMisPendientes() {
  const { data } = await sb.from('camiones')
    .select('*')
    .eq('propietario_id', currentUser.id)
    .eq('aprobacion', 'pendiente')
    .order('created_at', { ascending: false });

  const section = document.getElementById('pendientes-section');
  const list    = document.getElementById('pendientes-list');

  if (!data?.length) { section.style.display = 'none'; return; }

  section.style.display = 'block';
  // Sobrescribir el título de la sección
  const titulo = section.querySelector('.section-title');
  if (titulo) titulo.innerHTML = '⏳ Mis unidades en espera de aprobación';

  list.innerHTML = data.map(c => `
    <div class="truck-list-item">
      <div class="truck-list-item-info">
        <div class="truck-list-item-name">${c.emoji} ${c.id} — ${c.tipo}</div>
        <div class="truck-list-item-sub">${c.operador} · ${c.capacidad} ton</div>
      </div>
      <span class="badge badge-busy" style="font-size:0.72rem">⏳ Pendiente</span>
    </div>`).join('');
}

// Muestra las unidades pendientes de TODOS (solo superadmin)
async function renderPendientes() {
  if (currentUser.rol !== 'superadmin') return;

  const section = document.getElementById('pendientes-section');
  const list    = document.getElementById('pendientes-list');
  list.innerHTML = `<div class="empty-state"><div class="icon">⏳</div>Cargando...</div>`;

  const { data } = await sb.from('camiones')
    .select('*, propietario:perfiles(nombre)')
    .eq('aprobacion', 'pendiente')
    .order('created_at', { ascending: false });

  if (!data?.length) { section.style.display = 'none'; return; }

  section.style.display = 'block';
  list.innerHTML = data.map(c => `
    <div class="truck-list-item">
      <div class="truck-list-item-info">
        <div class="truck-list-item-name">${c.emoji} ${c.id} — ${c.tipo}</div>
        <div class="truck-list-item-sub">
          ${c.operador} · ${c.capacidad} ton ·
          <em style="color:var(--text-muted)">${c.propietario?.nombre || '—'}</em>
        </div>
      </div>
      <div style="display:flex;gap:6px;flex-wrap:wrap;align-items:center">
        ${(c.archivos || []).length ? `<button class="btn-edit" onclick="verArchivos('${c.id}')">📎 Archivos</button>` : ''}
        <button class="btn-edit btn-aprobar" onclick="aprobarUnidad('${c.id}')">✓ Aprobar</button>
        <button class="btn-edit btn-rechazar" onclick="rechazarUnidad('${c.id}')">✕ Rechazar</button>
      </div>
    </div>`).join('');
}

async function aprobarUnidad(id) {
  const { error } = await sb.from('camiones').update({ aprobacion: 'aprobada' }).eq('id', id);
  if (error) { showToast('Error al aprobar'); return; }
  await renderAdmin();
  showToast(`✓ Unidad ${id} aprobada y publicada`);
}

async function rechazarUnidad(id) {
  if (!confirm(`¿Rechazar la unidad ${id}? Se eliminará del sistema.`)) return;
  const { data: c } = await sb.from('camiones').select('archivos').eq('id', id).single();
  if (c?.archivos?.length) await sb.storage.from('unidades').remove(c.archivos);
  await sb.from('camiones').delete().eq('id', id);
  await renderAdmin();
  showToast(`Unidad ${id} rechazada`);
}

async function eliminarUnidad(id) {
  if (!confirm(`¿Eliminar la unidad ${id}? Esta acción no se puede deshacer.`)) return;
  const { data: c } = await sb.from('camiones').select('archivos').eq('id', id).single();
  if (c?.archivos?.length) await sb.storage.from('unidades').remove(c.archivos);
  const { error } = await sb.from('camiones').delete().eq('id', id);
  if (error) { showToast('Error: no tienes permiso para eliminar esta unidad'); return; }
  await renderAdmin();
  showToast(`Unidad ${id} eliminada`);
}

async function verArchivos(id) {
  const modal = document.getElementById('modal-archivos');
  const list  = document.getElementById('archivos-list');
  document.getElementById('modal-archivos-sub').textContent = `Unidad ${id}`;
  list.innerHTML = `<div style="color:var(--text-muted);font-size:0.85rem">Generando enlaces seguros...</div>`;
  modal.classList.add('open');

  const { data: c } = await sb.from('camiones').select('archivos').eq('id', id).single();
  const archivos = c?.archivos || [];

  if (!archivos.length) {
    list.innerHTML = `<div style="color:var(--text-muted);font-size:0.85rem">Sin archivos adjuntos.</div>`;
    return;
  }

  const links = await Promise.all(archivos.map(async path => {
    const { data } = await sb.storage.from('unidades').createSignedUrl(path, 3600);
    return { path, url: data?.signedUrl };
  }));

  list.innerHTML = links.map(f => {
    const nombre = f.path.split('/').pop();
    const esImg  = /\.(jpg|jpeg|png|gif|webp)$/i.test(nombre);
    return `<div class="archivo-item">
      ${esImg ? `<img src="${f.url}" class="archivo-preview">` : ''}
      <a href="${f.url}" target="_blank" class="archivo-link">📎 ${nombre}</a>
    </div>`;
  }).join('');
}

async function toggleEstado(id, estadoActual) {
  const opts = ['disponible', 'ocupado', 'mantenimiento'];
  const next = opts[(opts.indexOf(estadoActual) + 1) % opts.length];
  const { error } = await sb.from('camiones').update({ estado: next }).eq('id', id);
  if (error) { showToast('Error: no tienes permiso para cambiar este camión'); return; }
  await renderAdmin();
  showToast(`Estado de ${id} cambiado a: ${next}`);
}

async function agregarCamion() {
  const tipo   = document.getElementById('admin-tipo').value;
  const cap    = parseInt(document.getElementById('admin-cap').value) || 0;
  const op     = document.getElementById('admin-op').value.trim();
  const estado = document.getElementById('admin-estado').value;

  if (!op || !cap) { alert('Completa todos los campos.'); return; }

  // Generar ID automático
  const prefijos = { 'Torton': 'T', 'Rabón': 'R', 'Full': 'F', 'Plataforma': 'P' };
  const letra = prefijos[tipo] || 'U';
  const { data: existentes } = await sb.from('camiones').select('id').like('id', `${letra}-%`);
  const maxNum = (existentes || []).reduce((max, c) => {
    const n = parseInt(c.id.split('-')[1]) || 0;
    return Math.max(max, n);
  }, 0);
  const id = `${letra}-${String(maxNum + 1).padStart(3, '0')}`;

  // Subir archivos al storage
  const fotosFiles = Array.from(document.getElementById('admin-fotos').files || []);
  const docsFiles  = Array.from(document.getElementById('admin-docs').files  || []);
  const archivos   = [];
  for (const file of [...fotosFiles, ...docsFiles]) {
    const path = `${currentUser.id}/${id}/${Date.now()}_${file.name}`;
    const { data: up, error: upErr } = await sb.storage.from('unidades').upload(path, file);
    if (!upErr && up) archivos.push(up.path);
  }

  const esSuperAdmin = currentUser.rol === 'superadmin';
  const emojis = { 'Torton': '🚛', 'Rabón': '🚚', 'Full': '🚛', 'Plataforma': '🏗️' };
  const { error } = await sb.from('camiones').insert({
    id, tipo, capacidad: cap, operador: op, estado,
    emoji: emojis[tipo] || '🚛',
    propietario_id: currentUser.id,
    archivos,
    aprobacion: esSuperAdmin ? 'aprobada' : 'pendiente'
  });
  if (error) { alert('Error: ' + (error.message || 'No se pudo agregar.')); return; }

  // Notificar al superadmin por email si la unidad queda pendiente
  if (!esSuperAdmin) {
    try {
      const session = (await sb.auth.getSession()).data.session;
      await fetch(`${FN_URL.replace('gestionar-usuario', 'enviar-notificacion')}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session.access_token}`
        },
        body: JSON.stringify({
          camion: { id, tipo, operador: op, capacidad: cap, estado },
          propietarioNombre: currentUser.nombre
        })
      });
    } catch (_) { /* El email falla silenciosamente */ }
  }

  // Limpiar formulario
  document.getElementById('admin-op').value    = '';
  document.getElementById('admin-cap').value   = '';
  document.getElementById('admin-fotos').value = '';
  document.getElementById('admin-docs').value  = '';
  document.getElementById('fotos-label').textContent = 'Seleccionar fotos';
  document.getElementById('docs-label').textContent  = 'Seleccionar documentos (PDF / imagen)';

  await renderAdmin();
  showToast(esSuperAdmin
    ? `✓ Unidad ${id} agregada`
    : `✓ Unidad ${id} enviada — recibirás confirmación por correo`);
}

function updateFileLabel(inputId, labelId) {
  const files = document.getElementById(inputId).files;
  const label = document.getElementById(labelId);
  if (!files.length) {
    label.textContent = inputId === 'admin-fotos'
      ? 'Seleccionar fotos'
      : 'Seleccionar documentos (PDF / imagen)';
  } else {
    label.textContent = `${files.length} archivo${files.length > 1 ? 's' : ''} seleccionado${files.length > 1 ? 's' : ''}`;
  }
}
