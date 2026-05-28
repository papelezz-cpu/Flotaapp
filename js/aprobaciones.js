// ── MÓDULO DE REVISIONES (solo superadmin) ─────────────

// ─── Modal genérico para rechazo con nota ──────────────
let _rechazarNotaCb = null;

function _abrirRechazarNota(titulo, label, callback) {
  document.getElementById('rn-titulo').textContent = titulo;
  document.getElementById('rn-label').textContent  = label;
  document.getElementById('rn-nota').value         = '';
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
         { data: cuentasPend }, { data: docsEmpresa }] = await Promise.all([
    sb.from('pedidos').select('*').eq('estado', 'pendiente_revision').order('created_at'),
    sb.from('pedidos').select('*').eq('estado', 'pendiente_acuerdo').order('created_at'),
    sb.from('operadores').select('*, propietario:perfiles(nombre)').eq('aprobacion', 'pendiente').order('created_at'),
    sb.from('camiones'  ).select('*, propietario:perfiles(nombre)').eq('aprobacion', 'pendiente').order('created_at', { ascending: false }),
    sb.from('custodios' ).select('*, propietario:perfiles(nombre)').eq('aprobacion', 'pendiente').order('created_at', { ascending: false }),
    sb.from('patios'    ).select('*, propietario:perfiles(nombre)').eq('aprobacion', 'pendiente').order('created_at', { ascending: false }),
    sb.from('lavados'   ).select('*, propietario:perfiles(nombre)').eq('aprobacion', 'pendiente').order('id', { ascending: false }),
    sb.from('solicitudes_cuenta').select('*').eq('estado', 'pendiente').order('created_at', { ascending: false }),
    sb.from('perfiles').select('user_id, nombre, fecha_vencimiento_permiso_sct, fecha_vencimiento_permiso_sct_pendiente, fecha_vencimiento_seguro_rc, fecha_vencimiento_seguro_rc_pendiente, fecha_vencimiento_seguro_carga, fecha_vencimiento_seguro_carga_pendiente, doc_permiso_sct, doc_permiso_sct_pendiente, doc_seguro_rc, doc_seguro_rc_pendiente, doc_seguro_carga, doc_seguro_carga_pendiente').eq('perfil_docs_pendiente', true),
  ]);

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
          <button class="btn-apr-rechazar" onclick="rechazarDocsEmpresa('${p.user_id}','${esc(p.nombre || '')}')">✕ Rechazar</button>
        </div>
      </div>`).join('');
  }

  // ── CUENTAS POR VERIFICAR ────────────────────────────
  html += `<div class="apr-bloque-title">👤 Cuentas por verificar <span class="apr-count">${cuentasPend.length}</span></div>`;
  if (!cuentasPend.length) {
    html += `<div class="apr-empty">Sin solicitudes de cuenta pendientes</div>`;
  } else {
    const verDoc = (path, label) => path
      ? `<a href="#" onclick="verDocRegistro('${esc(path)}');return false" class="btn-edit" style="font-size:0.75rem;display:inline-block;margin:2px 4px 2px 0">📄 ${label}</a>`
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
          <div class="apr-actions">
            <button class="btn-apr-aprobar" onclick="aprobarCuenta('${s.user_id}')">✓ Aprobar cuenta</button>
            <button class="btn-apr-rechazar" onclick="rechazarCuenta('${s.user_id}')">✕ Rechazar</button>
          </div>
        </div>`;
      return _colapseCard(`cuenta-${s.user_id}`, header, body);
    }).join('');
  }

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
                ${p.detalles_contacto_nombre ? `<div class="apr-oferta-row"><span>Contacto:</span>${esc(p.detalles_contacto_nombre)} ${esc(p.detalles_contacto_tel||'')}</div>` : ''}
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
  html += ``; if (false) {
  html += `<div class="apr-bloque-title" style="margin-top:28px">👷 Operadores por aprobar <span class="apr-count">${(operadores || []).length}</span></div>`;

  if (!operadores?.length) {
    html += `<div class="apr-empty">Sin operadores pendientes de aprobación</div>`;
  } else {
    html += (operadores || []).map(op => {
      const nombre = [op.nombre, op.primer_apellido, op.segundo_apellido].filter(Boolean).join(' ');
      const foto   = op.foto_operador
        ? `<img src="${esc(op.foto_operador)}" style="width:56px;height:56px;border-radius:50%;object-fit:cover;border:2px solid var(--border);flex-shrink:0" alt="foto">`
        : `<div style="width:56px;height:56px;border-radius:50%;background:var(--accent);color:#fff;display:flex;align-items:center;justify-content:center;font-size:1.3rem;font-weight:700;flex-shrink:0">${(op.nombre||'?')[0].toUpperCase()}</div>`;
      const venceColor  = op.fecha_vencimiento && new Date(op.fecha_vencimiento) < new Date() ? 'var(--danger)' : 'inherit';
      const diffOpHtml  = _diffHtml(op, {
        nombre:'Nombre', primer_apellido:'Primer apellido', segundo_apellido:'Segundo apellido',
        curp:'CURP', rfc:'RFC', nss:'NSS', sexo:'Sexo', tipo_sanguineo:'Tipo sanguíneo',
        correo:'Correo', telefono:'Teléfono', num_trabajador:'Núm. trabajador',
        nivel_estudio:'Nivel de estudio', area:'Área', puesto:'Puesto',
        num_licencia:'Núm. licencia', clase_licencia:'Clase licencia', tipo_licencia:'Tipo licencia',
        fecha_expedicion:'Fecha expedición', fecha_vencimiento:'Vencimiento',
        fecha_examen_medico:'Examen médico',
      });
      return `
        <div class="apr-card" id="aprop-${op.id}">
          <div class="apr-card-header">
            <div style="display:flex;align-items:center;gap:14px">
              ${foto}
              <div>
                <div class="apr-tipo">👷 ${esc(nombre)}</div>
                <div class="apr-sub">${esc(op.id)} · Empresa: <strong>${esc(op.propietario?.nombre || '—')}</strong></div>
              </div>
            </div>
            ${op.es_edicion ? '<span class="apr-edicion-tag">✏️ Edición</span>' : '<span class="badge badge-revision">Pendiente</span>'}
          </div>
          ${diffOpHtml}
          <div class="apr-op-detalle">
            <div class="apr-op-section-title">Datos personales</div>
            <div class="apr-op-grid">
              <div class="apr-op-row"><span>CURP</span><strong>${esc(op.curp || '—')}</strong></div>
              <div class="apr-op-row"><span>RFC</span><strong>${esc(op.rfc || '—')}</strong></div>
              <div class="apr-op-row"><span>NSS</span><strong>${esc(op.nss || '—')}</strong></div>
              <div class="apr-op-row"><span>Sexo</span><strong>${esc(op.sexo || '—')}</strong></div>
              <div class="apr-op-row"><span>Tipo sanguíneo</span><strong>${esc(op.tipo_sanguineo || '—')}</strong></div>
              <div class="apr-op-row"><span>Correo</span><strong>${esc(op.correo || '—')}</strong></div>
              <div class="apr-op-row"><span>Teléfono</span><strong>${esc(op.telefono || '—')}</strong></div>
            </div>
            <div class="apr-op-section-title">Datos laborales</div>
            <div class="apr-op-grid">
              <div class="apr-op-row"><span>Núm. trabajador</span><strong>${esc(op.num_trabajador || '—')}</strong></div>
              <div class="apr-op-row"><span>Nivel de estudio</span><strong>${esc(op.nivel_estudio || '—')}</strong></div>
              <div class="apr-op-row"><span>Área</span><strong>${esc(op.area || '—')}</strong></div>
              <div class="apr-op-row"><span>Puesto</span><strong>${esc(op.puesto || '—')}</strong></div>
              <div class="apr-op-row"><span>Examen médico</span><strong>${op.fecha_examen_medico ? fmtFecha(op.fecha_examen_medico) : '—'}</strong></div>
            </div>
            <div class="apr-op-section-title">Licencia de conducir</div>
            <div class="apr-op-grid">
              <div class="apr-op-row"><span>Número</span><strong>${esc(op.num_licencia || '—')}</strong></div>
              <div class="apr-op-row"><span>Clase</span><strong>${esc(op.clase_licencia || '—')}</strong></div>
              <div class="apr-op-row"><span>Tipo</span><strong>${esc(op.tipo_licencia || '—')}</strong></div>
              <div class="apr-op-row"><span>Expedición</span><strong>${op.fecha_expedicion ? fmtFecha(op.fecha_expedicion) : '—'}</strong></div>
              <div class="apr-op-row"><span>Vencimiento</span><strong style="color:${venceColor}">${op.fecha_vencimiento ? fmtFecha(op.fecha_vencimiento) : '—'}</strong></div>
            </div>
            ${op.foto_licencia ? `<a href="${esc(op.foto_licencia)}" target="_blank" class="btn-edit" style="font-size:0.75rem;display:inline-block;margin-top:8px">🪪 Ver foto de licencia</a>` : ''}
          </div>
          <div class="apr-actions">
            <button class="btn-apr-aprobar"  onclick="aprobarOperador('${op.id}')">✓ Aprobar</button>
            <button class="btn-apr-rechazar" onclick="rechazarOperador('${op.id}')">✕ Rechazar con comentarios</button>
          </div>
        </div>`;
    }).join('');
  }

  // ── UNIDADES POR APROBAR ─────────────────────────────
  html += `<div class="apr-bloque-title" style="margin-top:28px">🚛 Unidades por aprobar <span class="apr-count">${(camiones || []).length}</span></div>`;
  if (!camiones?.length) {
    html += `<div class="apr-empty">Sin unidades pendientes</div>`;
  } else {
    html += (camiones || []).map(c => {
      const campos = `
        <div class="apr-op-detalle">
          <div class="apr-op-section-title">Vehículo</div>
          <div class="apr-op-grid">
            <div class="apr-op-row"><span>Tipo</span><strong>${esc(c.tipo || '—')}</strong></div>
            <div class="apr-op-row"><span>Marca</span><strong>${esc(c.marca || '—')}</strong></div>
            <div class="apr-op-row"><span>Versión</span><strong>${esc(c.version || '—')}</strong></div>
            <div class="apr-op-row"><span>Año</span><strong>${c.modelo_anio || '—'}</strong></div>
            <div class="apr-op-row"><span>Color</span><strong>${esc(c.color || '—')}</strong></div>
            <div class="apr-op-row"><span>Capacidad</span><strong>${c.capacidad ? c.capacidad + ' ton' : '—'}</strong></div>
            <div class="apr-op-row"><span>Dimensiones</span><strong>${esc(c.dimensiones || '—')}</strong></div>
            <div class="apr-op-row"><span>Combustible</span><strong>${esc(c.tipo_combustible || '—')}</strong></div>
          </div>
          <div class="apr-op-section-title">Identificación</div>
          <div class="apr-op-grid">
            <div class="apr-op-row"><span>Placas</span><strong>${esc(c.placas || '—')}</strong></div>
            <div class="apr-op-row"><span>Tipo placa</span><strong>${esc(c.tipo_placa || '—')}</strong></div>
            <div class="apr-op-row"><span>Núm. serie (NIV)</span><strong>${esc(c.num_serie || '—')}</strong></div>
            <div class="apr-op-row"><span>Núm. motor</span><strong>${esc(c.num_motor || '—')}</strong></div>
            <div class="apr-op-row"><span>Núm. económico</span><strong>${esc(c.num_economico || '—')}</strong></div>
          </div>
          <div class="apr-op-section-title">Tarjeta de circulación</div>
          <div class="apr-op-grid">
            <div class="apr-op-row"><span>Número TC</span><strong>${esc(c.tarjeta_circulacion || '—')}</strong></div>
            <div class="apr-op-row"><span>Fecha expedición</span><strong>${c.fecha_expedicion_tc ? fmtFecha(c.fecha_expedicion_tc) : '—'}</strong></div>
          </div>
          ${c.imagen_tc ? `<a href="#" onclick="verArchivoPublico('${esc(c.imagen_tc)}')" class="btn-edit" style="font-size:0.75rem;display:inline-block;margin:4px 0">🪪 Ver imagen TC</a>` : ''}
          <div class="apr-op-section-title">CAAT</div>
          <div class="apr-op-grid">
            <div class="apr-op-row"><span>Número CAAT</span><strong>${esc(c.caat || '—')}</strong></div>
            <div class="apr-op-row"><span>Vigencia</span><strong>${c.vigencia_caat ? fmtFecha(c.vigencia_caat) : '—'}</strong></div>
          </div>
          ${c.imagen_caat ? `<a href="#" onclick="verArchivoPublico('${esc(c.imagen_caat)}')" class="btn-edit" style="font-size:0.75rem;display:inline-block;margin:4px 0">📄 Ver imagen CAAT</a>` : ''}
          ${(c.archivos || []).length ? `<div style="margin-top:6px"><button class="btn-edit" onclick="verArchivos('${c.id}')">📎 Ver fotos/documentos</button></div>` : ''}
        </div>`;
      const diffHtml = _diffHtml(c, {
        tipo:'Tipo', marca:'Marca', version:'Versión', modelo_anio:'Año',
        color:'Color', capacidad:'Capacidad (ton)', dimensiones:'Dimensiones',
        tipo_combustible:'Combustible', placas:'Placas', tipo_placa:'Tipo placa',
        num_serie:'Núm. serie', num_motor:'Núm. motor', num_economico:'Núm. económico',
        tarjeta_circulacion:'Núm. TC', fecha_expedicion_tc:'Fecha TC',
        caat:'CAAT', vigencia_caat:'Vigencia CAAT', precio_dia:'Precio/día',
      });
      return `
        <div class="apr-card" id="aprcam-${c.id}">
          <div class="apr-card-header">
            <div>
              <div class="apr-tipo">${c.emoji || '🚛'} ${c.id} — ${esc(c.tipo)}</div>
              <div class="apr-sub">Empresa: <strong>${esc(c.propietario?.nombre || '—')}</strong> · ${c.capacidad || '—'} ton</div>
            </div>
            ${c.es_edicion ? '<span class="apr-edicion-tag">✏️ Edición</span>' : '<span class="badge badge-revision">Pendiente</span>'}
          </div>
          ${diffHtml}
          ${campos}
          <div class="apr-actions">
            <button class="btn-apr-aprobar"  onclick="aprobarCamion('${c.id}')">✓ Aprobar</button>
            <button class="btn-apr-rechazar" onclick="rechazarCamion('${c.id}')">✕ Rechazar con comentarios</button>
          </div>
        </div>`;
    }).join('');
  }

  // ── CUSTODIOS ─────────────────────────────────────────
  if (custodios?.length) {
    html += `<div class="apr-bloque-title" style="margin-top:28px">👮 Custodios por aprobar <span class="apr-count">${custodios.length}</span></div>`;
    html += custodios.map(c => {
      const diffCustHtml = _diffHtml(c, {
        nombre:'Nombre', tipo:'Tipo', descripcion:'Descripción',
        disponibilidad:'Disponibilidad', precio_dia:'Precio/día',
        certificaciones:'Certificaciones',
      });
      return `
      <div class="apr-card" id="aprec-${c.id}">
        <div class="apr-card-header">
          <div>
            <div class="apr-tipo">👮 ${c.id} — ${esc(c.nombre)}</div>
            <div class="apr-sub">Empresa: <strong>${esc(c.propietario?.nombre || '—')}</strong></div>
          </div>
          ${c.es_edicion ? '<span class="apr-edicion-tag">✏️ Edición</span>' : '<span class="badge badge-revision">Pendiente</span>'}
        </div>
        ${diffCustHtml}
        <div class="apr-op-detalle">
          <div class="apr-op-section-title">Datos del custodio</div>
          <div class="apr-op-grid">
            <div class="apr-op-row"><span>Tipo</span><strong>${esc(c.tipo || '—')}</strong></div>
            <div class="apr-op-row"><span>Disponibilidad</span><strong>${esc(c.disponibilidad || '—')}</strong></div>
            <div class="apr-op-row"><span>Precio / día</span><strong>${c.precio_dia ? '$'+Number(c.precio_dia).toLocaleString('es-MX')+' MXN' : '—'}</strong></div>
          </div>
          ${c.descripcion ? `<div class="apr-op-section-title">Descripción</div><div class="apr-desc">${esc(c.descripcion)}</div>` : ''}
          ${(c.certificaciones||[]).length ? `<div class="apr-op-section-title">Certificaciones</div><div class="pedido-chips">${(c.certificaciones||[]).map(x=>`<span class="cargo-chip">${esc(x)}</span>`).join('')}</div>` : ''}
        </div>
        <div class="apr-actions">
          <button class="btn-apr-aprobar"  onclick="aprobarRecurso('custodios','${c.id}')">✓ Aprobar</button>
          <button class="btn-apr-rechazar" onclick="rechazarRecursoCompleto('custodios','${c.id}')">✕ Rechazar con comentarios</button>
        </div>
      </div>`;
    }).join('');
  }

  // ── PATIOS ────────────────────────────────────────────
  if (patios?.length) {
    html += `<div class="apr-bloque-title" style="margin-top:28px">🏭 Patios por aprobar <span class="apr-count">${patios.length}</span></div>`;
    html += patios.map(p => {
      const diffPatHtml = _diffHtml(p, {
        nombre:'Nombre', tipo:'Tipo', ubicacion:'Ubicación',
        area_m2:'Área (m²)', capacidad_vehiculos:'Capacidad (veh.)',
        precio_dia:'Precio/día', servicios:'Servicios',
      });
      return `
      <div class="apr-card" id="aprec-${p.id}">
        <div class="apr-card-header">
          <div>
            <div class="apr-tipo">🏭 ${p.id} — ${esc(p.nombre)}</div>
            <div class="apr-sub">Empresa: <strong>${esc(p.propietario?.nombre || '—')}</strong></div>
          </div>
          ${p.es_edicion ? '<span class="apr-edicion-tag">✏️ Edición</span>' : '<span class="badge badge-revision">Pendiente</span>'}
        </div>
        ${diffPatHtml}
        <div class="apr-op-detalle">
          <div class="apr-op-section-title">Datos del patio</div>
          <div class="apr-op-grid">
            <div class="apr-op-row"><span>Tipo</span><strong>${esc(p.tipo || '—')}</strong></div>
            <div class="apr-op-row"><span>Ubicación</span><strong>${esc(p.ubicacion || '—')}</strong></div>
            <div class="apr-op-row"><span>Área</span><strong>${p.area_m2 ? p.area_m2+' m²' : '—'}</strong></div>
            <div class="apr-op-row"><span>Capacidad</span><strong>${p.capacidad_vehiculos ? p.capacidad_vehiculos+' veh.' : '—'}</strong></div>
            <div class="apr-op-row"><span>Precio / día</span><strong>${p.precio_dia ? '$'+Number(p.precio_dia).toLocaleString('es-MX')+' MXN' : '—'}</strong></div>
          </div>
          ${(p.servicios||[]).length ? `<div class="apr-op-section-title">Servicios</div><div class="pedido-chips">${(p.servicios||[]).map(x=>`<span class="cargo-chip">${esc(x)}</span>`).join('')}</div>` : ''}
        </div>
        <div class="apr-actions">
          <button class="btn-apr-aprobar"  onclick="aprobarRecurso('patios','${p.id}')">✓ Aprobar</button>
          <button class="btn-apr-rechazar" onclick="rechazarRecursoCompleto('patios','${p.id}')">✕ Rechazar con comentarios</button>
        </div>
      </div>`;
    }).join('');
  }

  // ── LAVADOS ───────────────────────────────────────────
  if (lavados?.length) {
    html += `<div class="apr-bloque-title" style="margin-top:28px">🚿 Lavados por aprobar <span class="apr-count">${lavados.length}</span></div>`;
    html += lavados.map(l => {
      const diffLavHtml = _diffHtml(l, {
        nombre:'Nombre', ubicacion:'Ubicación', capacidad:'Cap. simultánea',
        horario:'Horario', precio_lavado:'Precio',
        tipos_vehiculo:'Tipos de vehículo', tipos_lavado:'Tipos de lavado',
        descripcion:'Descripción',
      });
      return `
      <div class="apr-card" id="aprec-${l.id}">
        <div class="apr-card-header">
          <div>
            <div class="apr-tipo">🚿 ${l.id} — ${esc(l.nombre)}</div>
            <div class="apr-sub">Empresa: <strong>${esc(l.propietario?.nombre || '—')}</strong></div>
          </div>
          ${l.es_edicion ? '<span class="apr-edicion-tag">✏️ Edición</span>' : '<span class="badge badge-revision">Pendiente</span>'}
        </div>
        ${diffLavHtml}
        <div class="apr-op-detalle">
          <div class="apr-op-section-title">Datos del servicio</div>
          <div class="apr-op-grid">
            <div class="apr-op-row"><span>Ubicación</span><strong>${esc(l.ubicacion || '—')}</strong></div>
            <div class="apr-op-row"><span>Capacidad simultánea</span><strong>${l.capacidad || '—'}</strong></div>
            <div class="apr-op-row"><span>Horario</span><strong>${esc(l.horario || '—')}</strong></div>
            <div class="apr-op-row"><span>Precio</span><strong>${l.precio_lavado ? '$'+Number(l.precio_lavado).toLocaleString('es-MX')+' MXN' : '—'}</strong></div>
          </div>
          ${(l.tipos_vehiculo||[]).length ? `<div class="apr-op-section-title">Tipos de vehículo</div><div class="pedido-chips">${(l.tipos_vehiculo||[]).map(x=>`<span class="cargo-chip">${esc(x)}</span>`).join('')}</div>` : ''}
          ${(l.tipos_lavado||[]).length ? `<div class="apr-op-section-title">Tipos de lavado</div><div class="pedido-chips">${(l.tipos_lavado||[]).map(x=>`<span class="cargo-chip">${esc(x)}</span>`).join('')}</div>` : ''}
          ${l.descripcion ? `<div class="apr-desc" style="margin-top:6px">${esc(l.descripcion)}</div>` : ''}
        </div>
        <div class="apr-actions">
          <button class="btn-apr-aprobar"  onclick="aprobarRecurso('lavados','${l.id}')">✓ Aprobar</button>
          <button class="btn-apr-rechazar" onclick="rechazarRecursoCompleto('lavados','${l.id}')">✕ Rechazar con comentarios</button>
        </div>
      </div>`;
    }).join('');
  }
  } // fin if(false) — secciones legacy reemplazadas por empresa

  content.innerHTML = html;
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
        ${c.imagen_tc  ? `<a href="#" onclick="verArchivoPublico('${esc(c.imagen_tc)}')"  class="btn-edit" style="font-size:0.75rem">🪪 TC</a>` : ''}
        ${c.doc_sct    ? `<a href="#" onclick="verArchivoPublico('${esc(c.doc_sct)}')"    class="btn-edit" style="font-size:0.75rem">📄 SCT</a>` : ''}
        ${c.doc_seguro ? `<a href="#" onclick="verArchivoPublico('${esc(c.doc_seguro)}')" class="btn-edit" style="font-size:0.75rem">📄 Seguro</a>` : ''}
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
        <div style="margin-top:6px;display:flex;flex-wrap:wrap;gap:4px">
          ${op.foto_licencia    ? `<a href="${esc(op.foto_licencia)}"    target="_blank" class="btn-edit" style="font-size:0.75rem">🪪 Licencia</a>` : ''}
          ${op.doc_examen_medico ? `<a href="${esc(op.doc_examen_medico)}" target="_blank" class="btn-edit" style="font-size:0.75rem">📄 Examen médico</a>` : ''}
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
          : `<a href="#" onclick="verArchivoPublico('${esc(p.doc_permiso)}');return false" class="btn-edit" style="font-size:0.75rem;display:inline-block;margin-top:6px">📄 Ver permiso operativo</a>`) : ''}
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

async function aprobarCuenta(userId) {
  const { data: sc } = await sb.from('solicitudes_cuenta')
    .select('nombre').eq('user_id', userId).single();

  const [{ error }] = await Promise.all([
    sb.from('perfiles').update({ aprobacion_cuenta: null }).eq('user_id', userId),
    sb.from('solicitudes_cuenta').update({ estado: 'aprobada' }).eq('user_id', userId),
  ]);
  if (error) { showToast('Error al aprobar', 'error'); return; }

  await sb.from('notificaciones').insert({
    user_id: userId,
    tipo:    'cuenta_aprobada',
    titulo:  '¡Cuenta aprobada!',
    mensaje: 'Tu cuenta ha sido verificada. Ya puedes iniciar sesión en PortGo.',
    leido:   false,
  });

  document.getElementById(`aprcuenta-${userId}`)?.remove();
  showToast(`✓ Cuenta de ${esc(sc?.nombre || 'usuario')} aprobada`);
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
  await sb.from('pedidos').update({ estado: 'abierto', rechazo_nota: null }).eq('id', pedidoId);

  const { data: ped } = await sb.from('pedidos').select('tipo_camion, origen, destino, cliente_id').eq('id', pedidoId).single();

  // Notificar al cliente que su solicitud fue aprobada
  if (ped?.cliente_id) {
    const ruta = ped.origen ? ` (${ped.origen}${ped.destino ? ' → ' + ped.destino : ''})` : '';
    await sb.from('notificaciones').insert({
      user_id: ped.cliente_id,
      tipo:    'solicitud_aprobada',
      titulo:  '✅ Tu solicitud fue aprobada',
      mensaje: `Tu solicitud de ${ped.tipo_camion || 'servicio'}${ruta} fue aprobada y ya está publicada. Pronto recibirás ofertas de proveedores.`,
      leido:   false,
    });
  }

  // Notificar a todos los admins que hay nueva solicitud disponible
  const { data: admins } = await sb.from('perfiles').select('user_id').in('rol', ['admin', 'superadmin']);
  if (admins?.length) {
    await sb.from('notificaciones').insert(admins.map(a => ({
      user_id: a.user_id,
      tipo:    'nueva_solicitud',
      titulo:  'Nueva solicitud publicada',
      mensaje: `Se aprobó una solicitud de ${esc(ped?.tipo_camion || 'servicio')}. Ya está disponible para ofertar.`,
      leido:   false,
    })));
  }

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
        await sb.from('notificaciones').insert({
          user_id: ped.cliente_id,
          tipo:    'solicitud_rechazada',
          titulo:  'Solicitud no aprobada',
          mensaje: `Tu solicitud de ${esc(ped.tipo_camion || 'servicio')} no fue aprobada.${nota ? ' Motivo: ' + nota : ''}`,
          leido:   false,
        });
      }
      showToast('Solicitud rechazada y notificada al cliente');
      renderAprobaciones();
      if (document.getElementById('view-pedidos')?.classList.contains('active')) renderPedidos();
    }
  );
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
  fetch(FN_NOTIFICACION, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      tipo:        'acuerdo_aprobado',
      tipo_camion: ped.tipo_camion,
      clienteId:   ped.cliente_id,
      adminId:     oferta.admin_id,
    }),
  }).catch(() => {});

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
    await sb.from('notificaciones').insert({
      user_id: op.propietario_id,
      tipo:    'recurso_rechazado',
      titulo:  '⚠ Operador requiere correcciones',
      mensaje: `El operador ${esc(op.nombre)} (${id}) necesita ajustes.${camposStr}${nota ? ' Comentario: ' + nota : ''} Entra al tab Operadores para corregir y reenviar.`,
      leido:   false,
    });
  }

  cerrarRechazarOperador();
  showToast(`Operador ${id} devuelto con comentarios`);
  renderAprobaciones();
  renderAdminOperadores();
}

async function aprobarOperador(id) {
  const { data: op } = await sb.from('operadores').select('propietario_id, nombre, primer_apellido').eq('id', id).single();
  const { error } = await sb.from('operadores').update({ aprobacion: 'aprobada', es_edicion: false, campos_editados: null, snapshot_anterior: null }).eq('id', id);
  if (error) { showToast('Error al aprobar operador', 'error'); return; }

  if (op?.propietario_id) {
    const nombre = [op.nombre, op.primer_apellido].filter(Boolean).join(' ');
    await sb.from('notificaciones').insert({
      user_id: op.propietario_id,
      tipo:    'recurso_aprobado',
      titulo:  '✓ Operador aprobado',
      mensaje: `Tu operador ${nombre} (${id}) fue aprobado y ya puede asignarse a unidades.`,
      leido:   false,
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
  await sb.from('pedidos').update({
    estado:              'en_negociacion',
    oferta_pendiente_id: null,
    rechazo_nota:        nota || null,
  }).eq('id', pedidoId);

  // Revertir oferta a enviada para que el cliente la vuelva a ver
  if (ofertaId) {
    await sb.from('ofertas').update({ estado: 'enviada' }).eq('id', ofertaId);
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
  await sb.from('camiones').update({ aprobacion: 'aprobada', es_edicion: false, campos_editados: null, snapshot_anterior: null }).eq('id', id);
  if (c?.propietario_id) {
    await sb.from('notificaciones').insert({
      user_id: c.propietario_id,
      tipo:    'recurso_aprobado',
      titulo:  '✓ Unidad aprobada',
      mensaje: `Tu unidad ${id} (${esc(c.tipo || '')}) fue aprobada y ya está visible en el catálogo.`,
      leido:   false,
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
    await sb.from('notificaciones').insert({
      user_id: c.propietario_id,
      tipo:    'recurso_rechazado',
      titulo:  '⚠ Unidad requiere correcciones',
      mensaje: `Tu unidad ${id} (${esc(c.tipo || '')}) necesita ajustes.${camposStr}${nota ? ' Comentario: ' + nota : ''} Entra al panel Admin para corregir y reenviar.`,
      leido:   false,
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
    await sb.from('notificaciones').insert({
      user_id: r.propietario_id,
      tipo:    'recurso_rechazado',
      titulo:  `⚠ ${tipoLabel.charAt(0).toUpperCase() + tipoLabel.slice(1)} requiere correcciones`,
      mensaje: `Tu ${tipoLabel} "${esc(r.nombre || id)}" necesita ajustes.${camposStr}${nota ? ' Comentario: ' + nota : ''} Entra al panel Admin para ver el motivo y corregir.`,
      leido:   false,
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

    const { data: admins } = await sb.from('perfiles').select('user_id').in('rol', ['admin', 'superadmin']);
    if (admins?.length) {
      await sb.from('notificaciones').insert(admins.map(a => ({
        user_id: a.user_id,
        tipo:    'nueva_solicitud',
        titulo:  `${solic.length} solicitudes publicadas`,
        mensaje: `Se aprobaron ${solic.length} solicitudes. Ya están disponibles para ofertar.`,
        leido:   false,
      })));
    }
    await renderAprobaciones();
    if (document.getElementById('view-pedidos')?.classList.contains('active')) renderPedidos();
    showToast(`✓ ${solic.length} solicitud${solic.length !== 1 ? 'es' : ''} aprobada${solic.length !== 1 ? 's' : ''} y publicada${solic.length !== 1 ? 's' : ''}`);
  }, { confirmLabel: 'Aprobar todas' });
}

function aprobarTodosAcuerdos() {
  showConfirm('¿Aprobar todos los acuerdos pendientes? Se crearán reservaciones para cada uno.', async () => {
    const { data: acuerdos } = await sb.from('pedidos').select('id, oferta_pendiente_id').eq('estado', 'pendiente_acuerdo');
    if (!acuerdos?.length) { showToast('No hay acuerdos pendientes'); return; }
    let ok = 0, err = 0;
    for (const a of acuerdos) {
      try {
        const { data: ped } = await sb.from('pedidos').select('*').eq('id', a.id).single();
        if (!ped?.oferta_pendiente_id) { err++; continue; }
        const { data: oferta } = await sb.from('ofertas').select('*').eq('id', ped.oferta_pendiente_id).single();
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

  await sb.from('notificaciones').insert({
    user_id: userId, tipo: 'docs_empresa_aprobados',
    titulo:  '✅ Documentos aprobados',
    mensaje: 'El superadmin aprobó tus documentos legales de empresa. Ya están vigentes en la plataforma.',
    leido:   false,
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
      await sb.from('notificaciones').insert({
        user_id: userId, tipo: 'docs_empresa_rechazados',
        titulo:  '⚠ Documentos rechazados',
        mensaje: `El superadmin rechazó tus documentos de empresa.${nota ? ' Motivo: ' + nota : ''} Corrígelos y vuelve a enviarlos.`,
        leido:   false,
      });
      document.getElementById(`apr-docs-${userId}`)?.remove();
      showToast('Documentos rechazados y notificados');
      _loadAprBadge();
    }
  );
}
