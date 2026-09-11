// ── MÓDULO DE OPERADORES ───────────────────────────────
let _operadorEditId = null;

// Documentos que YA tiene el operador que se está editando. Sin esto, editar
// un teléfono obligaba a volver a subir los cinco archivos: el formulario los
// exigía siempre y el payload ponía NULL en las columnas cuando no se elegía
// archivo, así que no relajar una cosa sin la otra es lo que evita que una
// edición borre las rutas guardadas.
let _operadorEditDocs = {};

// Campo del formulario → columna donde vive su ruta.
const OP_DOCS = [
  { input: 'op-foto-file',        col: 'foto_operador',           label: 'la foto del operador' },
  { input: 'op-lic-file',         col: 'foto_licencia',           label: 'la foto de la licencia de conducir' },
  { input: 'op-doc-medico',       col: 'doc_examen_medico',       label: 'el documento del examen médico' },
  { input: 'op-doc-tox',          col: 'doc_examen_toxicologico', label: 'el documento del examen toxicológico' },
  { input: 'op-doc-antecedentes', col: 'doc_carta_antecedentes',  label: 'la carta de no antecedentes penales' },
];

// Aviso de "ya cargado" junto a cada campo de archivo, con enlace al que hay.
function _pintarDocsExistentes() {
  OP_DOCS.forEach(({ input, col }) => {
    const el = document.getElementById(input);
    if (!el) return;
    document.getElementById(`${input}-actual`)?.remove();
    const url = _operadorEditDocs[col];
    if (!url) return;
    const nota = document.createElement('div');
    nota.id = `${input}-actual`;
    nota.style.cssText = 'font-size:0.72rem;color:var(--text-muted);margin-top:4px';
    nota.innerHTML = `✓ Ya cargado — <a href="${esc(url)}" target="_blank" rel="noopener">ver el actual</a>. Elige un archivo solo si quieres reemplazarlo.`;
    el.insertAdjacentElement('afterend', nota);
  });
}

function _limpiarDocsExistentes() {
  _operadorEditDocs = {};
  OP_DOCS.forEach(({ input }) => document.getElementById(`${input}-actual`)?.remove());
}

function _autoIdOperador() {
  return `OP-${crypto.randomUUID().split('-')[0].toUpperCase()}`;
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
  let vence = '';
  if (op.fecha_vencimiento) {
    const dias = Math.ceil((new Date(op.fecha_vencimiento) - new Date()) / 86400000);
    const color = dias < 0 ? 'var(--danger)' : dias <= 30 ? 'var(--warning, #d97706)' : 'var(--text-muted)';
    const aviso = dias < 0 ? ' ⚠ vencida' : dias <= 30 ? ` ⚠ vence en ${dias} día${dias !== 1 ? 's' : ''}` : '';
    vence = `<div class="op-sub" style="color:${color}">Licencia vence: ${fmtFecha(op.fecha_vencimiento)}${aviso}</div>`;
  }
  const licFotoBtn = op.foto_licencia
    ? `<button class="btn-edit" style="font-size:0.7rem" onclick="window.open('${escJs(op.foto_licencia)}','_blank')">🪪 Ver licencia</button>`
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
        <button class="btn-edit" onclick="editarOperadorAprobado('${op.id}')">✏ Editar</button>
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

async function editarOperadorAprobado(id) {
  // Igual que editarOperadorRechazado pero marca modo edición-aprobación
  await editarOperadorRechazado(id);
  // Cambiar el texto del botón para que quede claro que es una edición
  const btn = document.querySelector('#admin-content-operador .btn-add');
  if (btn) btn.textContent = '✏ Guardar cambios y enviar a aprobación';
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
  set('op-examen-tox',      op.fecha_examen_toxicologico);
  set('op-antecedentes',    op.fecha_carta_antecedentes);
  set('op-num-licencia',     op.num_licencia);
  set('op-fecha-expedicion', op.fecha_expedicion);
  set('op-fecha-vencimiento',op.fecha_vencimiento);
  set('op-vence-peligrosa',  op.fecha_vencimiento_licencia_peligrosa);

  const selMap = { 'op-sexo': 'sexo', 'op-sangre': 'tipo_sanguineo', 'op-clase-licencia': 'clase_licencia', 'op-tipo-licencia': 'tipo_licencia', 'op-nivel-estudio': 'nivel_estudio' };
  Object.entries(selMap).forEach(([elId, field]) => {
    const el = document.getElementById(elId);
    if (el && op[field]) el.value = op[field];
  });

  // Los archivos que ya tiene se conservan: junto a cada campo sale un
  // "✓ Ya cargado" con enlace al actual, y solo hay que elegir archivo si se
  // quiere reemplazar. Antes se limpiaban las vistas previas y la validación
  // los exigía todos, así que corregir una errata en el teléfono obligaba a
  // volver a subir los cinco documentos.
  _operadorEditDocs = {
    foto_operador:           op.foto_operador,
    foto_licencia:           op.foto_licencia,
    doc_examen_medico:       op.doc_examen_medico,
    doc_examen_toxicologico: op.doc_examen_toxicologico,
    doc_carta_antecedentes:  op.doc_carta_antecedentes,
    doc_licencia_peligrosa:  op.doc_licencia_peligrosa,
  };
  document.getElementById('op-foto-preview').innerHTML = '';
  document.getElementById('op-lic-preview').innerHTML  = '';
  _pintarDocsExistentes();

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
  ['op-foto-file', 'op-lic-file', 'op-doc-medico', 'op-doc-tox', 'op-doc-antecedentes', 'op-doc-peligrosa'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.value = '';
  });
  document.getElementById('op-foto-preview').innerHTML = '';
  document.getElementById('op-lic-preview').innerHTML  = '';
  // Sin esto, un alta nueva hecha después de editar heredaría los documentos
  // del operador anterior: la validación los daría por cumplidos y el payload
  // guardaría las rutas de otro.
  _limpiarDocsExistentes();
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
  if (!nombre) { showToast('El nombre del operador es obligatorio.', 'error'); restore(); return; }

  // Se registran datos sensibles de un tercero: sin esta declaración no se
  // continúa (ver privacidad.html §4).
  if (!document.getElementById('op-consent-sensibles')?.checked) {
    showToast('Debes declarar que cuentas con el consentimiento del operador.', 'error');
    restore(); return;
  }

  const propietarioId = currentUser.rol === 'superadmin'
    ? document.getElementById('sa-empresa-operador')?.value
    : currentUser.id;
  if (!propietarioId) { showToast('Selecciona una empresa propietaria', 'error'); restore(); return; }

  // Validar CURP único dentro de la misma empresa (evita operadores duplicados)
  const curp = v('op-curp');
  if (curp) {
    let dupQ = sb.from('operadores').select('id').eq('propietario_id', propietarioId).eq('curp', curp);
    if (_operadorEditId) dupQ = dupQ.neq('id', _operadorEditId);
    const { data: dup, error: dupErr } = await dupQ;
    if (dupErr) { showToast('Error al validar CURP: ' + dupErr.message, 'error'); restore(); return; }
    if (dup?.length) { showToast(`Ya existe un operador con esta CURP en la empresa (${dup[0].id}).`, 'error'); restore(); return; }
  }

  // Validar archivos obligatorios
  const fotoFile    = document.getElementById('op-foto-file')?.files?.[0];
  const licFile     = document.getElementById('op-lic-file')?.files?.[0];
  const docMedFile  = document.getElementById('op-doc-medico')?.files?.[0];
  const docToxFile  = document.getElementById('op-doc-tox')?.files?.[0];
  const docAntFile  = document.getElementById('op-doc-antecedentes')?.files?.[0];
  // Cada documento es obligatorio, pero uno que YA está guardado ya cumple:
  // en una edición solo se pide el archivo que falta. Sin esto, cambiar un
  // teléfono obligaba a volver a subir los cinco.
  const _docFalta = OP_DOCS.find(({ input, col }) =>
    !document.getElementById(input)?.files?.[0] && !_operadorEditDocs[col]);
  if (_docFalta) {
    showToast(`Debes adjuntar ${_docFalta.label}`, 'error');
    restore(); return;
  }

  // La fecha va con el documento, no aparte. js/vigencias.js vigila
  // fecha_examen_medico, fecha_examen_toxicologico, fecha_carta_antecedentes y
  // fecha_vencimiento, y filtra con .lte. — un campo NULL no entra nunca en esa
  // comparación. Un operador con el papel subido y sin fecha no aparece jamás
  // en Vigencias: el documento está, y nada comprueba si sigue vigente. Pedir
  // el archivo sin pedir la fecha era dar por cubierto un control que no lo
  // estaba.
  const _fechaFalta = [
    ['op-examen',            'la fecha del examen médico'],
    ['op-examen-tox',        'la fecha del examen toxicológico'],
    ['op-antecedentes',      'la fecha de la carta de no antecedentes penales'],
    ['op-fecha-vencimiento', 'la fecha de vencimiento de la licencia'],
  ].find(([elId]) => !document.getElementById(elId)?.value);
  if (_fechaFalta) {
    showToast(`Falta ${_fechaFalta[1]}. Sin ella el documento no se vigila en Vigencias.`, 'error');
    restore(); return;
  }

  const isEdit = !!_operadorEditId;
  const id = isEdit ? _operadorEditId : _autoIdOperador();

  // OJO al tocar esto: las cuatro variables de abajo entran tal cual en el
  // payload, así que dejarlas en null cuando no se elige archivo BORRA la ruta
  // guardada. Por eso cada una cae de vuelta a _operadorEditDocs, que en un
  // alta nueva está vacío y no estorba.
  let fotoOperadorUrl = _operadorEditDocs.foto_operador || null;
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
  let fotoLicenciaUrl = _operadorEditDocs.foto_licencia || null;
  if (licFile) {
    const ext  = licFile.name.split('.').pop();
    const path = `${propietarioId}/${id}/licencia_${Date.now()}.${ext}`;
    const { error: upErr } = await sb.storage.from('operadores').upload(path, licFile, { upsert: true });
    if (!upErr) {
      const { data: pub } = sb.storage.from('operadores').getPublicUrl(path);
      fotoLicenciaUrl = pub?.publicUrl || null;
    }
  }

  // Subir documentos legales opcionales
  const _uploadOpDoc = async (inputId, nombre, colActual) => {
    const file = document.getElementById(inputId)?.files?.[0];
    // Sin archivo nuevo se devuelve el que ya estaba, no null: null borraría
    // la ruta guardada al escribir el payload.
    if (!file) return _operadorEditDocs[colActual] || null;
    const ext  = file.name.split('.').pop();
    const path = `${propietarioId}/${id}/${nombre}_${Date.now()}.${ext}`;
    const { error } = await sb.storage.from('operadores').upload(path, file, { upsert: true });
    if (error) return null;
    return sb.storage.from('operadores').getPublicUrl(path).data?.publicUrl || null;
  };
  const [docMedUrl, docToxUrl, docAntUrl, docPeligrosaUrl] = await Promise.all([
    _uploadOpDoc('op-doc-medico',       'examen_medico',      'doc_examen_medico'),
    _uploadOpDoc('op-doc-tox',          'examen_tox',         'doc_examen_toxicologico'),
    _uploadOpDoc('op-doc-antecedentes', 'antecedentes',       'doc_carta_antecedentes'),
    _uploadOpDoc('op-doc-peligrosa',    'licencia_peligrosa', 'doc_licencia_peligrosa'),
  ]);

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
    fecha_examen_medico:         v('op-examen')            || null,
    fecha_examen_toxicologico:   v('op-examen-tox')        || null,
    fecha_carta_antecedentes:    v('op-antecedentes')      || null,
    doc_examen_medico:           docMedUrl,
    doc_examen_toxicologico:     docToxUrl,
    doc_carta_antecedentes:      docAntUrl,
    num_licencia:         v('op-num-licencia')      || null,
    clase_licencia:       v('op-clase-licencia')    || null,
    tipo_licencia:        v('op-tipo-licencia')     || null,
    fecha_expedicion:     v('op-fecha-expedicion')  || null,
    fecha_vencimiento:    v('op-fecha-vencimiento') || null,
    fecha_vencimiento_licencia_peligrosa: v('op-vence-peligrosa') || null,
    doc_licencia_peligrosa: docPeligrosaUrl,
    foto_operador:        fotoOperadorUrl,
    foto_licencia:        fotoLicenciaUrl,
    aprobacion:           'pendiente',
  };

  let error;
  let esEdicionAprobado = false;
  if (isEdit) {
    const { data: anterior } = await sb.from('operadores').select('*').eq('id', id).single();
    const esAprobado = anterior?.aprobacion === 'aprobada';
    esEdicionAprobado = esAprobado;
    const camposEditados = esAprobado
      ? Object.keys(payload).filter(k => JSON.stringify(anterior?.[k]) !== JSON.stringify(payload[k]))
      : [];
    const { error: e } = await sb.from('operadores').update({
      ...payload,
      aprobacion:        'pendiente',
      rechazo_nota:      null,
      rechazo_campos:    null,
      es_edicion:        esAprobado,
      campos_editados:   esAprobado ? camposEditados : null,
      snapshot_anterior: esAprobado ? anterior : null,
    }).eq('id', id);
    error = e;
  } else {
    const { error: e } = await sb.from('operadores').insert(payload);
    error = e;
  }
  // _dbError vive en js/admin.js, que carga antes que este archivo. Traduce los
  // choques de índice único —CURP o número de trabajador repetidos dentro de la
  // misma empresa— a algo que se entienda; sin él salía el texto crudo de
  // Postgres hablando de restricciones.
  if (error) {
    const detalle = typeof _dbError === 'function' ? _dbError(error) : (error.message || '');
    showToast('Error al guardar: ' + detalle, 'error'); restore(); return;
  }

  // Constancia de la declaración de consentimiento sobre los datos sensibles
  // de este operador (quién la hizo, para quién y cuándo).
  const { error: errConsent } = await sb.from('consentimientos').insert({
    user_id:    currentUser.id,
    tipo:       'datos_sensibles_operador',
    version:    LEGAL_VERSION_PRIVACIDAD,
    contexto:   'alta_operador',
    referencia: id,
  });
  if (errConsent) console.error('No se pudo registrar la declaración:', errConsent);

  // Notificar a superadmins
  await sb.rpc('notificar_superadmins', {
    p_tipo:    'nuevo_recurso_pendiente',
    p_titulo:  esEdicionAprobado ? '✏️ Operador editado — revisión pendiente' : '👷 Nuevo operador por aprobar',
    p_mensaje: esEdicionAprobado
      ? `La empresa ${currentUser.nombre} editó al operador ${nombre} (${id}). Revisa los cambios en Pendientes.`
      : `${currentUser.nombre} registró al operador ${nombre} (${id}). Revísalo en el panel de aprobaciones.`,
  });

  restore();
  showToast(isEdit ? `✓ Correcciones enviadas — ${id} en revisión nuevamente` : `✓ Operador ${id} enviado — pendiente de aprobación`);
  closeAgregarOperador();          // limpia form y hace scroll al listado
  await renderAdminOperadores();   // refresca lista y prefill siguiente número
  if (currentUser.rol !== 'superadmin') renderMisPendientes();
  renderAprobaciones();
}

function eliminarOperador(id) {
  showConfirm(`¿Eliminar al operador ${id}? Esta acción no se puede deshacer.`, async () => {
    await sb.from('operadores').delete().eq('id', id);
    document.getElementById(`opcard-${id}`)?.remove();
    _poblarSelectOperadores();
    _prefillNumTrabajador();
    showToast(`Operador ${id} eliminado`);
  }, { danger: true, confirmLabel: 'Eliminar' });
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
