// ── MÓDULO PEDIDOS DE SERVICIO ─────────────────────────

let pedidoDetalle      = null;   // pedido abierto en modal
let ofertaDetalleId    = null;   // oferta en modal responder-contra
let pedidoParaOfertar  = null;   // pedido sobre el que el admin ofertará
let _pendingOferta     = null;   // oferta en espera de confirmar detalles
let _pendingPedido     = null;   // pedido en espera de confirmar detalles
let _filtroTipo        = 'todos';
let _filtroBusqueda    = '';

const TIPO_EMOJI = {
  Torton:'🚛', Rabón:'🚚', Full:'🚛', Plataforma:'🏗️', Cualquiera:'🚛',
  'Lavado Exterior':'🚿', 'Lavado Interior':'🚿', 'Lavado Completo':'🚿',
  'Lavado de Motor':'🚿', 'Desinfección':'🧴', 'Lavado Contenedor':'🚿',
};

// Tiempo restante antes de que expire una oferta
function fmtTiempoRestante(isoStr) {
  if (!isoStr) return '';
  const diff = new Date(isoStr) - Date.now();
  if (diff <= 0) return 'Expirada';
  const hrs = Math.floor(diff / 3600000);
  if (hrs < 1) return `Expira en ${Math.max(1, Math.floor(diff / 60000))} min`;
  if (hrs < 24) return `Expira en ${hrs} h`;
  const days = Math.floor(hrs / 24);
  return `Expira en ${days} día${days > 1 ? 's' : ''}`;
}

// ── RENDER PRINCIPAL ───────────────────────────────────

async function renderPedidos() {
  const container = document.getElementById('pedidos-list');
  container.innerHTML = skeletonList(3);

  // Botones de servicio: solo para clientes logueados
  const btnServ = document.getElementById('ped-serv-btns');
  if (btnServ) {
    btnServ.style.display = (currentUser.id && currentUser.rol === 'cliente') ? 'grid' : 'none';
  }
  // Barra de filtros: para cualquier usuario logueado
  const filtrosBar = document.getElementById('ped-filtros-bar');
  if (filtrosBar) filtrosBar.style.display = currentUser.id ? '' : 'none';

  // Fetch pedidos + ofertas en paralelo
  // Para clientes excluir acordado/cancelado directo en la query
  const esCliente = currentUser.id && currentUser.rol === 'cliente';
  let pedidosQ = sb.from('pedidos').select('*').order('created_at', { ascending: false });
  if (esCliente) pedidosQ = pedidosQ.not('estado', 'in', '("acordado","cancelado")');

  const [{ data: pedidos, error }, { data: todasOfertas }] = await Promise.all([
    pedidosQ,
    sb.from('ofertas').select('*').order('created_at', { ascending: true })
  ]);

  if (error) {
    container.innerHTML = `<div class="empty-state"><div class="icon">❌</div>Error al cargar solicitudes.</div>`;
    return;
  }

  // Mapear ofertas por pedido
  const ofertasMap = {};
  (todasOfertas || []).forEach(o => {
    if (!ofertasMap[o.pedido_id]) ofertasMap[o.pedido_id] = [];
    ofertasMap[o.pedido_id].push(o);
  });

  // Expiración lazy: marcar como rechazadas ofertas vencidas (fire-and-forget)
  const expiradas = (todasOfertas || []).filter(o =>
    o.estado === 'enviada' && o.expira_en && new Date(o.expira_en) < new Date()
  );
  if (expiradas.length) {
    sb.from('ofertas').update({ estado: 'rechazada' })
      .in('id', expiradas.map(o => o.id)).then(() => {});
  }

  const _filtrar = lista => {
    let r = lista;
    if (_filtroTipo !== 'todos') {
      r = r.filter(p => {
        const t = p.tipo_camion || '';
        if (_filtroTipo === 'camion')   return !t.startsWith('Lavado') && t !== 'Desinfección' && !t.startsWith('Custodio') && t !== 'Supervisión remota' && !t.startsWith('Patio') && t !== 'Bodega';
        if (_filtroTipo === 'custodio') return t.startsWith('Custodio') || t === 'Supervisión remota';
        if (_filtroTipo === 'patio')    return t.startsWith('Patio') || t === 'Bodega';
        if (_filtroTipo === 'lavado')   return t.startsWith('Lavado') || t === 'Desinfección';
        return true;
      });
    }
    if (_filtroBusqueda) {
      const q = _filtroBusqueda;
      r = r.filter(p => [p.tipo_camion, p.origen, p.destino, p.descripcion, p.cliente_nombre, p.tipo_carga]
        .some(v => v && v.toLowerCase().includes(q)));
    }
    return r;
  };

  let html = '';

  // ── CLIENTE ────────────────────────────────────────
  if (currentUser.id && currentUser.rol === 'cliente') {
    // Acordado y cancelado se mueven a reservaciones; no mostrar aquí
    const misPedidos   = _filtrar((pedidos || []).filter(p => p.cliente_id === currentUser.id && !['acordado','cancelado'].includes(p.estado)));
    const otrosPedidos = _filtrar((pedidos || []).filter(p => p.cliente_id !== currentUser.id && p.estado === 'abierto'));

    if (misPedidos.length) {
      html += `<div class="ped-seccion-title">Mis solicitudes</div>`;
      html += misPedidos.map(p => pedidoCardHTML(p, ofertasMap[p.id] || [], 'cliente')).join('');
    }
    if (otrosPedidos.length) {
      html += `<div class="ped-seccion-title">Otras solicitudes activas</div>`;
      html += otrosPedidos.map(p => pedidoCardHTML(p, ofertasMap[p.id] || [], 'publico')).join('');
    }
    if (!misPedidos.length && !otrosPedidos.length) {
      html = `<div class="empty-state"><div class="icon">📋</div>Sin solicitudes activas.<br><small style="color:var(--text-muted)">Publica la primera con el botón de arriba.</small></div>`;
    }

  // ── ADMIN / SUPERADMIN ─────────────────────────────
  } else if (currentUser.id && ['admin','superadmin'].includes(currentUser.rol)) {
    const misOfertaIds = new Set(
      (todasOfertas || []).filter(o => o.admin_id === currentUser.id).map(o => o.pedido_id)
    );

    // Pedidos donde tengo oferta activa (enviada o contra_oferta)
    const misNegociaciones = _filtrar((pedidos || []).filter(p =>
      (ofertasMap[p.id] || []).some(o => o.admin_id === currentUser.id && ['enviada','contra_oferta'].includes(o.estado))
    ));
    const misNegIds = new Set(misNegociaciones.map(p => p.id));

    // Pedidos abiertos donde aún no he ofertado
    const disponibles = _filtrar((pedidos || []).filter(p =>
      p.estado === 'abierto' && !misOfertaIds.has(p.id)
    ));

    if (misNegociaciones.length) {
      html += `<div class="ped-seccion-title">Mis negociaciones</div>`;
      html += misNegociaciones.map(p => {
        const mia = (ofertasMap[p.id] || []).find(o => o.admin_id === currentUser.id);
        return pedidoCardHTML(p, ofertasMap[p.id] || [], 'admin_propio', mia);
      }).join('');
    }
    if (disponibles.length) {
      html += `<div class="ped-seccion-title">${misNegociaciones.length ? 'Otras solicitudes disponibles' : 'Solicitudes disponibles'}</div>`;
      html += disponibles.map(p => pedidoCardHTML(p, ofertasMap[p.id] || [], 'admin')).join('');
    }
    if (!misNegociaciones.length && !disponibles.length) {
      html = `<div class="empty-state"><div class="icon">📋</div>No hay solicitudes abiertas en este momento.</div>`;
    }

  // ── PÚBLICO / GUEST ────────────────────────────────
  } else {
    const abiertos = (pedidos || []).filter(p => p.estado === 'abierto');
    if (abiertos.length) {
      html += abiertos.map(p => pedidoCardHTML(p, ofertasMap[p.id] || [], 'publico')).join('');
    } else {
      html = `<div class="empty-state"><div class="icon">📋</div>Sin solicitudes activas.<br><small>Inicia sesión como cliente para publicar una.</small></div>`;
    }
  }

  container.innerHTML = html ||
    `<div class="empty-state"><div class="icon">📋</div>Sin actividad.</div>`;
}

// ── CARD DE PEDIDO ─────────────────────────────────────

function pedidoCardHTML(p, ofertas, vista, miOferta = null) {
  const badgeCls = {
    abierto:         'badge-avail',
    en_negociacion:  'badge-busy',
    acordado:        'badge-acordado',
    cancelado:       'badge-maint',
  }[p.estado] || 'badge-maint';

  const ofertasVivaz   = ofertas.filter(o => o.estado !== 'rechazada');
  const estadoLabel = p.estado === 'abierto'
    ? (ofertasVivaz.length ? `${ofertasVivaz.length} oferta${ofertasVivaz.length > 1 ? 's' : ''}` : 'Sin ofertas aún')
    : p.estado === 'en_negociacion' ? 'En negociación'
    : p.estado === 'acordado'       ? '✓ Acordado'
    : p.estado === 'cancelado'      ? 'Cancelado'
    : p.estado;

  const ofertasVivas  = ofertasVivaz;
  const numOfertas    = ofertasVivas.length;
  const pendientes    = ofertas.filter(o => ['enviada','contra_oferta'].includes(o.estado));

  const precioBadge = p.precio_cliente
    ? `<span class="ped-precio">Ofrece: $${Number(p.precio_cliente).toLocaleString('es-MX')} MXN</span>`
    : '';

  const fechasTxt = p.fecha_ini
    ? `📅 ${fmtFecha(p.fecha_ini)}${p.fecha_fin && p.fecha_fin !== p.fecha_ini ? ' — ' + fmtFecha(p.fecha_fin) : ''}`
    : '';

  let acciones = '';

  if (vista === 'cliente' && p.estado !== 'cancelado') {
    acciones = `
      <button class="btn-ver-pedido" onclick="openPedidoDetalle('${p.id}')">
        Ver ofertas${pendientes.length ? `<span class="ped-badge-count">${pendientes.length}</span>` : ''}
      </button>
      ${p.estado === 'abierto'
        ? `<button class="btn-cancelar-ped" onclick="cancelarPedido('${p.id}')">Cancelar</button>`
        : ''}`;

  } else if (vista === 'admin') {
    acciones = `<button class="btn-ofertar" onclick="openHacerOferta('${p.id}')">Hacer oferta</button>`;

  } else if (vista === 'admin_propio' && miOferta) {
    const st = miOferta.estado;
    const etq = st === 'enviada'      ? 'Esperando respuesta'
              : st === 'contra_oferta' ? `Contraoferta: $${Number(miOferta.contra_precio).toLocaleString('es-MX')}`
              : st === 'aceptada'      ? '✓ Aceptada'
              : 'Rechazada';
    const bdg = st === 'aceptada' ? 'badge-avail' : st === 'rechazada' ? 'badge-maint' : 'badge-busy';
    const chatAdminBtn = (p.cliente_id && st !== 'rechazada')
      ? `<button class="btn-chat-hilo" onclick="openChatPedido('${p.id}','${p.cliente_id}','${esc(p.cliente_nombre||'')}')">💬 Chat</button>`
      : '';
    acciones = `
      <span class="badge ${bdg}" style="font-size:0.72rem">${etq}</span>
      ${st === 'contra_oferta'
        ? `<button class="btn-ofertar" onclick="openResponderContra('${miOferta.id}')">Responder</button>`
        : ''}
      ${chatAdminBtn}`;
  }

  // Superadmin puede eliminar cualquier pedido
  const btnEliminar = currentUser.rol === 'superadmin'
    ? `<button class="btn-edit btn-rechazar" style="font-size:0.72rem" onclick="eliminarPedido('${p.id}')">🗑 Eliminar</button>`
    : '';

  // Chips de detalles extra según tipo
  const esLavadoCard   = p.tipo_camion?.startsWith('Lavado') || p.tipo_camion === 'Desinfección';
  const esCustodioCard = p.tipo_camion?.startsWith('Custodio') || p.tipo_camion === 'Supervisión remota';
  const esPatioCard    = p.tipo_camion?.startsWith('Patio') || p.tipo_camion === 'Bodega';
  const esCamionCard   = !esLavadoCard && !esCustodioCard && !esPatioCard;

  const chips = [];
  if (esCamionCard) {
    if (p.tipo_carga)    chips.push(`📦 ${esc(p.tipo_carga)}`);
    if (p.peso_carga)    chips.push(`⚖️ ${p.peso_carga} ton`);
    if (p.capacidad_min) chips.push(`🚛 Mín ${p.capacidad_min} ton`);
    if (p.carga_peligrosa)  chips.push('⚠️ Peligrosa');
    if (p.temp_controlada)  chips.push('❄️ Temp. controlada');
    if (p.requiere_seguro)  chips.push('🛡️ Seguro');
    if (p.requiere_factura) chips.push('🧾 Factura');
  } else if (esCustodioCard) {
    if (p.num_custodios)    chips.push(`👮 x${p.num_custodios}`);
    if (p.zona_cobertura)   chips.push(`📍 ${esc(p.zona_cobertura)}`);
    if (p.horario_servicio) chips.push(`🕐 ${esc(p.horario_servicio)}`);
  } else if (esLavadoCard) {
    if (p.tipo_vehiculos)   chips.push(`🚛 ${esc(p.tipo_vehiculos)}`);
    if (p.num_vehiculos)    chips.push(`x${p.num_vehiculos} vehículos`);
    if (p.origen)           chips.push(`📍 ${esc(p.origen)}`);
    if (p.horario_servicio) chips.push(`🕐 ${esc(p.horario_servicio)}`);
  } else {
    if (p.num_vehiculos)  chips.push(`🚗 ${p.num_vehiculos} vehículos`);
    if (p.area_necesaria) chips.push(`📐 ${p.area_necesaria} m²`);
    if (p.tipo_vehiculos) chips.push(esc(p.tipo_vehiculos));
  }
  const chipsHTML = chips.length
    ? `<div class="pedido-chips">${chips.map(c => `<span class="cargo-chip">${c}</span>`).join('')}</div>` : '';

  return `
    <div class="pedido-card" id="ped-${p.id}">
      <div class="pedido-top">
        <div class="pedido-info">
          <div class="pedido-tipo">${TIPO_EMOJI[p.tipo_camion] || '🚛'} ${esc(p.tipo_camion)}</div>
          ${p.origen || p.destino
            ? `<div class="pedido-ruta">📍 ${esc(p.origen || '—')}${p.destino ? ' → ' + esc(p.destino) : ''}</div>` : ''}
          ${fechasTxt ? `<div class="pedido-fecha">${fechasTxt}</div>` : ''}
        </div>
        <span class="badge ${badgeCls}">${estadoLabel}</span>
      </div>
      ${chipsHTML}
      ${p.descripcion ? `<div class="pedido-desc">${esc(p.descripcion)}</div>` : ''}
      <div class="pedido-footer">
        <div style="display:flex;gap:10px;align-items:center;flex-wrap:wrap">
          ${precioBadge}
          ${numOfertas ? `<span class="ped-num-ofertas">${numOfertas} ${numOfertas === 1 ? 'oferta' : 'ofertas'}</span>` : ''}
          <span class="ped-cliente">👤 ${esc(p.cliente_nombre)}</span>
        </div>
        <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">
          ${acciones}
          ${btnEliminar}
        </div>
      </div>
    </div>`;
}

// ── CREAR PEDIDO ───────────────────────────────────────

function actualizarSubtipoPedido() {
  const val = document.getElementById('np-tipo')?.value || '';
  const esLavado   = val.startsWith('Lavado') || val === 'Desinfección';
  const esCustodio = val.startsWith('Custodio') || val === 'Supervisión remota';
  const esPatio    = val.startsWith('Patio') || val === 'Bodega';
  const esCamion   = !esLavado && !esCustodio && !esPatio;

  const g = id => document.getElementById(id);
  if (g('np-group-camion'))   g('np-group-camion').style.display   = esCamion   ? '' : 'none';
  if (g('np-group-custodio')) g('np-group-custodio').style.display = esCustodio ? '' : 'none';
  if (g('np-group-patio'))    g('np-group-patio').style.display    = esPatio    ? '' : 'none';
  if (g('np-group-lavado'))   g('np-group-lavado').style.display   = esLavado   ? '' : 'none';
}

function openNuevoPedido(servicio) {
  if (!currentUser.id) { showLoginOverlay(); return; }

  // Pre-seleccionar el tipo según el botón pulsado
  const select = document.getElementById('np-tipo');
  if (select && servicio) {
    const mapPrimero = {
      camion:   'Cualquiera',
      custodio: 'Custodio Armado',
      patio:    'Patio Techado',
      lavado:   'Lavado Exterior',
    };
    if (mapPrimero[servicio]) select.value = mapPrimero[servicio];
    actualizarSubtipoPedido();
  }

  document.getElementById('modal-nuevo-pedido').classList.add('open');
}
function closeNuevoPedido() {
  document.getElementById('modal-nuevo-pedido').classList.remove('open');
}

async function crearPedido() {
  const v    = id => document.getElementById(id)?.value?.trim() || '';
  const vb   = id => document.getElementById(id)?.checked || false;
  const vn   = id => parseFloat(document.getElementById(id)?.value) || null;
  const vi   = id => parseInt(document.getElementById(id)?.value) || null;

  const tipo = document.getElementById('np-tipo').value;
  const esLavado   = tipo.startsWith('Lavado') || tipo === 'Desinfección';
  const esCustodio = tipo.startsWith('Custodio') || tipo === 'Supervisión remota';
  const esPatio    = tipo.startsWith('Patio') || tipo === 'Bodega';
  const esCamion   = !esLavado && !esCustodio && !esPatio;

  // Validaciones por tipo
  if (esCamion) {
    if (!v('np-origen') || !v('np-carga') || !v('np-fecha-ini')) {
      alert('Por favor completa: tipo de carga, origen y fecha de carga.'); return;
    }
  } else if (esCustodio) {
    if (!v('np-zona') || !v('np-fecha-ini-cust')) {
      alert('Por favor completa: zona de cobertura y fecha de inicio.'); return;
    }
  } else if (esPatio) {
    if (!v('np-fecha-ini-patio')) {
      alert('Por favor completa la fecha de entrada.'); return;
    }
  } else if (esLavado) {
    if (!v('np-vehiculo-lavar') || !v('np-ubic-lav') || !v('np-fecha-ini-lav')) {
      alert('Por favor completa: tipo de vehículo, ubicación y fecha requerida.'); return;
    }
  }

  // Fechas por tipo
  const fechaIni = esCamion ? v('np-fecha-ini')
    : esCustodio ? v('np-fecha-ini-cust')
    : esPatio    ? v('np-fecha-ini-patio')
    :              v('np-fecha-ini-lav');
  const fechaFin = esCamion ? v('np-fecha-fin')
    : esCustodio ? v('np-fecha-fin-cust')
    : esPatio    ? v('np-fecha-fin-patio')
    :              null;

  const payload = {
    cliente_id:     currentUser.id,
    cliente_nombre: currentUser.nombre,
    cliente_email:  currentUser.email,
    tipo_camion:    tipo,
    descripcion:    v('np-desc')   || null,
    precio_cliente: vn('np-precio'),
    fecha_ini:      fechaIni       || null,
    fecha_fin:      fechaFin       || null,
    // Camión
    origen:           esCamion ? v('np-origen')  : esPatio ? v('np-origen') : esLavado ? v('np-ubic-lav') : null,
    destino:          esCamion ? v('np-destino') : null,
    capacidad_min:    esCamion ? vi('np-cap')    : null,
    tipo_carga:       esCamion ? v('np-carga')   : null,
    peso_carga:       esCamion ? vn('np-peso')   : null,
    num_bultos:       esCamion ? vi('np-bultos') : null,
    hora_carga:       esCamion ? v('np-hora')    : null,
    contacto_nombre:  esCamion ? v('np-contacto-nombre') : null,
    contacto_tel:     esCamion ? v('np-contacto-tel')    : null,
    carga_peligrosa:  esCamion ? vb('np-peligrosa')      : false,
    temp_controlada:  esCamion ? vb('np-temp')           : false,
    requiere_seguro:  esCamion ? vb('np-seguro')         : false,
    requiere_factura: esCamion ? vb('np-factura')        : false,
    // Custodio
    num_custodios:    esCustodio ? vi('np-num-custodios') : null,
    zona_cobertura:   esCustodio ? v('np-zona')           : null,
    horario_servicio: esCustodio ? v('np-horario') : esLavado ? v('np-horario-lav') : null,
    // Patio
    num_vehiculos:   esPatio ? vi('np-num-vehiculos')  : esLavado ? vi('np-num-vehiculos-lav') : null,
    tipo_vehiculos:  esPatio ? v('np-tipo-vehiculos')  : esLavado ? v('np-vehiculo-lavar')     : null,
    area_necesaria:  esPatio ? vn('np-area')           : null,
  };

  const { error } = await sb.from('pedidos').insert(payload);
  if (error) { showToast('Error al publicar: ' + (error.message || '')); return; }

  // Notificar a todos los admins de la nueva solicitud
  const { data: admins } = await sb.from('perfiles').select('user_id').in('rol', ['admin', 'superadmin']);
  if (admins?.length) {
    await sb.from('notificaciones').insert(admins.map(a => ({
      user_id: a.user_id,
      tipo:    'nueva_solicitud',
      titulo:  'Nueva solicitud publicada',
      mensaje: `Un cliente publicó una solicitud de ${tipo}. Revisa las solicitudes disponibles.`,
      leido:   false,
    })));
  }

  closeNuevoPedido();
  // Limpiar todos los campos del formulario
  document.getElementById('modal-nuevo-pedido').querySelectorAll('input, textarea, select').forEach(el => {
    if (el.type === 'checkbox') el.checked = false;
    else if (el.tagName !== 'SELECT') el.value = '';
  });
  actualizarSubtipoPedido();

  await renderPedidos();
  showToast('✓ Solicitud publicada — los proveedores ya pueden verte');
}

// ── DETALLE PEDIDO (cliente ve y responde ofertas) ─────

async function openPedidoDetalle(pedidoId) {
  const [{ data: p }, { data: ofertas }] = await Promise.all([
    sb.from('pedidos').select('*').eq('id', pedidoId).single(),
    sb.from('ofertas').select('*').eq('pedido_id', pedidoId).order('created_at', { ascending: false })
  ]);
  pedidoDetalle = p;

  document.getElementById('pedido-detalle-titulo').textContent =
    `${TIPO_EMOJI[p.tipo_camion] || '🚛'} ${p.tipo_camion}`;
  document.getElementById('pedido-detalle-sub').textContent =
    `${p.origen} → ${p.destino} · ${fmtFecha(p.fecha_ini)}`;

  const body = document.getElementById('pedido-detalle-body');
  const lista = ofertas || [];

  if (!lista.length) {
    body.innerHTML = `<div class="empty-state" style="padding:20px 0"><div class="icon">🕐</div>Aún no has recibido ofertas.</div>`;
  } else {
    body.innerHTML = lista.map(o => ofertaItemHTML(o)).join('');
  }

  document.getElementById('modal-pedido-detalle').classList.add('open');
}

function closePedidoDetalle() {
  document.getElementById('modal-pedido-detalle').classList.remove('open');
  pedidoDetalle = null;
}

// ── HTML DE OFERTA INDIVIDUAL ──────────────────────────

function ofertaItemHTML(o) {
  const expirada = o.estado === 'enviada' && o.expira_en && new Date(o.expira_en) < new Date();
  const estadoCls = o.estado === 'aceptada' ? 'badge-avail'
                  : (o.estado === 'rechazada' || expirada) ? 'badge-maint'
                  : 'badge-busy';
  const estadoLbl = expirada ? 'Expirada'
                  : {
    enviada:       'Oferta enviada',
    contra_oferta: 'Tu contraoferta pendiente',
    aceptada:      '✓ Aceptada',
    rechazada:     'Rechazada',
  }[o.estado] || o.estado;

  const tiempoRestante = (!expirada && o.estado === 'enviada' && o.expira_en)
    ? `<span style="font-size:0.7rem;color:var(--text-muted);display:block;margin-top:3px">${fmtTiempoRestante(o.expira_en)}</span>`
    : '';

  const fmt = num => `$${Number(num).toLocaleString('es-MX')} MXN`;

  // Botón de chat con el admin que ofertó (solo cliente)
  const chatOfertaBtn = (currentUser.rol === 'cliente' && o.admin_id && o.estado !== 'rechazada')
    ? `<button class="btn-chat-hilo" onclick="openChatPedido('${o.pedido_id}','${o.admin_id}','${esc(o.admin_nombre||'')}')">💬 Chat</button>`
    : '';

  let acciones = '';
  if (o.estado === 'enviada' && !expirada) {
    acciones = `
      <div class="oferta-acciones">
        <button class="btn-edit btn-aprobar" onclick="responderOferta('${o.id}','aceptar')">
          ✓ Aceptar ${fmt(o.precio_oferta)}
        </button>
        <button class="btn-edit" onclick="abrirContraoferta('${o.id}')">↩ Contraofertar</button>
        <button class="btn-edit btn-rechazar" onclick="responderOferta('${o.id}','rechazar')">✕ Rechazar</button>
        ${chatOfertaBtn}
      </div>`;
  } else if (o.estado === 'contra_oferta') {
    acciones = `<div class="oferta-acciones"><span style="font-size:0.78rem;color:var(--text-muted)">Esperando respuesta del proveedor…</span>${chatOfertaBtn}</div>`;
  }

  return `
    <div class="oferta-item" id="of-${o.id}">
      <div class="oferta-top">
        <div>
          <div class="oferta-empresa oferta-empresa-link" onclick="openEmpresaPerfil('${esc(o.admin_id||'')}','${esc(o.admin_nombre||'')}')">
            ${esc(o.admin_nombre)}<span class="oferta-ver-link"> Ver →</span>
          </div>
          ${o.camion_id ? `<div class="oferta-camion">🚛 ${esc(o.camion_id)}</div>` : ''}
        </div>
        <div style="text-align:right">
          <div class="oferta-precio">${fmt(o.precio_oferta)}</div>
          <span class="badge ${estadoCls}" style="font-size:0.7rem;margin-top:4px;display:inline-block">${estadoLbl}</span>
          ${tiempoRestante}
        </div>
      </div>
      ${o.mensaje ? `<div class="oferta-msg">"${esc(o.mensaje)}"</div>` : ''}
      ${o.contra_precio ? `
        <div class="oferta-contra">
          <span class="oferta-contra-label">Tu contraoferta</span>
          <strong>${fmt(o.contra_precio)}</strong>
          ${o.contra_mensaje ? `<span class="oferta-msg" style="margin-top:4px">"${esc(o.contra_mensaje)}"</span>` : ''}
        </div>` : ''}
      ${acciones}
      <div class="oferta-contra-form" id="contra-form-${o.id}" style="display:none;margin-top:12px">
        <div class="form-group" style="margin-bottom:10px">
          <label>Tu precio (MXN)</label>
          <input type="number" id="contra-precio-${o.id}" placeholder="Ej. 7500">
        </div>
        <div class="form-group" style="margin-bottom:10px">
          <label>Mensaje <span style="font-weight:400;color:var(--text-muted)">(opcional)</span></label>
          <input type="text" id="contra-msg-${o.id}" placeholder="Ej. Precio máximo que puedo ofrecer">
        </div>
        <div style="display:flex;gap:8px">
          <button class="btn-confirm" style="flex:2;padding:8px" onclick="enviarContraoferta('${o.id}')">Enviar contraoferta</button>
          <button class="btn-cancel"  style="flex:1;padding:8px" onclick="cerrarContraoferta('${o.id}')">Cancelar</button>
        </div>
      </div>
    </div>`;
}

function abrirContraoferta(ofertaId) {
  document.getElementById(`contra-form-${ofertaId}`).style.display = 'block';
  document.getElementById(`contra-precio-${ofertaId}`)?.focus();
}
function cerrarContraoferta(ofertaId) {
  document.getElementById(`contra-form-${ofertaId}`).style.display = 'none';
}

async function responderOferta(ofertaId, accion) {
  if (accion === 'aceptar') {
    // Abrir modal de detalles del servicio antes de cerrar el acuerdo
    const { data: oferta } = await sb.from('ofertas').select('*').eq('id', ofertaId).single();
    if (!oferta || !pedidoDetalle) { showToast('Error al cargar la oferta'); return; }
    _openDetallesServicio(oferta, pedidoDetalle);
    return;
  }
  // Rechazar
  const { error } = await sb.from('ofertas').update({ estado: 'rechazada' }).eq('id', ofertaId);
  if (error) { showToast('Error al procesar'); return; }
  await loadNotificaciones();
  if (pedidoDetalle) await openPedidoDetalle(pedidoDetalle.id);
  await renderPedidos();
  showToast('Oferta declinada');
}

function _openDetallesServicio(oferta, pedido) {
  try {
    _pendingOferta = oferta;
    _pendingPedido = pedido;
    // Cerrar el modal de detalle (mismo z-index) antes de abrir el nuevo
    document.getElementById('modal-pedido-detalle').classList.remove('open');
    const fmt = n => `$${Number(n).toLocaleString('es-MX')} MXN`;
    document.getElementById('ds-resumen').textContent =
      `Acuerdo con ${oferta.admin_nombre} · ${fmt(oferta.precio_oferta)} · ${pedido.tipo_camion}`;
    document.getElementById('ds-fecha').value           = (pedido.fecha_ini || '').split('T')[0];
    document.getElementById('ds-hora').value            = pedido.hora_carga || '';
    document.getElementById('ds-lugar').value           = pedido.detalles_lugar || pedido.origen || '';
    document.getElementById('ds-contacto-nombre').value = pedido.detalles_contacto_nombre || pedido.contacto_nombre || '';
    document.getElementById('ds-contacto-tel').value    = pedido.detalles_contacto_tel || pedido.contacto_tel || '';
    document.getElementById('modal-detalles-servicio').classList.add('open');
  } catch (e) {
    console.error('_openDetallesServicio error:', e);
    showToast('Error al abrir el formulario de detalles: ' + e.message, 'error');
  }
}

function closeDetallesServicio() {
  document.getElementById('modal-detalles-servicio').classList.remove('open');
  // Reabrir el detalle del pedido si el usuario canceló
  if (_pendingPedido) openPedidoDetalle(_pendingPedido.id);
  _pendingOferta = null;
  _pendingPedido = null;
}

async function confirmarDetallesServicio() {
  if (!_pendingOferta || !_pendingPedido) return;
  const v = id => document.getElementById(id)?.value?.trim() || '';
  const fecha = v('ds-fecha');
  const lugar = v('ds-lugar');
  if (!fecha || !lugar) { alert('Por favor completa la fecha y la dirección del servicio.'); return; }

  const oferta = _pendingOferta;
  const pedido = _pendingPedido;

  // Guardar detalles en el pedido
  await sb.from('pedidos').update({
    detalles_lugar:           lugar,
    detalles_hora:            v('ds-hora') || null,
    detalles_contacto_nombre: v('ds-contacto-nombre') || null,
    detalles_contacto_tel:    v('ds-contacto-tel') || null,
    detalles_completados:     true,
    fecha_ini:                fecha,
  }).eq('id', pedido.id);

  // Marcar oferta como aceptada
  await sb.from('ofertas').update({ estado: 'aceptada' }).eq('id', oferta.id);

  // Limpiar pendientes antes de cerrar para que closeDetallesServicio no reabra
  _pendingOferta = null;
  _pendingPedido = null;
  document.getElementById('modal-detalles-servicio').classList.remove('open');

  await cerrarAcuerdo(oferta, { ...pedido, fecha_ini: fecha });
  await loadNotificaciones();
  closePedidoDetalle();
  await renderPedidos();
  showToast('✓ ¡Acuerdo cerrado! Reservación creada');
}

async function enviarContraoferta(ofertaId) {
  const precio = parseFloat(document.getElementById(`contra-precio-${ofertaId}`).value);
  const msg    = document.getElementById(`contra-msg-${ofertaId}`).value.trim();
  if (!precio || precio <= 0) { alert('Ingresa un precio válido.'); return; }
  if (precio <= 0) return;

  const { error } = await sb.from('ofertas').update({
    contra_precio:  precio,
    contra_mensaje: msg || null,
    ronda:          2,
    estado:         'contra_oferta',
  }).eq('id', ofertaId);
  if (error) { showToast('Error al enviar contraoferta'); return; }

  if (pedidoDetalle) {
    await sb.from('pedidos').update({ estado: 'en_negociacion' }).eq('id', pedidoDetalle.id);
    await openPedidoDetalle(pedidoDetalle.id);
  }
  await renderPedidos();
  await loadNotificaciones();
  showToast('↩ Contraoferta enviada al proveedor');
}

// ── HACER OFERTA (admin) ───────────────────────────────

async function openHacerOferta(pedidoId) {
  if (!currentUser.id) { showLoginOverlay(); return; }
  pedidoParaOfertar = pedidoId;

  const select = document.getElementById('ho-camion');
  const label  = document.getElementById('ho-recurso-label');
  const warn   = document.getElementById('ho-sin-recursos');
  const btnEnv = document.getElementById('btn-enviar-oferta');

  select.innerHTML = '<option value="">Cargando…</option>';
  if (warn)   { warn.style.display = 'none'; warn.textContent = ''; }
  if (btnEnv) btnEnv.disabled = false;

  // Leer el pedido para saber qué tipo de recurso se solicita
  const { data: pedido } = await sb.from('pedidos').select('tipo_camion').eq('id', pedidoId).single();
  const tipo = pedido?.tipo_camion || '';

  const esCustodio = tipo.startsWith('Custodio') || tipo === 'Supervisión remota';
  const esPatio    = tipo.startsWith('Patio')    || tipo === 'Bodega';

  let recursos = [];
  let sinRecursosMsg = '';

  if (esCustodio) {
    if (label) label.textContent = 'Custodio que asignas *';
    let q = sb.from('custodios').select('*').eq('estado', 'disponible');
    if (currentUser.rol !== 'superadmin') q = q.eq('propietario_id', currentUser.id);
    const { data } = await q;
    recursos = data || [];
    sinRecursosMsg = '⚠ No tienes custodios disponibles registrados. Agrega uno en el panel Admin → Custodios antes de ofertar.';

    select.innerHTML = recursos.length
      ? `<option value="">— Selecciona un custodio —</option>`
      : `<option value="">Sin custodios disponibles</option>`;
    recursos.forEach(c => {
      const opt = document.createElement('option');
      opt.value       = c.id;
      opt.textContent = `${CUSTODIO_EMOJI[c.tipo] || '👮'} ${c.id} — ${c.nombre} (${c.tipo})`;
      select.appendChild(opt);
    });

  } else if (esPatio) {
    if (label) label.textContent = 'Patio que asignas *';
    let q = sb.from('patios').select('*').eq('estado', 'disponible');
    if (currentUser.rol !== 'superadmin') q = q.eq('propietario_id', currentUser.id);
    const { data } = await q;
    recursos = data || [];
    sinRecursosMsg = '⚠ No tienes patios disponibles registrados. Agrega uno en el panel Admin → Patios antes de ofertar.';

    select.innerHTML = recursos.length
      ? `<option value="">— Selecciona un patio —</option>`
      : `<option value="">Sin patios disponibles</option>`;
    recursos.forEach(p => {
      const opt = document.createElement('option');
      opt.value       = p.id;
      opt.textContent = `${PATIO_EMOJI[p.tipo] || '🏭'} ${p.id} — ${p.nombre} (${p.tipo})`;
      select.appendChild(opt);
    });

  } else {
    // Camión — query directo igual que custodios/patios
    if (label) label.textContent = 'Camión que asignas';
    let q = sb.from('camiones').select('*').eq('estado', 'disponible');
    if (currentUser.rol !== 'superadmin') q = q.eq('propietario_id', currentUser.id);
    const { data: camionesData } = await q;
    recursos = camionesData || [];
    sinRecursosMsg = '⚠ No tienes camiones disponibles. Verifica el estado de tus unidades en el panel Admin.';

    const CAMION_EMOJI = { Torton:'🚛', Rabón:'🚚', Full:'🚛', Plataforma:'🏗️' };
    select.innerHTML = recursos.length
      ? `<option value="">— Selecciona un camión —</option>`
      : `<option value="">Sin camiones disponibles</option>`;
    recursos.forEach(c => {
      const opt = document.createElement('option');
      opt.value       = c.id;
      opt.textContent = `${CAMION_EMOJI[c.tipo] || '🚛'} ${c.id} — ${c.tipo} (${c.capacidad} ton)`;
      select.appendChild(opt);
    });
  }

  // Si no hay recursos del tipo requerido, mostrar advertencia y bloquear envío
  if (!recursos.length && sinRecursosMsg) {
    if (warn)   { warn.textContent = sinRecursosMsg; warn.style.display = 'block'; }
    if (btnEnv) btnEnv.disabled = true;
  }

  document.getElementById('ho-precio').value  = '';
  document.getElementById('ho-mensaje').value = '';
  document.getElementById('modal-hacer-oferta').classList.add('open');
}
function closeHacerOferta() {
  document.getElementById('modal-hacer-oferta').classList.remove('open');
  pedidoParaOfertar = null;
}

async function enviarOferta() {
  const precio  = parseFloat(document.getElementById('ho-precio').value);
  const camion  = document.getElementById('ho-camion').value || null;
  const mensaje = document.getElementById('ho-mensaje').value.trim();
  if (!precio || precio <= 0) { alert('Ingresa un precio válido.'); return; }

  const { error } = await sb.from('ofertas').insert({
    pedido_id:     pedidoParaOfertar,
    admin_id:      currentUser.id,
    admin_nombre:  currentUser.nombre,
    camion_id:     camion,
    precio_oferta: precio,
    mensaje:       mensaje || null,
  });
  if (error) { showToast('Error al enviar: ' + (error.message || '')); return; }

  // Marcar pedido en negociación
  await sb.from('pedidos').update({ estado: 'en_negociacion' }).eq('id', pedidoParaOfertar);

  closeHacerOferta();
  await renderPedidos();
  await loadNotificaciones();
  showToast('✓ Oferta enviada al cliente');
}

// ── RESPONDER CONTRAOFERTA (admin) ─────────────────────

async function openResponderContra(ofertaId) {
  ofertaDetalleId = ofertaId;
  const { data: o } = await sb.from('ofertas').select('*').eq('id', ofertaId).single();
  const infoEl = document.getElementById('contra-detalle-info');
  if (infoEl && o) {
    const fmt = num => `$${Number(num).toLocaleString('es-MX')} MXN`;
    infoEl.innerHTML = `
      <div style="margin-bottom:6px"><strong>Tu oferta original:</strong> ${fmt(o.precio_oferta)}</div>
      <div><strong>Contraoferta del cliente:</strong> <span style="color:var(--amber);font-weight:700">${fmt(o.contra_precio)}</span></div>
      ${o.contra_mensaje ? `<div style="margin-top:6px;font-style:italic;color:var(--text-muted)">"${esc(o.contra_mensaje)}"</div>` : ''}`;
  }
  document.getElementById('modal-responder-contra').classList.add('open');
}
function closeResponderContra() {
  document.getElementById('modal-responder-contra').classList.remove('open');
  ofertaDetalleId = null;
}

async function responderContra(accion) {
  if (!ofertaDetalleId) return;
  const nuevo = accion === 'aceptar' ? 'aceptada' : 'rechazada';

  const { data: oferta } = await sb.from('ofertas').select('*').eq('id', ofertaDetalleId).single();
  const { error } = await sb.from('ofertas').update({ estado: nuevo }).eq('id', ofertaDetalleId);
  if (error) { showToast('Error'); return; }

  if (accion === 'aceptar' && oferta) {
    const { data: pedido } = await sb.from('pedidos').select('*').eq('id', oferta.pedido_id).single();
    // Usar precio de la contraoferta del cliente como precio final
    if (pedido) await cerrarAcuerdo({ ...oferta, precio_oferta: oferta.contra_precio }, pedido);
  }

  closeResponderContra();
  await renderPedidos();
  await loadNotificaciones();
  showToast(accion === 'aceptar' ? '✓ Acuerdo confirmado — reservación creada' : 'Contraoferta rechazada');
}

// ── CERRAR ACUERDO → CREAR RESERVACIÓN ────────────────

async function cerrarAcuerdo(oferta, pedido) {
  // Obtener las otras ofertas activas ANTES de rechazarlas (para notificar)
  const { data: otrasOfertas } = await sb.from('ofertas')
    .select('id, admin_id, admin_nombre')
    .eq('pedido_id', pedido.id)
    .neq('id', oferta.id)
    .in('estado', ['enviada','contra_oferta']);

  // Rechazar todas las demás ofertas pendientes del pedido
  if (otrasOfertas?.length) {
    await sb.from('ofertas')
      .update({ estado: 'rechazada' })
      .in('id', otrasOfertas.map(o => o.id));

    // Notificar a cada admin cuya oferta quedó rechazada
    const notifs = otrasOfertas.map(o => ({
      user_id: o.admin_id,
      tipo:    'oferta_no_seleccionada',
      titulo:  'Tu oferta no fue seleccionada',
      mensaje: `El cliente eligió otro proveedor para su solicitud de ${esc(pedido.tipo_camion || 'servicio')} (${esc(pedido.origen || '')}${pedido.destino ? ' → ' + esc(pedido.destino) : ''}). Gracias por participar.`,
      leido:   false,
    }));
    await sb.from('notificaciones').insert(notifs);
  }

  // Marcar pedido como acordado
  await sb.from('pedidos').update({ estado: 'acordado' }).eq('id', pedido.id);

  // Detectar tipo de recurso del pedido para guardarlo en la reservación
  const tipoPedido = pedido.tipo_camion || '';
  const recursoTipo = tipoPedido.startsWith('Custodio') || tipoPedido === 'Supervisión remota'
    ? 'custodio'
    : tipoPedido.startsWith('Patio') || tipoPedido === 'Bodega'
      ? 'patio'
      : 'camion';

  // Crear reservación automáticamente
  const { error } = await sb.from('reservaciones').insert({
    unidad:          oferta.camion_id || null,
    recurso_tipo:    recursoTipo,
    cliente:         pedido.cliente_nombre,
    cliente_email:   pedido.cliente_email,
    cliente_user_id: pedido.cliente_id,
    propietario_id:  oferta.admin_id,
    fecha_ini:       pedido.fecha_ini,
    fecha_fin:       pedido.fecha_fin || pedido.fecha_ini,
    descripcion:     pedido.descripcion,
    estado:          'Activa',
    precio_acordado: oferta.precio_oferta,
  });
  if (error) console.error('Error creando reservación desde pedido:', error);

  // Marcar camión como ocupado solo si la reserva ya inició (solo aplica a camiones)
  if (recursoTipo === 'camion' && oferta.camion_id && pedido.fecha_ini <= today()) {
    await sb.from('camiones').update({ estado: 'ocupado' }).eq('id', oferta.camion_id);
  }
}

// ── CANCELAR PEDIDO ────────────────────────────────────

async function cancelarPedido(pedidoId) {
  if (!confirm('¿Cancelar esta solicitud? Las ofertas activas quedarán descartadas.')) return;
  await sb.from('pedidos').update({ estado: 'cancelado' }).eq('id', pedidoId);
  await renderPedidos();
  showToast('Pedido cancelado');
}

// ── ELIMINAR PEDIDO (superadmin) ───────────────────────

async function eliminarPedido(pedidoId) {
  if (!confirm('¿Eliminar esta solicitud permanentemente? Esta acción no se puede deshacer.')) return;
  // Eliminar ofertas asociadas primero (si RLS lo requiere)
  await sb.from('ofertas').delete().eq('pedido_id', pedidoId);
  const { error } = await sb.from('pedidos').delete().eq('id', pedidoId);
  if (error) { showToast('Error al eliminar: ' + (error.message || '')); return; }
  document.getElementById(`ped-${pedidoId}`)?.remove();
  showToast('🗑 Pedido eliminado');
}

// ── PERFIL DE EMPRESA (desde oferta) ──────────────────

async function openEmpresaPerfil(adminId, adminNombre) {
  if (!adminId) return;
  const titulo = document.getElementById('ep-titulo');
  const body   = document.getElementById('ep-body');
  if (titulo) titulo.textContent = adminNombre || 'Empresa';
  if (body)   body.innerHTML = '<div style="text-align:center;padding:20px;color:var(--text-muted)">Cargando…</div>';
  document.getElementById('modal-empresa-perfil').classList.add('open');

  const [
    { data: perfil },
    { data: camiones },
    { data: custodios },
    { data: patios },
    { data: lavados },
    { data: cals }
  ] = await Promise.all([
    sb.from('perfiles').select('descripcion, nombre').eq('user_id', adminId).single(),
    sb.from('camiones').select('id, estado').eq('propietario_id', adminId),
    sb.from('custodios').select('id, estado').eq('propietario_id', adminId),
    sb.from('patios').select('id, estado').eq('propietario_id', adminId),
    sb.from('lavados').select('id').eq('propietario_id', adminId),
    sb.from('calificaciones').select('rating').eq('admin_id', adminId),
  ]);

  const avgRating = cals?.length
    ? (cals.reduce((s, c) => s + c.rating, 0) / cals.length).toFixed(1)
    : null;

  const starsHTML = avgRating
    ? `<div class="ep-stars">
        <span style="color:#f59e0b;font-size:1.1rem">${'★'.repeat(Math.round(+avgRating))}${'☆'.repeat(5 - Math.round(+avgRating))}</span>
        <span style="color:var(--text-muted);font-size:0.8rem"> ${avgRating} · ${cals.length} reseña${cals.length !== 1 ? 's' : ''}</span>
       </div>`
    : '<div style="color:var(--text-muted);font-size:0.82rem;margin-bottom:12px">Sin calificaciones aún</div>';

  const recursos = [];
  const disp = arr => arr?.filter(x => x.estado === 'disponible').length ?? 0;
  if (camiones?.length)  recursos.push(`🚛 ${camiones.length} camión${camiones.length > 1 ? 'es' : ''} — ${disp(camiones)} disponible${disp(camiones) !== 1 ? 's' : ''}`);
  if (custodios?.length) recursos.push(`👮 ${custodios.length} custodio${custodios.length > 1 ? 's' : ''} — ${disp(custodios)} disponible${disp(custodios) !== 1 ? 's' : ''}`);
  if (patios?.length)    recursos.push(`🏭 ${patios.length} patio${patios.length > 1 ? 's' : ''} — ${disp(patios)} disponible${disp(patios) !== 1 ? 's' : ''}`);
  if (lavados?.length)   recursos.push(`🚿 ${lavados.length} servicio${lavados.length > 1 ? 's' : ''} de lavado`);

  if (body) body.innerHTML = `
    <div style="padding:4px 0">
      ${starsHTML}
      ${perfil?.descripcion ? `<p style="color:var(--text-muted);font-size:0.85rem;margin-bottom:14px">${esc(perfil.descripcion)}</p>` : ''}
      <div style="display:flex;flex-direction:column;gap:6px">
        ${recursos.map(r => `<div class="ep-recurso-row">${r}</div>`).join('')}
        ${!recursos.length ? '<div style="color:var(--text-muted);font-size:0.85rem">Sin recursos registrados aún</div>' : ''}
      </div>
    </div>`;
}

function closeEmpresaPerfil() {
  document.getElementById('modal-empresa-perfil').classList.remove('open');
}

// ── FILTROS SOLICITUDES ────────────────────────────────

function filtrarPedidosTipo(tipo) {
  _filtroTipo = tipo;
  document.querySelectorAll('.ped-filtro-pill').forEach(el =>
    el.classList.toggle('active', el.dataset.tipo === tipo));
  renderPedidos();
}

function buscarPedidos() {
  _filtroBusqueda = (document.getElementById('ped-search')?.value || '').toLowerCase().trim();
  renderPedidos();
}
