// ── MÓDULO DE REVISIONES (solo superadmin) ─────────────

async function renderAprobaciones() {
  if (currentUser.rol !== 'superadmin') return;

  const section = document.getElementById('aprobaciones-section');
  if (section) section.style.display = '';

  const content = document.getElementById('aprobaciones-content');
  if (!content) return;
  content.innerHTML = '<div style="text-align:center;padding:16px;color:var(--text-muted)">Cargando…</div>';

  const [{ data: solicitudes }, { data: acuerdos }] = await Promise.all([
    sb.from('pedidos').select('*').eq('estado', 'pendiente_revision').order('created_at'),
    sb.from('pedidos').select('*').eq('estado', 'pendiente_acuerdo').order('created_at'),
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

  // ── SOLICITUDES POR REVISAR ──────────────────────────
  html += `<div class="apr-bloque-title">📋 Solicitudes por revisar <span class="apr-count">${(solicitudes || []).length}</span></div>`;

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

  content.innerHTML = html;
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
