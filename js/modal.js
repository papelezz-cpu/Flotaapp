// ── MODAL DE RESERVA ──────────────────────────────────
// currentRecurso unifica camiones, custodios y patios
// { id, tipo_recurso, propietario_id, displayName, tipo, empresaNombre }

let currentRecurso = null;

// Llamado desde camiones.js
function openReserva(id) {
  const c = allCamiones.find(c => c.id === id);
  if (!c) return;
  currentRecurso = {
    id:            c.id,
    tipo_recurso:  'camion',
    propietario_id: c.propietario_id,
    displayName:   `${c.tipo} ${c.id} · ${c.capacidad} ton`,
    tipo:          c.tipo,
    empresaNombre: c.empresaNombre,
  };
  _abrirModalReserva();
}

// Llamado desde recursos.js (custodios y patios)
function openReservaRecurso(tipo_recurso, id, nombre, propietario_id) {
  const iconos = { custodio: '👮', patio: '🏭' };
  currentRecurso = {
    id,
    tipo_recurso,
    propietario_id: propietario_id || null,
    displayName:   `${iconos[tipo_recurso] || ''} ${nombre} (${id})`,
    tipo:          nombre,
    empresaNombre: null,
  };
  _abrirModalReserva();
}

function _abrirModalReserva() {
  document.getElementById('modal-truck-name').textContent = currentRecurso.displayName;
  if (currentUser.id) {
    const n = document.getElementById('res-nombre');
    const e = document.getElementById('res-email');
    if (n && !n.value) n.value = currentUser.nombre || '';
    if (e && !e.value) e.value = currentUser.email  || '';
  }
  document.getElementById('modal-reserva').classList.add('open');
}

function closeModal() {
  document.getElementById('modal-reserva').classList.remove('open');
}

async function confirmarReserva() {
  const nombre = document.getElementById('res-nombre').value.trim();
  const email  = document.getElementById('res-email').value.trim();
  const tel    = document.getElementById('res-tel').value.trim();
  const ini    = document.getElementById('res-fecha-ini').value;
  const fin    = document.getElementById('res-fecha-fin').value;
  const desc   = document.getElementById('res-desc').value.trim();

  if (!nombre || !ini || !fin) {
    showToast('Por favor completa los campos requeridos.', 'error');
    return;
  }
  if (fin < ini) {
    showToast('La fecha de fin no puede ser anterior a la de inicio.', 'error');
    return;
  }

  // Verificar solapamiento solo si hay un recurso asignado.
  //
  // H-06: esta es la TERCERA capa que vigila el solape, y hasta el 2026-09-25
  // era la única que seguía comparando solo `unidad`. Las otras dos viven en la
  // base —`check_reservacion_disponibilidad()` y `reservaciones_sin_solape`— y
  // ya distinguen el tipo. Sin esta línea el falso positivo seguía vivo justo
  // donde el usuario lo ve: `unidad` guarda el id de un camión, un custodio, un
  // patio o un lavado, así que un patio que compartiera cadena de id con un
  // camión daba «Este recurso ya está reservado» sobre un recurso libre, y ni
  // llegaba a la base.
  //
  // `tipo_recurso` se lee con la MISMA expresión que usa el insert de abajo, a
  // propósito: si las dos difirieran, el aviso hablaría de un recurso distinto
  // del que se va a guardar.
  //
  // Lo que NO se toca aquí: el `.neq('estado','Cancelada')`. Las dos capas de la
  // base solo miran `Pendiente` y `Activa`, así que esta consulta bloquea de más
  // —también sobre `PorAprobar`, `Completada` o `CancelacionSolicitada`—. Puede
  // ser deliberado y cambiarlo abriría reservas que hoy se rechazan, que es otra
  // decisión y no la de H-06. Queda anotado como hueco.
  if (currentRecurso?.id) {
    const { data: conflictos } = await sb.from('reservaciones')
      .select('fecha_ini, fecha_fin')
      .eq('unidad', currentRecurso.id)
      .eq('recurso_tipo', currentRecurso?.tipo_recurso || 'camion')
      .neq('estado', 'Cancelada')
      .lte('fecha_ini', fin)
      .gte('fecha_fin', ini);

    if (conflictos?.length) {
      const c = conflictos[0];
      showToast(`Este recurso ya está reservado del ${fmtFecha(c.fecha_ini)} al ${fmtFecha(c.fecha_fin)}. Elige otras fechas.`, 'error');
      return;
    }
  }

  // propietario_id es indispensable: renderReserv filtra por él, sin él la
  // empresa dueña nunca vería la solicitud para aceptarla.
  const { error: errRes } = await sb.from('reservaciones').insert({
    unidad:          currentRecurso?.id   || null,
    propietario_id:  currentRecurso?.propietario_id || null,
    recurso_tipo:    currentRecurso?.tipo_recurso || 'camion',
    cliente:         nombre,
    cliente_email:   email,
    cliente_user_id: currentUser.id || null,
    telefono:        tel,
    fecha_ini:       ini,
    fecha_fin:       fin,
    descripcion:     desc,
    estado:          'Pendiente',
  });
  if (errRes) { showToast('Error al guardar la reserva: ' + (errRes.message || ''), 'error'); return; }

  // Notificación por email (silencioso si falla)
  if (currentRecurso?.propietario_id) {
    _notificarEmail({
      tipo: 'nueva_reserva',
      propietario_id: currentRecurso.propietario_id,
      camion:  { id: currentRecurso.id, tipo: currentRecurso.tipo },
      reserva: { cliente: nombre, email, telefono: tel, fecha_ini: ini, fecha_fin: fin, descripcion: desc }
    });
  }
  if (email) {
    _notificarEmail({
      tipo: 'solicitud_recibida',
      clienteEmail:  email,
      clienteNombre: nombre,
      camion:   { id: currentRecurso?.id, tipo: currentRecurso?.tipo, empresa: currentRecurso?.empresaNombre },
      fecha_ini: ini,
      fecha_fin: fin
    });
  }

  closeModal();
  filtrarRecursos();
  showToast('✓ Solicitud enviada — la empresa confirmará pronto');
}
