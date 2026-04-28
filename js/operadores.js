// ── MÓDULO DE OPERADORES ───────────────────────────────

async function _autoIdOperador(propietarioId) {
  const { data } = await sb.from('operadores').select('id').eq('propietario_id', propietarioId);
  const nums = (data || []).map(o => parseInt((o.id || '').replace('OP-', '')) || 0);
  const max  = nums.length ? Math.max(...nums) : 0;
  return `OP-${String(max + 1).padStart(3, '0')}`;
}

// ── CATÁLOGO DE OPERADORES ────────────────────────────

async function renderAdminOperadores() {
  const container = document.getElementById('admin-operadores-list');
  if (!container) return;
  container.innerHTML = skeletonList(2);

  let q = sb.from('operadores').select('*').eq('aprobacion', 'aprobada').order('id');
  if (currentUser.rol !== 'superadmin') q = q.eq('propietario_id', currentUser.id);
  const { data, error } = await q;

  if (error) {
    container.innerHTML = `<div class="empty-state"><div class="icon">❌</div>Error al cargar operadores.</div>`;
    return;
  }
  if (!data?.length) {
    container.innerHTML = `<div class="empty-state"><div class="icon">👷</div>Sin operadores aprobados.<br><small style="color:var(--text-muted)">Agrega el primero con el botón de arriba.</small></div>`;
    return;
  }
  container.innerHTML = data.map(op => _operadorCardHTML(op)).join('');
  // Actualizar selectores de operador en los formularios de camión
  _poblarSelectOperadores(data);
}

function _operadorCardHTML(op) {
  const nombre = [op.nombre, op.primer_apellido, op.segundo_apellido].filter(Boolean).join(' ');
  const foto   = op.foto_operador
    ? `<img src="${esc(op.foto_operador)}" class="op-foto-img" alt="foto operador">`
    : `<div class="op-foto-inicial">${(op.nombre || '?')[0].toUpperCase()}</div>`;

  const licInfo = op.num_licencia
    ? `<div class="op-sub">🪪 ${esc(op.num_licencia)}${op.clase_licencia ? ' · Clase ' + esc(op.clase_licencia) : ''}${op.tipo_licencia ? ' · ' + esc(op.tipo_licencia) : ''}</div>`
    : '';
  const vence = op.fecha_vencimiento
    ? `<div class="op-sub" style="color:${new Date(op.fecha_vencimiento) < new Date() ? 'var(--danger)' : 'var(--text-muted)'}">Vence: ${fmtFecha(op.fecha_vencimiento)}</div>`
    : '';
  const licFotoBtn = op.foto_licencia
    ? `<button class="btn-edit" style="font-size:0.7rem" onclick="window.open('${esc(op.foto_licencia)}','_blank')">🪪 Ver licencia</button>`
    : '';

  return `
    <div class="operador-card" id="opcard-${op.id}">
      <div class="op-foto-wrap">${foto}</div>
      <div class="op-info">
        <div class="op-nombre">${esc(nombre)}</div>
        <div class="op-sub">${esc(op.id)}${op.puesto ? ' · ' + esc(op.puesto) : ''}${op.area ? ' · ' + esc(op.area) : ''}</div>
        ${licInfo}${vence}
      </div>
      <div class="op-actions">
        ${licFotoBtn}
        <button class="btn-edit btn-rechazar" onclick="eliminarOperador('${op.id}')">🗑</button>
      </div>
    </div>`;
}

// ── MODAL AGREGAR OPERADOR ────────────────────────────

function openAgregarOperador() {
  if (!currentUser.id) return;
  document.getElementById('op-foto-preview').innerHTML = '';
  document.getElementById('op-lic-preview').innerHTML  = '';
  document.getElementById('modal-agregar-operador').classList.add('open');
}

function closeAgregarOperador() {
  document.getElementById('modal-agregar-operador').classList.remove('open');
  document.getElementById('modal-agregar-operador')
    .querySelectorAll('input:not([type=file]), select, textarea')
    .forEach(el => { el.value = ''; });
  document.getElementById('op-foto-preview').innerHTML = '';
  document.getElementById('op-lic-preview').innerHTML  = '';
}

function opFotoPreview(input, previewId) {
  const preview = document.getElementById(previewId);
  const file    = input.files?.[0];
  if (!file) { preview.innerHTML = ''; return; }
  const reader  = new FileReader();
  reader.onload = e => {
    preview.innerHTML = `<img src="${e.target.result}" class="op-upload-preview" alt="preview">`;
  };
  reader.readAsDataURL(file);
}

async function agregarOperador() {
  const v = id => document.getElementById(id)?.value?.trim() || '';

  const nombre = v('op-nombre');
  if (!nombre) { alert('El nombre del operador es obligatorio.'); return; }

  const propietarioId = currentUser.rol === 'superadmin'
    ? document.getElementById('sa-empresa-operador')?.value
    : currentUser.id;
  if (!propietarioId) { showToast('Selecciona una empresa propietaria', 'error'); return; }

  const id = await _autoIdOperador(propietarioId);

  // Subir foto del operador
  let fotoOperadorUrl = null;
  const fotoFile = document.getElementById('op-foto-file')?.files?.[0];
  if (fotoFile) {
    const ext  = fotoFile.name.split('.').pop();
    const path = `${propietarioId}/${id}/foto_${Date.now()}.${ext}`;
    const { error: upErr } = await sb.storage.from('operadores').upload(path, fotoFile, { upsert: true });
    if (!upErr) {
      const { data: pub } = sb.storage.from('operadores').getPublicUrl(path);
      fotoOperadorUrl = pub?.publicUrl || null;
    }
  }

  // Subir foto de licencia
  let fotoLicenciaUrl = null;
  const licFile = document.getElementById('op-lic-file')?.files?.[0];
  if (licFile) {
    const ext  = licFile.name.split('.').pop();
    const path = `${propietarioId}/${id}/licencia_${Date.now()}.${ext}`;
    const { error: upErr } = await sb.storage.from('operadores').upload(path, licFile, { upsert: true });
    if (!upErr) {
      const { data: pub } = sb.storage.from('operadores').getPublicUrl(path);
      fotoLicenciaUrl = pub?.publicUrl || null;
    }
  }

  const payload = {
    id,
    propietario_id:       propietarioId,
    curp:                 v('op-curp')             || null,
    nombre,
    primer_apellido:      v('op-apellido1')         || null,
    segundo_apellido:     v('op-apellido2')         || null,
    sexo:                 v('op-sexo')              || null,
    rfc:                  v('op-rfc')               || null,
    nss:                  v('op-nss')               || null,
    tipo_sanguineo:       v('op-sangre')            || null,
    num_trabajador:       v('op-num-trabajador')    || null,
    nivel_estudio:        v('op-nivel-estudio')     || null,
    correo:               v('op-correo')            || null,
    telefono:             v('op-telefono')          || null,
    area:                 v('op-area')              || null,
    puesto:               v('op-puesto')            || null,
    fecha_examen_medico:  v('op-examen')            || null,
    num_licencia:         v('op-num-licencia')      || null,
    clase_licencia:       v('op-clase-licencia')    || null,
    tipo_licencia:        v('op-tipo-licencia')     || null,
    fecha_expedicion:     v('op-fecha-expedicion')  || null,
    fecha_vencimiento:    v('op-fecha-vencimiento') || null,
    foto_operador:        fotoOperadorUrl,
    foto_licencia:        fotoLicenciaUrl,
    aprobacion:           'pendiente',
  };

  const { error } = await sb.from('operadores').insert(payload);
  if (error) { showToast('Error al guardar: ' + (error.message || ''), 'error'); return; }

  // Notificar a superadmins
  const { data: supers } = await sb.from('perfiles').select('user_id').eq('rol', 'superadmin');
  if (supers?.length) {
    await sb.from('notificaciones').insert(supers.map(s => ({
      user_id: s.user_id,
      tipo:    'operador_pendiente',
      titulo:  '👷 Nuevo operador por aprobar',
      mensaje: `${currentUser.nombre} registró al operador ${nombre} (${id}). Revísalo en el panel de aprobaciones.`,
      leido:   false,
    })));
  }

  closeAgregarOperador();
  renderAdminOperadores();
  if (currentUser.rol !== 'superadmin') renderMisPendientes();
  renderAprobaciones();
  showToast(`✓ Operador ${id} registrado — pendiente de aprobación`);
}

async function eliminarOperador(id) {
  if (!confirm(`¿Eliminar al operador ${id}? Esta acción no se puede deshacer.`)) return;
  await sb.from('operadores').delete().eq('id', id);
  document.getElementById(`opcard-${id}`)?.remove();
  _poblarSelectOperadores();
  showToast(`Operador ${id} eliminado`);
}

// ── POPULAR SELECT EN FORMULARIOS DE CAMIÓN ───────────

async function _poblarSelectOperadores(operadoresData) {
  let data = operadoresData;
  if (!data) {
    let q = sb.from('operadores')
      .select('id, nombre, primer_apellido, segundo_apellido')
      .eq('aprobacion', 'aprobada').order('nombre');
    if (currentUser.rol !== 'superadmin') q = q.eq('propietario_id', currentUser.id);
    const res = await q;
    data = res.data || [];
  }

  const opts = `<option value="">— Sin operador asignado —</option>` +
    (data || []).map(op => {
      const full = [op.nombre, op.primer_apellido, op.segundo_apellido].filter(Boolean).join(' ');
      return `<option value="${esc(full)}">${esc(full)} (${op.id})</option>`;
    }).join('');

  ['admin-op', 'editar-op'].forEach(id => {
    const sel = document.getElementById(id);
    if (!sel) return;
    const prev = sel.value;
    sel.innerHTML = opts;
    if (prev) sel.value = prev;
  });
}
