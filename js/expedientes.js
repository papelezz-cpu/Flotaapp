// ── EXPEDIENTES DOCUMENTALES DEL VIAJE ──────────────────
//
// Dos momentos en que el transportista se queda varado por papeles:
//   · ingreso_puerto  — sin pedimento, carta de liberación y BL revalidado no
//                       lo dejan entrar al recinto. Viaje en falso.
//   · entrega_vacios  — el contenedor vuelve al depósito que marca la naviera,
//                       y las demoras corren por día hasta que entra.
//
// Es un checklist, no una subida libre: con subida libre nadie sabe qué falta.
// El cliente sube, el transportista acepta o rechaza con nota. El guard de la
// base impide que cada quien haga lo del otro.

const EXP_ETAPAS = {
  ingreso_puerto: {
    icon: '⚓', titulo: 'Documentos para ingresar a puerto',
    desc: 'Lo que el recinto portuario pide para dejar entrar la unidad.',
  },
  entrega_vacios: {
    icon: '📦', titulo: 'Documentos para entregar vacíos',
    desc: 'Lo que se necesita para devolver el contenedor al depósito.',
  },
};

let _expActual = null;   // { expediente, docs, reserva, soyCliente }

// ── Estado de las demoras, derivado ─────────────────────
// Sin trabajo agendado: se calcula al pintar, igual que los cobros. La fecha
// límite es el último día sin cargo; a partir de ahí se cobra por día.
function estadoVacios(exp) {
  if (!exp?.fecha_limite_vacios) return null;
  const hoy   = new Date(); hoy.setHours(0, 0, 0, 0);
  const lim   = new Date(exp.fecha_limite_vacios + 'T00:00:00');
  const dias  = Math.round((lim - hoy) / 86400000);

  if (dias < 0)  return { clave: 'vencido',   cls: 'exp-dem-vencido',
                          label: `⚠ Demoras corriendo — ${Math.abs(dias)} día${Math.abs(dias) === 1 ? '' : 's'}`, dias };
  if (dias === 0) return { clave: 'hoy',      cls: 'exp-dem-hoy',
                          label: '⏰ Último día sin demoras', dias };
  if (dias <= 3) return { clave: 'porvencer', cls: 'exp-dem-porvencer',
                          label: `⏳ ${dias} día${dias === 1 ? '' : 's'} para devolver`, dias };
  return { clave: 'ok', cls: 'exp-dem-ok', label: `Devolver antes del ${fmtFecha(exp.fecha_limite_vacios)}`, dias };
}

// ── El transportista pide la documentación ──────────────
async function solicitarDocumentacion(reservaId, etapa) {
  const cfg = EXP_ETAPAS[etapa];
  if (!cfg) return;

  showConfirm(
    `¿Solicitar al cliente los ${cfg.titulo.toLowerCase()}? Le llegará aviso por campana y correo.`,
    async () => {
      const { data: exist } = await sb.from('expedientes')
        .select('id').eq('reserva_id', reservaId).eq('etapa', etapa).maybeSingle();
      if (exist) { abrirExpediente(reservaId, etapa); return; }

      const { data: exp, error } = await sb.from('expedientes')
        .insert({ reserva_id: reservaId, etapa, solicitado_por: currentUser.id })
        .select().single();
      if (error) { console.error(error); showToast('No se pudo solicitar: ' + (error.message || ''), 'error'); return; }

      // El checklist se copia del catálogo, no se referencia: si mañana editan
      // el catálogo, este expediente debe seguir diciendo lo que se pidió.
      const { data: cat } = await sb.from('documentos_catalogo')
        .select('*').eq('etapa', etapa).eq('activo', true).order('orden');

      if (cat?.length) {
        const { error: e2 } = await sb.from('expediente_documentos').insert(cat.map(c => ({
          expediente_id: exp.id,
          nombre:        c.nombre,
          descripcion:   c.descripcion,
          obligatorio:   c.obligatorio,
          orden:         c.orden,
        })));
        if (e2) { console.error(e2); showToast('El expediente se creó pero sin lista: ' + e2.message, 'error'); }
      }

      await _avisarCliente(reservaId, etapa, 'solicitud');
      showToast('✓ Documentación solicitada al cliente');
      abrirExpediente(reservaId, etapa);
      if (document.getElementById('view-reservaciones')?.classList.contains('active')) renderReserv();
    },
    { confirmLabel: 'Solicitar' }
  );
}

async function _avisarCliente(reservaId, etapa, motivo, detalle = '') {
  const { data: r } = await sb.from('reservaciones')
    .select('cliente_user_id, propietario_id, unidad').eq('id', reservaId).single();
  if (!r?.cliente_user_id) return;

  const cfg = EXP_ETAPAS[etapa];
  const txt = motivo === 'solicitud'
    ? `El transportista necesita los ${cfg.titulo.toLowerCase()} para el servicio "${r.unidad}". Súbelos desde Reservaciones.`
    : `Falta corregir documentación del servicio "${r.unidad}". ${detalle}`;

  await sb.from('notificaciones').insert({
    user_id: r.cliente_user_id,
    tipo:    'documentos_solicitados',
    titulo:  motivo === 'solicitud' ? `${cfg.icon} Documentación solicitada` : '⚠ Documento por corregir',
    mensaje: txt,
    leido:   false,
  });
  _notificarEmail({
    tipo: 'resolucion', destinoIds: [r.cliente_user_id],
    titulo: motivo === 'solicitud' ? 'Documentación solicitada' : 'Documento por corregir',
    mensaje: txt, nota: detalle || null, aprobado: motivo === 'solicitud',
  });
}

async function _avisarTransportista(reservaId, etapa, titulo, mensaje) {
  const { data: r } = await sb.from('reservaciones')
    .select('propietario_id').eq('id', reservaId).single();
  if (!r?.propietario_id) return;
  await sb.from('notificaciones').insert({
    user_id: r.propietario_id, tipo: 'documentos_listos', titulo, mensaje, leido: false,
  });
  _notificarEmail({ tipo: 'resolucion', destinoIds: [r.propietario_id], titulo, mensaje });
}

// ── Abrir el expediente ─────────────────────────────────
async function abrirExpediente(reservaId, etapa) {
  const { data: exp, error } = await sb.from('expedientes')
    .select('*').eq('reserva_id', reservaId).eq('etapa', etapa).maybeSingle();
  if (error) { console.error(error); showToast('No se pudo abrir: ' + error.message, 'error'); return; }
  if (!exp) { showToast('Todavía no se ha solicitado esta documentación'); return; }

  const [{ data: docs }, { data: reserva }] = await Promise.all([
    sb.from('expediente_documentos').select('*').eq('expediente_id', exp.id).order('orden'),
    sb.from('reservaciones').select('cliente_user_id, propietario_id, unidad, cliente').eq('id', reservaId).single(),
  ]);

  _expActual = {
    expediente: exp,
    docs: docs || [],
    reserva,
    soyCliente: reserva?.cliente_user_id === currentUser.id,
  };
  _renderExpediente();
  document.getElementById('modal-expediente').classList.add('open');
}

function cerrarExpediente() {
  document.getElementById('modal-expediente').classList.remove('open');
  _expActual = null;
}

function _renderExpediente() {
  if (!_expActual) return;
  const { expediente: e, docs, soyCliente } = _expActual;
  const cfg = EXP_ETAPAS[e.etapa];

  document.getElementById('exp-titulo').textContent = `${cfg.icon} ${cfg.titulo}`;

  const obligatorios = docs.filter(d => d.obligatorio);
  const listos = obligatorios.filter(d => d.estado === 'subido' || d.estado === 'aceptado').length;
  const rechazados = docs.filter(d => d.estado === 'rechazado').length;

  const dem = e.etapa === 'entrega_vacios' ? estadoVacios(e) : null;

  document.getElementById('exp-content').innerHTML = `
    <p class="exp-desc">${esc(cfg.desc)}</p>

    <div class="exp-progreso">
      <div class="exp-progreso-barra">
        <div class="exp-progreso-fill" style="width:${obligatorios.length ? Math.round(listos / obligatorios.length * 100) : 0}%"></div>
      </div>
      <span>${listos} de ${obligatorios.length} obligatorios</span>
      ${rechazados ? `<span class="exp-rechazados">${rechazados} por corregir</span>` : ''}
    </div>

    ${dem ? `<div class="exp-demoras ${dem.cls}">${esc(dem.label)}</div>` : ''}

    ${e.etapa === 'entrega_vacios' ? _expVaciosHTML(e, soyCliente) : ''}

    <div class="exp-lista">
      ${docs.map(d => _expDocHTML(d, soyCliente)).join('') ||
        '<div class="empty-state"><div class="icon">📄</div>Sin documentos en la lista. Revisa el catálogo.</div>'}
    </div>

    ${!soyCliente && e.estado !== 'completo' && listos === obligatorios.length && obligatorios.length ? `
      <button class="btn-confirm" style="width:100%;margin-top:14px" onclick="marcarExpedienteCompleto()">
        ✓ Documentación completa — dar por bueno el expediente
      </button>` : ''}
    ${e.estado === 'completo' ? '<div class="exp-completo">✓ El transportista dio por completo este expediente.</div>' : ''}
  `;
}

// Depósito y fecha límite: es donde está el dinero de las demoras.
function _expVaciosHTML(e, soyCliente) {
  return `
    <div class="exp-vacios">
      <div class="form-group">
        <label>Depósito de vacíos asignado</label>
        <input type="text" id="exp-deposito" value="${esc(e.deposito_vacios || '')}"
               placeholder="Ej. Patio Ferromex, Av. Tepeyac 300" ${soyCliente ? '' : 'disabled'}>
      </div>
      <div class="form-group">
        <label>Último día para devolver sin demoras</label>
        <input type="date" id="exp-fecha-limite" value="${e.fecha_limite_vacios || ''}" ${soyCliente ? '' : 'disabled'}>
      </div>
      ${soyCliente ? `<button class="btn-add" onclick="guardarDatosVacios()">💾 Guardar</button>` : ''}
    </div>`;
}

function _expDocHTML(d, soyCliente) {
  const badge = {
    pendiente: '<span class="exp-badge exp-badge--pend">Pendiente</span>',
    subido:    '<span class="exp-badge exp-badge--sub">Subido</span>',
    aceptado:  '<span class="exp-badge exp-badge--ok">✓ Aceptado</span>',
    rechazado: '<span class="exp-badge exp-badge--rech">⚠ Por corregir</span>',
  }[d.estado] || '';

  const acciones = soyCliente
    ? (d.estado === 'aceptado' ? ''
        : `<label class="exp-subir">
             ${d.estado === 'pendiente' ? '📎 Subir' : '🔄 Reemplazar'}
             <input type="file" accept=".pdf,.jpg,.jpeg,.png" onchange="subirDocumento('${d.id}', this)">
           </label>`)
    : (d.archivo_path ? `
        <button class="exp-btn" onclick="verDocumento('${d.id}')">👁 Ver</button>
        ${d.estado !== 'aceptado' ? `<button class="exp-btn exp-btn--ok" onclick="dictaminarDocumento('${d.id}', true)">✓ Aceptar</button>` : ''}
        <button class="exp-btn exp-btn--no" onclick="dictaminarDocumento('${d.id}', false)">⚠ Pedir corrección</button>`
      : '<span class="exp-esperando">Esperando al cliente</span>');

  return `
    <div class="exp-doc ${d.estado === 'rechazado' ? 'exp-doc--rech' : ''}">
      <div class="exp-doc-info">
        <div class="exp-doc-nombre">
          ${esc(d.nombre)}${d.obligatorio ? '' : ' <small>opcional</small>'}
          ${badge}
        </div>
        ${d.descripcion ? `<div class="exp-doc-desc">${esc(d.descripcion)}</div>` : ''}
        ${d.archivo_nombre ? `<div class="exp-doc-archivo">📄 ${esc(d.archivo_nombre)}</div>` : ''}
        ${d.nota_rechazo && d.estado === 'rechazado'
          ? `<div class="exp-doc-nota">⚠ ${esc(d.nota_rechazo)}</div>` : ''}
      </div>
      <div class="exp-doc-acciones">${acciones}</div>
    </div>`;
}

// ── Cliente: subir ──────────────────────────────────────
async function subirDocumento(docId, input) {
  const file = input?.files?.[0];
  if (!file || !_expActual) return;
  if (file.size > 10 * 1024 * 1024) { showToast('El archivo no puede pasar de 10 MB', 'error'); return; }

  showToast('Subiendo…');
  const ext  = file.name.split('.').pop();
  // La ruta empieza con el id del expediente: de ahí resuelve la política de
  // storage quién puede verlo.
  const path = `${_expActual.expediente.id}/${docId}_${Date.now()}.${ext}`;

  const { error: eUp } = await sb.storage.from('documentos-viaje').upload(path, file, { upsert: true });
  if (eUp) { console.error(eUp); showToast('No se pudo subir: ' + eUp.message, 'error'); return; }

  const { error } = await sb.from('expediente_documentos').update({
    archivo_path:   path,
    archivo_nombre: file.name,
    estado:         'subido',
    nota_rechazo:   null,
    subido_en:      new Date().toISOString(),
    subido_por:     currentUser.id,
  }).eq('id', docId);
  if (error) { console.error(error); showToast('No se pudo guardar: ' + error.message, 'error'); return; }

  await _refrescarExpediente();
  showToast('✓ Documento subido');
  await _avisarSiCompleto();
}

// Cuando ya está todo lo obligatorio, se avisa al transportista una sola vez.
async function _avisarSiCompleto() {
  const { expediente: e, docs } = _expActual;
  const oblig = docs.filter(d => d.obligatorio);
  const listos = oblig.filter(d => d.estado === 'subido' || d.estado === 'aceptado');
  if (!oblig.length || listos.length < oblig.length) return;
  if (e.estado !== 'solicitado') return;

  await sb.from('expedientes').update({ estado: 'en_revision' }).eq('id', e.id);
  const cfg = EXP_ETAPAS[e.etapa];
  await _avisarTransportista(e.reserva_id, e.etapa,
    '📄 Documentación lista para revisar',
    `El cliente subió todos los documentos obligatorios de "${cfg.titulo.toLowerCase()}". Revísalos, descárgalos e imprímelos.`);
  await _refrescarExpediente();
}

async function guardarDatosVacios() {
  if (!_expActual) return;
  const dep = document.getElementById('exp-deposito')?.value?.trim() || null;
  const lim = document.getElementById('exp-fecha-limite')?.value || null;
  const { error } = await sb.from('expedientes')
    .update({ deposito_vacios: dep, fecha_limite_vacios: lim })
    .eq('id', _expActual.expediente.id);
  if (error) { console.error(error); showToast('No se pudo guardar: ' + error.message, 'error'); return; }
  await _refrescarExpediente();
  showToast('✓ Datos de devolución guardados');
}

// ── Transportista: revisar ──────────────────────────────
async function verDocumento(docId) {
  const d = _expActual?.docs.find(x => x.id === docId);
  if (!d?.archivo_path) return;
  const { data, error } = await sb.storage.from('documentos-viaje')
    .createSignedUrl(d.archivo_path, 3600);
  if (error || !data?.signedUrl) { showToast('No se pudo abrir el archivo', 'error'); return; }
  window.open(data.signedUrl, '_blank');
}

function dictaminarDocumento(docId, aceptar) {
  if (aceptar) { _guardarDictamen(docId, 'aceptado', null); return; }
  _abrirRechazarNota(
    'Pedir corrección',
    '¿Qué falta o qué está mal? El cliente lo verá:',
    nota => _guardarDictamen(docId, 'rechazado', nota || null),
    { confirmLabel: 'Pedir corrección', danger: true }
  );
}

async function _guardarDictamen(docId, estado, nota) {
  const { error } = await sb.from('expediente_documentos')
    .update({ estado, nota_rechazo: nota }).eq('id', docId);
  if (error) { console.error(error); showToast('No se pudo guardar: ' + error.message, 'error'); return; }

  if (estado === 'rechazado') {
    const d = _expActual.docs.find(x => x.id === docId);
    await sb.from('expedientes').update({ estado: 'solicitado' }).eq('id', _expActual.expediente.id);
    await _avisarCliente(_expActual.expediente.reserva_id, _expActual.expediente.etapa,
      'correccion', `${d?.nombre || 'Un documento'}: ${nota || 'requiere corrección'}`);
  }
  await _refrescarExpediente();
  showToast(estado === 'aceptado' ? '✓ Documento aceptado' : 'Corrección solicitada al cliente');
}

async function marcarExpedienteCompleto() {
  const e = _expActual?.expediente;
  if (!e) return;
  const { error } = await sb.from('expedientes')
    .update({ estado: 'completo', completado_en: new Date().toISOString() }).eq('id', e.id);
  if (error) { console.error(error); showToast('No se pudo cerrar: ' + error.message, 'error'); return; }

  await sb.from('notificaciones').insert({
    user_id: _expActual.reserva.cliente_user_id,
    tipo:    'documentos_completos',
    titulo:  '✓ Documentación aceptada',
    mensaje: `El transportista dio por completa la documentación de "${EXP_ETAPAS[e.etapa].titulo.toLowerCase()}".`,
    leido:   false,
  });
  await _refrescarExpediente();
  showToast('✓ Expediente marcado como completo');
  if (document.getElementById('view-reservaciones')?.classList.contains('active')) renderReserv();
}

async function _refrescarExpediente() {
  if (!_expActual) return;
  const id = _expActual.expediente.id;
  const [{ data: exp }, { data: docs }] = await Promise.all([
    sb.from('expedientes').select('*').eq('id', id).single(),
    sb.from('expediente_documentos').select('*').eq('expediente_id', id).order('orden'),
  ]);
  if (exp)  _expActual.expediente = exp;
  if (docs) _expActual.docs = docs;
  _renderExpediente();
}

// ── Se dispara solo al entregar ─────────────────────────
// El expediente de vacíos nadie se acuerda de pedirlo, y es justo donde corren
// las demoras. Se abre al llegar el tracking a "Entregado" si hubo contenedor.
async function abrirExpedienteVaciosSiAplica(reserva) {
  if (!reserva?.pedido_id) return;
  const { data: ped } = await sb.from('pedidos')
    .select('categoria_carga, num_contenedores').eq('id', reserva.pedido_id).maybeSingle();
  const hayContenedor = ped?.categoria_carga === 'Contenerizada' || (ped?.num_contenedores || 0) > 0;
  if (!hayContenedor) return;

  const { data: exist } = await sb.from('expedientes')
    .select('id').eq('reserva_id', reserva.id).eq('etapa', 'entrega_vacios').maybeSingle();
  if (exist) return;

  const { data: exp, error } = await sb.from('expedientes')
    .insert({ reserva_id: reserva.id, etapa: 'entrega_vacios', solicitado_por: currentUser.id })
    .select().single();
  if (error) { console.error('No se pudo abrir el expediente de vacíos:', error); return; }

  const { data: cat } = await sb.from('documentos_catalogo')
    .select('*').eq('etapa', 'entrega_vacios').eq('activo', true).order('orden');
  if (cat?.length) {
    await sb.from('expediente_documentos').insert(cat.map(c => ({
      expediente_id: exp.id, nombre: c.nombre, descripcion: c.descripcion,
      obligatorio: c.obligatorio, orden: c.orden,
    })));
  }
  await _avisarCliente(reserva.id, 'entrega_vacios', 'solicitud');
  showToast('📦 Se abrió el expediente de entrega de vacíos');
}

// ── Botones dentro de la fila de la reservación ─────────
function expedienteBotonesHTML(r, soyCliente) {
  const btns = [];
  const pill = (etapa, exp) => {
    const cfg = EXP_ETAPAS[etapa];
    if (!exp) {
      if (soyCliente) return '';
      return `<button class="btn-edit exp-pedir" style="font-size:0.72rem"
                onclick="solicitarDocumentacion('${r.id}','${etapa}')">${cfg.icon} Solicitar documentación</button>`;
    }
    const dem = etapa === 'entrega_vacios' ? estadoVacios(exp) : null;
    const alerta = exp.estado !== 'completo' && soyCliente ? ' exp-pill--pend' : '';
    return `<button class="exp-pill${alerta}${dem && dem.clave !== 'ok' ? ' ' + dem.cls : ''}" style="font-size:0.72rem"
              onclick="abrirExpediente('${r.id}','${etapa}')">
              ${cfg.icon} ${exp.estado === 'completo' ? '✓' : ''} ${etapa === 'entrega_vacios' ? 'Vacíos' : 'Puerto'}
            </button>`;
  };
  btns.push(pill('ingreso_puerto', r._expIngreso));
  if (r._expVacios) btns.push(pill('entrega_vacios', r._expVacios));
  return btns.filter(Boolean).join('');
}

// Carga los expedientes de un lote de reservaciones en una sola consulta, para
// no hacer una por fila.
async function cargarExpedientes(reservas) {
  const ids = (reservas || []).map(r => r.id);
  if (!ids.length) return;
  const { data } = await sb.from('expedientes').select('*').in('reserva_id', ids);
  const porReserva = {};
  (data || []).forEach(e => {
    porReserva[e.reserva_id] = porReserva[e.reserva_id] || {};
    porReserva[e.reserva_id][e.etapa] = e;
  });
  reservas.forEach(r => {
    r._expIngreso = porReserva[r.id]?.ingreso_puerto || null;
    r._expVacios  = porReserva[r.id]?.entrega_vacios || null;
  });
}
