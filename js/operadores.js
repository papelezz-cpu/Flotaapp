// ── MÓDULO DE OPERADORES ───────────────────────────────
let _operadorEditId = null;

async function _autoIdOperador() {
  const { data } = await sb.from('operadores').select('id').like('id', 'OP-%');
  const nums = (data || []).map(o => parseInt((o.id || '').replace('OP-', '')) || 0);
  const max  = nums.length ? Math.max(...nums) : 0;
  return `OP-${String(max + 1).padStart(3, '0')}`;
}

// Número de trabajador automático, secuencial por empresa
async function _autoNumTrabajador(propietarioId) {
  if (!propietarioId) return '';
  const { data } = await sb.from('operadores')
    .select('num_trabajador')
    .eq('propietario_id', propietarioId);
  const nums = (data || []).map(o => parseInt((o.num_trabajador || '').replace(/\D/g, '')) || 0);
  const max  = nums.length ? Math.max(...nums) : 0;
  return String(max + 1).padStart(3, '0');
}

async function _prefillNumTrabajador() {
  const propietarioId = currentUser.rol === 'superadmin'
    ? document.getElementById('sa-empresa-operador')?.value
    : currentUser.id;
  const el = document.getElementById('op-num-trabajador');
  if (!el) return;
  if (!propietarioId) { el.value = ''; return; }
  el.value = await _autoNumTrabajador(propietarioId);
}

// ── CATÁLOGO DE OPERADORES ────────────────────────────

async function renderAdminOperadores() {
  const container = document.getElementById('admin-operadores-list');
  if (!container) return;
  container.innerHTML = skeletonList(2);

  const baseQ = () => {
    let q = sb.from('operadores').select('*').order('id');
    if (currentUser.rol !== 'superadmin') q = q.eq('propietario_id', currentUser.id);
    return q;
  };

  const [{ data: aprobados, error }, { data: rechazados }] = await Promise.all([
    baseQ().eq('aprobacion', 'aprobada'),
    baseQ().eq('aprobacion', 'rechazada'),
  ]);

  if (error) {
    container.innerHTML = `<div class="empty-state"><div class="icon">❌</div>Error al cargar operadores.</div>`;
    return;
  }

  let html = '';

  if (rechazados?.length) {
    html += `<div style="font-size:0.72rem;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:var(--danger);margin-bottom:8px">⚠ Requieren correcciones</div>`;
    html += rechazados.map(op => _operadorCardRechazadoHTML(op)).join('');
    html += `<div style="height:1px;background:var(--border);margin:16px 0"></div>`;
  }

  if (aprobados?.length) {
    html += aprobados.map(op => _operadorCardHTML(op)).join('');
    _poblarSelectOperadores(aprobados);
  } else if (!rechazados?.length) {
    html = `<div class="empty-state"><div class="icon">👷</div>Sin operadores registrados.<br><small style="color:var(--text-muted)">Completa el formulario y envía a aprobación.</small></div>`;
  }

  container.innerHTML = html;
  _prefillNumTrabajador();
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
        <div class="op-sub">${esc(op.id)}${op.num_trabajador ? ' · #' + esc(op.num_trabajador) : ''}${op.puesto ? ' · ' + esc(op.puesto) : ''}${op.area ? ' · ' + esc(op.area) : ''}</div>
        ${licInfo}${vence}
      </div>
      <div class="op-actions">
        ${licFotoBtn}
        <button class="btn-edit btn-rechazar" onclick="eliminarOperador('${op.id}')">🗑</button>
      </div>
    </div>`;
}

function _operadorCardRechazadoHTML(op) {
  const nombre = [op.nombre, op.primer_apellido, op.segundo_apellido].filter(Boolean).join(' ');
  const foto   = op.foto_operador
    ? `<img src="${esc(op.foto_operador)}" class="op-foto-img" alt="foto">`
    : `<div class="op-foto-inicial" style="background:var(--danger)">${(op.nombre||'?')[0].toUpperCase()}</div>`;

  const camposHtml = op.rechazo_campos?.length
    ? op.rechazo_campos.map(c => `<span class="cargo-chip cargo-chip-sm" style="border-color:rgba(239,68,68,0.3);color:var(--danger)">${esc(c)}</span>`).join('')
    : '';

  return `
    <div class="operador-card" id="opcard-${op.id}" style="border-color:var(--danger);border-width:1.5px">
      <div class="op-foto-wrap">${foto}</div>
      <div class="op-info">
        <div class="op-nombre">${esc(nombre)}</div>
        <div class="op-sub" style="color:var(--danger);font-weight:600">⚠ Requiere correcciones</div>
        ${camposHtml ? `<div style="margin-top:4px;display:flex;flex-wrap:wrap;gap:3px">${camposHtml}</div>` : ''}
        ${op.rechazo_nota ? `<div class="op-sub" style="margin-top:5px;font-style:italic;color:var(--text-muted)">"${esc(op.rechazo_nota)}"</div>` : ''}
      </div>
      <div class="op-actions">
        <button class="btn-edit btn-aprobar" onclick="editarOperadorRechazado('${op.id}')">✏ Corregir</button>
      </div>
    </div>`;
}

async function editarOperadorRechazado(id) {
  const { data: op, error } = await sb.from('operadores').select('*').eq('id', id).single();
  if (error || !op) { showToast('Error al cargar operador', 'error'); return; }

  _operadorEditId = id;

  const set = (elId, val) => { const el = document.getElementById(elId); if (el) el.value = val ?? ''; };
  set('op-nombre',           op.nombre);
  set('op-apellido1',        op.primer_apellido);
  set('op-apellido2',        op.segundo_apellido);
  set('op-curp',             op.curp);
  set('op-rfc',              op.rfc);
  set('op-nss',              op.nss);
  set('op-num-trabajador',   op.num_trabajador);
  set('op-correo',           op.correo);
  set('op-telefono',         op.telefono);
  set('op-area',             op.area);
  set('op-puesto',           op.puesto);
  set('op-examen',           op.fecha_examen_medico);
  set('op-num-licencia',     op.num_licencia);
  set('op-fecha-expedicion', op.fecha_expedicion);
  set('op-fecha-vencimiento',op.fecha_vencimiento);

  const selMap = { 'op-sexo': 'sexo', 'op-sangre': 'tipo_sanguineo', 'op-clase-licencia': 'clase_licencia', 'op-tipo-licencia': 'tipo_licencia', 'op-nivel-estudio': 'nivel_estudio' };
  Object.entries(selMap).forEach(([elId, field]) => {
    const el = document.getElementById(elId);
    if (el && op[field]) el.value = op[field];
  });

  if (op.foto_operador) document.getElementById('op-foto-preview').innerHTML = `<img src="${esc(op.foto_operador)}" class="op-upload-preview" alt="foto actual">`;
  if (op.foto_licencia) document.getElementById('op-lic-preview').innerHTML  = `<img src="${esc(op.foto_licencia)}"  class="op-upload-preview" alt="licencia actual">`;

  // Mostrar banner con motivo de rechazo
  const btn = document.querySelector('#admin-content-operador .btn-add');
  if (btn) btn.textContent = 'Guardar correcciones y reenviar';

  // Scroll al formulario
  document.querySelector('#admin-content-operador .admin-card')
    ?.scrollIntoView({ behavior: 'smooth', block: 'start' });

  showToast('Formulario cargado — corrige los campos y reenvía', 'info');
}

// ── LIMPIAR FORMULARIO ────────────────────────────────

function _limpiarFormOperador() {
  const contenedor = document.getElementById('admin-content-operador');
  if (!contenedor) return;
  contenedor.querySelectorAll('input:not([type=file])').forEach(el => { el.value = ''; });
  contenedor.querySelectorAll('select').forEach(el => { el.selectedIndex = 0; });
  ['op-foto-file', 'op-lic-file'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.value = '';
  });
  document.getElementById('op-foto-preview').innerHTML = '';
  document.getElementById('op-lic-preview').innerHTML  = '';
}

// Llamada al cambiar empresa (superadmin)
async function onCambioEmpresaOperador() {
  await _prefillNumTrabajador();
}

// Compatibilidad: openAgregarOperador ya no usa modal, solo limpia y prefill
function openAgregarOperador() {}

function closeAgregarOperador() {
  _operadorEditId = null;
  _limpiarFormOperador();
  _prefillNumTrabajador();
  const btn = document.querySelector('#admin-content-operador .btn-add');
  if (btn) btn.textContent = 'Enviar a aprobación';
  document.getElementById('admin-operadores-list')
    ?.closest('.admin-card')
    ?.scrollIntoView({ behavior: 'smooth', block: 'start' });
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
  const btn = document.querySelector('#admin-content-operador .btn-add');
  if (btn?.disabled) return;
  if (btn) { btn.disabled = true; btn.textContent = 'Guardando…'; }

  const restore = () => { if (btn) { btn.disabled = false; btn.textContent = 'Enviar a aprobación'; } };

  const v = id => document.getElementById(id)?.value?.trim() || '';

  const nombre = v('op-nombre');
  if (!nombre) { alert('El nombre del operador es obligatorio.'); restore(); return; }

  const propietarioId = currentUser.rol === 'superadmin'
    ? document.getElementById('sa-empresa-operador')?.value
    : currentUser.id;
  if (!propietarioId) { showToast('Selecciona una empresa propietaria', 'error'); restore(); return; }

  const isEdit = !!_operadorEditId;
  const id = isEdit ? _operadorEditId : await _autoIdOperador();

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

  let error;
  if (isEdit) {
    const { error: e } = await sb.from('operadores').update({
      ...payload, aprobacion: 'pendiente', rechazo_nota: null, rechazo_campos: null,
    }).eq('id', id);
    error = e;
  } else {
    const { error: e } = await sb.from('operadores').insert(payload);
    error = e;
  }
  if (error) { showToast('Error al guardar: ' + (error.message || ''), 'error'); restore(); return; }

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

  restore();
  showToast(isEdit ? `✓ Correcciones enviadas — ${id} en revisión nuevamente` : `✓ Operador ${id} enviado — pendiente de aprobación`);
  closeAgregarOperador();          // limpia form y hace scroll al listado
  await renderAdminOperadores();   // refresca lista y prefill siguiente número
  if (currentUser.rol !== 'superadmin') renderMisPendientes();
  renderAprobaciones();
}

async function eliminarOperador(id) {
  if (!confirm(`¿Eliminar al operador ${id}? Esta acción no se puede deshacer.`)) return;
  await sb.from('operadores').delete().eq('id', id);
  document.getElementById(`opcard-${id}`)?.remove();
  _poblarSelectOperadores();
  _prefillNumTrabajador();
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
