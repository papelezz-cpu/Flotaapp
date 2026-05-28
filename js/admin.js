// ── PANEL DE ADMINISTRACIÓN ───────────────────────────

const CARGO_TIPOS = ['General','Refrigerado','Peligroso','Frágil','Granel','Maquinaria','Automóviles','Contenedor','HAZMAT'];

let currentAdminTab = 'camion';

// edit-mode state for rejected trucks
let _camionRechazadoId = null;

const DIM_DEFAULTS = {
  'Torton':     '8.5m × 2.4m × 2.5m',
  'Rabón':      '5.5m × 2.4m × 2.4m',
  'Full':       '14.5m × 2.5m × 2.6m',
  'Plataforma': '13.5m × 2.5m — abierta',
  'Camioneta 1.5 ton caja seca':        '3.8m × 2.0m × 2.0m',
  'Camioneta 1.5 ton plataforma':       '3.8m × 2.0m — abierta',
  'Camioneta 3.5 ton caja seca':        '5.0m × 2.2m × 2.2m',
  'Camioneta 3.5 ton plataforma':       '5.0m × 2.2m — abierta',
  'Torton caja seca':                   '8.5m × 2.4m × 2.5m',
  'Torton plataforma':                  '8.5m × 2.5m — abierta',
  'Sencillo porta contenedor 40/20':    '12.2m × 2.44m — contenedor',
  'Sencillo plataforma':                '12.5m × 2.5m — abierta',
  'Full porta contenedor 40/20':        '16.5m × 2.5m — 2 contenedores',
  'Full plataforma':                    '16.5m × 2.5m — abierta',
  'Lowboy':                             '12m × 3.0m — especial',
  'Cama baja':                          '10m × 3.0m — especial',
  'Plataforma de 3 ejes (sobrepeso)':   '15m × 3.0m — especial',
  'HAZMAT':                             'Según unidad/permiso',
};

// Capacidades máximas reglamentadas (NOM-012-SCT-2) en toneladas de carga neta
const CAP_DEFAULTS = {
  'Camioneta 1.5 ton caja seca':      1.5,
  'Camioneta 1.5 ton plataforma':     1.5,
  'Camioneta 3.5 ton caja seca':      3.5,
  'Camioneta 3.5 ton plataforma':     3.5,
  'Rabón':                            8,
  'Torton':                           14,
  'Torton caja seca':                 14,
  'Torton plataforma':                14,
  'Sencillo porta contenedor 40/20':  24.5,
  'Sencillo plataforma':              24.5,
  'Plataforma':                       24.5,
  'Full':                             49,
  'Full porta contenedor 40/20':      49,
  'Full plataforma':                  49,
  'Lowboy':                           40,
  'Cama baja':                        35,
};

// Deshabilita un botón y devuelve función que lo restaura
function _btnLoading(id) {
  const btn = document.getElementById(id);
  if (!btn || btn.disabled) return () => {};
  const orig = btn.textContent;
  btn.disabled = true;
  btn.textContent = '⏳ Guardando...';
  return (texto) => { btn.disabled = false; btn.textContent = texto ?? orig; };
}

function _dbError(error) {
  const msg = (error?.message || '').toLowerCase();
  if (msg.includes('numeric field overflow') || msg.includes('out of range'))
    return 'Un campo numérico tiene un valor demasiado grande (p.ej. el precio). Reduce el número e intenta de nuevo.';
  if (msg.includes('invalid input syntax for type date') || msg.includes('date/time field'))
    return 'Una de las fechas ingresadas no tiene el formato correcto. Usa el selector de fecha.';
  if (msg.includes('invalid input syntax for type'))
    return 'Uno de los campos tiene un formato incorrecto. Verifica que los números y fechas sean válidos.';
  if (msg.includes('null value') || msg.includes('not-null') || msg.includes('violates not-null')) {
    const col = error?.message?.match(/column "([^"]+)"/)?.[1];
    return col ? `El campo "${col}" es obligatorio y no puede estar vacío.` : 'Falta un campo obligatorio.';
  }
  if (msg.includes('unique') || msg.includes('duplicate key'))
    return 'Ya existe un registro con ese valor. Verifica que no estés duplicando datos.';
  if (msg.includes('foreign key') || msg.includes('violates foreign key'))
    return 'Referencia inválida: uno de los valores seleccionados no existe en el sistema.';
  if (msg.includes('value too long') || msg.includes('character varying'))
    return 'Uno de los campos de texto supera el límite de caracteres permitido.';
  if (msg.includes('permission') || msg.includes('rls') || msg.includes('policy'))
    return 'No tienes permiso para realizar esta acción.';
  return error?.message || 'Error desconocido. Intenta de nuevo.';
}

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

  // Perfil de empresa: oculto para superadmin
  const perfilCard = document.getElementById('perfil-empresa-card');
  if (perfilCard) perfilCard.style.display = currentUser.rol === 'superadmin' ? 'none' : '';
  if (currentUser.rol !== 'superadmin') await renderPerfilEmpresa();

  // Dropdowns de empresa para superadmin
  if (currentUser.rol === 'superadmin') await _cargarEmpresasDropdowns();
  else document.querySelectorAll('.sa-empresa-row').forEach(el => el.style.display = 'none');

  if (currentUser.rol !== 'superadmin') renderMisPendientes();

  // Render the currently active admin tab
  if (currentAdminTab === 'custodio') renderAdminCustodios();
  else if (currentAdminTab === 'patio') renderAdminPatios();
  else if (currentAdminTab === 'lavado') renderAdminLavados();
  else if (currentAdminTab === 'operador') renderAdminOperadores();

  // Populate operator dropdowns in truck forms
  _poblarSelectOperadores();
}

// ── TABS ADMIN ────────────────────────────────────────

function cambiarAdminTab(tab) {
  currentAdminTab = tab;
  ['camion','custodio','patio','lavado','operador'].forEach(t => {
    document.getElementById(`admin-tab-${t}`)?.classList.toggle('active', t === tab);
    const el = document.getElementById(`admin-content-${t}`);
    if (el) el.style.display = t === tab ? '' : 'none';
  });
  if (tab === 'custodio') renderAdminCustodios();
  else if (tab === 'patio') renderAdminPatios();
  else if (tab === 'lavado') renderAdminLavados();
  else if (tab === 'operador') renderAdminOperadores();
  else renderAdmin();
}

// ── DROPDOWN EMPRESA (solo superadmin) ───────────────

async function _cargarEmpresasDropdowns() {
  const { data: empresas } = await sb.from('perfiles')
    .select('user_id, nombre')
    .eq('rol', 'admin')
    .order('nombre');

  const opts = (empresas || []).map(e =>
    `<option value="${e.user_id}">${esc(e.nombre)}</option>`
  ).join('');

  ['camion','custodio','patio','lavado','operador'].forEach(tipo => {
    const sel = document.getElementById(`sa-empresa-${tipo}`);
    if (sel) sel.innerHTML = `<option value="">— Selecciona empresa —</option>${opts}`;
  });
  document.querySelectorAll('.sa-empresa-row').forEach(el => el.style.display = '');
}

function _getPropietarioId(tipo) {
  if (currentUser.rol !== 'superadmin') return currentUser.id;
  const val = document.getElementById(`sa-empresa-${tipo}`)?.value;
  if (!val) { showToast('Selecciona una empresa propietaria', 'error'); return null; }
  return val;
}

// ── PERFIL DE EMPRESA ─────────────────────────────────

function togglePerfilCard() {
  const body = document.getElementById('perfil-card-body');
  const icon = document.getElementById('perfil-toggle-icon');
  const isOpen = body.style.display !== 'none';
  body.style.display = isOpen ? 'none' : 'block';
  icon.textContent   = isOpen ? '▼ Editar' : '▲ Ocultar';
}

function previewDocNombre(input, previewId) {
  const el = document.getElementById(previewId);
  if (!el) return;
  el.textContent = input.files?.[0] ? '📎 ' + input.files[0].name : '';
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
  set('pe-sct',       p.permiso_sct);
  set('pe-desc',      p.descripcion);
  const rc    = document.getElementById('pe-rc');
  const carga = document.getElementById('pe-carga');
  if (rc)    rc.checked    = !!p.seguro_rc;
  if (carga) carga.checked = !!p.seguro_carga;

  // Mostrar fechas pendientes o aprobadas en los campos de documentos
  const hayPend = !!p.perfil_docs_pendiente;
  set('pe-vence-sct',   hayPend ? p.fecha_vencimiento_permiso_sct_pendiente  : p.fecha_vencimiento_permiso_sct);
  set('pe-vence-rc',    hayPend ? p.fecha_vencimiento_seguro_rc_pendiente    : p.fecha_vencimiento_seguro_rc);
  set('pe-vence-carga', hayPend ? p.fecha_vencimiento_seguro_carga_pendiente : p.fecha_vencimiento_seguro_carga);

  const banner = document.getElementById('pe-docs-pendiente-banner');
  if (banner) banner.style.display = hayPend ? '' : 'none';

  const _docLink = (elId, url, label) => {
    const el = document.getElementById(elId);
    if (!el) return;
    el.innerHTML = url
      ? `<a href="${url}" target="_blank" style="font-size:0.78rem;color:var(--primary)">📄 Ver ${label}${hayPend ? ' (pendiente)' : ''}</a>`
      : '';
  };
  _docLink('pe-doc-sct-actual',   hayPend ? p.doc_permiso_sct_pendiente  : p.doc_permiso_sct,   'permiso SCT');
  _docLink('pe-doc-rc-actual',    hayPend ? p.doc_seguro_rc_pendiente     : p.doc_seguro_rc,     'seguro RC');
  _docLink('pe-doc-carga-actual', hayPend ? p.doc_seguro_carga_pendiente  : p.doc_seguro_carga,  'seguro de carga');
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

async function solicitarActualizacionDocs() {
  const sctDate   = document.getElementById('pe-vence-sct')?.value   || null;
  const rcDate    = document.getElementById('pe-vence-rc')?.value    || null;
  const cargaDate = document.getElementById('pe-vence-carga')?.value || null;
  if (!sctDate && !rcDate && !cargaDate) {
    showToast('Ingresa al menos una fecha de vencimiento', 'error'); return;
  }

  const _done = _btnLoading('btn-solicitar-docs');
  const uid = currentUser.id;
  const ts  = Date.now();

  const _uploadDoc = async (inputId, nombre) => {
    const file = document.getElementById(inputId)?.files?.[0];
    if (!file) return null;
    const ext  = file.name.split('.').pop();
    const path = `${uid}/${nombre}_${ts}.${ext}`;
    const { error } = await sb.storage.from('documentos-empresa').upload(path, file, { upsert: true });
    if (error) return null;
    return sb.storage.from('documentos-empresa').getPublicUrl(path).data?.publicUrl || null;
  };

  const [docSct, docRc, docCarga] = await Promise.all([
    _uploadDoc('pe-doc-sct',   'permiso_sct'),
    _uploadDoc('pe-doc-rc',    'seguro_rc'),
    _uploadDoc('pe-doc-carga', 'seguro_carga'),
  ]);

  const payload = {
    perfil_docs_pendiente:                    true,
    fecha_vencimiento_permiso_sct_pendiente:  sctDate,
    fecha_vencimiento_seguro_rc_pendiente:    rcDate,
    fecha_vencimiento_seguro_carga_pendiente: cargaDate,
  };
  if (docSct)   payload.doc_permiso_sct_pendiente  = docSct;
  if (docRc)    payload.doc_seguro_rc_pendiente     = docRc;
  if (docCarga) payload.doc_seguro_carga_pendiente  = docCarga;

  const { error } = await sb.from('perfiles').update(payload).eq('user_id', uid);
  if (error) { _done(); showToast('Error al enviar: ' + error.message, 'error'); return; }

  const { data: sas } = await sb.from('perfiles').select('user_id').eq('rol', 'superadmin');
  if (sas?.length) await sb.from('notificaciones').insert(sas.map(sa => ({
    user_id: sa.user_id, tipo: 'docs_empresa_pendientes',
    titulo:  '📋 Documentos de empresa para revisar',
    mensaje: `${esc(currentUser.nombre || '')} envió documentos de empresa para actualización.`,
    leido:   false,
  })));

  _done();
  showToast('✓ Documentos enviados — pendientes de aprobación');
  await renderPerfilEmpresa();
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
  const tipo   = document.getElementById(`${prefix}-tipo`)?.value || '';
  const dimEl  = document.getElementById(`${prefix}-dim`);
  const lblEl  = document.getElementById(`${prefix}-dim-label`);
  const capEl  = document.getElementById(`${prefix}-cap`);

  // Update label based on truck body type
  if (lblEl) {
    const esCaja = tipo.includes('caja seca') || tipo === 'Torton' || tipo === 'Rabón';
    const esCont = tipo.includes('contenedor');
    lblEl.textContent = esCaja ? 'Dimensiones de caja (L × A × H)' :
                        esCont ? 'Capacidad de contenedor'           :
                                 'Dimensiones de plataforma (L × A)';
  }

  // Auto-fill dimensions only when field is empty
  if (dimEl && tipo && DIM_DEFAULTS[tipo] && !dimEl.value) {
    dimEl.value = DIM_DEFAULTS[tipo];
  }

  // Auto-fill capacidad máxima reglamentada
  if (capEl && tipo && CAP_DEFAULTS[tipo]) {
    capEl.value = CAP_DEFAULTS[tipo];
  }
}

// ── EDITAR CAMIÓN ─────────────────────────────────────

async function editarCamion(id) {
  const c = allCamiones.find(x => x.id === id);
  if (!c) return;

  const set = (elId, val) => { const el = document.getElementById(elId); if (el) el.value = val ?? ''; };

  set('editar-id', c.id);
  document.getElementById('editar-subtitulo').textContent = `Unidad ${c.id} — ${c.tipo}`;
  set('editar-tipo', c.tipo);
  set('editar-cap', c.capacidad);
  set('editar-op', c.operador || '');
  set('editar-placas', c.placas || '');
  set('editar-tipo-placa', c.tipo_placa || '');
  set('editar-dim', c.dimensiones || '');
  set('editar-tiempo', c.tiempo_respuesta || '');
  set('editar-precio', c.precio_dia || '');
  set('editar-estado', c.estado);
  set('editar-marca', c.marca || '');
  set('editar-num-serie', c.num_serie || '');
  set('editar-num-motor', c.num_motor || '');
  set('editar-num-economico', c.num_economico || '');
  set('editar-combustible', c.tipo_combustible || '');
  set('editar-tc', c.tarjeta_circulacion || '');
  set('editar-fecha-tc', c.fecha_expedicion_tc || '');

  renderCargoChipsSelect('editar-tipo-carga', c.tipo_carga || []);
  document.getElementById('modal-editar').classList.add('open');
}

function closeEditarCamion() {
  document.getElementById('modal-editar').classList.remove('open');
}

async function guardarEdicion() {
  const id   = document.getElementById('editar-id').value;
  const tipo = document.getElementById('editar-tipo').value;
  const g    = elId => document.getElementById(elId)?.value?.trim() || null;

  const payload = {
    tipo,
    capacidad:           parseInt(document.getElementById('editar-cap').value)      || 0,
    operador:            document.getElementById('editar-op').value.trim()          || null,
    placas:              g('editar-placas'),
    tipo_placa:          g('editar-tipo-placa'),
    dimensiones:         g('editar-dim'),
    tipo_carga:          getSelectedCargo('editar-tipo-carga'),
    tiempo_respuesta:    document.getElementById('editar-tiempo').value             || null,
    precio_dia:          parseFloat(document.getElementById('editar-precio').value) || null,
    estado:              document.getElementById('editar-estado').value,
    emoji:               { Torton:'🚛', Rabón:'🚚', Full:'🚛', Plataforma:'🏗️' }[tipo] || '🚛',
    marca:               g('editar-marca'),
    num_serie:           g('editar-num-serie'),
    num_motor:           g('editar-num-motor'),
    num_economico:       g('editar-num-economico'),
    tipo_combustible:    g('editar-combustible'),
    tarjeta_circulacion: g('editar-tc'),
    fecha_expedicion_tc: g('editar-fecha-tc'),
  };

  const esSuperAdmin = currentUser.rol === 'superadmin';
  let updatePayload = payload;

  if (!esSuperAdmin) {
    // Fetch estado actual para calcular diff
    const { data: anterior } = await sb.from('camiones').select('*').eq('id', id).single();
    const camposEditados = Object.keys(payload).filter(k =>
      JSON.stringify(anterior?.[k]) !== JSON.stringify(payload[k])
    );
    updatePayload = {
      ...payload,
      aprobacion:        'pendiente',
      es_edicion:        true,
      campos_editados:   camposEditados,
      snapshot_anterior: anterior,
    };
  }

  const { error } = await sb.from('camiones').update(updatePayload).eq('id', id);
  if (error) { showToast('No se pudo actualizar: ' + _dbError(error), 'error'); return; }
  if (!esSuperAdmin) {
    const { data: sas } = await sb.from('perfiles').select('user_id').eq('rol', 'superadmin');
    if (sas?.length) await sb.from('notificaciones').insert(sas.map(sa => ({
      user_id: sa.user_id, tipo: 'nueva_unidad_pendiente',
      titulo:  'Unidad editada — revisión pendiente',
      mensaje: `La empresa ${esc(currentUser.nombre || '')} editó la unidad ${id}. Revisa los cambios en Pendientes.`,
      leido:   false,
    })));
  }
  closeEditarCamion();
  await renderAdmin();
  showToast(esSuperAdmin ? `✓ Unidad ${id} actualizada` : `✓ Cambios enviados — pendientes de aprobación`);
}

// ── PENDIENTES (EMPRESA) ──────────────────────────────

// Muestra los recursos pendientes Y rechazados del propio admin
async function renderMisPendientes() {
  const uid = currentUser.id;
  const estados = ['pendiente', 'rechazada'];

  const [{ data: camAll }, { data: cusAll }, { data: patAll }, { data: lavAll }, { data: opAll }] = await Promise.all([
    sb.from('camiones'  ).select('*').eq('propietario_id', uid).in('aprobacion', estados).order('created_at', { ascending: false }),
    sb.from('custodios' ).select('*').eq('propietario_id', uid).in('aprobacion', estados).order('created_at', { ascending: false }),
    sb.from('patios'    ).select('*').eq('propietario_id', uid).in('aprobacion', estados).order('created_at', { ascending: false }),
    sb.from('lavados'   ).select('*').eq('propietario_id', uid).in('aprobacion', estados).order('id', { ascending: false }),
    sb.from('operadores').select('*').eq('propietario_id', uid).in('aprobacion', estados).order('created_at', { ascending: false }),
  ]);

  const section = document.getElementById('pendientes-section');
  const list    = document.getElementById('pendientes-list');

  // Returns { banner, actions } — banner goes ABOVE the resource info row
  const _rechazoParts = (r, tabla, corregirFn) => {
    if (r.aprobacion !== 'rechazada') {
      return {
        banner: '',
        actions: `<span class="badge badge-busy" style="font-size:0.72rem;flex-shrink:0">⏳ En revisión</span>`,
      };
    }
    const campos = (r.rechazo_campos || []).map(f => `<span class="rechazo-chip">${esc(f)}</span>`).join('');
    const banner = `
      <div class="rechazo-banner">
        <div class="rechazo-header">⚠ El administrador solicitó correcciones</div>
        ${campos ? `<div class="rechazo-chips" style="margin-top:6px">${campos}</div>` : ''}
        ${r.rechazo_nota ? `<div class="rechazo-nota" style="margin-top:6px">"${esc(r.rechazo_nota)}"</div>` : ''}
        <div class="rechazo-aviso-archivos">📎 Por favor vuelve a subir todos los documentos e imágenes al corregir.</div>
      </div>`;
    const actions = `
      <div style="display:flex;gap:6px;flex-shrink:0">
        ${corregirFn ? `<button class="btn-edit btn-aprobar" onclick="${corregirFn}">✏ Corregir</button>` : ''}
        <button class="btn-edit btn-rechazar" onclick="eliminarMiRecurso('${tabla}','${r.id}')">🗑 Eliminar</button>
      </div>`;
    return { banner, actions };
  };

  const _card = (r, icono, nombre, sub, tabla, corregirFn) => {
    const { banner, actions } = _rechazoParts(r, tabla, corregirFn);
    const esRechazada = r.aprobacion === 'rechazada';
    return `
      <div class="truck-list-item${esRechazada ? ' item-rechazado' : ''}"
           style="${esRechazada ? 'flex-direction:column;align-items:stretch;gap:0' : ''}">
        ${banner}
        <div style="display:flex;justify-content:space-between;align-items:center">
          <div class="truck-list-item-info">
            <div class="truck-list-item-name">${icono} ${nombre}</div>
            <div class="truck-list-item-sub">${sub}</div>
          </div>
          ${actions}
        </div>
      </div>`;
  };

  const rows = [
    ...(camAll || []).map(c => _card(c, c.emoji || '🚛', `${c.id} — ${c.tipo}`,
        `${c.operador || '—'} · ${c.capacidad} ton`,
        'camiones', `editarCamionRechazado('${c.id}')`)),
    ...(cusAll || []).map(c => _card(c, '👮', `${c.id} — ${esc(c.nombre)}`,
        `${c.tipo} · ${c.disponibilidad || '—'}`,
        'custodios', null)),
    ...(patAll || []).map(p => _card(p, '🏭', `${p.id} — ${esc(p.nombre)}`,
        `${p.tipo}${p.area_m2 ? ' · ' + p.area_m2 + ' m²' : ''}`,
        'patios', null)),
    ...(lavAll || []).map(l => _card(l, '🚿', `${l.id} — ${esc(l.nombre)}`,
        (l.tipos_vehiculo || []).join(', ') || '—',
        'lavados', null)),
    ...(opAll || []).map(o => {
      const n = [o.nombre, o.primer_apellido].filter(Boolean).join(' ');
      return _card(o, '👷', `${o.id} — ${esc(n)}`, o.puesto || '—',
        'operadores', `editarOperadorRechazado('${o.id}')`);
    }),
  ];

  if (!rows.length) { section.style.display = 'none'; return; }

  section.style.display = 'block';
  const titulo = section.querySelector('.section-title');
  if (titulo) titulo.innerHTML = '⏳ Mis recursos pendientes o con correcciones';
  list.innerHTML = rows.join('');
}

function eliminarMiRecurso(tabla, id) {
  showConfirm(`¿Eliminar ${id}? Esta acción no se puede deshacer.`, async () => {
  if (tabla === 'camiones') {
    const { data: c } = await sb.from('camiones').select('archivos').eq('id', id).single();
    if (c?.archivos?.length) await sb.storage.from('unidades').remove(c.archivos);
  }
  if (tabla === 'operadores') {
    const { data: op } = await sb.from('operadores').select('foto_operador, foto_licencia').eq('id', id).single();
    const files = [op?.foto_operador, op?.foto_licencia].filter(Boolean);
    if (files.length) await sb.storage.from('operadores').remove(files);
  }
  const { error } = await sb.from(tabla).delete().eq('id', id).eq('propietario_id', currentUser.id);
  if (error) { showToast('Error al eliminar', 'error'); return; }
  showToast(`${id} eliminado`);
  renderMisPendientes();
  }, { danger: true, confirmLabel: 'Eliminar' });
}

async function editarCamionRechazado(id) {
  const { data: c } = await sb.from('camiones').select('*').eq('id', id).single();
  if (!c) { showToast('No se encontró la unidad', 'error'); return; }

  // Switch to camion tab
  cambiarAdminTab('camion');

  const set = (elId, val) => { const el = document.getElementById(elId); if (el) el.value = val ?? ''; };
  const setSelect = (elId, val) => {
    const el = document.getElementById(elId);
    if (!el) return;
    const opt = Array.from(el.options).find(o => o.value === val || o.text === val);
    if (opt) el.value = opt.value; else el.value = '';
  };

  setSelect('admin-tipo', c.tipo);
  set('admin-cap',          c.capacidad);
  set('admin-precio',       c.precio_dia);
  set('admin-placas',       c.placas);
  set('admin-dim',          c.dimensiones);
  set('admin-version',      c.version);
  set('admin-modelo-anio',  c.modelo_anio);
  set('admin-num-serie',    c.num_serie);
  set('admin-num-motor',    c.num_motor);
  set('admin-num-economico',c.num_economico);
  set('admin-tc',           c.tarjeta_circulacion);
  set('admin-fecha-tc',     c.fecha_expedicion_tc);
  setSelect('admin-marca',       c.marca);
  setSelect('admin-color',       c.color);
  setSelect('admin-tipo-placa',  c.tipo_placa);
  setSelect('admin-combustible', c.tipo_combustible);
  setSelect('admin-estado',      c.estado);
  setSelect('admin-tiempo',      c.tiempo_respuesta);
  renderCargoChipsSelect('admin-tipo-carga', c.tipo_carga || []);
  autoFillDimensiones('admin');

  _camionRechazadoId = id;
  const btn = document.getElementById('btn-agregar-camion');
  if (btn) btn.textContent = '💾 Guardar correcciones y reenviar';

  document.getElementById('admin-content-camion')?.scrollIntoView({ behavior: 'smooth' });
}

// Keep for backward compatibility (called after approving a resource via Pendientes tab)
async function aprobarRecurso(tabla, id) {
  const { data: recurso } = await sb.from(tabla).select('propietario_id, nombre').eq('id', id).single();
  const { error } = await sb.from(tabla).update({ aprobacion: 'aprobada', es_edicion: false, campos_editados: null, snapshot_anterior: null }).eq('id', id);
  if (error) { showToast('Error al aprobar'); return; }

  if (recurso?.propietario_id) {
    const tipoLabel = tabla === 'custodios' ? 'custodio' : tabla === 'patios' ? 'patio' : 'servicio de lavado';
    await sb.from('notificaciones').insert({
      user_id: recurso.propietario_id,
      tipo:    'recurso_aprobado',
      titulo:  '✓ Recurso aprobado',
      mensaje: `Tu ${tipoLabel} "${esc(recurso.nombre || id)}" fue aprobado y ya está visible en el catálogo.`,
      leido:   false,
    });
  }
  renderAdmin();
  renderAprobaciones();
  showToast(`✓ ${id} aprobado y publicado en el catálogo`);
}

// ── APROBACIÓN / ELIMINACIÓN ──────────────────────────

async function aprobarUnidad(id) {
  const { data: camion } = await sb.from('camiones').select('propietario_id').eq('id', id).single();
  const { error } = await sb.from('camiones').update({ aprobacion: 'aprobada' }).eq('id', id);
  if (error) { showToast('Error al aprobar'); return; }

  if (camion?.propietario_id) {
    await sb.from('notificaciones').insert({
      user_id: camion.propietario_id,
      tipo:    'recurso_aprobado',
      titulo:  '✓ Unidad aprobada',
      mensaje: `Tu unidad ${id} fue aprobada y ya está visible en el catálogo. ¡Ya puedes recibir solicitudes!`,
      leido:   false,
    });
  }

  renderAdmin(); renderPendientes();
  showToast(`✓ Unidad ${id} aprobada y publicada`);
}

function rechazarUnidad(id) {
  showConfirm(`¿Rechazar la unidad ${id}? Se eliminará del sistema.`, async () => {
    const { data: c } = await sb.from('camiones').select('archivos').eq('id', id).single();
    if (c?.archivos?.length) await sb.storage.from('unidades').remove(c.archivos);
    await sb.from('camiones').delete().eq('id', id);
    await renderAdmin();
    showToast(`Unidad ${id} rechazada`);
  }, { danger: true, confirmLabel: 'Rechazar' });
}

function eliminarUnidad(id) {
  showConfirm(`¿Eliminar la unidad ${id}? Esta acción no se puede deshacer.`, async () => {
    const { data: c } = await sb.from('camiones').select('archivos').eq('id', id).single();
    if (c?.archivos?.length) await sb.storage.from('unidades').remove(c.archivos);
    const { error } = await sb.from('camiones').delete().eq('id', id);
    if (error) { showToast('Error: no tienes permiso para eliminar esta unidad'); return; }
    await renderAdmin();
    showToast(`Unidad ${id} eliminada`);
  }, { danger: true, confirmLabel: 'Eliminar' });
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
  const g = elId => document.getElementById(elId)?.value?.trim() || null;

  const _done = _btnLoading('btn-agregar-camion');
  if (!cap) { _done(); showToast('La capacidad es obligatoria.', 'error'); return; }

  // Validar archivos obligatorios
  if (!document.getElementById('admin-foto-frente')?.files?.[0])  { _done(); showToast('Debes adjuntar la foto del frente de la unidad', 'error'); return; }
  if (!document.getElementById('admin-foto-placa')?.files?.[0])   { _done(); showToast('Debes adjuntar la foto de la placa', 'error'); return; }
  if (!document.getElementById('admin-doc-tc')?.files?.[0])       { _done(); showToast('Debes adjuntar la Tarjeta de Circulación', 'error'); return; }
  if (!document.getElementById('admin-doc-sct')?.files?.[0])      { _done(); showToast('Debes adjuntar el Permiso SCT', 'error'); return; }
  if (!document.getElementById('admin-doc-seguro')?.files?.[0])   { _done(); showToast('Debes adjuntar la Póliza de seguro', 'error'); return; }

  const prefijos = {
    'Torton': 'T', 'Torton caja seca': 'T', 'Torton plataforma': 'T',
    'Rabón': 'R',
    'Full': 'F', 'Full porta contenedor 40/20': 'F', 'Full plataforma': 'F',
    'Plataforma': 'P', 'Plataforma de 3 ejes (sobrepeso)': 'P',
    'Camioneta 1.5 ton caja seca': 'C', 'Camioneta 1.5 ton plataforma': 'C',
    'Camioneta 3.5 ton caja seca': 'C', 'Camioneta 3.5 ton plataforma': 'C',
    'Sencillo porta contenedor 40/20': 'S', 'Sencillo plataforma': 'S',
    'Lowboy': 'L', 'Cama baja': 'B', 'HAZMAT': 'H',
  };
  const letra = prefijos[tipo] || 'U';
  const { data: existentes } = await sb.from('camiones').select('id').like('id', `${letra}-%`);
  const maxNum = (existentes || []).reduce((max, c) => {
    const n = parseInt(c.id.split('-')[1]) || 0;
    return Math.max(max, n);
  }, 0);
  const id = `${letra}-${String(maxNum + 1).padStart(3, '0')}`;

  const esSuperAdmin  = currentUser.rol === 'superadmin';
  const propietarioId = _getPropietarioId('camion');
  if (!propietarioId) { _done(); return; }

  // Subir archivos al storage
  const _getFile = elId => document.getElementById(elId)?.files?.[0];
  const _getFiles = elId => Array.from(document.getElementById(elId)?.files || []);
  const archivos   = [];
  let   imagenTc   = null;
  let   docSctPath = null;
  let   docSegPath = null;

  const fotoEntradas = [
    { prefix: 'frente',   file: _getFile('admin-foto-frente') },
    { prefix: 'trasera',  file: _getFile('admin-foto-trasera') },
    { prefix: 'placa',    file: _getFile('admin-foto-placa') },
    ..._getFiles('admin-foto-laterales').map((f, i) => ({ prefix: `lat${i + 1}`, file: f })),
  ];
  const docEntradas = [
    { prefix: 'tc',     file: _getFile('admin-doc-tc') },
    { prefix: 'sct',    file: _getFile('admin-doc-sct') },
    { prefix: 'seguro', file: _getFile('admin-doc-seguro') },
  ];

  for (const { prefix, file } of [...fotoEntradas, ...docEntradas]) {
    if (!file) continue;
    const ext  = file.name.split('.').pop();
    const path = `${propietarioId}/${id}/${prefix}_${Date.now()}.${ext}`;
    const { data: up, error: upErr } = await sb.storage.from('unidades').upload(path, file);
    if (!upErr && up) {
      archivos.push(up.path);
      if (prefix === 'tc')     imagenTc   = up.path;
      if (prefix === 'sct')    docSctPath = up.path;
      if (prefix === 'seguro') docSegPath = up.path;
    }
  }

  const emojis = {
    'Torton': '🚛', 'Torton caja seca': '🚛', 'Torton plataforma': '🚛',
    'Rabón': '🚚',
    'Full': '🚛', 'Full porta contenedor 40/20': '🚛', 'Full plataforma': '🚛',
    'Plataforma': '🏗️', 'Plataforma de 3 ejes (sobrepeso)': '🏗️',
    'Camioneta 1.5 ton caja seca': '🚐', 'Camioneta 1.5 ton plataforma': '🚐',
    'Camioneta 3.5 ton caja seca': '🚐', 'Camioneta 3.5 ton plataforma': '🚐',
    'Sencillo porta contenedor 40/20': '🚛', 'Sencillo plataforma': '🚛',
    'Lowboy': '🏗️', 'Cama baja': '🏗️', 'HAZMAT': '⚠️',
  };

  const isEdit = !!_camionRechazadoId;
  const targetId = isEdit ? _camionRechazadoId : id;

  const camionPayload = {
    tipo, capacidad: cap, operador: op || null, estado,
    emoji: emojis[tipo] || '🚛',
    archivos,
    aprobacion:          isEdit ? 'pendiente' : (esSuperAdmin ? 'aprobada' : 'pendiente'),
    ...(isEdit && { rechazo_nota: null, rechazo_campos: null }),
    ...(placas         && { placas }),
    ...(dim            && { dimensiones: dim }),
    ...(tiempo         && { tiempo_respuesta: tiempo }),
    ...(tipoCarga.length && { tipo_carga: tipoCarga }),
    ...(precio         && { precio_dia: precio }),
    marca:               g('admin-marca'),
    version:             g('admin-version'),
    modelo_anio:         parseInt(document.getElementById('admin-modelo-anio')?.value) || null,
    color:               g('admin-color'),
    tipo_placa:          g('admin-tipo-placa'),
    num_serie:           g('admin-num-serie'),
    num_motor:           g('admin-num-motor'),
    num_economico:       g('admin-num-economico'),
    tipo_combustible:    g('admin-combustible'),
    tarjeta_circulacion:          g('admin-tc'),
    fecha_expedicion_tc:          document.getElementById('admin-fecha-tc')?.value          || null,
    fecha_vencimiento_tc:          document.getElementById('admin-vence-tc')?.value           || null,
    fecha_vencimiento_seguro:      document.getElementById('admin-vence-seguro')?.value       || null,
    fecha_vencimiento_permiso_sct: document.getElementById('admin-vence-permiso-sct')?.value  || null,
    caat:                          document.getElementById('admin-caat')?.value               || null,
    vigencia_caat:                    document.getElementById('admin-vigencia-caat')?.value         || null,
    fecha_vencimiento_verificacion:   document.getElementById('admin-vence-verificacion')?.value    || null,
    imagen_tc:  imagenTc,
    doc_sct:    docSctPath,
    doc_seguro: docSegPath,
  };

  let error;
  if (isEdit) {
    ({ error } = await sb.from('camiones').update(camionPayload).eq('id', targetId));
  } else {
    ({ error } = await sb.from('camiones').insert({
      id: targetId, propietario_id: propietarioId, ...camionPayload,
    }));
  }
  if (error) { _done(); showToast('No se pudo guardar: ' + _dbError(error), 'error'); return; }

  if (!esSuperAdmin) {
    const { data: sas } = await sb.from('perfiles').select('user_id').eq('rol', 'superadmin');
    if (sas?.length) await sb.from('notificaciones').insert(sas.map(sa => ({
      user_id: sa.user_id, tipo: 'nueva_unidad_pendiente',
      titulo:  'Nueva unidad pendiente de revisión',
      mensaje: `La empresa ${esc(currentUser.nombre || '')} dio de alta la unidad ${targetId} (${tipo}). Revísala en Pendientes.`,
      leido:   false,
    })));
  }

  // Limpiar formulario
  ['admin-cap','admin-precio','admin-placas','admin-dim','admin-version','admin-modelo-anio',
   'admin-num-serie','admin-num-motor','admin-num-economico','admin-tc','admin-fecha-tc',
   'admin-vence-tc','admin-vence-seguro','admin-vence-permiso-sct','admin-caat','admin-vigencia-caat','admin-vence-verificacion'].forEach(fid => {
    const el = document.getElementById(fid); if (el) el.value = '';
  });
  ['admin-foto-frente','admin-foto-laterales','admin-foto-trasera','admin-foto-placa',
   'admin-doc-tc','admin-doc-sct','admin-doc-seguro'].forEach(fid => {
    const el = document.getElementById(fid); if (el) el.value = '';
  });
  [['foto-frente-label','Adjuntar foto'],['foto-laterales-label','Adjuntar fotos'],
   ['foto-trasera-label','Adjuntar foto'],['foto-placa-label','Adjuntar foto'],
   ['doc-tc-label','Adjuntar documento'],['doc-sct-label','Adjuntar documento'],
   ['doc-seguro-label','Adjuntar documento']].forEach(([id, txt]) => {
    const el = document.getElementById(id); if (el) el.textContent = txt;
  });
  ['admin-marca','admin-color','admin-tipo-placa','admin-combustible'].forEach(fid => {
    const el = document.getElementById(fid); if (el) el.selectedIndex = 0;
  });
  renderCargoChipsSelect('admin-tipo-carga', []);

  // Reset rejected-truck edit mode
  _done('➕ Enviar a aprobación');
  _camionRechazadoId = null;

  await renderAdmin();
  const msg = isEdit
    ? `✓ Unidad ${targetId} corregida y reenviada — un administrador la revisará`
    : (esSuperAdmin ? `✓ Unidad ${targetId} agregada` : `✓ Unidad ${targetId} enviada — recibirás confirmación por correo`);
  showToast(msg);
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

function toggleSedenaFields(tipo) {
  const grp = document.getElementById('ac-sedena-group');
  if (grp) grp.style.display = tipo === 'Armado' ? '' : 'none';
}

function toggleSedenaEditFields(tipo) {
  const grp = document.getElementById('ec-sedena-group');
  if (grp) grp.style.display = tipo === 'Armado' ? '' : 'none';
}

async function agregarCustodio() {
  const nombre = document.getElementById('ac-nombre').value.trim();
  const tipo   = document.getElementById('ac-tipo').value;
  const desc   = document.getElementById('ac-desc').value.trim();
  const disp   = document.getElementById('ac-disp').value;
  const precio = parseFloat(document.getElementById('ac-precio').value) || null;
  const certs  = document.getElementById('ac-certs').value.trim();
  const _done = _btnLoading('btn-agregar-custodio');
  if (!nombre || !tipo) { _done(); showToast('Completa nombre y tipo.', 'error'); return; }

  const { data: existentes } = await sb.from('custodios').select('id').like('id','CUS-%');
  const maxNum = (existentes || []).reduce((max, c) => {
    const n = parseInt(c.id.split('-')[1]) || 0; return Math.max(max, n);
  }, 0);
  const id = `CUS-${String(maxNum + 1).padStart(3,'0')}`;

  const esSuperAdmin = currentUser.rol === 'superadmin';
  const propietarioId = _getPropietarioId('custodio');
  if (!propietarioId) { _done(); return; }

  // Subir documento SEDENA si es custodio armado
  let docSedenaUrl = null;
  if (tipo === 'Armado') {
    const sedenaFile = document.getElementById('ac-doc-sedena')?.files?.[0];
    if (sedenaFile) {
      const ext  = sedenaFile.name.split('.').pop();
      const path = `${propietarioId}/${id}/licencia_sedena_${Date.now()}.${ext}`;
      const { error: upErr } = await sb.storage.from('custodios').upload(path, sedenaFile, { upsert: true });
      if (!upErr) docSedenaUrl = sb.storage.from('custodios').getPublicUrl(path).data?.publicUrl || null;
    }
  }

  const { error } = await sb.from('custodios').insert({
    id, nombre, tipo, descripcion: desc || null,
    disponibilidad: disp,
    precio_dia: precio,
    propietario_id: propietarioId,
    certificaciones: certs ? certs.split(',').map(s => s.trim()).filter(Boolean) : [],
    fecha_vencimiento_cert:            document.getElementById('ac-vence-cert')?.value    || null,
    porta_arma:                        tipo === 'Armado',
    num_licencia_sedena:               document.getElementById('ac-num-sedena')?.value.trim() || null,
    fecha_vencimiento_licencia_sedena: document.getElementById('ac-vence-sedena')?.value  || null,
    doc_licencia_sedena:               docSedenaUrl,
    aprobacion: esSuperAdmin ? 'aprobada' : 'pendiente',
  });
  if (error) { _done(); showToast('No se pudo guardar: ' + _dbError(error), 'error'); return; }

  if (!esSuperAdmin) {
    const { data: sas } = await sb.from('perfiles').select('user_id').eq('rol', 'superadmin');
    if (sas?.length) await sb.from('notificaciones').insert(sas.map(sa => ({
      user_id: sa.user_id, tipo: 'nuevo_recurso_pendiente',
      titulo:  'Nuevo custodio pendiente de revisión',
      mensaje: `La empresa ${esc(currentUser.nombre || '')} dio de alta el custodio ${id} (${nombre}). Revísalo en Pendientes.`,
      leido:   false,
    })));
  }

  ['ac-nombre','ac-desc','ac-precio','ac-certs','ac-vence-cert','ac-num-sedena','ac-vence-sedena'].forEach(i => {
    const el = document.getElementById(i); if (el) el.value = '';
  });
  document.getElementById('ac-tipo').value = 'Armado';
  toggleSedenaFields('Armado');
  _done();
  await renderAdminCustodios();
  await renderMisPendientes();
  showToast(esSuperAdmin ? `✓ Custodio ${id} agregado` : `✓ Custodio ${id} enviado — recibirás confirmación`);
}

async function editarCustodio(id) {
  const { data: c } = await sb.from('custodios').select('*').eq('id', id).single();
  if (!c) return;
  const setVal = (elId, val) => { const el = document.getElementById(elId); if (el) el.value = val ?? ''; };
  setVal('ec-id',     c.id);
  setVal('ec-nombre', c.nombre);
  setVal('ec-tipo',   c.tipo);
  setVal('ec-desc',   c.descripcion || '');
  setVal('ec-disp',   c.disponibilidad || '24/7');
  setVal('ec-precio', c.precio_dia || '');
  setVal('ec-certs',  (c.certificaciones || []).join(', '));
  setVal('ec-estado', c.estado);
  setVal('ec-vence-cert',  c.fecha_vencimiento_cert);
  setVal('ec-num-sedena',  c.num_licencia_sedena);
  setVal('ec-vence-sedena', c.fecha_vencimiento_licencia_sedena);

  const docEl = document.getElementById('ec-doc-sedena-actual');
  if (docEl) {
    docEl.innerHTML = c.doc_licencia_sedena
      ? `<a href="${c.doc_licencia_sedena}" target="_blank" style="font-size:0.78rem;color:var(--primary)">📄 Ver licencia SEDENA actual</a>`
      : '';
  }

  toggleSedenaEditFields(c.tipo);
  document.getElementById('modal-editar-custodio').classList.add('open');
}

function closeEditarCustodio() {
  document.getElementById('modal-editar-custodio').classList.remove('open');
}

async function guardarEdicionCustodio() {
  const id   = document.getElementById('ec-id').value;
  const tipo = document.getElementById('ec-tipo').value;
  const certs = document.getElementById('ec-certs').value.trim();

  // Upload SEDENA doc if a new file was selected
  let docSedenaUrl = null;
  if (tipo === 'Armado') {
    const sedenaFile = document.getElementById('ec-doc-sedena')?.files?.[0];
    if (sedenaFile) {
      const ext  = sedenaFile.name.split('.').pop();
      const path = `${currentUser.id}/${id}/licencia_sedena_${Date.now()}.${ext}`;
      const { error: upErr } = await sb.storage.from('custodios').upload(path, sedenaFile, { upsert: true });
      if (!upErr) docSedenaUrl = sb.storage.from('custodios').getPublicUrl(path).data?.publicUrl || null;
    }
  }

  const payload = {
    nombre:          document.getElementById('ec-nombre').value.trim(),
    tipo,
    descripcion:     document.getElementById('ec-desc').value.trim() || null,
    disponibilidad:  document.getElementById('ec-disp').value,
    precio_dia:      parseFloat(document.getElementById('ec-precio').value) || null,
    certificaciones: certs ? certs.split(',').map(s => s.trim()).filter(Boolean) : [],
    estado:          document.getElementById('ec-estado').value,
    fecha_vencimiento_cert:            document.getElementById('ec-vence-cert')?.value    || null,
    porta_arma:                        tipo === 'Armado',
    num_licencia_sedena:               document.getElementById('ec-num-sedena')?.value.trim() || null,
    fecha_vencimiento_licencia_sedena: document.getElementById('ec-vence-sedena')?.value  || null,
  };
  if (docSedenaUrl) payload.doc_licencia_sedena = docSedenaUrl;

  const esSA = currentUser.rol === 'superadmin';
  let upd = payload;
  if (!esSA) {
    const { data: ant } = await sb.from('custodios').select('*').eq('id', id).single();
    upd = { ...payload, aprobacion:'pendiente', es_edicion:true,
      campos_editados: Object.keys(payload).filter(k => JSON.stringify(ant?.[k]) !== JSON.stringify(payload[k])),
      snapshot_anterior: ant };
  }
  const { error } = await sb.from('custodios').update(upd).eq('id', id);
  if (error) { showToast('No se pudo guardar: ' + _dbError(error), 'error'); return; }
  if (!esSA) {
    const { data: sas } = await sb.from('perfiles').select('user_id').eq('rol', 'superadmin');
    if (sas?.length) await sb.from('notificaciones').insert(sas.map(sa => ({
      user_id: sa.user_id, tipo: 'nuevo_recurso_pendiente',
      titulo:  'Custodio editado — revisión pendiente',
      mensaje: `La empresa ${esc(currentUser.nombre || '')} editó el custodio ${id}. Revisa los cambios en Pendientes.`,
      leido:   false,
    })));
  }
  closeEditarCustodio();
  await renderAdminCustodios();
  showToast(esSA ? `✓ Custodio ${id} actualizado` : `✓ Cambios enviados — pendientes de aprobación`);
}

function eliminarCustodio(id) {
  showConfirm(`¿Eliminar custodio ${id}? Esta acción no se puede deshacer.`, async () => {
    await sb.from('custodios').delete().eq('id', id);
    await renderAdminCustodios();
    showToast(`Custodio ${id} eliminado`);
  }, { danger: true, confirmLabel: 'Eliminar' });
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
  const _done = _btnLoading('btn-agregar-patio');
  if (!nombre || !tipo) { _done(); showToast('Completa nombre y tipo.', 'error'); return; }

  const { data: existentes } = await sb.from('patios').select('id').like('id','PAT-%');
  const maxNum = (existentes || []).reduce((max, p) => {
    const n = parseInt(p.id.split('-')[1]) || 0; return Math.max(max, n);
  }, 0);
  const id = `PAT-${String(maxNum + 1).padStart(3,'0')}`;

  const esSuperAdmin = currentUser.rol === 'superadmin';
  const propietarioId = _getPropietarioId('patio');
  if (!propietarioId) { _done(); return; }

  // Upload permiso doc if provided
  let docPermisoUrl = null;
  const permisoFile = document.getElementById('ap-doc-permiso')?.files?.[0];
  if (permisoFile) {
    const ext  = permisoFile.name.split('.').pop();
    const path = `${propietarioId}/${id}/permiso_${Date.now()}.${ext}`;
    const { error: upErr } = await sb.storage.from('unidades').upload(path, permisoFile, { upsert: true });
    if (!upErr) {
      const { data: signed } = await sb.storage.from('unidades').createSignedUrl(path, 60 * 60 * 24 * 365);
      docPermisoUrl = signed?.signedUrl || null;
    }
  }

  const { error } = await sb.from('patios').insert({
    id, nombre, tipo,
    ubicacion: ubic || null,
    area_m2: area, capacidad_vehiculos: capVeh, precio_dia: precio,
    propietario_id: propietarioId,
    servicios: svcsRaw ? svcsRaw.split(',').map(s => s.trim()).filter(Boolean) : [],
    aprobacion: esSuperAdmin ? 'aprobada' : 'pendiente',
    fecha_vencimiento_permiso: document.getElementById('ap-vence-permiso')?.value || null,
    doc_permiso: docPermisoUrl,
  });
  if (error) { _done(); showToast('No se pudo guardar: ' + _dbError(error), 'error'); return; }

  if (!esSuperAdmin) {
    const { data: sas } = await sb.from('perfiles').select('user_id').eq('rol', 'superadmin');
    if (sas?.length) await sb.from('notificaciones').insert(sas.map(sa => ({
      user_id: sa.user_id, tipo: 'nuevo_recurso_pendiente',
      titulo:  'Nuevo patio pendiente de revisión',
      mensaje: `La empresa ${esc(currentUser.nombre || '')} dio de alta el patio ${id} (${nombre}). Revísalo en Pendientes.`,
      leido:   false,
    })));
  }

  ['ap-nombre','ap-ubic','ap-area','ap-cap','ap-precio','ap-svcs','ap-vence-permiso','ap-doc-permiso'].forEach(i => {
    const el = document.getElementById(i); if (el) el.value = '';
  });
  _done();
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
  document.getElementById('ep-svcs').value         = (p.servicios || []).join(', ');
  document.getElementById('ep-vence-permiso').value = p.fecha_vencimiento_permiso || '';
  document.getElementById('ep-estado').value        = p.estado;
  document.getElementById('modal-editar-patio').classList.add('open');
}

function closeEditarPatio() {
  document.getElementById('modal-editar-patio').classList.remove('open');
}

async function guardarEdicionPatio() {
  const id = document.getElementById('ep-id').value;
  const svcsRaw = document.getElementById('ep-svcs').value.trim();
  const payload = {
    nombre:              document.getElementById('ep-nombre').value.trim(),
    tipo:                document.getElementById('ep-tipo').value,
    ubicacion:           document.getElementById('ep-ubic').value.trim()    || null,
    area_m2:             parseFloat(document.getElementById('ep-area').value)   || null,
    capacidad_vehiculos: parseInt(document.getElementById('ep-cap').value)      || null,
    precio_dia:          parseFloat(document.getElementById('ep-precio').value) || null,
    servicios:                svcsRaw ? svcsRaw.split(',').map(s => s.trim()).filter(Boolean) : [],
    fecha_vencimiento_permiso: document.getElementById('ep-vence-permiso')?.value || null,
    estado:                   document.getElementById('ep-estado').value,
  };
  const esSA = currentUser.rol === 'superadmin';
  let upd = payload;
  if (!esSA) {
    const { data: ant } = await sb.from('patios').select('*').eq('id', id).single();
    upd = { ...payload, aprobacion:'pendiente', es_edicion:true,
      campos_editados: Object.keys(payload).filter(k => JSON.stringify(ant?.[k]) !== JSON.stringify(payload[k])),
      snapshot_anterior: ant };
  }
  const { error } = await sb.from('patios').update(upd).eq('id', id);
  if (error) { showToast('No se pudo guardar: ' + _dbError(error), 'error'); return; }
  if (!esSA) {
    const { data: sas } = await sb.from('perfiles').select('user_id').eq('rol', 'superadmin');
    if (sas?.length) await sb.from('notificaciones').insert(sas.map(sa => ({
      user_id: sa.user_id, tipo: 'nuevo_recurso_pendiente',
      titulo:  'Patio editado — revisión pendiente',
      mensaje: `La empresa ${esc(currentUser.nombre || '')} editó el patio ${id}. Revisa los cambios en Pendientes.`,
      leido:   false,
    })));
  }
  closeEditarPatio();
  await renderAdminPatios();
  showToast(esSA ? `✓ Patio ${id} actualizado` : `✓ Cambios enviados — pendientes de aprobación`);
}

function eliminarPatio(id) {
  showConfirm(`¿Eliminar patio ${id}? Esta acción no se puede deshacer.`, async () => {
    await sb.from('patios').delete().eq('id', id);
    await renderAdminPatios();
    showToast(`Patio ${id} eliminado`);
  }, { danger: true, confirmLabel: 'Eliminar' });
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

  const _done = _btnLoading('btn-agregar-lavado');
  if (!nombre) { _done(); showToast('Escribe un nombre para el servicio.', 'error'); return; }

  const propietarioId = _getPropietarioId('lavado');
  if (!propietarioId) { _done(); return; }

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
    propietario_id: propietarioId,
    aprobacion: currentUser.rol === 'superadmin' ? 'aprobada' : 'pendiente',
  });
  if (error) { _done(); showToast('No se pudo guardar: ' + _dbError(error), 'error'); return; }

  if (currentUser.rol !== 'superadmin') {
    const { data: sas } = await sb.from('perfiles').select('user_id').eq('rol', 'superadmin');
    if (sas?.length) await sb.from('notificaciones').insert(sas.map(sa => ({
      user_id: sa.user_id, tipo: 'nuevo_recurso_pendiente',
      titulo:  'Nuevo servicio de lavado pendiente de revisión',
      mensaje: `La empresa ${esc(currentUser.nombre || '')} dio de alta el servicio ${id} (${nombre}). Revísalo en Pendientes.`,
      leido:   false,
    })));
  }

  ['al-nombre','al-tipos-vehiculo','al-tipos-lavado','al-capacidad','al-ubic','al-horario','al-precio','al-desc']
    .forEach(i => { const el = document.getElementById(i); if (el) el.value = ''; });
  _done();
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
  const payload = {
    nombre:         document.getElementById('elav-nombre').value.trim(),
    tipos_vehiculo: tiposVehRaw ? tiposVehRaw.split(',').map(s => s.trim()).filter(Boolean) : [],
    tipos_lavado:   tiposLavRaw ? tiposLavRaw.split(',').map(s => s.trim()).filter(Boolean) : [],
    capacidad:      parseInt(document.getElementById('elav-capacidad').value)    || null,
    ubicacion:      document.getElementById('elav-ubic').value.trim()            || null,
    horario:        document.getElementById('elav-horario').value.trim()         || null,
    precio_lavado:  parseFloat(document.getElementById('elav-precio').value)     || null,
    estado:         document.getElementById('elav-estado').value,
  };
  const esSA = currentUser.rol === 'superadmin';
  let upd = payload;
  if (!esSA) {
    const { data: ant } = await sb.from('lavados').select('*').eq('id', id).single();
    upd = { ...payload, aprobacion:'pendiente', es_edicion:true,
      campos_editados: Object.keys(payload).filter(k => JSON.stringify(ant?.[k]) !== JSON.stringify(payload[k])),
      snapshot_anterior: ant };
  }
  const { error } = await sb.from('lavados').update(upd).eq('id', id);
  if (error) { showToast('No se pudo guardar: ' + _dbError(error), 'error'); return; }
  if (!esSA) {
    const { data: sas } = await sb.from('perfiles').select('user_id').eq('rol', 'superadmin');
    if (sas?.length) await sb.from('notificaciones').insert(sas.map(sa => ({
      user_id: sa.user_id, tipo: 'nuevo_recurso_pendiente',
      titulo:  'Servicio de lavado editado — revisión pendiente',
      mensaje: `La empresa ${esc(currentUser.nombre || '')} editó el servicio de lavado ${id}. Revisa los cambios en Pendientes.`,
      leido:   false,
    })));
  }
  closeEditarLavado();
  await renderAdminLavados();
  showToast(esSA ? `✓ Servicio ${id} actualizado` : `✓ Cambios enviados — pendientes de aprobación`);
}

function eliminarLavado(id) {
  showConfirm(`¿Eliminar servicio de lavado ${id}? Esta acción no se puede deshacer.`, async () => {
  await sb.from('lavados').delete().eq('id', id);
  await renderAdminLavados();
  showToast(`Servicio ${id} eliminado`);
  }, { danger: true, confirmLabel: 'Eliminar' });
}

function updateFileLabel(inputId, labelId) {
  const files = document.getElementById(inputId)?.files;
  const label = document.getElementById(labelId);
  if (!label) return;
  const defaults = {
    'admin-foto-frente':    'Adjuntar foto',
    'admin-foto-laterales': 'Adjuntar fotos',
    'admin-foto-trasera':   'Adjuntar foto',
    'admin-foto-placa':     'Adjuntar foto',
    'admin-doc-tc':         'Adjuntar documento',
    'admin-doc-sct':        'Adjuntar documento',
    'admin-doc-seguro':     'Adjuntar documento',
  };
  if (!files?.length) {
    label.textContent = defaults[inputId] || 'Seleccionar archivo';
  } else {
    label.textContent = `${files.length} archivo${files.length > 1 ? 's' : ''} seleccionado${files.length > 1 ? 's' : ''}`;
  }
}
