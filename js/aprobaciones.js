// ── MÓDULO DE REVISIONES (solo superadmin) ─────────────

async function renderAprobaciones() {
  if (currentUser.rol !== 'superadmin') return;

  const section = document.getElementById('aprobaciones-section');
  if (section) section.style.display = '';

  const content = document.getElementById('aprobaciones-content');
  if (!content) return;
  content.innerHTML = '<div style="text-align:center;padding:16px;color:var(--text-muted)">Cargando…</div>';

  const [{ data: solicitudes }, { data: acuerdos }, { data: operadores },
         { data: camiones }, { data: custodios }, { data: patios }, { data: lavados },
         { data: cuentasPend }] = await Promise.all([
    sb.from('pedidos').select('*').eq('estado', 'pendiente_revision').order('created_at'),
    sb.from('pedidos').select('*').eq('estado', 'pendiente_acuerdo').order('created_at'),
    sb.from('operadores').select('*, propietario:perfiles(nombre)').eq('aprobacion', 'pendiente').order('created_at'),
    sb.from('camiones'  ).select('*, propietario:perfiles(nombre)').eq('aprobacion', 'pendiente').order('created_at', { ascending: false }),
    sb.from('custodios' ).select('*, propietario:perfiles(nombre)').eq('aprobacion', 'pendiente').order('created_at', { ascending: false }),
    sb.from('patios'    ).select('*, propietario:perfiles(nombre)').eq('aprobacion', 'pendiente').order('created_at', { ascending: false }),
    sb.from('lavados'   ).select('*, propietario:perfiles(nombre)').eq('aprobacion', 'pendiente').order('created_at', { ascending: false }),
    sb.from('solicitudes_cuenta').select('*').eq('estado', 'pendiente').order('created_at', { ascending: false }),
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

  let html = '';

  // ── CUENTAS POR VERIFICAR ────────────────────────────
  html += `<div class="apr-bloque-title">👤 Cuentas por verificar <span class="apr-count">${cuentasPend.length}</span></div>`;
  if (!cuentasPend.length) {
    html += `<div class="apr-empty">Sin solicitudes de cuenta pendientes</div>`;
  } else {
    const verDoc = (path, label) => path
      ? `<a href="#" onclick="verDocRegistro('${esc(path)}');return false" class="btn-edit" style="font-size:0.75rem;display:inline-block;margin:2px 4px 2px 0">📄 ${label}</a>`
      : '';
    html += cuentasPend.map(s => {
      const rolLabel  = s.rol === 'cliente' ? '🛒 Cliente' : '🏢 Empresa';
      const fachada   = Array.isArray(s.doc_fotos_oficinas) ? s.doc_fotos_oficinas[0] : null;
      const idDoc     = s.doc_id_oficial || s.doc_id_representante;
      return `
        <div class="apr-card" id="aprcuenta-${s.user_id}">
          <div class="apr-card-header">
            <div>
              <div class="apr-tipo">${rolLabel} — ${esc(s.nombre || '—')}</div>
              <div class="apr-sub">${esc(s.email)} · ${esc(s.telefono || '—')}</div>
            </div>
            <span class="badge badge-revision">Pendiente</span>
          </div>
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
            <div style="margin-top:6px;display:flex;flex-wrap:wrap;gap:2px">
              ${verDoc(idDoc,                    'Identificación')}
              ${verDoc(s.doc_comprobante_dom,    'Comp. domicilio')}
              ${verDoc(s.doc_foto_domicilio,     'Foto domicilio')}
              ${verDoc(fachada,                  'Foto fachada')}
              ${verDoc(s.doc_constancia_fiscal,  'Const. Fiscal SAT')}
              ${verDoc(s.doc_acta_constitutiva,  'Acta constitutiva')}
              ${verDoc(s.doc_poder_notarial,     'Poder notarial')}
            </div>
          </div>
          <div class="apr-actions">
            <button class="btn-apr-aprobar" onclick="aprobarCuenta('${s.user_id}')">✓ Aprobar cuenta</button>
            <button class="btn-apr-rechazar" onclick="rechazarCuenta('${s.user_id}')">✕ Rechazar</button>
          </div>
        </div>`;
    }).join('');
  }

  // ── SOLICITUDES POR REVISAR ──────────────────────────
  html += `<div class="apr-bloque-title" style="margin-top:28px">📋 Solicitudes por revisar <span class="apr-count">${(solicitudes || []).length}</span></div>`;

  if (!solicitudes?.length) {
    html += `<div class="apr-empty">Sin solicitudes pendientes de revisión</div>`;
  } else {
    html += (solicitudes || []).map(p => {
      const chips = _buildChipsSol(p);
      return `
        <div class="apr-card" id="aprsol-${p.id}">
          <div class="apr-card-header">
            <div>
              <div class="apr-tipo">${TIPO_EMOJI[p.tipo_camion] || '🚛'} ${esc(p.tipo_camion)}</div>
              <div class="apr-sub">Cliente: <strong>${esc(p.cliente_nombre)}</strong> · ${esc(p.cliente_email)}</div>
              ${p.fecha_ini ? `<div class="apr-sub">📅 ${fmtFecha(p.fecha_ini)}${p.fecha_fin && p.fecha_fin !== p.fecha_ini ? ' — ' + fmtFecha(p.fecha_fin) : ''}</div>` : ''}
            </div>
            <span class="badge badge-revision">En revisión</span>
          </div>
          ${p.origen || p.destino ? `<div class="apr-ruta">📍 ${esc(p.origen || '—')}${p.destino ? ' → ' + esc(p.destino) : ''}</div>` : ''}
          ${chips}
          ${p.descripcion ? `<div class="apr-desc">"${esc(p.descripcion)}"</div>` : ''}
          ${p.precio_cliente ? `<div class="apr-precio">Presupuesto cliente: <strong>$${Number(p.precio_cliente).toLocaleString('es-MX')} MXN</strong></div>` : ''}
          <div class="apr-actions">
            <button class="btn-apr-aprobar" onclick="aprobarSolicitud('${p.id}')">✓ Aprobar y publicar</button>
            <button class="btn-apr-rechazar" onclick="rechazarSolicitud('${p.id}')">✕ Rechazar</button>
          </div>
        </div>`;
    }).join('');
  }

  // ── ACUERDOS POR APROBAR ─────────────────────────────
  html += `<div class="apr-bloque-title" style="margin-top:28px">🤝 Acuerdos por aprobar <span class="apr-count">${(acuerdos || []).length}</span></div>`;

  if (!acuerdos?.length) {
    html += `<div class="apr-empty">Sin acuerdos pendientes de aprobación</div>`;
  } else {
    html += (acuerdos || []).map(p => {
      const oferta = p.oferta_pendiente_id ? ofertasMap[p.oferta_pendiente_id] : null;
      const chips  = _buildChipsSol(p);
      return `
        <div class="apr-card" id="apracu-${p.id}">
          <div class="apr-card-header">
            <div>
              <div class="apr-tipo">${TIPO_EMOJI[p.tipo_camion] || '🚛'} ${esc(p.tipo_camion)}</div>
              <div class="apr-sub">Cliente: <strong>${esc(p.cliente_nombre)}</strong></div>
              ${p.fecha_ini ? `<div class="apr-sub">📅 ${fmtFecha(p.fecha_ini)}${p.fecha_fin && p.fecha_fin !== p.fecha_ini ? ' — ' + fmtFecha(p.fecha_fin) : ''}</div>` : ''}
            </div>
            <span class="badge badge-acuerdo-rev">Acuerdo en revisión</span>
          </div>
          ${p.origen || p.destino ? `<div class="apr-ruta">📍 ${esc(p.origen || '—')}${p.destino ? ' → ' + esc(p.destino) : ''}</div>` : ''}
          ${chips}
          ${p.descripcion ? `<div class="apr-desc">"${esc(p.descripcion)}"</div>` : ''}
          ${oferta ? `
            <div class="apr-oferta-box">
              <div class="apr-oferta-title">Oferta del proveedor</div>
              <div class="apr-oferta-row">
                <span>Empresa:</span><strong>${esc(oferta.admin_nombre || '—')}</strong>
              </div>
              ${oferta.camion_id ? `<div class="apr-oferta-row"><span>Unidad:</span><strong>${esc(oferta.camion_id)}</strong></div>` : ''}
              <div class="apr-oferta-row">
                <span>Precio acordado:</span><strong class="apr-precio-acuerdo">$${Number(oferta.precio_oferta).toLocaleString('es-MX')} MXN</strong>
              </div>
              ${oferta.mensaje ? `<div class="apr-oferta-row"><span>Nota proveedor:</span>"${esc(oferta.mensaje)}"</div>` : ''}
              ${p.detalles_lugar ? `<div class="apr-oferta-row"><span>Dirección servicio:</span>${esc(p.detalles_lugar)}</div>` : ''}
              ${p.detalles_hora  ? `<div class="apr-oferta-row"><span>Hora:</span>${esc(p.detalles_hora)}</div>` : ''}
              ${p.detalles_contacto_nombre ? `<div class="apr-oferta-row"><span>Contacto:</span>${esc(p.detalles_contacto_nombre)} ${esc(p.detalles_contacto_tel || '')}</div>` : ''}
              ${p.precio_cliente ? `<div class="apr-oferta-row"><span>Presupuesto original cliente:</span>$${Number(p.precio_cliente).toLocaleString('es-MX')} MXN</div>` : ''}
            </div>` : '<div class="apr-empty" style="margin:8px 0">⚠️ No se encontró la oferta asociada</div>'}
          <div class="apr-actions">
            <button class="btn-apr-aprobar" onclick="aprobarAcuerdo('${p.id}')">✓ Aprobar acuerdo</button>
            <button class="btn-apr-rechazar" onclick="rechazarAcuerdo('${p.id}')">✕ Rechazar</button>
          </div>
        </div>`;
    }).join('');
  }

  // ── OPERADORES POR APROBAR ───────────────────────────
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

  content.innerHTML = html;
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

async function rechazarCuenta(userId) {
  const nota = prompt('Motivo del rechazo (el usuario lo verá al intentar iniciar sesión):');
  if (nota === null) return;

  const notaTrim = nota.trim() || null;
  const [{ error }] = await Promise.all([
    sb.from('perfiles').update({ aprobacion_cuenta: 'rechazada', nota_rechazo_cuenta: notaTrim }).eq('user_id', userId),
    sb.from('solicitudes_cuenta').update({ estado: 'rechazada', nota_rechazo: notaTrim }).eq('user_id', userId),
  ]);
  if (error) { showToast('Error al rechazar', 'error'); return; }

  document.getElementById(`aprcuenta-${userId}`)?.remove();
  showToast('Solicitud rechazada');
  _loadAprBadge();
}

function _diffHtml(recurso, labels) {
  if (!recurso.es_edicion || !recurso.campos_editados?.length || !recurso.snapshot_anterior) return '';
  const dateFields  = new Set(['fecha_expedicion_tc','vigencia_caat','fecha_vencimiento','fecha_expedicion','fecha_examen_medico']);
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

  // Notificar a todos los admins que hay nueva solicitud disponible
  const { data: ped } = await sb.from('pedidos').select('tipo_camion, origen, destino').eq('id', pedidoId).single();
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

async function rechazarSolicitud(pedidoId) {
  const nota = prompt('Motivo del rechazo (se enviará al cliente):') ?? '';

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

// ── APROBAR ACUERDO ──────────────────────────────────────

async function aprobarAcuerdo(pedidoId) {
  const { data: ped } = await sb.from('pedidos').select('*').eq('id', pedidoId).single();
  if (!ped?.oferta_pendiente_id) { showToast('Error: no hay oferta asociada', 'error'); return; }

  const { data: oferta } = await sb.from('ofertas').select('*').eq('id', ped.oferta_pendiente_id).single();
  if (!oferta) { showToast('Error: oferta no encontrada', 'error'); return; }

  // Ejecutar el cierre real (rechaza otras ofertas, crea reservación, marca camión ocupado)
  await cerrarAcuerdo(oferta, ped);

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


async function rechazarAcuerdo(pedidoId) {
  const nota = prompt('Motivo del rechazo (se notificará a ambas partes):') ?? '';

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
