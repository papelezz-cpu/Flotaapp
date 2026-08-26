// ── MÓDULO DE REVISIONES (solo superadmin) ─────────────

// Avisa de una resolución del superadmin por campana Y por correo.
//
// Todas estas resoluciones (cuenta aprobada, camión rechazado, solicitud
// publicada, finalización aprobada…) llegaban solo a la campana, o sea que el
// usuario se enteraba únicamente si abría la app — justo lo que no hace
// mientras espera a que le aprueben la cuenta para poder entrar.
//
// El correo es transaccional: va sobre algo del propio usuario que él está
// esperando, así que NO se puede silenciar desde el perfil (ver
// TIPOS_SILENCIABLES en supabase/functions/enviar-notificacion).
async function _notificarResolucion(destinos, { tipo, titulo, mensaje, nota = null, aprobado = true }) {
  const ids = [...new Set((Array.isArray(destinos) ? destinos : [destinos]).filter(Boolean))];
  if (!ids.length) return;

  const { error } = await sb.from('notificaciones').insert(ids.map(uid => ({
    user_id: uid,
    tipo,
    titulo,
    mensaje: nota ? `${mensaje} Motivo: ${nota}` : mensaje,
    leido:   false,
  })));
  if (error) console.error('No se pudo notificar en la campana:', error);

  _notificarEmail({ tipo: 'resolucion', destinoIds: ids, titulo, mensaje, nota, aprobado });
}

// ─── Modal genérico para rechazo con nota ──────────────
let _rechazarNotaCb = null;

// opts: { confirmLabel, danger } — por defecto se comporta como rechazo, que
// es el uso original; privacidad.js lo reutiliza para respuestas afirmativas.
function _abrirRechazarNota(titulo, label, callback, opts = {}) {
  const { confirmLabel = '✕ Confirmar rechazo', danger = true } = opts;
  document.getElementById('rn-titulo').textContent = titulo;
  document.getElementById('rn-label').textContent  = label;
  document.getElementById('rn-nota').value         = '';
  const btn = document.getElementById('rn-confirm');
  if (btn) {
    btn.textContent = confirmLabel;
    btn.style.background   = danger ? 'var(--danger)' : 'var(--green)';
    btn.style.borderColor  = danger ? 'var(--danger)' : 'var(--green)';
  }
  _rechazarNotaCb = callback;
  document.getElementById('modal-rechazar-nota').classList.add('open');
  setTimeout(() => document.getElementById('rn-nota')?.focus(), 100);
}

function cerrarRechazarNota() {
  document.getElementById('modal-rechazar-nota').classList.remove('open');
  _rechazarNotaCb = null;
}

function confirmarRechazarNota() {
  const nota = document.getElementById('rn-nota').value.trim();
  const cb   = _rechazarNotaCb;
  cerrarRechazarNota();
  if (cb) cb(nota);
}

async function renderAprobaciones() {
  if (currentUser.rol !== 'superadmin') return;

  const section = document.getElementById('aprobaciones-section');
  if (section) section.style.display = '';

  const content = document.getElementById('aprobaciones-content');
  if (!content) return;
  content.innerHTML = '<div style="text-align:center;padding:16px;color:var(--text-muted)">Cargando…</div>';

  const [{ data: solicitudes }, { data: acuerdos }, { data: operadores },
         { data: camiones }, { data: custodios }, { data: patios }, { data: lavados },
         { data: cuentasPend }, { data: docsEmpresa }, { data: finalizaciones },
         { data: cancelaciones }] = await Promise.all([
    sb.from('pedidos').select('*').eq('estado', 'pendiente_revision').order('created_at'),
    sb.from('pedidos').select('*').eq('estado', 'pendiente_acuerdo').order('created_at'),
    sb.from('operadores').select('*, propietario:perfiles(nombre)').eq('aprobacion', 'pendiente').order('created_at'),
    sb.from('camiones'  ).select('*, propietario:perfiles(nombre)').eq('aprobacion', 'pendiente').order('created_at', { ascending: false }),
    sb.from('custodios' ).select('*, propietario:perfiles(nombre)').eq('aprobacion', 'pendiente').order('created_at', { ascending: false }),
    sb.from('patios'    ).select('*, propietario:perfiles(nombre)').eq('aprobacion', 'pendiente').order('created_at', { ascending: false }),
    sb.from('lavados'   ).select('*, propietario:perfiles(nombre)').eq('aprobacion', 'pendiente').order('id', { ascending: false }),
    sb.from('solicitudes_cuenta').select('*').eq('estado', 'pendiente').order('created_at', { ascending: false }),
    sb.from('perfiles').select('user_id, nombre, fecha_vencimiento_permiso_sct, fecha_vencimiento_permiso_sct_pendiente, fecha_vencimiento_seguro_rc, fecha_vencimiento_seguro_rc_pendiente, fecha_vencimiento_seguro_carga, fecha_vencimiento_seguro_carga_pendiente, doc_permiso_sct, doc_permiso_sct_pendiente, doc_seguro_rc, doc_seguro_rc_pendiente, doc_seguro_carga, doc_seguro_carga_pendiente').eq('perfil_docs_pendiente', true),
    sb.from('reservaciones').select('*').eq('estado', 'PorAprobar').order('completado_en'),
    sb.from('reservaciones').select('*').eq('estado', 'CancelacionSolicitada').order('cancelacion_solicitada_en'),
  ]);

  // Nombre de empresa para finalizaciones y cancelaciones pendientes
  const finEmpresaMap = {};
  const _conPropietario = [...(finalizaciones || []), ...(cancelaciones || [])];
  if (_conPropietario.length) {
    const propIds = [...new Set(_conPropietario.map(r => r.propietario_id).filter(Boolean))];
    if (propIds.length) {
      const { data: props } = await sb.from('perfiles').select('user_id, nombre').in('user_id', propIds);
      (props || []).forEach(p => { finEmpresaMap[p.user_id] = p.nombre; });
    }
  }

  // Cargar ofertas pendientes para los acuerdos
  let ofertasMap = {};
  if (acuerdos?.length) {
    const ofertaIds = acuerdos.filter(p => p.oferta_pendiente_id).map(p => p.oferta_pendiente_id);
    if (ofertaIds.length) {
      const { data: ofertas } = await sb.from('ofertas').select('*').in('id', ofertaIds);
      (ofertas || []).forEach(o => { ofertasMap[o.id] = o; });
    }
  }

  // Compliance de empresa para cada admin con acuerdo pendiente
  const empresaComplianceMap = {};
  if (acuerdos?.length) {
    const _hoyAcu = new Date().toISOString().slice(0, 10);
    const adminIds = [...new Set(
      acuerdos.map(p => p.oferta_pendiente_id && ofertasMap[p.oferta_pendiente_id]?.admin_id).filter(Boolean)
    )];
    if (adminIds.length) {
      const { data: perfilesEmp } = await sb.from('perfiles')
        .select('user_id, fecha_vencimiento_permiso_sct, fecha_vencimiento_seguro_rc, fecha_vencimiento_seguro_carga')
        .in('user_id', adminIds);
      (perfilesEmp || []).forEach(p => {
        const exp = [];
        if (p.fecha_vencimiento_permiso_sct  && p.fecha_vencimiento_permiso_sct  < _hoyAcu) exp.push('SCT');
        if (p.fecha_vencimiento_seguro_rc    && p.fecha_vencimiento_seguro_rc    < _hoyAcu) exp.push('RC');
        if (p.fecha_vencimiento_seguro_carga && p.fecha_vencimiento_seguro_carga < _hoyAcu) exp.push('Carga');
        empresaComplianceMap[p.user_id] = exp;
      });
    }
  }

  // ── AGRUPAR RECURSOS POR EMPRESA ────────────────────
  const empresasMap = {};
  const _addEmp = (propId, propNombre, tipo, item) => {
    if (!propId) return;
    if (!empresasMap[propId]) empresasMap[propId] = { nombre: propNombre || propId, camiones:[], operadores:[], custodios:[], patios:[], lavados:[] };
    empresasMap[propId][tipo].push(item);
  };
  (camiones   || []).forEach(c => _addEmp(c.propietario_id, c.propietario?.nombre, 'camiones',   c));
  (operadores || []).forEach(o => _addEmp(o.propietario_id, o.propietario?.nombre, 'operadores', o));
  (custodios  || []).forEach(c => _addEmp(c.propietario_id, c.propietario?.nombre, 'custodios',  c));
  (patios     || []).forEach(p => _addEmp(p.propietario_id, p.propietario?.nombre, 'patios',     p));
  (lavados    || []).forEach(l => _addEmp(l.propietario_id, l.propietario?.nombre, 'lavados',    l));

  const totalRecursos = (camiones?.length||0)+(operadores?.length||0)+(custodios?.length||0)+(patios?.length||0)+(lavados?.length||0);

  // Helper: tarjeta colapsable genérica
  const _colapseCard = (uid, headerHtml, bodyHtml) => `
    <div class="apr-empresa-card" id="aprc-outer-${uid}">
      <div class="apr-empresa-header" onclick="toggleEmpresaApr('aprc-${uid}')">
        ${headerHtml}
        <span class="apr-emp-toggle" id="apr-tog-aprc-${uid}">▼</span>
      </div>
      <div class="apr-empresa-items" id="apr-emp-aprc-${uid}" style="display:none">
        ${bodyHtml}
      </div>
    </div>`;

  // Paneles por pestaña. Cada bloque escribe en el suyo con `html +=` a través
  // de la variable `html`, que se reasigna antes de cada sección (ver más
  // abajo cómo se ensamblan al final).
  const P = { cuentas: '', solicitudes: '', acuerdos: '', servicios: '', recursos: '' };
  let html = '';

  // ── DOCUMENTOS DE EMPRESA PENDIENTES ─────────────────
  if (docsEmpresa?.length) {
    html += `<div class="apr-bloque-title">📋 Documentos de empresa <span class="apr-count">${docsEmpresa.length}</span></div>`;
    const _verDoc = (url, label) => url
      ? `<a href="${url}" target="_blank" class="btn-edit" style="font-size:0.75rem;display:inline-block;margin:2px 4px 2px 0">📄 ${label}</a>`
      : `<span style="font-size:0.75rem;color:var(--text-muted)">Sin archivo</span>`;
    const _fecha = (act, pend) => {
      const linea = `${fmtFecha(pend) || '—'}`;
      const prev  = act ? `<span style="text-decoration:line-through;color:var(--text-muted);margin-left:6px;font-size:0.8rem">${fmtFecha(act)}</span>` : '';
      return linea + prev;
    };
    html += docsEmpresa.map(p => `
      <div class="apr-card" id="apr-docs-${p.user_id}">
        <div class="apr-card-header">
          <div>
            <div class="apr-tipo">🏢 ${esc(p.nombre || p.user_id)}</div>
            <div class="apr-sub">Actualización de documentos legales</div>
          </div>
          <span class="apr-edicion-tag">📤 Enviado</span>
        </div>
        <div class="apr-op-detalle">
          <div class="apr-op-grid">
            <div class="apr-op-row"><span>Permiso SCT</span><strong>${_fecha(p.fecha_vencimiento_permiso_sct, p.fecha_vencimiento_permiso_sct_pendiente)}</strong></div>
            <div class="apr-op-row" style="grid-column:1/-1">${_verDoc(p.doc_permiso_sct_pendiente, 'Ver permiso SCT')}</div>
            <div class="apr-op-row"><span>Seguro RC</span><strong>${_fecha(p.fecha_vencimiento_seguro_rc, p.fecha_vencimiento_seguro_rc_pendiente)}</strong></div>
            <div class="apr-op-row" style="grid-column:1/-1">${_verDoc(p.doc_seguro_rc_pendiente, 'Ver seguro RC')}</div>
            <div class="apr-op-row"><span>Seguro de carga</span><strong>${_fecha(p.fecha_vencimiento_seguro_carga, p.fecha_vencimiento_seguro_carga_pendiente)}</strong></div>
            <div class="apr-op-row" style="grid-column:1/-1">${_verDoc(p.doc_seguro_carga_pendiente, 'Ver seguro carga')}</div>
          </div>
        </div>
        <div class="apr-actions">
          <button class="btn-apr-aprobar"  onclick="aprobarDocsEmpresa('${p.user_id}')">✓ Aprobar documentos</button>
          <button class="btn-apr-rechazar" onclick="rechazarDocsEmpresa('${p.user_id}','${escJs(p.nombre || '')}')">✕ Rechazar</button>
        </div>
      </div>`).join('');
  }

  // ── CUENTAS POR VERIFICAR ────────────────────────────
  html += `<div class="apr-bloque-title">👤 Cuentas por verificar <span class="apr-count">${cuentasPend.length}</span></div>`;
  if (!cuentasPend.length) {
    html += `<div class="apr-empty">Sin solicitudes de cuenta pendientes</div>`;
  } else {
    const verDoc = (path, label) => path
      ? `<a href="#" onclick="verDocRegistro('${escJs(path)}');return false" class="btn-edit" style="font-size:0.75rem;display:inline-block;margin:2px 4px 2px 0">📄 ${label}</a>`
      : '';
    html += cuentasPend.map(s => {
      const rolLabel = s.rol === 'cliente' ? '🛒 Cliente' : '🏢 Empresa';
      const fachada  = Array.isArray(s.doc_fotos_oficinas) ? s.doc_fotos_oficinas[0] : null;
      const idDoc    = s.doc_id_oficial || s.doc_id_representante;
      const header = `
        <div style="flex:1;display:flex;align-items:center;gap:12px;min-width:0">
          <div>
            <div class="apr-empresa-name">${rolLabel} — ${esc(s.nombre || '—')}</div>
            <div class="apr-empresa-counts">
              <span class="apr-ec">${esc(s.email)}</span>
              ${s.telefono ? `<span class="apr-ec">📞 ${esc(s.telefono)}</span>` : ''}
              <span class="apr-ec-total">Pendiente</span>
            </div>
          </div>
        </div>`;
      const body = `
        <div class="apr-card" id="aprcuenta-${s.user_id}" style="margin:8px 0 0;border:none;box-shadow:none">
          <div class="apr-op-detalle">
            ${s.rol === 'admin' ? `
              <div class="apr-op-section-title">Datos de la empresa</div>
              <div class="apr-op-grid">
                <div class="apr-op-row"><span>Razón social</span><strong>${esc(s.razon_social || '—')}</strong></div>
                <div class="apr-op-row"><span>RFC</span><strong>${esc(s.rfc || '—')}</strong></div>
                <div class="apr-op-row"><span>Tipo persona</span><strong>${esc(s.tipo_persona || '—')}</strong></div>
              </div>` : `
              <div class="apr-op-section-title">Datos personales</div>
              <div class="apr-op-grid">
                <div class="apr-op-row"><span>RFC</span><strong>${esc(s.rfc || '—')}</strong></div>
                <div class="apr-op-row"><span>CURP</span><strong>${esc(s.curp || '—')}</strong></div>
              </div>`}
            <div class="apr-op-section-title">Domicilio</div>
            <div class="apr-op-grid">
              <div class="apr-op-row"><span>Calle</span><strong>${esc(s.calle || '—')}</strong></div>
              <div class="apr-op-row"><span>Colonia</span><strong>${esc(s.colonia || '—')}</strong></div>
              <div class="apr-op-row"><span>CP</span><strong>${esc(s.cp || '—')}</strong></div>
              <div class="apr-op-row"><span>Ciudad / Estado</span><strong>${esc([s.ciudad, s.estado_mx].filter(Boolean).join(', '))}</strong></div>
            </div>
            <div class="apr-op-section-title">Documentos</div>
            <div style="margin-top:6px;display:flex;flex-wrap:wrap;gap:4px">
              ${verDoc(idDoc, 'Identificación')}
              ${verDoc(s.doc_comprobante_dom,   'Comp. domicilio')}
              ${verDoc(s.doc_foto_domicilio,    'Foto domicilio')}
              ${verDoc(fachada,                 'Foto fachada')}
              ${verDoc(s.doc_constancia_fiscal, 'Const. Fiscal SAT')}
              ${verDoc(s.doc_acta_constitutiva, 'Acta constitutiva')}
              ${verDoc(s.doc_poder_notarial,    'Poder notarial')}
            </div>
          </div>
          <div class="apr-actions" style="flex-wrap:wrap">
            <button class="btn-apr-aprobar" onclick="aprobarCuenta('${s.user_id}','documental')">✓ Aprobar sin verificación física</button>
            <button class="btn-apr-aprobar" onclick="aprobarCuenta('${s.user_id}','fisica')">✓ Aprobar con verificación física</button>
            <button class="btn-apr-rechazar" onclick="rechazarCuenta('${s.user_id}')">✕ Rechazar</button>
          </div>
        </div>`;
      return _colapseCard(`cuenta-${s.user_id}`, header, body);
    }).join('');
  }

  P.cuentas = html; html = '';

  // ── SOLICITUDES POR REVISAR (agrupadas por cliente) ──
  const batchSol = (solicitudes||[]).length > 1
    ? `<button class="btn-apr-batch" onclick="aprobarTodasSolicitudes()">✓ Aprobar todas</button>` : '';
  html += `<div class="apr-bloque-title" style="margin-top:28px;display:flex;align-items:center;gap:10px;flex-wrap:wrap">📋 Solicitudes por revisar <span class="apr-count">${(solicitudes||[]).length}</span>${batchSol}</div>`;
  if (!solicitudes?.length) {
    html += `<div class="apr-empty">Sin solicitudes pendientes de revisión</div>`;
  } else {
    const solPorCliente = {};
    (solicitudes || []).forEach(p => {
      const key = p.cliente_id || p.cliente_email;
      if (!solPorCliente[key]) solPorCliente[key] = { nombre: p.cliente_nombre, email: p.cliente_email, items: [] };
      solPorCliente[key].items.push(p);
    });
    html += Object.entries(solPorCliente).map(([key, grupo]) => {
      const n = grupo.items.length;
      const header = `
        <div style="flex:1;min-width:0">
          <div class="apr-empresa-name">👤 ${esc(grupo.nombre)}</div>
          <div class="apr-empresa-counts">
            <span class="apr-ec">📋 ${n} solicitud${n > 1 ? 'es' : ''}</span>
            <span class="apr-ec-total">En revisión</span>
          </div>
        </div>`;
      const body = grupo.items.map(p => {
        const chips = _buildChipsSol(p);
        return `
          <div class="apr-card" id="aprsol-${p.id}" style="margin:8px 0;border-radius:8px">
            <div class="apr-empresa-subtitulo">${TIPO_EMOJI[p.tipo_camion] || '🚛'} ${esc(p.tipo_camion)}${p.fecha_ini ? ` · 📅 ${fmtFecha(p.fecha_ini)}` : ''}${p.precio_cliente ? ` · 💰 $${Number(p.precio_cliente).toLocaleString('es-MX')}` : ''}</div>
            ${p.origen || p.destino ? `<div class="apr-ruta">📍 ${esc(p.origen||'—')}${p.destino ? ' → '+esc(p.destino) : ''}</div>` : ''}
            ${chips}
            ${p.descripcion ? `<div class="apr-desc">"${esc(p.descripcion)}"</div>` : ''}
            <div class="apr-actions">
              <button class="btn-apr-aprobar" onclick="aprobarSolicitud('${p.id}')">✓ Aprobar y publicar</button>
              <button class="btn-apr-rechazar" onclick="rechazarSolicitud('${p.id}')">✕ Rechazar</button>
            </div>
          </div>`;
      }).join('');
      return _colapseCard(`solg-${key}`, header, body);
    }).join('');
  }

  P.solicitudes = html; html = '';

  // ── ACUERDOS POR APROBAR (agrupados por cliente) ─────
  const batchAcu = (acuerdos||[]).length > 1
    ? `<button class="btn-apr-batch" onclick="aprobarTodosAcuerdos()">✓ Aprobar todos</button>` : '';
  html += `<div class="apr-bloque-title" style="margin-top:28px;display:flex;align-items:center;gap:10px;flex-wrap:wrap">🤝 Acuerdos por aprobar <span class="apr-count">${(acuerdos||[]).length}</span>${batchAcu}</div>`;
  if (!acuerdos?.length) {
    html += `<div class="apr-empty">Sin acuerdos pendientes de aprobación</div>`;
  } else {
    const acuPorCliente = {};
    (acuerdos || []).forEach(p => {
      const key = p.cliente_id || p.cliente_email;
      if (!acuPorCliente[key]) acuPorCliente[key] = { nombre: p.cliente_nombre, email: p.cliente_email, items: [] };
      acuPorCliente[key].items.push(p);
    });
    html += Object.entries(acuPorCliente).map(([key, grupo]) => {
      const n = grupo.items.length;
      const header = `
        <div style="flex:1;min-width:0">
          <div class="apr-empresa-name">👤 ${esc(grupo.nombre)}</div>
          <div class="apr-empresa-counts">
            <span class="apr-ec">🤝 ${n} acuerdo${n > 1 ? 's' : ''}</span>
            <span class="apr-ec-total">En revisión</span>
          </div>
        </div>`;
      const body = grupo.items.map(p => {
        const oferta = p.oferta_pendiente_id ? ofertasMap[p.oferta_pendiente_id] : null;
        const chips  = _buildChipsSol(p);
        return `
          <div class="apr-card" id="apracu-${p.id}" style="margin:8px 0;border-radius:8px">
            <div class="apr-empresa-subtitulo">${TIPO_EMOJI[p.tipo_camion] || '🚛'} ${esc(p.tipo_camion)}${oferta ? ` · 🏢 ${esc(oferta.admin_nombre||'—')}` : ''}${p.fecha_ini ? ` · 📅 ${fmtFecha(p.fecha_ini)}` : ''}${oferta ? ` · 💰 $${Number(oferta.precio_oferta).toLocaleString('es-MX')}` : ''}</div>
            ${p.origen || p.destino ? `<div class="apr-ruta">📍 ${esc(p.origen||'—')}${p.destino ? ' → '+esc(p.destino) : ''}</div>` : ''}
            ${chips}
            ${p.descripcion ? `<div class="apr-desc">"${esc(p.descripcion)}"</div>` : ''}
            ${oferta ? (() => {
                const docsVen = empresaComplianceMap[oferta.admin_id] || [];
                return `
              <div class="apr-oferta-box">
                <div class="apr-oferta-title">Oferta del proveedor</div>
                <div class="apr-oferta-row"><span>Empresa:</span><strong>${esc(oferta.admin_nombre||'—')}${docsVen.length ? ` <span style="color:var(--danger);font-size:0.8rem">⛔ Docs vencidos: ${docsVen.join(', ')}</span>` : ' <span style="color:var(--success,#22c55e);font-size:0.8rem">✅</span>'}</strong></div>
                ${oferta.camion_id ? `<div class="apr-oferta-row"><span>Unidad:</span><strong>${esc(oferta.camion_id)}</strong></div>` : ''}
                ${oferta.operador_nombre ? `<div class="apr-oferta-row"><span>Chofer:</span><strong>${esc(oferta.operador_nombre)}</strong></div>` : ''}
                <div class="apr-oferta-row"><span>Precio acordado:</span><strong class="apr-precio-acuerdo">$${Number(oferta.precio_oferta).toLocaleString('es-MX')} MXN</strong></div>
                ${oferta.mensaje ? `<div class="apr-oferta-row"><span>Nota proveedor:</span>"${esc(oferta.mensaje)}"</div>` : ''}
                ${p.detalles_lugar ? `<div class="apr-oferta-row"><span>Dirección:</span>${esc(p.detalles_lugar)}</div>` : ''}
                ${p.detalles_hora  ? `<div class="apr-oferta-row"><span>Hora:</span>${esc(p.detalles_hora)}</div>` : ''}
                ${p.precio_cliente ? `<div class="apr-oferta-row"><span>Presupuesto original:</span>$${Number(p.precio_cliente).toLocaleString('es-MX')} MXN</div>` : ''}
              </div>`;
              })() : '<div class="apr-empty" style="margin:8px 0">⚠️ No se encontró la oferta asociada</div>'}
            <div class="apr-actions">
              <button class="btn-apr-aprobar" onclick="aprobarAcuerdo('${p.id}')">✓ Aprobar acuerdo</button>
              <button class="btn-apr-rechazar" onclick="rechazarAcuerdo('${p.id}')">✕ Rechazar</button>
            </div>
          </div>`;
      }).join('');
      return _colapseCard(`acug-${key}`, header, body);
    }).join('');
  }

  P.acuerdos = html; html = '';

  // ── FINALIZACIONES DE SERVICIO POR APROBAR ───────────
  html += `<div class="apr-bloque-title" style="margin-top:28px">🏁 Finalizaciones por aprobar <span class="apr-count">${(finalizaciones||[]).length}</span></div>`;
  if (!finalizaciones?.length) {
    html += `<div class="apr-empty">Sin finalizaciones pendientes de aprobación</div>`;
  } else {
    const _verEvFin = async (paths) => {
      if (!paths?.length) return '<span style="font-size:0.78rem;color:var(--text-muted)">Sin evidencia</span>';
      const enlaces = await Promise.all(paths.map(async (e) => {
        if (String(e).startsWith('http')) return e;
        const { data } = await sb.storage.from('unidades').createSignedUrl(e, 3600);
        return data?.signedUrl || null;
      }));
      return enlaces.map((url, i) => url
        ? `<a href="${esc(url)}" target="_blank" class="btn-edit" style="font-size:0.75rem;margin:2px 4px 2px 0;display:inline-block">📎 Foto ${i + 1}</a>`
        : `<span style="font-size:0.75rem;color:var(--text-muted)">Foto ${i + 1} (no disponible)</span>`
      ).join('');
    };
    const bodies = await Promise.all(finalizaciones.map(async r => {
      const evEmpresaHtml = await _verEvFin(r.evidencias);
      const evClienteHtml = await _verEvFin(r.evidencias_cliente);
      const faltaEmpresa = !(r.evidencias?.length);
      const faltaCliente = !(r.evidencias_cliente?.length);
      return `
        <div class="apr-card" id="aprfin-${r.id}">
          <div class="apr-card-header">
            <div>
              <div class="apr-tipo">🏁 ${esc(r.cliente || 'Cliente')} ↔ ${esc(finEmpresaMap[r.propietario_id] || '—')}</div>
              <div class="apr-sub">Unidad: <strong>${esc(r.unidad || '—')}</strong> · ${fmtFecha(r.fecha_ini)} → ${fmtFecha(r.fecha_fin)}</div>
            </div>
            <span class="badge badge-acuerdo-rev">En revisión</span>
          </div>
          <div class="apr-op-detalle">
            <div class="apr-op-grid">
              <div class="apr-op-row"><span>Precio acordado</span><strong>${r.precio_acordado ? '$' + Number(r.precio_acordado).toLocaleString('es-MX') + ' MXN' : '—'}</strong></div>
              <div class="apr-op-row"><span>Pago</span><strong style="color:${r.pagado ? 'var(--green,#22c55e)' : 'var(--amber)'}">${r.pagado ? '💰 Marcado como pagado' : '⚠️ No marcado como pagado'}</strong></div>
              <div class="apr-op-row"><span>Solicitó el cierre</span><strong>${r.finalizacion_solicitada_por === 'cliente' ? 'Cliente' : 'Empresa'}</strong></div>
              <div class="apr-op-row"><span>Seguimiento</span><strong>${esc(r.tracking_estado || '—')}</strong></div>
            </div>
            <div class="apr-op-section-title">Evidencia de la empresa ${faltaEmpresa ? '<span style="color:var(--amber)">⚠️ falta</span>' : ''}</div>
            <div style="margin:4px 0 10px">${evEmpresaHtml}</div>
            <div class="apr-op-section-title">Evidencia del cliente ${faltaCliente ? '<span style="color:var(--amber)">⚠️ falta</span>' : ''}</div>
            <div style="margin:4px 0">${evClienteHtml}</div>
          </div>
          <div class="apr-actions">
            <button class="btn-apr-aprobar" onclick="aprobarFinalizacion('${r.id}')">✓ Aprobar finalización</button>
            <button class="btn-apr-rechazar" onclick="rechazarFinalizacion('${r.id}')">✕ Rechazar</button>
          </div>
        </div>`;
    }));
    // Agrupadas por empresa: el superadmin normalmente resuelve "los pendientes
    // de tal transportista", y es quien opera el servicio.
    const finPorEmpresa = {};
    finalizaciones.forEach((r, i) => {
      const key = r.propietario_id || 'sin-empresa';
      if (!finPorEmpresa[key]) finPorEmpresa[key] = { nombre: finEmpresaMap[r.propietario_id] || 'Empresa sin nombre', items: [] };
      finPorEmpresa[key].items.push(bodies[i]);
    });
    html += Object.entries(finPorEmpresa).map(([key, g]) => {
      const n = g.items.length;
      const header = `
        <div style="flex:1;min-width:0">
          <div class="apr-empresa-name">🏢 ${esc(g.nombre)}</div>
          <div class="apr-empresa-counts">
            <span class="apr-ec">🏁 ${n} finalizaci${n > 1 ? 'ones' : 'ón'}</span>
            <span class="apr-ec-total">Por aprobar</span>
          </div>
        </div>`;
      return _colapseCard(`fing-${key}`, header, g.items.join(''));
    }).join('');
  }

  // ── CANCELACIONES SOLICITADAS POR EL CLIENTE ─────────
  // Se muestra bien visible el punto del viaje en que se pidió: cancelar antes
  // de salir y cancelar con la carga en tránsito no son lo mismo.
  html += `<div class="apr-bloque-title" style="margin-top:28px">🚫 Cancelaciones por revisar <span class="apr-count">${(cancelaciones||[]).length}</span></div>`;
  if (!cancelaciones?.length) {
    html += `<div class="apr-empty">Sin solicitudes de cancelación</div>`;
  } else {
    const _tarjetaCancel = r => {
      const punto = r.cancelacion_tracking_estado || r.tracking_estado || 'Confirmado';
      const arranco = punto !== 'Confirmado';
      return `
        <div class="apr-card" id="aprcancel-${r.id}" style="${arranco ? 'border-color:rgba(239,68,68,0.45)' : ''}">
          <div class="apr-card-header">
            <div>
              <div class="apr-tipo">🚫 ${esc(r.cliente || 'Cliente')} ↔ ${esc(finEmpresaMap[r.propietario_id] || '—')}</div>
              <div class="apr-sub">Unidad: <strong>${esc(r.unidad || '—')}</strong> · ${fmtFecha(r.fecha_ini)} → ${fmtFecha(r.fecha_fin)}</div>
            </div>
            <span class="badge ${arranco ? 'badge-maint' : 'badge-revision'}">${arranco ? '⚠ Servicio iniciado' : 'Sin iniciar'}</span>
          </div>
          <div class="apr-op-detalle">
            <div class="apr-op-grid">
              <div class="apr-op-row"><span>Punto del viaje</span><strong style="color:${arranco ? 'var(--danger)' : 'var(--text-main)'}">${esc(punto)}</strong></div>
              <div class="apr-op-row"><span>Motivo</span><strong>${esc(r.cancelacion_motivo || '—')}</strong></div>
              <div class="apr-op-row"><span>Solicitada</span><strong>${r.cancelacion_solicitada_en ? fmtFecha(r.cancelacion_solicitada_en) : '—'}</strong></div>
              <div class="apr-op-row"><span>Precio acordado</span><strong>${r.precio_acordado ? '$' + Number(r.precio_acordado).toLocaleString('es-MX') + ' MXN' : '—'}</strong></div>
            </div>
            ${r.cancelacion_detalle
              ? `<div class="apr-op-section-title">Detalle del cliente</div>
                 <div style="margin:4px 0;font-size:0.85rem;font-style:italic;color:var(--text-muted)">"${esc(r.cancelacion_detalle)}"</div>`
              : ''}
            ${arranco
              ? `<div class="apr-rechazo-nota" style="margin-top:10px">El servicio ya había iniciado. Considera hablar con la empresa antes de aprobar: puede haber costos incurridos.</div>`
              : ''}
          </div>
          <div class="apr-actions">
            <button class="btn-apr-aprobar" onclick="aprobarCancelacionCliente('${r.id}')">✓ Aprobar cancelación</button>
            <button class="btn-apr-rechazar" onclick="rechazarCancelacionCliente('${r.id}')">✕ Rechazar</button>
          </div>
        </div>`;
    };
    // Agrupadas por empresa, igual que las finalizaciones: quedan juntas las
    // dos decisiones sobre servicios del mismo transportista.
    const cancelPorEmpresa = {};
    cancelaciones.forEach(r => {
      const key = r.propietario_id || 'sin-empresa';
      if (!cancelPorEmpresa[key]) cancelPorEmpresa[key] = { nombre: finEmpresaMap[r.propietario_id] || 'Empresa sin nombre', items: [], iniciados: 0 };
      cancelPorEmpresa[key].items.push(_tarjetaCancel(r));
      const punto = r.cancelacion_tracking_estado || r.tracking_estado || 'Confirmado';
      if (punto !== 'Confirmado') cancelPorEmpresa[key].iniciados++;
    });
    html += Object.entries(cancelPorEmpresa).map(([key, g]) => {
      const n = g.items.length;
      const header = `
        <div style="flex:1;min-width:0">
          <div class="apr-empresa-name">🏢 ${esc(g.nombre)}</div>
          <div class="apr-empresa-counts">
            <span class="apr-ec">🚫 ${n} cancelaci${n > 1 ? 'ones' : 'ón'}</span>
            ${g.iniciados
              ? `<span class="apr-ec" style="color:var(--danger)">⚠ ${g.iniciados} con servicio iniciado</span>`
              : '<span class="apr-ec-total">Sin iniciar</span>'}
          </div>
        </div>`;
      return _colapseCard(`cancelg-${key}`, header, g.items.join(''));
    }).join('');
  }

  P.servicios = html; html = '';

  // ── RECURSOS POR EMPRESA ─────────────────────────────
  html += `<div class="apr-bloque-title" style="margin-top:28px">📦 Recursos por aprobar <span class="apr-count">${totalRecursos}</span></div>`;
  if (totalRecursos === 0) {
    html += `<div class="apr-empty">Sin recursos pendientes de aprobación</div>`;
  } else {
    html += `<div class="apr-emp-filter"><input type="text" id="apr-emp-filter" placeholder="🔍 Filtrar por empresa…" oninput="filtrarEmpresasApr()"></div>`;
    for (const [empId, emp] of Object.entries(empresasMap)) {
      const total = emp.camiones.length + emp.operadores.length + emp.custodios.length + emp.patios.length + emp.lavados.length;
      const counts = [
        emp.camiones.length   ? `🚛 ${emp.camiones.length} unidad${emp.camiones.length>1?'es':''}` : '',
        emp.operadores.length ? `👷 ${emp.operadores.length} operador${emp.operadores.length>1?'es':''}` : '',
        emp.custodios.length  ? `👮 ${emp.custodios.length} custodio${emp.custodios.length>1?'s':''}` : '',
        emp.patios.length     ? `🏭 ${emp.patios.length} patio${emp.patios.length>1?'s':''}` : '',
        emp.lavados.length    ? `🚿 ${emp.lavados.length} lavado${emp.lavados.length>1?'s':''}` : '',
      ].filter(Boolean);

      html += `
        <div class="apr-empresa-card" data-empresa="${esc(emp.nombre.toLowerCase())}">
          <div class="apr-empresa-header" onclick="toggleEmpresaApr('${empId}')">
            <div class="apr-empresa-name">🏢 ${esc(emp.nombre)}</div>
            <div class="apr-empresa-counts">
              ${counts.map(c => `<span class="apr-ec">${c}</span>`).join('')}
              <span class="apr-ec-total">${total} pendiente${total>1?'s':''}</span>
            </div>
            <span class="apr-emp-toggle" id="apr-tog-${empId}">▼</span>
          </div>
          <div class="apr-empresa-items" id="apr-emp-${empId}" style="display:none">
            ${_renderEmpresaItems(emp)}
          </div>
        </div>`;
    }
  }

  // ── PLACEHOLDER: mantiene operadores en bloque empresa ─
  html += `<!-- fin recursos por empresa -->`;

  // ── OPERADORES POR APROBAR (legacy placeholder — eliminado) ───────────────────────────
  // Las secciones sueltas por tipo de recurso (operadores, camiones,
  // custodios, patios, lavados) se reemplazaron por la agrupación por
  // empresa de arriba. Vivían aquí dentro de un `if (false)`.

  P.recursos = html;

  content.innerHTML = _aprTabsHTML(P, {
    cuentas:     (docsEmpresa?.length || 0) + (cuentasPend?.length || 0),
    solicitudes: (solicitudes || []).length,
    acuerdos:    (acuerdos || []).length,
    servicios:   (finalizaciones || []).length + (cancelaciones || []).length,
    recursos:    totalRecursos,
  });
}

// ── PESTAÑAS DEL PANEL ─────────────────────────────────
// Antes era una sola página con 7 secciones apiladas. Se agrupan por tipo de
// decisión: al revisar, normalmente estás en un modo ("validar empresas",
// "despachar acuerdos"), y saltar entre ellos cuesta.
const APR_TABS = [
  { id: 'cuentas',     icon: '👤', label: 'Cuentas'     },
  { id: 'solicitudes', icon: '📋', label: 'Solicitudes' },
  { id: 'acuerdos',    icon: '🤝', label: 'Acuerdos'    },
  { id: 'servicios',   icon: '🏁', label: 'Servicios'   },
  { id: 'recursos',    icon: '📦', label: 'Recursos'    },
];

// Se recuerda entre re-renders: al aprobar algo la vista se recarga, y volver
// siempre a la primera pestaña sería perder el lugar.
let _aprTabActiva = null;

function _aprTabsHTML(paneles, conteos) {
  // Si no hay pestaña recordada (o la recordada quedó vacía), abrir la primera
  // que tenga pendientes.
  if (!_aprTabActiva || !conteos[_aprTabActiva]) {
    _aprTabActiva = APR_TABS.find(t => conteos[t.id] > 0)?.id || 'cuentas';
  }

  const tabs = APR_TABS.map(t => {
    const n = conteos[t.id] || 0;
    return `<button class="apr-tab ${t.id === _aprTabActiva ? 'active' : ''}"
              onclick="cambiarAprTab('${t.id}')">
              ${t.icon} ${t.label}
              <span class="apr-tab-count ${n ? '' : 'cero'}">${n}</span>
            </button>`;
  }).join('');

  const panels = APR_TABS.map(t => `
    <div class="apr-panel ${t.id === _aprTabActiva ? 'active' : ''}" id="apr-panel-${t.id}">
      ${paneles[t.id] || `<div class="apr-empty">Sin pendientes en esta sección</div>`}
    </div>`).join('');

  return `<div class="apr-tabs">${tabs}</div>${panels}`;
}

function cambiarAprTab(id) {
  _aprTabActiva = id;
  document.querySelectorAll('.apr-tab').forEach(t =>
    t.classList.toggle('active', t.getAttribute('onclick')?.includes(`'${id}'`)));
  document.querySelectorAll('.apr-panel').forEach(p =>
    p.classList.toggle('active', p.id === `apr-panel-${id}`));
}

function toggleEmpresaApr(empId) {
  const el  = document.getElementById('apr-emp-' + empId);
  const tog = document.getElementById('apr-tog-' + empId);
  if (!el) return;
  const open = el.style.display !== 'none';
  el.style.display  = open ? 'none' : '';
  if (tog) tog.textContent = open ? '▼' : '▲';
}

function filtrarEmpresasApr() {
  const q = (document.getElementById('apr-emp-filter')?.value || '').toLowerCase();
  document.querySelectorAll('.apr-empresa-card').forEach(card => {
    card.style.display = !q || (card.dataset.empresa || '').includes(q) ? '' : 'none';
  });
}

function _renderEmpresaItems(emp) {
  let html = '';
  const secciones = [
    { key:'camiones',   icon:'🚛', titulo:'Unidades',   render: c => _renderCamionCard(c) },
    { key:'operadores', icon:'👷', titulo:'Operadores',  render: o => _renderOperadorCard(o) },
    { key:'custodios',  icon:'👮', titulo:'Custodios',   render: c => _renderCustodioCard(c) },
    { key:'patios',     icon:'🏭', titulo:'Patios',      render: p => _renderPatioCard(p) },
    { key:'lavados',    icon:'🚿', titulo:'Lavados',     render: l => _renderLavadoCard(l) },
  ];
  for (const s of secciones) {
    if (!emp[s.key]?.length) continue;
    html += `<div class="apr-empresa-subtitulo">${s.icon} ${s.titulo} (${emp[s.key].length})</div>`;
    html += emp[s.key].map(s.render).join('');
  }
  return html;
}

function _renderCamionCard(c) {
  const hoy = new Date().toISOString().slice(0, 10);
  const _vence = (fecha, label) => {
    if (!fecha) return `<div class="apr-op-row"><span>${label}</span><strong style="color:var(--text-muted)">— Sin fecha</strong></div>`;
    const vencido = fecha < hoy;
    const color   = vencido ? 'var(--danger)' : 'inherit';
    return `<div class="apr-op-row"><span>${label}</span><strong style="color:${color}">${fmtFecha(fecha)}${vencido ? ' ⛔' : ''}</strong></div>`;
  };
  const campos = `
    <div class="apr-op-detalle">
      <div class="apr-op-section-title">Vehículo</div>
      <div class="apr-op-grid">
        <div class="apr-op-row"><span>Tipo</span><strong>${esc(c.tipo || '—')}</strong></div>
        <div class="apr-op-row"><span>Marca</span><strong>${esc(c.marca || '—')}</strong></div>
        <div class="apr-op-row"><span>Año</span><strong>${c.modelo_anio || '—'}</strong></div>
        <div class="apr-op-row"><span>Color</span><strong>${esc(c.color || '—')}</strong></div>
        <div class="apr-op-row"><span>Capacidad</span><strong>${c.capacidad ? c.capacidad + ' ton' : '—'}</strong></div>
        <div class="apr-op-row"><span>Combustible</span><strong>${esc(c.tipo_combustible || '—')}</strong></div>
      </div>
      <div class="apr-op-section-title">Identificación</div>
      <div class="apr-op-grid">
        <div class="apr-op-row"><span>Placas</span><strong>${esc(c.placas || '—')}</strong></div>
        <div class="apr-op-row"><span>Núm. serie (NIV)</span><strong>${esc(c.num_serie || '—')}</strong></div>
        <div class="apr-op-row"><span>Núm. motor</span><strong>${esc(c.num_motor || '—')}</strong></div>
        <div class="apr-op-row"><span>Núm. económico</span><strong>${esc(c.num_economico || '—')}</strong></div>
      </div>
      <div class="apr-op-section-title">Vigencias de documentos</div>
      <div class="apr-op-grid">
        ${_vence(c.fecha_vencimiento_tc,           'Tarjeta de circulación')}
        ${_vence(c.fecha_vencimiento_seguro,        'Seguro')}
        ${_vence(c.fecha_vencimiento_permiso_sct,   'Permiso SCT')}
        ${_vence(c.vigencia_caat,                   'CAAT')}
        ${_vence(c.fecha_vencimiento_verificacion,  'Verificación vehicular')}
      </div>
      <div style="margin-top:6px;display:flex;flex-wrap:wrap;gap:4px">
        ${c.imagen_tc  ? `<a href="#" onclick="verArchivoPublico('${escJs(c.imagen_tc)}')"  class="btn-edit" style="font-size:0.75rem">🪪 TC</a>` : ''}
        ${c.doc_sct    ? `<a href="#" onclick="verArchivoPublico('${escJs(c.doc_sct)}')"    class="btn-edit" style="font-size:0.75rem">📄 SCT</a>` : ''}
        ${c.doc_seguro ? `<a href="#" onclick="verArchivoPublico('${escJs(c.doc_seguro)}')" class="btn-edit" style="font-size:0.75rem">📄 Seguro</a>` : ''}
        ${c.doc_caat   ? `<a href="#" onclick="verArchivoPublico('${escJs(c.doc_caat)}')"   class="btn-edit" style="font-size:0.75rem">📄 CAAT</a>` : ''}
        ${c.doc_verificacion ? `<a href="#" onclick="verArchivoPublico('${escJs(c.doc_verificacion)}')" class="btn-edit" style="font-size:0.75rem">📄 Verificación</a>` : ''}
        ${(c.archivos||[]).length ? `<button class="btn-edit" style="font-size:0.75rem" onclick="verArchivos('${c.id}')">📎 Todos los archivos</button>` : ''}
      </div>
      <div class="apr-op-section-title" style="margin-top:10px">Núm. CAAT</div>
      <div class="apr-op-grid">
        <div class="apr-op-row"><span>Número CAAT</span><strong>${esc(c.caat || '—')}</strong></div>
        <div class="apr-op-row"><span>TC expedición</span><strong>${c.fecha_expedicion_tc ? fmtFecha(c.fecha_expedicion_tc) : '—'}</strong></div>
      </div>
    </div>`;
  const diffHtml = _diffHtml(c, {
    tipo:'Tipo', marca:'Marca', version:'Versión', modelo_anio:'Año',
    color:'Color', capacidad:'Capacidad (ton)', dimensiones:'Dimensiones',
    tipo_combustible:'Combustible', placas:'Placas', tipo_placa:'Tipo placa',
    num_serie:'Núm. serie', num_motor:'Núm. motor', num_economico:'Núm. económico',
    tarjeta_circulacion:'Núm. TC', fecha_expedicion_tc:'Fecha TC',
    caat:'CAAT', vigencia_caat:'Vigencia CAAT', precio_dia:'Precio/día',
    fecha_vencimiento_tc:'Vence TC', fecha_vencimiento_seguro:'Vence Seguro',
    fecha_vencimiento_permiso_sct:'Vence SCT', fecha_vencimiento_verificacion:'Vence Verificación',
  });
  return `
    <div class="apr-card" id="aprcam-${c.id}">
      <div class="apr-card-header">
        <div>
          <div class="apr-tipo">${c.emoji || '🚛'} ${c.id} — ${esc(c.tipo)}</div>
          <div class="apr-sub">${c.capacidad || '—'} ton</div>
        </div>
        ${c.es_edicion ? '<span class="apr-edicion-tag">✏️ Edición</span>' : '<span class="badge badge-revision">Pendiente</span>'}
      </div>
      ${diffHtml}${campos}
      <div class="apr-actions">
        <button class="btn-apr-aprobar"  onclick="aprobarCamion('${c.id}')">✓ Aprobar</button>
        <button class="btn-apr-rechazar" onclick="rechazarCamion('${c.id}')">✕ Rechazar con comentarios</button>
      </div>
    </div>`;
}

function _renderOperadorCard(op) {
  const hoy    = new Date().toISOString().slice(0, 10);
  const nombre = [op.nombre, op.primer_apellido, op.segundo_apellido].filter(Boolean).join(' ');
  const foto   = op.foto_operador
    ? `<img src="${esc(op.foto_operador)}" style="width:48px;height:48px;border-radius:50%;object-fit:cover;border:2px solid var(--border)" alt="foto">`
    : `<div style="width:48px;height:48px;border-radius:50%;background:var(--accent);color:#fff;display:flex;align-items:center;justify-content:center;font-size:1.2rem;font-weight:700">${(op.nombre||'?')[0].toUpperCase()}</div>`;

  const _vence = (fecha, label) => {
    if (!fecha) return `<div class="apr-op-row"><span>${label}</span><strong style="color:var(--text-muted)">— Sin fecha</strong></div>`;
    const vencido = fecha < hoy;
    return `<div class="apr-op-row"><span>${label}</span><strong style="color:${vencido ? 'var(--danger)' : 'inherit'}">${fmtFecha(fecha)}${vencido ? ' ⛔' : ''}</strong></div>`;
  };
  const _venceAnual = (fechaExamen, label) => {
    if (!fechaExamen) return `<div class="apr-op-row"><span>${label}</span><strong style="color:var(--text-muted)">— Sin fecha</strong></div>`;
    const d = new Date(fechaExamen + 'T00:00:00');
    d.setFullYear(d.getFullYear() + 1);
    const expStr  = d.toISOString().slice(0, 10);
    const vencido = expStr < hoy;
    return `<div class="apr-op-row"><span>${label}</span><strong style="color:${vencido ? 'var(--danger)' : 'inherit'}">${fmtFecha(fechaExamen)} → vence ${fmtFecha(expStr)}${vencido ? ' ⛔' : ''}</strong></div>`;
  };

  const diffHtml = _diffHtml(op, {
    nombre:'Nombre', primer_apellido:'Primer apellido', segundo_apellido:'Segundo apellido',
    curp:'CURP', nss:'NSS', num_licencia:'Núm. licencia', clase_licencia:'Clase licencia',
    fecha_vencimiento:'Vencimiento licencia', fecha_examen_medico:'Examen médico',
    fecha_examen_toxicologico:'Examen toxicológico', fecha_carta_antecedentes:'Carta antecedentes',
  });
  return `
    <div class="apr-card" id="aprop-${op.id}">
      <div class="apr-card-header">
        <div style="display:flex;align-items:center;gap:12px">
          ${foto}
          <div>
            <div class="apr-tipo">👷 ${esc(nombre)}</div>
            <div class="apr-sub">${esc(op.id)} · Lic: ${esc(op.clase_licencia||'—')}</div>
          </div>
        </div>
        ${op.es_edicion ? '<span class="apr-edicion-tag">✏️ Edición</span>' : '<span class="badge badge-revision">Pendiente</span>'}
      </div>
      ${diffHtml}
      <div class="apr-op-detalle">
        <div class="apr-op-section-title">Identificación</div>
        <div class="apr-op-grid">
          <div class="apr-op-row"><span>CURP</span><strong>${esc(op.curp||'—')}</strong></div>
          <div class="apr-op-row"><span>NSS</span><strong>${esc(op.nss||'—')}</strong></div>
          <div class="apr-op-row"><span>Núm. licencia</span><strong>${esc(op.num_licencia||'—')}</strong></div>
          <div class="apr-op-row"><span>Clase</span><strong>${esc(op.clase_licencia||'—')}</strong></div>
        </div>
        <div class="apr-op-section-title">Vigencias</div>
        <div class="apr-op-grid">
          ${_vence(op.fecha_vencimiento, 'Licencia de conducir')}
          ${_venceAnual(op.fecha_examen_medico, 'Examen médico (1 año)')}
          ${_venceAnual(op.fecha_examen_toxicologico, 'Examen toxicológico (1 año)')}
          ${_venceAnual(op.fecha_carta_antecedentes, 'Carta antecedentes (1 año)')}
        </div>
        <div class="apr-op-section-title" style="margin-top:10px">Documentos</div>
        <div style="display:flex;flex-wrap:wrap;gap:6px;margin-top:4px">
          ${op.foto_operador         ? `<a href="${esc(op.foto_operador)}"              target="_blank" class="btn-edit" style="font-size:0.75rem">📷 Foto operador</a>`       : '<span style="font-size:0.72rem;color:var(--danger)">⚠ Sin foto operador</span>'}
          ${op.foto_licencia         ? `<a href="${esc(op.foto_licencia)}"              target="_blank" class="btn-edit" style="font-size:0.75rem">🪪 Licencia</a>`            : '<span style="font-size:0.72rem;color:var(--danger)">⚠ Sin foto licencia</span>'}
          ${op.doc_examen_medico     ? `<a href="${esc(op.doc_examen_medico)}"          target="_blank" class="btn-edit" style="font-size:0.75rem">📄 Examen médico</a>`       : '<span style="font-size:0.72rem;color:var(--danger)">⚠ Sin examen médico</span>'}
          ${op.doc_examen_toxicologico ? `<a href="${esc(op.doc_examen_toxicologico)}"  target="_blank" class="btn-edit" style="font-size:0.75rem">🧪 Examen toxicológico</a>` : '<span style="font-size:0.72rem;color:var(--danger)">⚠ Sin examen tox.</span>'}
          ${op.doc_carta_antecedentes  ? `<a href="${esc(op.doc_carta_antecedentes)}"   target="_blank" class="btn-edit" style="font-size:0.75rem">📋 No antecedentes</a>`     : '<span style="font-size:0.72rem;color:var(--danger)">⚠ Sin carta antecedentes</span>'}
        </div>
      </div>
      <div class="apr-actions">
        <button class="btn-apr-aprobar"  onclick="aprobarOperador('${op.id}')">✓ Aprobar</button>
        <button class="btn-apr-rechazar" onclick="rechazarOperador('${op.id}')">✕ Rechazar con comentarios</button>
      </div>
    </div>`;
}

function _renderCustodioCard(c) {
  const hoy = new Date().toISOString().slice(0, 10);
  const _vence = (fecha, label) => {
    if (!fecha) return `<div class="apr-op-row"><span>${label}</span><strong style="color:var(--text-muted)">— Sin fecha</strong></div>`;
    const vencido = fecha < hoy;
    return `<div class="apr-op-row"><span>${label}</span><strong style="color:${vencido ? 'var(--danger)' : 'inherit'}">${fmtFecha(fecha)}${vencido ? ' ⛔' : ''}</strong></div>`;
  };
  const diffHtml = _diffHtml(c, {
    nombre:'Nombre', tipo:'Tipo', descripcion:'Descripción',
    disponibilidad:'Disponibilidad', precio_dia:'Precio/día', certificaciones:'Certificaciones',
    porta_arma:'Porta arma', num_licencia_sedena:'Núm. lic. SEDENA',
    fecha_vencimiento_cert:'Vence certificación', fecha_vencimiento_licencia_sedena:'Vence lic. SEDENA',
  });
  return `
    <div class="apr-card" id="aprec-${c.id}">
      <div class="apr-card-header">
        <div>
          <div class="apr-tipo">👮 ${c.id} — ${esc(c.nombre)}</div>
          <div class="apr-sub">${esc(c.tipo||'—')} · ${c.precio_dia ? '$'+Number(c.precio_dia).toLocaleString('es-MX')+'/día' : '—'}</div>
        </div>
        ${c.es_edicion ? '<span class="apr-edicion-tag">✏️ Edición</span>' : '<span class="badge badge-revision">Pendiente</span>'}
      </div>
      ${diffHtml}
      <div class="apr-op-detalle">
        <div class="apr-op-section-title">Vigencias</div>
        <div class="apr-op-grid">
          ${_vence(c.fecha_vencimiento_cert, 'Certificación')}
          ${c.porta_arma ? _vence(c.fecha_vencimiento_licencia_sedena, 'Licencia SEDENA') : ''}
          ${c.porta_arma && c.num_licencia_sedena ? `<div class="apr-op-row"><span>Núm. lic. SEDENA</span><strong>${esc(c.num_licencia_sedena)}</strong></div>` : ''}
        </div>
        ${c.doc_licencia_sedena ? `<a href="${esc(c.doc_licencia_sedena)}" target="_blank" class="btn-edit" style="font-size:0.75rem;display:inline-block;margin-top:6px">📄 Licencia SEDENA</a>` : ''}
        ${(c.certificaciones||[]).length ? `<div class="apr-op-section-title">Certificaciones</div><div class="pedido-chips">${(c.certificaciones||[]).map(x=>`<span class="cargo-chip">${esc(x)}</span>`).join('')}</div>` : ''}
      </div>
      <div class="apr-actions">
        <button class="btn-apr-aprobar"  onclick="aprobarRecurso('custodios','${c.id}')">✓ Aprobar</button>
        <button class="btn-apr-rechazar" onclick="rechazarRecursoCompleto('custodios','${c.id}')">✕ Rechazar</button>
      </div>
    </div>`;
}

function _renderPatioCard(p) {
  const hoy = new Date().toISOString().slice(0, 10);
  const _vence = (fecha, label) => {
    if (!fecha) return `<div class="apr-op-row"><span>${label}</span><strong style="color:var(--text-muted)">— Sin fecha</strong></div>`;
    const vencido = fecha < hoy;
    return `<div class="apr-op-row"><span>${label}</span><strong style="color:${vencido ? 'var(--danger)' : 'inherit'}">${fmtFecha(fecha)}${vencido ? ' ⛔' : ''}</strong></div>`;
  };
  const diffHtml = _diffHtml(p, {
    nombre:'Nombre', tipo:'Tipo', ubicacion:'Ubicación',
    area_m2:'Área (m²)', capacidad_vehiculos:'Capacidad (veh.)',
    precio_dia:'Precio/día', servicios:'Servicios',
    fecha_vencimiento_permiso:'Vence permiso operativo',
  });
  return `
    <div class="apr-card" id="aprec-${p.id}">
      <div class="apr-card-header">
        <div>
          <div class="apr-tipo">🏭 ${p.id} — ${esc(p.nombre)}</div>
          <div class="apr-sub">${esc(p.tipo||'—')} · ${esc(p.ubicacion||'—')}</div>
        </div>
        ${p.es_edicion ? '<span class="apr-edicion-tag">✏️ Edición</span>' : '<span class="badge badge-revision">Pendiente</span>'}
      </div>
      ${diffHtml}
      <div class="apr-op-detalle">
        <div class="apr-op-grid">
          ${_vence(p.fecha_vencimiento_permiso, 'Permiso operativo')}
        </div>
        ${p.doc_permiso ? (p.doc_permiso.startsWith('http')
          ? `<a href="${esc(p.doc_permiso)}" target="_blank" class="btn-edit" style="font-size:0.75rem;display:inline-block;margin-top:6px">📄 Ver permiso operativo</a>`
          : `<a href="#" onclick="verArchivoPublico('${escJs(p.doc_permiso)}');return false" class="btn-edit" style="font-size:0.75rem;display:inline-block;margin-top:6px">📄 Ver permiso operativo</a>`) : ''}
      </div>
      <div class="apr-actions">
        <button class="btn-apr-aprobar"  onclick="aprobarRecurso('patios','${p.id}')">✓ Aprobar</button>
        <button class="btn-apr-rechazar" onclick="rechazarRecursoCompleto('patios','${p.id}')">✕ Rechazar</button>
      </div>
    </div>`;
}

function _renderLavadoCard(l) {
  const diffHtml = _diffHtml(l, { nombre:'Nombre', ubicacion:'Ubicación', capacidad:'Cap. simultánea', horario:'Horario', precio_lavado:'Precio', tipos_vehiculo:'Tipos vehículo', tipos_lavado:'Tipos lavado' });
  return `
    <div class="apr-card" id="aprec-${l.id}">
      <div class="apr-card-header">
        <div>
          <div class="apr-tipo">🚿 ${l.id} — ${esc(l.nombre)}</div>
          <div class="apr-sub">${esc(l.ubicacion||'—')}</div>
        </div>
        ${l.es_edicion ? '<span class="apr-edicion-tag">✏️ Edición</span>' : '<span class="badge badge-revision">Pendiente</span>'}
      </div>
      ${diffHtml}
      <div class="apr-actions">
        <button class="btn-apr-aprobar"  onclick="aprobarRecurso('lavados','${l.id}')">✓ Aprobar</button>
        <button class="btn-apr-rechazar" onclick="rechazarRecursoCompleto('lavados','${l.id}')">✕ Rechazar</button>
      </div>
    </div>`;
}

function verArchivoPublico(path) {
  sb.storage.from('unidades').createSignedUrl(path, 3600).then(({ data }) => {
    if (data?.signedUrl) window.open(data.signedUrl, '_blank');
  });
}

function verDocRegistro(path) {
  sb.storage.from('registros').createSignedUrl(path, 3600).then(({ data }) => {
    if (data?.signedUrl) window.open(data.signedUrl, '_blank');
  });
}

async function aprobarCuenta(userId, metodo) {
  const esFisica = metodo === 'fisica';
  const { data: sc } = await sb.from('solicitudes_cuenta')
    .select('nombre').eq('user_id', userId).single();

  const [{ error }] = await Promise.all([
    sb.from('perfiles').update({ aprobacion_cuenta: null, metodo_verificacion: metodo, verificado: esFisica }).eq('user_id', userId),
    sb.from('solicitudes_cuenta').update({ estado: 'aprobada' }).eq('user_id', userId),
  ]);
  if (error) { showToast('Error al aprobar', 'error'); return; }

  await _notificarResolucion(userId, {
    tipo:    'cuenta_aprobada',
    titulo:  '¡Cuenta aprobada!',
    mensaje: esFisica
      ? 'Tu cuenta ha sido verificada con validación física. Ya puedes iniciar sesión en PortGo.'
      : 'Tu cuenta ha sido verificada mediante revisión documental. Ya puedes iniciar sesión en PortGo.',
  });

  document.getElementById(`aprcuenta-${userId}`)?.remove();
  showToast(`✓ Cuenta de ${esc(sc?.nombre || 'usuario')} aprobada (${esFisica ? 'verificación física' : 'sin verificación física'})`);
  _loadAprBadge();
}

function rechazarCuenta(userId) {
  _abrirRechazarNota(
    'Rechazar solicitud de cuenta',
    'Motivo (el usuario lo verá al intentar iniciar sesión):',
    async nota => {
      const notaTrim = nota || null;
      const [{ error }] = await Promise.all([
        sb.from('perfiles').update({ aprobacion_cuenta: 'rechazada', nota_rechazo_cuenta: notaTrim }).eq('user_id', userId),
        sb.from('solicitudes_cuenta').update({ estado: 'rechazada', nota_rechazo: notaTrim }).eq('user_id', userId),
      ]);
      if (error) { showToast('Error al rechazar', 'error'); return; }

      // El correo importa más que la campana aquí: el usuario no puede entrar
      // a la app a leerla, precisamente porque su cuenta está rechazada.
      await _notificarResolucion(userId, {
        tipo:     'cuenta_rechazada',
        titulo:   'Tu solicitud de cuenta no fue aprobada',
        mensaje:  'Revisa el motivo y vuelve a enviar tu solicitud desde PortGo con la información corregida.',
        nota:     notaTrim,
        aprobado: false,
      });

      document.getElementById(`aprcuenta-${userId}`)?.remove();
      showToast('Solicitud rechazada');
      _loadAprBadge();
    }
  );
}

function _diffHtml(recurso, labels) {
  if (!recurso.es_edicion || !recurso.campos_editados?.length || !recurso.snapshot_anterior) return '';
  const dateFields  = new Set([
    'fecha_expedicion_tc','vigencia_caat','fecha_vencimiento','fecha_expedicion',
    'fecha_examen_medico','fecha_examen_toxicologico','fecha_carta_antecedentes',
    'fecha_vencimiento_cert','fecha_vencimiento_licencia_sedena','fecha_vencimiento_permiso',
    'fecha_vencimiento_tc','fecha_vencimiento_seguro','fecha_vencimiento_permiso_sct',
    'fecha_vencimiento_verificacion',
  ]);
  const priceFields = new Set(['precio_dia','precio_lavado']);

  const fmt = (key, val) => {
    if (val === null || val === undefined || val === '') return '—';
    if (dateFields.has(key))  return fmtFecha(val);
    if (priceFields.has(key)) return '$' + Number(val).toLocaleString('es-MX') + ' MXN';
    if (Array.isArray(val))   return val.join(', ') || '—';
    if (typeof val === 'boolean') return val ? 'Sí' : 'No';
    return esc(String(val));
  };

  const rows = recurso.campos_editados
    .filter(k => labels[k])
    .map(k => `
      <div class="apr-diff-row">
        <div class="apr-diff-field">${labels[k]}</div>
        <div class="apr-diff-antes">${fmt(k, recurso.snapshot_anterior[k])}</div>
        <div class="apr-diff-flecha">→</div>
        <div class="apr-diff-nuevo">${fmt(k, recurso[k])}</div>
      </div>`).join('');

  if (!rows) return '';
  return `
    <div class="apr-diff">
      <div class="apr-diff-title">✏️ Campos modificados</div>
      ${rows}
    </div>`;
}

function _buildChipsSol(p) {
  const chips = [];
  if (p.tipo_carga)        chips.push(`📦 ${esc(p.tipo_carga)}`);
  if (p.peso_carga)        chips.push(`⚖️ ${p.peso_carga} ton`);
  if (p.capacidad_min)     chips.push(`🚛 Mín ${p.capacidad_min} ton`);
  if (p.zona_cobertura)    chips.push(`📍 ${esc(p.zona_cobertura)}`);
  if (p.num_custodios)     chips.push(`👮 x${p.num_custodios}`);
  if (p.horario_servicio)  chips.push(`🕐 ${esc(p.horario_servicio)}`);
  if (p.num_vehiculos)     chips.push(`🚗 x${p.num_vehiculos} veh.`);
  if (p.tipo_vehiculos)    chips.push(esc(p.tipo_vehiculos));
  if (p.carga_peligrosa)   chips.push('⚠️ Peligrosa');
  if (p.temp_controlada)   chips.push('❄️ Temp. controlada');
  if (p.requiere_seguro)   chips.push('🛡️ Seguro');
  if (p.requiere_factura)  chips.push('🧾 Factura');
  if (!chips.length) return '';
  return `<div class="pedido-chips" style="margin:8px 0 4px">${chips.map(c => `<span class="cargo-chip">${c}</span>`).join('')}</div>`;
}

// ── APROBAR SOLICITUD ────────────────────────────────────

async function aprobarSolicitud(pedidoId) {
  // Mismo hueco que en aprobarCamion: si RLS no deja escribir, el update no
  // falla, afecta 0 filas, y la solicitud se quedaba en pendiente_revision
  // mientras la pantalla decía que ya estaba publicada.
  if (!await actualizarConfirmado('pedidos', { id: pedidoId },
        { estado: 'abierto', rechazo_nota: null }, 'la solicitud')) return;

  const { data: ped } = await sb.from('pedidos')
    .select('tipo_camion, origen, destino, cliente_id, cliente_nombre, fecha_ini, fecha_fin, fecha_arribo_puerto, tipo_carga, precio_cliente, plazo_pago')
    .eq('id', pedidoId).single();

  // Notificar al cliente que su solicitud fue aprobada
  if (ped?.cliente_id) {
    const ruta = ped.origen ? ` (${ped.origen}${ped.destino ? ' → ' + ped.destino : ''})` : '';
    await _notificarResolucion(ped.cliente_id, {
      tipo:    'solicitud_aprobada',
      titulo:  'Tu solicitud fue aprobada',
      mensaje: `Tu solicitud de ${ped.tipo_camion || 'servicio'}${ruta} fue aprobada y ya está publicada. Pronto recibirás ofertas de proveedores.`,
    });
  }

  // Avisar solo a las empresas que podrían ofertar por este tipo de servicio.
  // Antes iba a todos los admins + superadmins: una empresa que solo tiene
  // plataformas recibía aviso de cada torton, y eso entrena a ignorar la campana.
  const destinatarios = await _adminsConFlotaPara(ped?.tipo_camion);
  const rutaTxt = ped?.origen ? ` ${ped.origen}${ped.destino ? ' → ' + ped.destino : ''}` : '';
  if (destinatarios.length) {
    await sb.from('notificaciones').insert(destinatarios.map(uid => ({
      user_id: uid,
      tipo:    'nueva_solicitud',
      titulo:  'Nueva solicitud para ofertar',
      mensaje: `${ped?.tipo_camion || 'Servicio'}${rutaTxt} — ya está disponible para ofertar.`,
      leido:   false,
    })));
  }

  // Correo a esas mismas empresas. La Edge Function vuelve a resolver los
  // destinatarios del lado del servidor con la misma regla; el cliente nunca
  // manda la lista de correos.
  _notificarEmail({
    tipo:           'nueva_solicitud',
    tipo_camion:    ped?.tipo_camion,
    origen:         ped?.origen,
    destino:        ped?.destino,
    fecha_ini:      ped?.fecha_ini,
    fecha_fin:      ped?.fecha_fin,
    fecha_arribo_puerto: ped?.fecha_arribo_puerto,
    tipo_carga:     ped?.tipo_carga,
    precio_cliente: ped?.precio_cliente,
    plazo_pago:     ped?.plazo_pago,
  });

  document.getElementById(`aprsol-${pedidoId}`)?.remove();
  showToast('✓ Solicitud aprobada y publicada');
  renderAprobaciones();
  if (document.getElementById('view-pedidos')?.classList.contains('active')) renderPedidos();
}

// ── RECHAZAR SOLICITUD ───────────────────────────────────

function rechazarSolicitud(pedidoId) {
  _abrirRechazarNota(
    'Rechazar solicitud',
    'Motivo del rechazo (se enviará al cliente):',
    async nota => {
      const { data: ped } = await sb.from('pedidos').select('cliente_id, tipo_camion').eq('id', pedidoId).single();
      await sb.from('pedidos').update({ estado: 'rechazado', rechazo_nota: nota || null }).eq('id', pedidoId);
      if (ped?.cliente_id) {
        await _notificarResolucion(ped.cliente_id, {
          tipo:     'solicitud_rechazada',
          titulo:   'Tu solicitud no fue aprobada',
          mensaje:  `Tu solicitud de ${ped.tipo_camion || 'servicio'} no fue aprobada. Puedes corregirla y volver a publicarla desde PortGo.`,
          nota:     nota || null,
          aprobado: false,
        });
      }
      showToast('Solicitud rechazada y notificada al cliente');
      renderAprobaciones();
      if (document.getElementById('view-pedidos')?.classList.contains('active')) renderPedidos();
    }
  );
}

// ── APROBAR / RECHAZAR FINALIZACIÓN DE SERVICIO ──────────

async function aprobarFinalizacion(reservaId) {
  const { data: r } = await sb.from('reservaciones')
    .select('unidad, recurso_tipo, cliente_user_id, propietario_id, cliente, pedido_id, plazo_pago')
    .eq('id', reservaId).single();
  if (!r) { showToast('No se encontró la reserva', 'error'); return; }

  // Aquí arranca el reloj del cobro: el servicio quedó cerrado y, según el
  // plazo pactado, se calcula cuándo vence el pago. Las reservaciones viejas
  // no traen el plazo, así que se busca en el pedido como respaldo.
  let plazo = r.plazo_pago;
  if (!plazo && r.pedido_id) {
    const { data: p } = await sb.from('pedidos').select('plazo_pago').eq('id', r.pedido_id).maybeSingle();
    plazo = p?.plazo_pago || null;
  }
  const ahora = new Date().toISOString();

  const { error } = await sb.from('reservaciones').update({
    estado: 'Completada',
    finalizacion_aprobada_por: currentUser.id,
    finalizacion_aprobada_en: ahora,
    plazo_pago: plazo,
    fecha_vencimiento_pago: calcularVencimientoPago(plazo, ahora),
  }).eq('id', reservaId);
  if (error) { showToast('Error al aprobar: ' + error.message, 'error'); return; }

  if (r.pedido_id) {
    await sb.from('pedidos').update({ estado: 'finalizado' }).eq('id', r.pedido_id);
  }
  if (r.unidad) {
    const tabla = r.recurso_tipo === 'custodio' ? 'custodios' : r.recurso_tipo === 'patio' ? 'patios' : 'camiones';
    await sb.from(tabla).update({ estado: 'disponible' }).eq('id', r.unidad);
  }

  await _notificarResolucion(r.cliente_user_id, {
    tipo:    'servicio_completado',
    titulo:  'Servicio completado',
    mensaje: 'Se aprobó la finalización de tu servicio. Ya puedes calificarlo en PortGo.',
  });
  await _notificarResolucion(r.propietario_id, {
    tipo:    'servicio_completado',
    titulo:  'Finalización aprobada',
    mensaje: `El servicio con ${r.cliente || 'el cliente'} fue aprobado como completado.`,
  });

  document.getElementById(`aprfin-${reservaId}`)?.remove();
  showToast('✓ Finalización aprobada');
  renderAprobaciones();
}

function rechazarFinalizacion(reservaId) {
  _abrirRechazarNota(
    'Rechazar finalización',
    'Motivo (se notificará a cliente y empresa; la reserva vuelve a Activa):',
    nota => _ejecutarRechazarFinalizacion(reservaId, nota)
  );
}

async function _ejecutarRechazarFinalizacion(reservaId, nota) {
  const { data: r } = await sb.from('reservaciones')
    .select('cliente_user_id, propietario_id, cliente').eq('id', reservaId).single();

  const { error } = await sb.from('reservaciones').update({
    estado: 'Activa',
    finalizacion_nota: nota || null,
  }).eq('id', reservaId);
  if (error) { showToast('Error al rechazar: ' + error.message, 'error'); return; }

  const notifs = [];
  if (r?.cliente_user_id) notifs.push({
    user_id: r.cliente_user_id, tipo: 'finalizacion_rechazada', titulo: 'Finalización no aprobada',
    mensaje: `El superadmin no aprobó el cierre del servicio.${nota ? ' Motivo: ' + nota : ''} El servicio sigue activo.`, leido: false,
  });
  if (r?.propietario_id) notifs.push({
    user_id: r.propietario_id, tipo: 'finalizacion_rechazada', titulo: 'Finalización no aprobada',
    mensaje: `El superadmin no aprobó el cierre del servicio con ${esc(r?.cliente || 'el cliente')}.${nota ? ' Motivo: ' + nota : ''} El servicio sigue activo.`, leido: false,
  });
  if (notifs.length) await sb.from('notificaciones').insert(notifs);

  document.getElementById(`aprfin-${reservaId}`)?.remove();
  showToast('Finalización rechazada, la reserva vuelve a Activa');
  renderAprobaciones();
}

// ── RESOLVER CANCELACIÓN SOLICITADA POR EL CLIENTE ───────
// A diferencia de cuando cancela la empresa, aquí el pedido NO se reabre a
// nuevas ofertas: el cliente ya no quiere el servicio, así que se cierra.

function aprobarCancelacionCliente(reservaId) {
  _abrirRechazarNota(
    'Aprobar cancelación',
    'Nota para las partes (opcional):',
    nota => _ejecutarAprobarCancelacion(reservaId, nota),
    { confirmLabel: '✓ Aprobar cancelación', danger: false }
  );
}

async function _ejecutarAprobarCancelacion(reservaId, nota) {
  const { data: r } = await sb.from('reservaciones')
    .select('unidad, recurso_tipo, cliente_user_id, propietario_id, cliente, pedido_id')
    .eq('id', reservaId).single();
  if (!r) { showToast('No se encontró la reserva', 'error'); return; }

  const { error } = await sb.from('reservaciones').update({
    estado:                      'Cancelada',
    cancelacion_resuelta_en:     new Date().toISOString(),
    cancelacion_resuelta_por:    currentUser.id,
    cancelacion_nota_resolucion: nota || null,
  }).eq('id', reservaId);
  if (error) { showToast('Error al aprobar: ' + error.message, 'error'); return; }

  // Liberar la unidad comprometida
  if (r.unidad) {
    const tabla = r.recurso_tipo === 'custodio' ? 'custodios'
                : r.recurso_tipo === 'patio'    ? 'patios'
                : r.recurso_tipo === 'lavado'   ? 'lavados' : 'camiones';
    await sb.from(tabla).update({ estado: 'disponible' }).eq('id', r.unidad);
  }

  // El pedido se cierra: fue el cliente quien desistió del servicio.
  if (r.pedido_id) {
    const { error: errPed } = await sb.from('pedidos')
      .update({ estado: 'cancelado', oferta_pendiente_id: null })
      .eq('id', r.pedido_id);
    if (errPed) showToast('La reserva se canceló, pero el pedido no se cerró: ' + errPed.message, 'error');
  }

  const notifs = [];
  if (r.cliente_user_id) notifs.push({
    user_id: r.cliente_user_id, tipo: 'cancelacion_aprobada', titulo: 'Cancelación aprobada',
    mensaje: `Tu solicitud de cancelación fue aprobada.${nota ? ' Nota: ' + nota : ''} La solicitud quedó cerrada.`, leido: false,
  });
  if (r.propietario_id) notifs.push({
    user_id: r.propietario_id, tipo: 'cancelacion_aprobada', titulo: 'Servicio cancelado',
    mensaje: `Se aprobó la cancelación del servicio con ${esc(r.cliente || 'el cliente')}. Tu unidad quedó disponible de nuevo.${nota ? ' Nota: ' + nota : ''}`, leido: false,
  });
  if (notifs.length) await sb.from('notificaciones').insert(notifs);

  document.getElementById(`aprcancel-${reservaId}`)?.remove();
  showToast('Cancelación aprobada — unidad liberada y solicitud cerrada');
  renderAprobaciones();
}

function rechazarCancelacionCliente(reservaId) {
  _abrirRechazarNota(
    'Rechazar cancelación',
    'Motivo (se notificará al cliente; el servicio sigue activo):',
    nota => _ejecutarRechazarCancelacion(reservaId, nota)
  );
}

async function _ejecutarRechazarCancelacion(reservaId, nota) {
  const { data: r } = await sb.from('reservaciones')
    .select('cliente_user_id, propietario_id, cliente').eq('id', reservaId).single();

  const { error } = await sb.from('reservaciones').update({
    estado:                      'Activa',
    cancelacion_resuelta_en:     new Date().toISOString(),
    cancelacion_resuelta_por:    currentUser.id,
    cancelacion_nota_resolucion: nota || null,
  }).eq('id', reservaId);
  if (error) { showToast('Error al rechazar: ' + error.message, 'error'); return; }

  const notifs = [];
  if (r?.cliente_user_id) notifs.push({
    user_id: r.cliente_user_id, tipo: 'cancelacion_rechazada', titulo: 'Cancelación no aprobada',
    mensaje: `Tu solicitud de cancelación no fue aprobada.${nota ? ' Motivo: ' + nota : ''} El servicio sigue activo.`, leido: false,
  });
  if (r?.propietario_id) notifs.push({
    user_id: r.propietario_id, tipo: 'cancelacion_rechazada', titulo: 'El servicio continúa',
    mensaje: `No se aprobó la cancelación solicitada por ${esc(r?.cliente || 'el cliente')}. El servicio sigue activo.`, leido: false,
  });
  if (notifs.length) await sb.from('notificaciones').insert(notifs);

  document.getElementById(`aprcancel-${reservaId}`)?.remove();
  showToast('Cancelación rechazada — el servicio sigue activo');
  renderAprobaciones();
}

// ── APROBAR ACUERDO ──────────────────────────────────────

async function aprobarAcuerdo(pedidoId) {
  const { data: ped } = await sb.from('pedidos').select('*').eq('id', pedidoId).single();
  if (!ped?.oferta_pendiente_id) { showToast('Error: no hay oferta asociada', 'error'); return; }

  const { data: oferta } = await sb.from('ofertas').select('*').eq('id', ped.oferta_pendiente_id).single();
  if (!oferta) { showToast('Error: oferta no encontrada', 'error'); return; }

  // Verificar documentos de empresa del proveedor
  const hoy = new Date().toISOString().slice(0, 10);
  const { data: ep } = await sb.from('perfiles')
    .select('nombre, fecha_vencimiento_permiso_sct, fecha_vencimiento_seguro_rc, fecha_vencimiento_seguro_carga')
    .eq('user_id', oferta.admin_id).single();

  const docsVencidos = [];
  if (ep) {
    if (ep.fecha_vencimiento_permiso_sct  && ep.fecha_vencimiento_permiso_sct  < hoy) docsVencidos.push('Permiso SCT');
    if (ep.fecha_vencimiento_seguro_rc    && ep.fecha_vencimiento_seguro_rc    < hoy) docsVencidos.push('Seguro RC');
    if (ep.fecha_vencimiento_seguro_carga && ep.fecha_vencimiento_seguro_carga < hoy) docsVencidos.push('Seguro de carga');
  }

  const ejecutar = () => _ejecutarAprobarAcuerdo(ped, oferta);

  if (docsVencidos.length) {
    showConfirm(
      `⚠️ La empresa "${esc(ep.nombre || oferta.admin_nombre)}" tiene documentos vencidos: ${docsVencidos.join(', ')}. ¿Aprobar el acuerdo de todas formas?`,
      ejecutar,
      { danger: true, confirmLabel: 'Aprobar igualmente', cancelLabel: 'Cancelar' }
    );
  } else {
    ejecutar();
  }
}

async function _ejecutarAprobarAcuerdo(ped, oferta) {
  // Ejecutar el cierre real (rechaza otras ofertas, crea reservación, marca recurso ocupado)
  try {
    await cerrarAcuerdo(oferta, ped);
  } catch (e) {
    if (e.message === 'RECURSO_NO_DISPONIBLE') {
      showToast('❌ El recurso ya tiene una reserva activa en esas fechas. Rechaza el acuerdo antes de asignar otro recurso.', 'error');
    } else {
      showToast('Error al crear reservación: ' + e.message, 'error');
    }
    return;
  }

  // Notificar a cliente y proveedor
  const notifs = [
    {
      user_id: ped.cliente_id,
      tipo:    'acuerdo_aprobado',
      titulo:  '¡Acuerdo aprobado!',
      mensaje: `Tu acuerdo de ${esc(ped.tipo_camion || 'servicio')} fue aprobado. Ya tienes una reservación activa.`,
      leido:   false,
    },
    {
      user_id: oferta.admin_id,
      tipo:    'acuerdo_aprobado',
      titulo:  '¡Acuerdo aprobado!',
      mensaje: `El acuerdo con ${esc(ped.cliente_nombre || 'el cliente')} para ${esc(ped.tipo_camion || 'servicio')} fue aprobado. Revisa tus reservaciones.`,
      leido:   false,
    },
  ];
  await sb.from('notificaciones').insert(notifs);

  // Correo al cliente y proveedor: acuerdo aprobado
  _notificarEmail({
    tipo:        'acuerdo_aprobado',
    tipo_camion: ped.tipo_camion,
    clienteId:   ped.cliente_id,
    adminId:     oferta.admin_id,
  });

  showToast('✓ Acuerdo aprobado. Reservación creada');
  renderAprobaciones();
  if (document.getElementById('view-pedidos')?.classList.contains('active')) renderPedidos();
}

// ── RECHAZAR ACUERDO ─────────────────────────────────────

// ── APROBAR / RECHAZAR OPERADOR ──────────────────────────

// ── MODAL RECHAZO OPERADOR ───────────────────────────────

function rechazarOperador(id) {
  document.getElementById('ro-operador-id').value = id;
  document.getElementById('ro-nota').value = '';
  document.querySelectorAll('#ro-campos input[type=checkbox]').forEach(c => { c.checked = false; });
  document.getElementById('modal-rechazar-operador').classList.add('open');
}

function cerrarRechazarOperador() {
  document.getElementById('modal-rechazar-operador').classList.remove('open');
}

async function confirmarRechazarOperador() {
  const id     = document.getElementById('ro-operador-id').value;
  const nota   = document.getElementById('ro-nota').value.trim();
  const campos = Array.from(document.querySelectorAll('#ro-campos input[type=checkbox]:checked'))
    .map(c => c.value);

  const { data: op } = await sb.from('operadores').select('propietario_id, nombre').eq('id', id).single();
  const { error } = await sb.from('operadores').update({
    aprobacion:      'rechazada',
    rechazo_nota:    nota   || null,
    rechazo_campos:  campos.length ? campos : null,
  }).eq('id', id);

  if (error) { showToast('Error al rechazar', 'error'); return; }

  if (op?.propietario_id) {
    const camposStr = campos.length ? ` Corregir: ${campos.join(', ')}.` : '';
    await _notificarResolucion(op.propietario_id, {
      tipo:     'recurso_rechazado',
      titulo:   'Operador requiere correcciones',
      mensaje:  `El operador ${op.nombre} (${id}) necesita ajustes.${camposStr} Entra al tab Operadores para corregir y reenviar.`,
      nota:     nota || null,
      aprobado: false,
    });
  }

  cerrarRechazarOperador();
  showToast(`Operador ${id} devuelto con comentarios`);
  renderAprobaciones();
  renderAdminOperadores();
}

async function aprobarOperador(id) {
  const { data: op } = await sb.from('operadores').select('propietario_id, nombre, primer_apellido').eq('id', id).single();
  const ok = await actualizarConfirmado('operadores', { id },
    { aprobacion: 'aprobada', es_edicion: false, campos_editados: null, snapshot_anterior: null },
    `el operador ${id}`);
  if (!ok) return;

  if (op?.propietario_id) {
    const nombre = [op.nombre, op.primer_apellido].filter(Boolean).join(' ');
    await _notificarResolucion(op.propietario_id, {
      tipo:    'recurso_aprobado',
      titulo:  'Operador aprobado',
      mensaje: `Tu operador ${nombre} (${id}) fue aprobado y ya puede asignarse a unidades.`,
    });
  }

  document.getElementById(`aprop-${id}`)?.remove();
  showToast(`✓ Operador ${id} aprobado`);
  renderAprobaciones();
  renderAdminOperadores();
}


function rechazarAcuerdo(pedidoId) {
  _abrirRechazarNota(
    'Rechazar acuerdo',
    'Motivo del rechazo (se notificará a ambas partes):',
    nota => _ejecutarRechazarAcuerdo(pedidoId, nota)
  );
}

async function _ejecutarRechazarAcuerdo(pedidoId, nota) {
  const { data: ped } = await sb.from('pedidos').select('*').eq('id', pedidoId).single();
  const ofertaId = ped?.oferta_pendiente_id;

  // Regresar pedido a negociación
  const { error: errPed } = await sb.from('pedidos').update({
    estado:              'en_negociacion',
    oferta_pendiente_id: null,
    rechazo_nota:        nota || null,
  }).eq('id', pedidoId);
  if (errPed) { showToast('Error al rechazar acuerdo: ' + errPed.message, 'error'); return; }

  // Revertir oferta a enviada para que el cliente la vuelva a ver
  if (ofertaId) {
    const { error: errOf } = await sb.from('ofertas').update({ estado: 'enviada' }).eq('id', ofertaId);
    if (errOf) console.warn('No se pudo revertir estado de oferta:', errOf.message);
  }

  // Notificar a cliente y proveedor
  const notifs = [];
  if (ped?.cliente_id) {
    notifs.push({
      user_id: ped.cliente_id,
      tipo:    'acuerdo_rechazado',
      titulo:  'Acuerdo no aprobado',
      mensaje: `El acuerdo de ${esc(ped.tipo_camion || 'servicio')} no fue aprobado y regresa a negociación.${nota ? ' Motivo: ' + nota : ''}`,
      leido:   false,
    });
  }

  // Get admin_id from oferta
  if (ofertaId) {
    const { data: of2 } = await sb.from('ofertas').select('admin_id, admin_nombre').eq('id', ofertaId).single();
    if (of2?.admin_id) {
      notifs.push({
        user_id: of2.admin_id,
        tipo:    'acuerdo_rechazado',
        titulo:  'Acuerdo no aprobado',
        mensaje: `El acuerdo con ${esc(ped?.cliente_nombre || 'el cliente')} no fue aprobado y regresa a negociación.${nota ? ' Motivo: ' + nota : ''}`,
        leido:   false,
      });
    }
  }
  if (notifs.length) await sb.from('notificaciones').insert(notifs);

  showToast('Acuerdo rechazado. Vuelve a negociación');
  renderAprobaciones();
  if (document.getElementById('view-pedidos')?.classList.contains('active')) renderPedidos();
}

// ── APROBAR / RECHAZAR CAMIÓN ────────────────────────────

async function aprobarCamion(id) {
  const { data: c } = await sb.from('camiones').select('propietario_id, tipo').eq('id', id).single();
  const ok = await actualizarConfirmado('camiones', { id },
    { aprobacion: 'aprobada', es_edicion: false, campos_editados: null, snapshot_anterior: null },
    `la unidad ${id}`);
  if (!ok) return;

  if (c?.propietario_id) {
    await _notificarResolucion(c.propietario_id, {
      tipo:    'recurso_aprobado',
      titulo:  'Unidad aprobada',
      mensaje: `Tu unidad ${id} (${c.tipo || ''}) fue aprobada y ya está visible en el catálogo.`,
    });
  }
  document.getElementById(`aprcam-${id}`)?.remove();
  showToast(`✓ Unidad ${id} aprobada`);
  renderAprobaciones();
  renderAdmin();
}

function rechazarCamion(id) {
  document.getElementById('rc-camion-id').value = id;
  document.getElementById('rc-nota').value = '';
  document.querySelectorAll('#rc-campos input[type=checkbox]').forEach(c => { c.checked = false; });
  document.getElementById('modal-rechazar-camion').classList.add('open');
}

function cerrarRechazarCamion() {
  document.getElementById('modal-rechazar-camion').classList.remove('open');
}

async function confirmarRechazarCamion() {
  const id     = document.getElementById('rc-camion-id').value;
  const nota   = document.getElementById('rc-nota').value.trim();
  const campos = Array.from(document.querySelectorAll('#rc-campos input[type=checkbox]:checked')).map(c => c.value);

  const { data: c } = await sb.from('camiones').select('propietario_id, tipo').eq('id', id).single();
  const { error }   = await sb.from('camiones').update({
    aprobacion: 'rechazada', rechazo_nota: nota || null, rechazo_campos: campos.length ? campos : null,
  }).eq('id', id);

  if (error) { showToast('Error al rechazar', 'error'); return; }

  if (c?.propietario_id) {
    const camposStr = campos.length ? ` Corregir: ${campos.join(', ')}.` : '';
    await _notificarResolucion(c.propietario_id, {
      tipo:     'recurso_rechazado',
      titulo:   'Unidad requiere correcciones',
      mensaje:  `Tu unidad ${id} (${c.tipo || ''}) necesita ajustes.${camposStr} Entra al panel Admin para corregir y reenviar.`,
      nota:     nota || null,
      aprobado: false,
    });
  }

  cerrarRechazarCamion();
  showToast(`Unidad ${id} devuelta con comentarios`);
  renderAprobaciones();
}

// ── RECHAZAR RECURSO COMPLETO (custodios, patios, lavados) ──

const _CAMPOS_RECURSO = {
  custodios: ['Nombre','Tipo de custodio','Descripción','Certificaciones','Disponibilidad','Precio'],
  patios:    ['Nombre','Tipo de patio','Ubicación','Área (m²)','Capacidad (vehículos)','Servicios','Precio'],
  lavados:   ['Nombre','Tipos de vehículo','Tipos de lavado','Capacidad simultánea','Ubicación','Horario','Precio'],
};

function rechazarRecursoCompleto(tabla, id) {
  document.getElementById('rrs-tabla').value = tabla;
  document.getElementById('rrs-id').value    = id;
  document.getElementById('rrs-nota').value  = '';

  const campos = _CAMPOS_RECURSO[tabla] || [];
  document.getElementById('rrs-campos').innerHTML = campos.map(c =>
    `<label class="ro-chip"><input type="checkbox" value="${c}"> ${c}</label>`
  ).join('');

  const titulos = { custodios:'custodio', patios:'patio', lavados:'servicio de lavado' };
  document.getElementById('rrs-titulo').textContent =
    `✕ Rechazar ${titulos[tabla] || 'recurso'} con comentarios`;

  document.getElementById('modal-rechazar-recurso').classList.add('open');
}

function cerrarRechazarRecurso() {
  document.getElementById('modal-rechazar-recurso').classList.remove('open');
}

async function confirmarRechazarRecurso() {
  const tabla  = document.getElementById('rrs-tabla').value;
  const id     = document.getElementById('rrs-id').value;
  const nota   = document.getElementById('rrs-nota').value.trim();
  const campos = Array.from(document.querySelectorAll('#rrs-campos input[type=checkbox]:checked')).map(c => c.value);

  const { data: r } = await sb.from(tabla).select('propietario_id, nombre').eq('id', id).single();
  const { error }   = await sb.from(tabla).update({
    aprobacion:     'rechazada',
    rechazo_nota:   nota   || null,
    rechazo_campos: campos.length ? campos : null,
  }).eq('id', id);

  if (error) { showToast('Error al rechazar', 'error'); return; }

  if (r?.propietario_id) {
    const tipoLabel = tabla === 'custodios' ? 'custodio' : tabla === 'patios' ? 'patio' : 'servicio de lavado';
    const camposStr = campos.length ? ` Corregir: ${campos.join(', ')}.` : '';
    await _notificarResolucion(r.propietario_id, {
      tipo:     'recurso_rechazado',
      titulo:   `${tipoLabel.charAt(0).toUpperCase() + tipoLabel.slice(1)} requiere correcciones`,
      mensaje:  `Tu ${tipoLabel} "${r.nombre || id}" necesita ajustes.${camposStr} Entra al panel Admin para ver el motivo y corregir.`,
      nota:     nota || null,
      aprobado: false,
    });
  }

  cerrarRechazarRecurso();
  showToast(`${id} devuelto con comentarios`);
  renderAprobaciones();
}

// ── APROBACIÓN EN LOTE ────────────────────────────────────

function aprobarTodasSolicitudes() {
  showConfirm('¿Aprobar y publicar todas las solicitudes pendientes de revisión?', async () => {
    const { data: solic } = await sb.from('pedidos').select('id, cliente_id, tipo_camion, origen, destino').eq('estado', 'pendiente_revision');
    if (!solic?.length) { showToast('No hay solicitudes pendientes'); return; }
    for (const p of solic) {
      await sb.from('pedidos').update({ estado: 'abierto', rechazo_nota: null }).eq('id', p.id);
    }

    // Notificar a cada cliente cuya solicitud fue aprobada
    const notifClientes = solic.filter(p => p.cliente_id).map(p => {
      const ruta = p.origen ? ` (${p.origen}${p.destino ? ' → ' + p.destino : ''})` : '';
      return {
        user_id: p.cliente_id,
        tipo:    'solicitud_aprobada',
        titulo:  '✅ Tu solicitud fue aprobada',
        mensaje: `Tu solicitud de ${p.tipo_camion || 'servicio'}${ruta} fue aprobada y ya está publicada. Pronto recibirás ofertas de proveedores.`,
        leido:   false,
      };
    });
    if (notifClientes.length) await sb.from('notificaciones').insert(notifClientes);

    // En lote los tipos son mixtos, así que va a todas las empresas activas.
    // Un solo correo con el resumen: mandar uno por solicitud serían N correos
    // a la vez y Gmail empieza a limitar.
    const destinatarios = await _adminsConFlotaPara(null);
    if (destinatarios.length) {
      await sb.from('notificaciones').insert(destinatarios.map(uid => ({
        user_id: uid,
        tipo:    'nueva_solicitud',
        titulo:  `${solic.length} solicitudes publicadas`,
        mensaje: `Se aprobaron ${solic.length} solicitudes. Ya están disponibles para ofertar.`,
        leido:   false,
      })));
    }
    _notificarEmail({
      tipo:  'solicitudes_lote',
      total: solic.length,
      rutas: solic.map(p => {
        const r = p.origen ? ` — ${p.origen}${p.destino ? ' → ' + p.destino : ''}` : '';
        return `${p.tipo_camion || 'Servicio'}${r}`;
      }),
    });

    await renderAprobaciones();
    if (document.getElementById('view-pedidos')?.classList.contains('active')) renderPedidos();
    showToast(`✓ ${solic.length} solicitud${solic.length !== 1 ? 'es' : ''} aprobada${solic.length !== 1 ? 's' : ''} y publicada${solic.length !== 1 ? 's' : ''}`);
  }, { confirmLabel: 'Aprobar todas' });
}

function aprobarTodosAcuerdos() {
  showConfirm('¿Aprobar todos los acuerdos pendientes? Se crearán reservaciones para cada uno.', async () => {
    // Dos consultas en total, no dos por acuerdo: antes esto pedía el pedido
    // completo y su oferta dentro del bucle, con 2N+1 viajes de red.
    const { data: acuerdos } = await sb.from('pedidos').select('*').eq('estado', 'pendiente_acuerdo');
    if (!acuerdos?.length) { showToast('No hay acuerdos pendientes'); return; }

    const ofertaIds = acuerdos.map(p => p.oferta_pendiente_id).filter(Boolean);
    const ofertasPorId = {};
    if (ofertaIds.length) {
      const { data: ofs } = await sb.from('ofertas').select('*').in('id', ofertaIds);
      (ofs || []).forEach(o => { ofertasPorId[o.id] = o; });
    }

    let ok = 0, err = 0;
    for (const ped of acuerdos) {
      try {
        const oferta = ped.oferta_pendiente_id && ofertasPorId[ped.oferta_pendiente_id];
        if (!oferta) { err++; continue; }
        await _ejecutarAprobarAcuerdo(ped, oferta);
        ok++;
      } catch (_) { err++; }
    }
    showToast(`✓ ${ok} acuerdo${ok !== 1 ? 's' : ''} aprobado${ok !== 1 ? 's' : ''}${err ? ` · ${err} con error` : ''}`);
  }, { confirmLabel: 'Aprobar todos' });
}

// ── APROBAR / RECHAZAR DOCUMENTOS DE EMPRESA ─────────────

async function aprobarDocsEmpresa(userId) {
  const { data: p } = await sb.from('perfiles')
    .select('nombre, fecha_vencimiento_permiso_sct_pendiente, fecha_vencimiento_seguro_rc_pendiente, fecha_vencimiento_seguro_carga_pendiente, doc_permiso_sct_pendiente, doc_seguro_rc_pendiente, doc_seguro_carga_pendiente')
    .eq('user_id', userId).single();
  if (!p) { showToast('Error al obtener el perfil', 'error'); return; }

  const upd = {
    perfil_docs_pendiente:              false,
    fecha_vencimiento_permiso_sct_pendiente:  null,
    fecha_vencimiento_seguro_rc_pendiente:    null,
    fecha_vencimiento_seguro_carga_pendiente: null,
    doc_permiso_sct_pendiente:   null,
    doc_seguro_rc_pendiente:     null,
    doc_seguro_carga_pendiente:  null,
    docs_aprobados_en:  new Date().toISOString(),
    docs_aprobados_por: currentUser.id,
  };
  if (p.fecha_vencimiento_permiso_sct_pendiente)  upd.fecha_vencimiento_permiso_sct  = p.fecha_vencimiento_permiso_sct_pendiente;
  if (p.fecha_vencimiento_seguro_rc_pendiente)    upd.fecha_vencimiento_seguro_rc    = p.fecha_vencimiento_seguro_rc_pendiente;
  if (p.fecha_vencimiento_seguro_carga_pendiente) upd.fecha_vencimiento_seguro_carga = p.fecha_vencimiento_seguro_carga_pendiente;
  if (p.doc_permiso_sct_pendiente)  upd.doc_permiso_sct  = p.doc_permiso_sct_pendiente;
  if (p.doc_seguro_rc_pendiente)    upd.doc_seguro_rc    = p.doc_seguro_rc_pendiente;
  if (p.doc_seguro_carga_pendiente) upd.doc_seguro_carga = p.doc_seguro_carga_pendiente;

  const { error } = await sb.from('perfiles').update(upd).eq('user_id', userId);
  if (error) { showToast('Error al aprobar: ' + error.message, 'error'); return; }

  await _notificarResolucion(userId, {
    tipo:    'docs_empresa_aprobados',
    titulo:  'Documentos aprobados',
    mensaje: 'Se aprobaron tus documentos legales de empresa. Ya están vigentes en la plataforma.',
  });

  document.getElementById(`apr-docs-${userId}`)?.remove();
  showToast(`✓ Documentos de ${esc(p.nombre || 'empresa')} aprobados`);
  _loadAprBadge();
}

function rechazarDocsEmpresa(userId, nombre) {
  _abrirRechazarNota(
    `Rechazar documentos de ${nombre || 'empresa'}`,
    'Motivo del rechazo (visible para la empresa)',
    async nota => {
      await sb.from('perfiles').update({
        perfil_docs_pendiente:                    false,
        fecha_vencimiento_permiso_sct_pendiente:  null,
        fecha_vencimiento_seguro_rc_pendiente:    null,
        fecha_vencimiento_seguro_carga_pendiente: null,
        doc_permiso_sct_pendiente:   null,
        doc_seguro_rc_pendiente:     null,
        doc_seguro_carga_pendiente:  null,
      }).eq('user_id', userId);
      await _notificarResolucion(userId, {
        tipo:     'docs_empresa_rechazados',
        titulo:   'Documentos no aprobados',
        mensaje:  'Tus documentos de empresa no fueron aprobados. Corrígelos y vuelve a enviarlos desde tu perfil.',
        nota:     nota || null,
        aprobado: false,
      });
      document.getElementById(`apr-docs-${userId}`)?.remove();
      showToast('Documentos rechazados y notificados');
      _loadAprBadge();
    }
  );
}
