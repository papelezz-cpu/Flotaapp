// ── MÓDULO PEDIDOS DE SERVICIO ─────────────────────────

let pedidoDetalle      = null;   // pedido abierto en modal
let ofertaDetalleId    = null;   // oferta en modal responder-contra
let pedidoParaOfertar  = null;   // pedido sobre el que el admin ofertará

const TIPO_EMOJI = { Torton:'🚛', Rabón:'🚚', Full:'🚛', Plataforma:'🏗️', Cualquiera:'🚛' };

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

  // Botón crear pedido: solo para clientes logueados
  const btnNuevo = document.getElementById('btn-nuevo-pedido');
  if (btnNuevo) {
    btnNuevo.style.display = (currentUser.id && currentUser.rol === 'cliente') ? 'inline-flex' : 'none';
  }

  // Fetch pedidos + ofertas en paralelo
  const [{ data: pedidos, error }, { data: todasOfertas }] = await Promise.all([
    sb.from('pedidos').select('*').order('created_at', { ascending: false }),
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

  let html = '';

  // ── CLIENTE ────────────────────────────────────────
  if (currentUser.id && currentUser.rol === 'cliente') {
    const misPedidos   = (pedidos || []).filter(p => p.cliente_id === currentUser.id);
    const otrosPedidos = (pedidos || []).filter(p => p.cliente_id !== currentUser.id && p.estado === 'abierto');

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
    const misNegociaciones = (pedidos || []).filter(p =>
      (ofertasMap[p.id] || []).some(o => o.admin_id === currentUser.id && ['enviada','contra_oferta'].includes(o.estado))
    );
    const misNegIds = new Set(misNegociaciones.map(p => p.id));

    // Pedidos abiertos donde aún no he ofertado
    const disponibles = (pedidos || []).filter(p =>
      p.estado === 'abierto' && !misOfertaIds.has(p.id)
    );

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

  const estadoLabel = {
    abierto:        'Buscando ofertas',
    en_negociacion: 'En negociación',
    acordado:       '✓ Acordado',
    cancelado:      'Cancelado',
  }[p.estado] || p.estado;

  const ofertasVivas  = ofertas.filter(o => o.estado !== 'rechazada');
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
    acciones = `
      <span class="badge ${bdg}" style="font-size:0.72rem">${etq}</span>
      ${st === 'contra_oferta'
        ? `<button class="btn-ofertar" onclick="openResponderContra('${miOferta.id}')">Responder</button>`
        : ''}`;
  }

  // Superadmin puede eliminar cualquier pedido
  const btnEliminar = currentUser.rol === 'superadmin'
    ? `<button class="btn-edit btn-rechazar" style="font-size:0.72rem" onclick="eliminarPedido('${p.id}')">🗑 Eliminar</button>`
    : '';

  return `
    <div class="pedido-card" id="ped-${p.id}">
      <div class="pedido-top">
        <div class="pedido-info">
          <div class="pedido-tipo">${TIPO_EMOJI[p.tipo_camion] || '🚛'} ${esc(p.tipo_camion)}${p.capacidad_min ? ` · mín ${p.capacidad_min} ton` : ''}</div>
          ${p.origen || p.destino
            ? `<div class="pedido-ruta">📍 ${esc(p.origen || '—')} → ${esc(p.destino || '—')}</div>` : ''}
          ${fechasTxt ? `<div class="pedido-fecha">${fechasTxt}</div>` : ''}
          ${p.tipo_carga ? `<div class="pedido-carga">📦 ${esc(p.tipo_carga)}</div>` : ''}
        </div>
        <span class="badge ${badgeCls}">${estadoLabel}</span>
      </div>
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
  const esCamion = !val.startsWith('Custodio') && !val.startsWith('Patio') && val !== 'Supervisión remota' && val !== 'Bodega';
  ['np-cap-group','np-carga-group'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.style.display = esCamion ? '' : 'none';
  });
}

function openNuevoPedido() {
  if (!currentUser.id) { showLoginOverlay(); return; }
  document.getElementById('modal-nuevo-pedido').classList.add('open');
}
function closeNuevoPedido() {
  document.getElementById('modal-nuevo-pedido').classList.remove('open');
}

async function crearPedido() {
  const tipo      = document.getElementById('np-tipo').value;
  const capacidad = parseInt(document.getElementById('np-cap').value)     || null;
  const tipoCarga = document.getElementById('np-carga').value.trim();
  const origen    = document.getElementById('np-origen').value.trim();
  const destino   = document.getElementById('np-destino').value.trim();
  const fechaIni  = document.getElementById('np-fecha-ini').value;
  const fechaFin  = document.getElementById('np-fecha-fin').value;
  const desc      = document.getElementById('np-desc').value.trim();
  const precio    = parseFloat(document.getElementById('np-precio').value) || null;

  if (!origen || !destino || !fechaIni) {
    alert('Por favor completa origen, destino y fecha de inicio.'); return;
  }

  const { error } = await sb.from('pedidos').insert({
    cliente_id:     currentUser.id,
    cliente_nombre: currentUser.nombre,
    cliente_email:  currentUser.email,
    tipo_camion:    tipo,
    capacidad_min:  capacidad,
    tipo_carga:     tipoCarga  || null,
    origen, destino,
    fecha_ini:      fechaIni,
    fecha_fin:      fechaFin  || null,
    descripcion:    desc      || null,
    precio_cliente: precio,
  });
  if (error) { showToast('Error al publicar pedido'); return; }

  closeNuevoPedido();
  ['np-cap','np-carga','np-origen','np-destino','np-fecha-ini','np-fecha-fin','np-desc','np-precio']
    .forEach(id => { const el = document.getElementById(id); if (el) el.value = ''; });

  await renderPedidos();
  showToast('✓ Pedido publicado — los proveedores ya pueden ver tu solicitud');
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

  let acciones = '';
  if (o.estado === 'enviada' && !expirada) {
    acciones = `
      <div class="oferta-acciones">
        <button class="btn-edit btn-aprobar" onclick="responderOferta('${o.id}','aceptar')">
          ✓ Aceptar ${fmt(o.precio_oferta)}
        </button>
        <button class="btn-edit" onclick="abrirContraoferta('${o.id}')">↩ Contraofertar</button>
        <button class="btn-edit btn-rechazar" onclick="responderOferta('${o.id}','rechazar')">✕ Rechazar</button>
      </div>`;
  } else if (o.estado === 'contra_oferta') {
    acciones = `<div class="oferta-acciones"><span style="font-size:0.78rem;color:var(--text-muted)">Esperando respuesta del proveedor…</span></div>`;
  }

  return `
    <div class="oferta-item" id="of-${o.id}">
      <div class="oferta-top">
        <div>
          <div class="oferta-empresa">${esc(o.admin_nombre)}</div>
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
  const nuevo = accion === 'aceptar' ? 'aceptada' : 'rechazada';
  if (accion === 'aceptar' && !confirm('¿Confirmas aceptar esta oferta? Se creará la reservación.')) return;

  const { data: oferta } = await sb.from('ofertas').select('*').eq('id', ofertaId).single();
  const { error } = await sb.from('ofertas').update({ estado: nuevo }).eq('id', ofertaId);
  if (error) { showToast('Error al procesar'); return; }

  if (accion === 'aceptar' && oferta && pedidoDetalle) {
    await cerrarAcuerdo(oferta, pedidoDetalle);
  }

  await loadNotificaciones();
  if (pedidoDetalle) await openPedidoDetalle(pedidoDetalle.id);
  await renderPedidos();
  showToast(accion === 'aceptar' ? '✓ ¡Acuerdo cerrado! Reservación creada' : 'Oferta declinada');
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
    // Camión (comportamiento original)
    if (label) label.textContent = 'Camión que asignas';
    const misCamiones = allCamiones.filter(c =>
      (currentUser.rol === 'superadmin' || c.propietario_id === currentUser.id) &&
      c.estado === 'disponible'
    );
    recursos = misCamiones;
    sinRecursosMsg = '⚠ No tienes camiones disponibles. Verifica el estado de tus unidades en el panel Admin.';

    select.innerHTML = `<option value="">Sin asignar camión aún</option>`;
    misCamiones.forEach(c => {
      const opt = document.createElement('option');
      opt.value       = c.id;
      opt.textContent = `${c.emoji} ${c.id} — ${c.tipo} (${c.capacidad} ton)`;
      select.appendChild(opt);
    });
  }

  // Si no hay recursos del tipo requerido, mostrar advertencia y bloquear envío
  if ((esCustodio || esPatio) && !recursos.length) {
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
