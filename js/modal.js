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
    alert('Por favor completa los campos requeridos.');
    return;
  }
  if (fin < ini) {
    alert('La fecha de fin no puede ser anterior a la de inicio.');
    return;
  }

  // Verificar solapamiento solo si hay un recurso asignado
  if (currentRecurso?.id) {
    const { data: conflictos } = await sb.from('reservaciones')
      .select('fecha_ini, fecha_fin')
      .eq('unidad', currentRecurso.id)
      .neq('estado', 'Cancelada')
      .lte('fecha_ini', fin)
      .gte('fecha_fin', ini);

    if (conflictos?.length) {
      const c = conflictos[0];
      alert(`Este recurso ya está reservado del ${fmtFecha(c.fecha_ini)} al ${fmtFecha(c.fecha_fin)}.\nElige otras fechas.`);
      return;
    }
  }

  const { error: errRes } = await sb.from('reservaciones').insert({
    unidad:          currentRecurso?.id   || null,
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
  if (errRes) { alert('Error al guardar la reserva: ' + (errRes.message || '')); return; }

  // Notificación por email (silencioso si falla)
  try {
    const session = (await sb.auth.getSession()).data.session;
    const token   = session?.access_token;
    const fnBase  = typeof FN_URL !== 'undefined'
      ? FN_URL.replace('gestionar-usuario', 'enviar-notificacion')
      : null;
    if (fnBase && token && currentRecurso?.propietario_id) {
      fetch(fnBase, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
        body: JSON.stringify({
          tipo: 'nueva_reserva',
          propietario_id: currentRecurso.propietario_id,
          camion:  { id: currentRecurso.id, tipo: currentRecurso.tipo },
          reserva: { cliente: nombre, email, telefono: tel, fecha_ini: ini, fecha_fin: fin, descripcion: desc }
        })
      });
    }
    if (fnBase && token && email) {
      fetch(fnBase, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
        body: JSON.stringify({
          tipo: 'solicitud_recibida',
          clienteEmail:  email,
          clienteNombre: nombre,
          camion:   { id: currentRecurso?.id, tipo: currentRecurso?.tipo, empresa: currentRecurso?.empresaNombre },
          fecha_ini: ini,
          fecha_fin: fin
        })
      });
    }
  } catch (_) { /* silencioso */ }

  closeModal();
  filtrarRecursos();
  showToast('✓ Solicitud enviada — la empresa confirmará pronto');
}
