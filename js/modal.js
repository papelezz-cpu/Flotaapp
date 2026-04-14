// ── MODAL DE RESERVA ──────────────────────────────────

let selectedTruck = null;

function openReserva(id) {
  selectedTruck = allCamiones.find(c => c.id === id);
  document.getElementById('modal-truck-name').textContent =
    `${selectedTruck.tipo} ${selectedTruck.id} · ${selectedTruck.capacidad} ton`;

  // Auto-llenar con datos del usuario autenticado
  if (currentUser.id) {
    const nombreInput = document.getElementById('res-nombre');
    const emailInput  = document.getElementById('res-email');
    if (!nombreInput.value) nombreInput.value = currentUser.nombre || '';
    if (!emailInput.value)  emailInput.value  = currentUser.email  || '';
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

  // #2 — Validación de fechas
  if (fin < ini) {
    alert('La fecha de fin no puede ser anterior a la de inicio.');
    return;
  }

  // #2 — Verificar solapamiento con reservas existentes
  const { data: conflictos } = await sb.from('reservaciones')
    .select('fecha_ini, fecha_fin')
    .eq('unidad', selectedTruck.id)
    .neq('estado', 'Cancelada')
    .lte('fecha_ini', fin)
    .gte('fecha_fin', ini);

  if (conflictos?.length) {
    const c = conflictos[0];
    alert(`Este camión ya está reservado del ${fmtFecha(c.fecha_ini)} al ${fmtFecha(c.fecha_fin)}.\nElige otras fechas.`);
    return;
  }

  const { error: errRes } = await sb.from('reservaciones').insert({
    unidad: selectedTruck.id, cliente: nombre, cliente_email: email,
    telefono: tel, fecha_ini: ini, fecha_fin: fin, descripcion: desc,
    estado: 'Pendiente',
    cliente_user_id: currentUser.id || null
  });
  if (errRes) { alert('Error al guardar la reserva.'); return; }

  // Enviar emails (silencioso si falla — limitación del plan Resend)
  try {
    const session = (await sb.auth.getSession()).data.session;
    const token   = session?.access_token;
    const fnBase  = typeof FN_URL !== 'undefined'
      ? FN_URL.replace('gestionar-usuario', 'enviar-notificacion')
      : null;
    if (fnBase && token) {
      // Email a la empresa (dueño del camión)
      fetch(fnBase, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
        body: JSON.stringify({
          tipo: 'nueva_reserva',
          propietario_id: selectedTruck.propietario_id,
          camion: { id: selectedTruck.id, tipo: selectedTruck.tipo },
          reserva: { cliente: nombre, email, telefono: tel, fecha_ini: ini, fecha_fin: fin, descripcion: desc }
        })
      });
      // Acuse de recibo al cliente (con CC al superadmin)
      if (email) {
        fetch(fnBase, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
          body: JSON.stringify({
            tipo: 'solicitud_recibida',
            clienteEmail: email,
            clienteNombre: nombre,
            camion: { id: selectedTruck.id, tipo: selectedTruck.tipo, empresa: selectedTruck.empresaNombre },
            fecha_ini: ini,
            fecha_fin: fin
          })
        });
      }
    }
  } catch (_) { /* silencioso */ }

  closeModal();
  await renderCamiones();
  showToast('✓ Solicitud enviada — la empresa confirmará pronto');
}
