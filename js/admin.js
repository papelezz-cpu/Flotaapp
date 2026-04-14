// ── PANEL DE ADMINISTRACIÓN ───────────────────────────

const CARGO_TIPOS = ['General','Refrigerado','Peligroso','Frágil','Granel','Maquinaria','Automóviles','Contenedor'];

const DIM_DEFAULTS = {
  'Torton':     '8.5m × 2.4m × 2.5m',
  'Rabón':      '5.5m × 2.4m × 2.4m',
  'Full':       '14.5m × 2.5m × 2.6m',
  'Plataforma': '13.5m × 2.5m — abierta',
};

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
            <button class="btn-edit" onclick="editarCamion('${c.id}')">✏ Editar</button>
            <button class="btn-edit btn-rechazar" onclick="eliminarUnidad('${c.id}')">🗑</button>
          </div>
        </div>`;
    }).join('');
  }

  // Inicializar chips del formulario de agregar
  renderCargoChipsSelect('admin-tipo-carga', []);
  autoFillDimensiones('admin');

  // Cargar perfil de empresa
  await renderPerfilEmpresa();

  renderPendientes();
  if (currentUser.rol !== 'superadmin') renderMisPendientes();
}

// ── PERFIL DE EMPRESA ─────────────────────────────────

function togglePerfilCard() {
  const body = document.getElementById('perfil-card-body');
  const icon = document.getElementById('perfil-toggle-icon');
  const isOpen = body.style.display !== 'none';
  body.style.display = isOpen ? 'none' : 'block';
  icon.textContent   = isOpen ? '▼ Editar' : '▲ Ocultar';
}

async function renderPerfilEmpresa() {
  if (!currentUser.id) return;
  const { data: p } = await sb.from('perfiles').select('*').eq('user_id', currentUser.id).single();
  if (!p) return;
  const set = (id, val) => { const el = document.getElementById(id); if (el) el.value = val ?? ''; };
  set('pe-razon',    p.razon_social);
  set('pe-rfc',      p.rfc);
  set('pe-telefono', p.telefono);
  set('pe-anos',     p.anos_operacion);
  set('pe-unidades', p.num_unidades);
  set('pe-sct',      p.permiso_sct);
  set('pe-desc',     p.descripcion);
  const rc    = document.getElementById('pe-rc');
  const carga = document.getElementById('pe-carga');
  if (rc)    rc.checked    = !!p.seguro_rc;
  if (carga) carga.checked = !!p.seguro_carga;
}

async function guardarPerfilEmpresa() {
  const payload = {
    razon_social:   document.getElementById('pe-razon').value.trim(),
    rfc:            document.getElementById('pe-rfc').value.trim(),
    telefono:       document.getElementById('pe-telefono').value.trim(),
    anos_operacion: parseInt(document.getElementById('pe-anos').value)    || null,
    num_unidades:   parseInt(document.getElementById('pe-unidades').value) || null,
    permiso_sct:    document.getElementById('pe-sct').value.trim(),
    descripcion:    document.getElementById('pe-desc').value.trim(),
    seguro_rc:      document.getElementById('pe-rc').checked,
    seguro_carga:   document.getElementById('pe-carga').checked,
  };
  const { error } = await sb.from('perfiles').update(payload).eq('user_id', currentUser.id);
  if (error) { showToast('Error al guardar perfil'); return; }
  showToast('✓ Perfil actualizado');
  togglePerfilCard();
}

// ── CHIPS DE TIPO DE CARGA ────────────────────────────

function renderCargoChipsSelect(containerId, selected = []) {
  const container = document.getElementById(containerId);
  if (!container) return;
  container.innerHTML = CARGO_TIPOS.map(t => {
    const sel = selected.includes(t) ? 'selected' : '';
    return `<button type="button" class="cargo-chip-toggle ${sel}" onclick="toggleCargaChip(this)">${esc(t)}</button>`;
  }).join('');
}

function toggleCargaChip(btn) {
  btn.classList.toggle('selected');
}

function getSelectedCargo(containerId) {
  return Array.from(document.querySelectorAll(`#${containerId} .cargo-chip-toggle.selected`))
    .map(b => b.textContent);
}

// ── DIMENSIONES AUTO-FILL ─────────────────────────────

function autoFillDimensiones(prefix = 'admin') {
  const tipo  = document.getElementById(`${prefix}-tipo`)?.value;
  const dimEl = document.getElementById(`${prefix}-dim`);
  if (dimEl && tipo && DIM_DEFAULTS[tipo] && !dimEl.value) {
    dimEl.value = DIM_DEFAULTS[tipo];
  }
}

// ── EDITAR CAMIÓN ─────────────────────────────────────

async function editarCamion(id) {
  const c = allCamiones.find(x => x.id === id);
  if (!c) return;

  document.getElementById('editar-id').value          = c.id;
  document.getElementById('editar-subtitulo').textContent = `Unidad ${c.id} — ${c.tipo}`;
  document.getElementById('editar-tipo').value         = c.tipo;
  document.getElementById('editar-cap').value          = c.capacidad;
  document.getElementById('editar-op').value           = c.operador;
  document.getElementById('editar-placas').value       = c.placas || '';
  document.getElementById('editar-dim').value          = c.dimensiones || '';
  document.getElementById('editar-tiempo').value       = c.tiempo_respuesta || '';
  document.getElementById('editar-precio').value       = c.precio_dia || '';
  document.getElementById('editar-estado').value       = c.estado;

  renderCargoChipsSelect('editar-tipo-carga', c.tipo_carga || []);
  document.getElementById('modal-editar').classList.add('open');
}

function closeEditarCamion() {
  document.getElementById('modal-editar').classList.remove('open');
}

async function guardarEdicion() {
  const id = document.getElementById('editar-id').value;
  const tipo = document.getElementById('editar-tipo').value;
  const payload = {
    tipo,
    capacidad:        parseInt(document.getElementById('editar-cap').value)    || 0,
    operador:         document.getElementById('editar-op').value.trim(),
    placas:           document.getElementById('editar-placas').value.trim()    || null,
    dimensiones:      document.getElementById('editar-dim').value.trim()       || null,
    tipo_carga:       getSelectedCargo('editar-tipo-carga'),
    tiempo_respuesta: document.getElementById('editar-tiempo').value           || null,
    precio_dia:       parseFloat(document.getElementById('editar-precio').value) || null,
    estado:           document.getElementById('editar-estado').value,
    emoji:            { Torton:'🚛', Rabón:'🚚', Full:'🚛', Plataforma:'🏗️' }[tipo] || '🚛',
  };

  const { error } = await sb.from('camiones').update(payload).eq('id', id);
  if (error) { showToast('Error: ' + (error.message || 'No se pudo actualizar')); return; }
  closeEditarCamion();
  await renderAdmin();
  showToast(`✓ Unidad ${id} actualizada`);
}

// ── PENDIENTES ────────────────────────────────────────

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
        <button class="btn-edit btn-aprobar"  onclick="aprobarUnidad('${c.id}')">✓ Aprobar</button>
        <button class="btn-edit btn-rechazar" onclick="rechazarUnidad('${c.id}')">✕ Rechazar</button>
      </div>
    </div>`).join('');
}

// ── APROBACIÓN / ELIMINACIÓN ──────────────────────────

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

// ── AGREGAR CAMIÓN ────────────────────────────────────

async function agregarCamion() {
  const tipo   = document.getElementById('admin-tipo').value;
  const cap    = parseInt(document.getElementById('admin-cap').value) || 0;
  const op     = document.getElementById('admin-op').value.trim();
  const estado = document.getElementById('admin-estado').value;
  const precio = parseFloat(document.getElementById('admin-precio').value) || null;
  const placas = document.getElementById('admin-placas').value.trim() || null;
  const dim    = document.getElementById('admin-dim').value.trim()    || null;
  const tiempo = document.getElementById('admin-tiempo').value        || null;
  const tipoCarga = getSelectedCargo('admin-tipo-carga');

  if (!op || !cap) { alert('Completa los campos obligatorios (operador y capacidad).'); return; }

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
    aprobacion: esSuperAdmin ? 'aprobada' : 'pendiente',
    ...(placas    && { placas }),
    ...(dim       && { dimensiones: dim }),
    ...(tiempo    && { tiempo_respuesta: tiempo }),
    ...(tipoCarga.length && { tipo_carga: tipoCarga }),
    ...(precio    && { precio_dia: precio }),
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
    } catch (_) { /* silencioso */ }
  }

  // Limpiar formulario
  ['admin-op','admin-cap','admin-precio','admin-placas','admin-dim'].forEach(id => {
    document.getElementById(id).value = '';
  });
  document.getElementById('admin-fotos').value  = '';
  document.getElementById('admin-docs').value   = '';
  document.getElementById('fotos-label').textContent = 'Seleccionar fotos';
  document.getElementById('docs-label').textContent  = 'Seleccionar documentos (PDF / imagen)';
  renderCargoChipsSelect('admin-tipo-carga', []);

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
