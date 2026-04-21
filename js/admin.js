// ── PANEL DE ADMINISTRACIÓN ───────────────────────────

const CARGO_TIPOS = ['General','Refrigerado','Peligroso','Frágil','Granel','Maquinaria','Automóviles','Contenedor'];

let currentAdminTab = 'camion';

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

  // Render the currently active admin tab
  if (currentAdminTab === 'custodio') renderAdminCustodios();
  else if (currentAdminTab === 'patio') renderAdminPatios();
  else if (currentAdminTab === 'lavado') renderAdminLavados();
}

// ── TABS ADMIN ────────────────────────────────────────

function cambiarAdminTab(tab) {
  currentAdminTab = tab;
  ['camion','custodio','patio','lavado'].forEach(t => {
    document.getElementById(`admin-tab-${t}`)?.classList.toggle('active', t === tab);
    const el = document.getElementById(`admin-content-${t}`);
    if (el) el.style.display = t === tab ? '' : 'none';
  });
  if (tab === 'custodio') renderAdminCustodios();
  else if (tab === 'patio') renderAdminPatios();
  else if (tab === 'lavado') renderAdminLavados();
  else renderAdmin();
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
  const uid = currentUser.id;
  const [{ data: camPend }, { data: cusPend }, { data: patPend }, { data: lavPend }] = await Promise.all([
    sb.from('camiones' ).select('*').eq('propietario_id', uid).eq('aprobacion', 'pendiente').order('created_at', { ascending: false }),
    sb.from('custodios').select('*').eq('propietario_id', uid).eq('aprobacion', 'pendiente').order('created_at', { ascending: false }),
    sb.from('patios'   ).select('*').eq('propietario_id', uid).eq('aprobacion', 'pendiente').order('created_at', { ascending: false }),
    sb.from('lavados'  ).select('*').eq('propietario_id', uid).eq('aprobacion', 'pendiente').order('created_at', { ascending: false }),
  ]);

  const section = document.getElementById('pendientes-section');
  const list    = document.getElementById('pendientes-list');

  const todos = [
    ...(camPend || []).map(c => ({ tipo: 'camion',   label: `${c.emoji || '🚛'} ${c.id} — ${c.tipo}`, sub: `${c.operador} · ${c.capacidad} ton` })),
    ...(cusPend || []).map(c => ({ tipo: 'custodio', label: `👮 ${c.id} — ${c.nombre}`, sub: `${c.tipo} · ${c.disponibilidad || ''}` })),
    ...(patPend || []).map(p => ({ tipo: 'patio',    label: `🏭 ${p.id} — ${p.nombre}`, sub: `${p.tipo}${p.area_m2 ? ' · ' + p.area_m2 + ' m²' : ''}` })),
    ...(lavPend || []).map(l => ({ tipo: 'lavado',   label: `🚿 ${l.id} — ${l.nombre}`, sub: (l.tipos_vehiculo || []).join(', ') || '—' })),
  ];

  if (!todos.length) { section.style.display = 'none'; return; }

  section.style.display = 'block';
  const titulo = section.querySelector('.section-title');
  if (titulo) titulo.innerHTML = '⏳ Mis servicios en espera de aprobación';

  list.innerHTML = todos.map(t => `
    <div class="truck-list-item">
      <div class="truck-list-item-info">
        <div class="truck-list-item-name">${t.label}</div>
        <div class="truck-list-item-sub">${t.sub}</div>
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

  const [{ data: camiones }, { data: custodios }, { data: patios }, { data: lavados }] = await Promise.all([
    sb.from('camiones' ).select('*, propietario:perfiles(nombre)').eq('aprobacion', 'pendiente').order('created_at', { ascending: false }),
    sb.from('custodios').select('*, propietario:perfiles(nombre)').eq('aprobacion', 'pendiente').order('created_at', { ascending: false }),
    sb.from('patios'   ).select('*, propietario:perfiles(nombre)').eq('aprobacion', 'pendiente').order('created_at', { ascending: false }),
    sb.from('lavados'  ).select('*, propietario:perfiles(nombre)').eq('aprobacion', 'pendiente').order('created_at', { ascending: false }),
  ]);

  const total = (camiones?.length || 0) + (custodios?.length || 0) + (patios?.length || 0) + (lavados?.length || 0);
  if (!total) { section.style.display = 'none'; return; }

  section.style.display = 'block';

  const rowCamion = (c) => `
    <div class="truck-list-item">
      <div class="truck-list-item-info">
        <div class="truck-list-item-name">${c.emoji || '🚛'} ${c.id} — ${c.tipo}</div>
        <div class="truck-list-item-sub">${c.operador} · ${c.capacidad} ton · <em style="color:var(--text-muted)">${c.propietario?.nombre || '—'}</em></div>
      </div>
      <div style="display:flex;gap:6px;flex-wrap:wrap;align-items:center">
        ${(c.archivos || []).length ? `<button class="btn-edit" onclick="verArchivos('${c.id}')">📎 Archivos</button>` : ''}
        <button class="btn-edit btn-aprobar"  onclick="aprobarUnidad('${c.id}')">✓ Aprobar</button>
        <button class="btn-edit btn-rechazar" onclick="rechazarUnidad('${c.id}')">✕ Rechazar</button>
      </div>
    </div>`;

  const rowRecurso = (r, tipo, icon, label, sub) => `
    <div class="truck-list-item">
      <div class="truck-list-item-info">
        <div class="truck-list-item-name">${icon} ${r.id} — ${esc(label)}</div>
        <div class="truck-list-item-sub">${esc(sub)} · <em style="color:var(--text-muted)">${r.propietario?.nombre || '—'}</em></div>
      </div>
      <div style="display:flex;gap:6px;flex-wrap:wrap;align-items:center">
        <button class="btn-edit btn-aprobar"  onclick="aprobarRecurso('${tipo}','${r.id}')">✓ Aprobar</button>
        <button class="btn-edit btn-rechazar" onclick="rechazarRecurso('${tipo}','${r.id}')">✕ Rechazar</button>
      </div>
    </div>`;

  list.innerHTML = [
    ...(camiones  || []).map(c => rowCamion(c)),
    ...(custodios || []).map(c => rowRecurso(c, 'custodios', '👮', c.nombre, `${c.tipo} · ${c.disponibilidad || ''}`)),
    ...(patios    || []).map(p => rowRecurso(p, 'patios',    '🏭', p.nombre, `${p.tipo}${p.area_m2 ? ' · ' + p.area_m2 + ' m²' : ''}`)),
    ...(lavados   || []).map(l => rowRecurso(l, 'lavados',   '🚿', l.nombre, (l.tipos_vehiculo || []).join(', ') || '—')),
  ].join('');
}

async function aprobarRecurso(tabla, id) {
  const { error } = await sb.from(tabla).update({ aprobacion: 'aprobada' }).eq('id', id);
  if (error) { showToast('Error al aprobar'); return; }
  renderAdmin(); renderPendientes();
  showToast(`✓ ${id} aprobado y publicado en el catálogo`);
}

async function rechazarRecurso(tabla, id) {
  if (!confirm(`¿Rechazar ${id}? Se eliminará del sistema.`)) return;
  await sb.from(tabla).delete().eq('id', id);
  renderPendientes();
  showToast(`${id} rechazado`);
}

// ── APROBACIÓN / ELIMINACIÓN ──────────────────────────

async function aprobarUnidad(id) {
  const { error } = await sb.from('camiones').update({ aprobacion: 'aprobada' }).eq('id', id);
  if (error) { showToast('Error al aprobar'); return; }
  renderAdmin(); renderPendientes();
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

// ── CUSTODIOS (ADMIN) ─────────────────────────────────

async function renderAdminCustodios() {
  const list = document.getElementById('admin-custodios-list');
  if (!list) return;
  list.innerHTML = `<div class="empty-state"><div class="icon">⏳</div>Cargando...</div>`;

  let query = sb.from('custodios').select('*').eq('aprobacion', 'aprobada').order('id');
  if (currentUser.rol !== 'superadmin') query = query.eq('propietario_id', currentUser.id);
  const { data, error } = await query;
  if (error || !data?.length) {
    list.innerHTML = `<div class="empty-state"><div class="icon">👮</div>Sin custodios registrados.</div>`;
    return;
  }
  list.innerHTML = data.map(c => {
    const badgeCls = c.estado === 'disponible' ? 'badge-avail' : c.estado === 'ocupado' ? 'badge-busy' : 'badge-maint';
    return `
      <div class="truck-list-item">
        <div class="truck-list-item-info">
          <div class="truck-list-item-name">${CUSTODIO_EMOJI[c.tipo] || '👮'} ${c.id} — ${esc(c.nombre)}</div>
          <div class="truck-list-item-sub">
            ${esc(c.tipo)} · ${esc(c.disponibilidad || '—')} ·
            <span class="badge ${badgeCls}" style="font-size:0.68rem">${c.estado}</span>
          </div>
        </div>
        <div style="display:flex;gap:6px">
          <button class="btn-edit" onclick="editarCustodio('${c.id}')">✏ Editar</button>
          <button class="btn-edit btn-rechazar" onclick="eliminarCustodio('${c.id}')">🗑</button>
        </div>
      </div>`;
  }).join('');
}

async function agregarCustodio() {
  const nombre = document.getElementById('ac-nombre').value.trim();
  const tipo   = document.getElementById('ac-tipo').value;
  const desc   = document.getElementById('ac-desc').value.trim();
  const disp   = document.getElementById('ac-disp').value;
  const precio = parseFloat(document.getElementById('ac-precio').value) || null;
  const certs  = document.getElementById('ac-certs').value.trim();
  if (!nombre || !tipo) { alert('Completa nombre y tipo.'); return; }

  const { data: existentes } = await sb.from('custodios').select('id').like('id','CUS-%');
  const maxNum = (existentes || []).reduce((max, c) => {
    const n = parseInt(c.id.split('-')[1]) || 0; return Math.max(max, n);
  }, 0);
  const id = `CUS-${String(maxNum + 1).padStart(3,'0')}`;

  const esSuperAdmin = currentUser.rol === 'superadmin';
  const { error } = await sb.from('custodios').insert({
    id, nombre, tipo, descripcion: desc || null,
    disponibilidad: disp,
    precio_dia: precio,
    propietario_id: currentUser.id,
    certificaciones: certs ? certs.split(',').map(s => s.trim()).filter(Boolean) : [],
    aprobacion: esSuperAdmin ? 'aprobada' : 'pendiente',
  });
  if (error) { showToast('Error: ' + (error.message || '')); return; }

  ['ac-nombre','ac-desc','ac-precio','ac-certs'].forEach(i => {
    const el = document.getElementById(i); if (el) el.value = '';
  });
  await renderAdminCustodios();
  await renderMisPendientes();
  showToast(esSuperAdmin ? `✓ Custodio ${id} agregado` : `✓ Custodio ${id} enviado — recibirás confirmación`);
}

async function editarCustodio(id) {
  const { data: c } = await sb.from('custodios').select('*').eq('id', id).single();
  if (!c) return;
  document.getElementById('ec-id').value     = c.id;
  document.getElementById('ec-nombre').value = c.nombre;
  document.getElementById('ec-tipo').value   = c.tipo;
  document.getElementById('ec-desc').value   = c.descripcion || '';
  document.getElementById('ec-disp').value   = c.disponibilidad || '24/7';
  document.getElementById('ec-precio').value = c.precio_dia || '';
  document.getElementById('ec-certs').value  = (c.certificaciones || []).join(', ');
  document.getElementById('ec-estado').value = c.estado;
  document.getElementById('modal-editar-custodio').classList.add('open');
}

function closeEditarCustodio() {
  document.getElementById('modal-editar-custodio').classList.remove('open');
}

async function guardarEdicionCustodio() {
  const id = document.getElementById('ec-id').value;
  const certs = document.getElementById('ec-certs').value.trim();
  const { error } = await sb.from('custodios').update({
    nombre:          document.getElementById('ec-nombre').value.trim(),
    tipo:            document.getElementById('ec-tipo').value,
    descripcion:     document.getElementById('ec-desc').value.trim() || null,
    disponibilidad:  document.getElementById('ec-disp').value,
    precio_dia:      parseFloat(document.getElementById('ec-precio').value) || null,
    certificaciones: certs ? certs.split(',').map(s => s.trim()).filter(Boolean) : [],
    estado:          document.getElementById('ec-estado').value,
  }).eq('id', id);
  if (error) { showToast('Error: ' + (error.message || '')); return; }
  closeEditarCustodio();
  await renderAdminCustodios();
  showToast(`✓ Custodio ${id} actualizado`);
}

async function eliminarCustodio(id) {
  if (!confirm(`¿Eliminar custodio ${id}?`)) return;
  await sb.from('custodios').delete().eq('id', id);
  await renderAdminCustodios();
  showToast(`Custodio ${id} eliminado`);
}

// ── PATIOS (ADMIN) ─────────────────────────────────────

async function renderAdminPatios() {
  const list = document.getElementById('admin-patios-list');
  if (!list) return;
  list.innerHTML = `<div class="empty-state"><div class="icon">⏳</div>Cargando...</div>`;

  let query = sb.from('patios').select('*').eq('aprobacion', 'aprobada').order('id');
  if (currentUser.rol !== 'superadmin') query = query.eq('propietario_id', currentUser.id);
  const { data, error } = await query;
  if (error || !data?.length) {
    list.innerHTML = `<div class="empty-state"><div class="icon">🏭</div>Sin patios registrados.</div>`;
    return;
  }
  list.innerHTML = data.map(p => {
    const badgeCls = p.estado === 'disponible' ? 'badge-avail' : p.estado === 'ocupado' ? 'badge-busy' : 'badge-maint';
    return `
      <div class="truck-list-item">
        <div class="truck-list-item-info">
          <div class="truck-list-item-name">${PATIO_EMOJI[p.tipo] || '🏭'} ${p.id} — ${esc(p.nombre)}</div>
          <div class="truck-list-item-sub">
            ${esc(p.tipo)} · ${p.area_m2 ? p.area_m2 + ' m²' : '—'} ·
            <span class="badge ${badgeCls}" style="font-size:0.68rem">${p.estado}</span>
          </div>
        </div>
        <div style="display:flex;gap:6px">
          <button class="btn-edit" onclick="editarPatio('${p.id}')">✏ Editar</button>
          <button class="btn-edit btn-rechazar" onclick="eliminarPatio('${p.id}')">🗑</button>
        </div>
      </div>`;
  }).join('');
}

async function agregarPatio() {
  const nombre   = document.getElementById('ap-nombre').value.trim();
  const tipo     = document.getElementById('ap-tipo').value;
  const ubic     = document.getElementById('ap-ubic').value.trim();
  const area     = parseFloat(document.getElementById('ap-area').value) || null;
  const capVeh   = parseInt(document.getElementById('ap-cap').value)    || null;
  const precio   = parseFloat(document.getElementById('ap-precio').value) || null;
  const svcsRaw  = document.getElementById('ap-svcs').value.trim();
  if (!nombre || !tipo) { alert('Completa nombre y tipo.'); return; }

  const { data: existentes } = await sb.from('patios').select('id').like('id','PAT-%');
  const maxNum = (existentes || []).reduce((max, p) => {
    const n = parseInt(p.id.split('-')[1]) || 0; return Math.max(max, n);
  }, 0);
  const id = `PAT-${String(maxNum + 1).padStart(3,'0')}`;

  const esSuperAdmin = currentUser.rol === 'superadmin';
  const { error } = await sb.from('patios').insert({
    id, nombre, tipo,
    ubicacion: ubic || null,
    area_m2: area, capacidad_vehiculos: capVeh, precio_dia: precio,
    propietario_id: currentUser.id,
    servicios: svcsRaw ? svcsRaw.split(',').map(s => s.trim()).filter(Boolean) : [],
    aprobacion: esSuperAdmin ? 'aprobada' : 'pendiente',
  });
  if (error) { showToast('Error: ' + (error.message || '')); return; }

  ['ap-nombre','ap-ubic','ap-area','ap-cap','ap-precio','ap-svcs'].forEach(i => {
    const el = document.getElementById(i); if (el) el.value = '';
  });
  await renderAdminPatios();
  await renderMisPendientes();
  showToast(esSuperAdmin ? `✓ Patio ${id} agregado` : `✓ Patio ${id} enviado — recibirás confirmación`);
}

async function editarPatio(id) {
  const { data: p } = await sb.from('patios').select('*').eq('id', id).single();
  if (!p) return;
  document.getElementById('ep-id').value     = p.id;
  document.getElementById('ep-nombre').value = p.nombre;
  document.getElementById('ep-tipo').value   = p.tipo;
  document.getElementById('ep-ubic').value   = p.ubicacion || '';
  document.getElementById('ep-area').value   = p.area_m2 || '';
  document.getElementById('ep-cap').value    = p.capacidad_vehiculos || '';
  document.getElementById('ep-precio').value = p.precio_dia || '';
  document.getElementById('ep-svcs').value   = (p.servicios || []).join(', ');
  document.getElementById('ep-estado').value = p.estado;
  document.getElementById('modal-editar-patio').classList.add('open');
}

function closeEditarPatio() {
  document.getElementById('modal-editar-patio').classList.remove('open');
}

async function guardarEdicionPatio() {
  const id = document.getElementById('ep-id').value;
  const svcsRaw = document.getElementById('ep-svcs').value.trim();
  const { error } = await sb.from('patios').update({
    nombre:              document.getElementById('ep-nombre').value.trim(),
    tipo:                document.getElementById('ep-tipo').value,
    ubicacion:           document.getElementById('ep-ubic').value.trim()   || null,
    area_m2:             parseFloat(document.getElementById('ep-area').value)  || null,
    capacidad_vehiculos: parseInt(document.getElementById('ep-cap').value)     || null,
    precio_dia:          parseFloat(document.getElementById('ep-precio').value) || null,
    servicios:           svcsRaw ? svcsRaw.split(',').map(s => s.trim()).filter(Boolean) : [],
    estado:              document.getElementById('ep-estado').value,
  }).eq('id', id);
  if (error) { showToast('Error: ' + (error.message || '')); return; }
  closeEditarPatio();
  await renderAdminPatios();
  showToast(`✓ Patio ${id} actualizado`);
}

async function eliminarPatio(id) {
  if (!confirm(`¿Eliminar patio ${id}?`)) return;
  await sb.from('patios').delete().eq('id', id);
  await renderAdminPatios();
  showToast(`Patio ${id} eliminado`);
}

// ── LAVADOS (ADMIN) ────────────────────────────────────

async function renderAdminLavados() {
  const list = document.getElementById('admin-lavados-list');
  if (!list) return;
  list.innerHTML = `<div class="empty-state"><div class="icon">⏳</div>Cargando...</div>`;

  let query = sb.from('lavados').select('*').eq('aprobacion', 'aprobada').order('id');
  if (currentUser.rol !== 'superadmin') query = query.eq('propietario_id', currentUser.id);
  const { data, error } = await query;
  if (error || !data?.length) {
    list.innerHTML = `<div class="empty-state"><div class="icon">🚿</div>Sin servicios de lavado registrados.</div>`;
    return;
  }
  list.innerHTML = data.map(l => {
    const badgeCls = l.estado === 'disponible' ? 'badge-avail' : l.estado === 'ocupado' ? 'badge-busy' : 'badge-maint';
    const vehiculos = (l.tipos_vehiculo || []).join(', ') || '—';
    return `
      <div class="truck-list-item">
        <div class="truck-list-item-info">
          <div class="truck-list-item-name">🚿 ${l.id} — ${esc(l.nombre)}</div>
          <div class="truck-list-item-sub">
            ${esc(vehiculos)} ·
            <span class="badge ${badgeCls}" style="font-size:0.68rem">${l.estado}</span>
          </div>
        </div>
        <div style="display:flex;gap:6px">
          <button class="btn-edit" onclick="editarLavado('${l.id}')">✏ Editar</button>
          <button class="btn-edit btn-rechazar" onclick="eliminarLavado('${l.id}')">🗑</button>
        </div>
      </div>`;
  }).join('');
}

async function agregarLavado() {
  const nombre      = document.getElementById('al-nombre').value.trim();
  const tiposVehRaw = document.getElementById('al-tipos-vehiculo').value.trim();
  const tiposLavRaw = document.getElementById('al-tipos-lavado').value.trim();
  const capacidad   = parseInt(document.getElementById('al-capacidad').value) || null;
  const ubic        = document.getElementById('al-ubic').value.trim();
  const horario     = document.getElementById('al-horario').value.trim();
  const precio      = parseFloat(document.getElementById('al-precio').value) || null;
  const desc        = document.getElementById('al-desc').value.trim();

  if (!nombre) { alert('Escribe un nombre para el servicio.'); return; }

  const { data: existentes } = await sb.from('lavados').select('id').like('id','LAV-%');
  const maxNum = (existentes || []).reduce((max, l) => {
    const n = parseInt(l.id.split('-')[1]) || 0; return Math.max(max, n);
  }, 0);
  const id = `LAV-${String(maxNum + 1).padStart(3,'0')}`;

  const { error } = await sb.from('lavados').insert({
    id, nombre,
    tipos_vehiculo: tiposVehRaw ? tiposVehRaw.split(',').map(s => s.trim()).filter(Boolean) : [],
    tipos_lavado:   tiposLavRaw ? tiposLavRaw.split(',').map(s => s.trim()).filter(Boolean) : [],
    capacidad, ubicacion: ubic || null, horario: horario || null,
    precio_lavado: precio, descripcion: desc || null,
    propietario_id: currentUser.id,
    aprobacion: currentUser.rol === 'superadmin' ? 'aprobada' : 'pendiente',
  });
  if (error) { showToast('Error: ' + (error.message || '')); return; }

  ['al-nombre','al-tipos-vehiculo','al-tipos-lavado','al-capacidad','al-ubic','al-horario','al-precio','al-desc']
    .forEach(i => { const el = document.getElementById(i); if (el) el.value = ''; });
  await renderAdminLavados();
  await renderMisPendientes();
  showToast(currentUser.rol === 'superadmin' ? `✓ Servicio ${id} agregado` : `✓ Servicio ${id} enviado — recibirás confirmación`);
}

async function editarLavado(id) {
  const { data: l } = await sb.from('lavados').select('*').eq('id', id).single();
  if (!l) return;
  document.getElementById('elav-id').value             = l.id;
  document.getElementById('elav-nombre').value         = l.nombre;
  document.getElementById('elav-tipos-vehiculo').value = (l.tipos_vehiculo || []).join(', ');
  document.getElementById('elav-tipos-lavado').value   = (l.tipos_lavado   || []).join(', ');
  document.getElementById('elav-capacidad').value      = l.capacidad || '';
  document.getElementById('elav-ubic').value           = l.ubicacion || '';
  document.getElementById('elav-horario').value        = l.horario   || '';
  document.getElementById('elav-precio').value         = l.precio_lavado || '';
  document.getElementById('elav-estado').value         = l.estado;
  document.getElementById('modal-editar-lavado').classList.add('open');
}

function closeEditarLavado() {
  document.getElementById('modal-editar-lavado').classList.remove('open');
}

async function guardarEdicionLavado() {
  const id = document.getElementById('elav-id').value;
  const tiposVehRaw = document.getElementById('elav-tipos-vehiculo').value.trim();
  const tiposLavRaw = document.getElementById('elav-tipos-lavado').value.trim();
  const { error } = await sb.from('lavados').update({
    nombre:         document.getElementById('elav-nombre').value.trim(),
    tipos_vehiculo: tiposVehRaw ? tiposVehRaw.split(',').map(s => s.trim()).filter(Boolean) : [],
    tipos_lavado:   tiposLavRaw ? tiposLavRaw.split(',').map(s => s.trim()).filter(Boolean) : [],
    capacidad:      parseInt(document.getElementById('elav-capacidad').value)    || null,
    ubicacion:      document.getElementById('elav-ubic').value.trim()            || null,
    horario:        document.getElementById('elav-horario').value.trim()         || null,
    precio_lavado:  parseFloat(document.getElementById('elav-precio').value)     || null,
    estado:         document.getElementById('elav-estado').value,
  }).eq('id', id);
  if (error) { showToast('Error: ' + (error.message || '')); return; }
  closeEditarLavado();
  await renderAdminLavados();
  showToast(`✓ Servicio ${id} actualizado`);
}

async function eliminarLavado(id) {
  if (!confirm(`¿Eliminar servicio de lavado ${id}?`)) return;
  await sb.from('lavados').delete().eq('id', id);
  await renderAdminLavados();
  showToast(`Servicio ${id} eliminado`);
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
