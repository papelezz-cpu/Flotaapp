// ── MODAL DE RESERVA ──────────────────────────────────

let selectedTruck = null;

function openReserva(id) {
  selectedTruck = allCamiones.find(c => c.id === id);
  document.getElementById('modal-truck-name').textContent =
    `${selectedTruck.tipo} ${selectedTruck.id} · ${selectedTruck.capacidad} ton`;
  document.getElementById('modal-reserva').classList.add('open');
}

function closeModal() {
  document.getElementById('modal-reserva').classList.remove('open');
}

async function confirmarReserva() {
  const nombre = document.getElementById('res-nombre').value.trim();
  const tel    = document.getElementById('res-tel').value.trim();
  const ini    = document.getElementById('res-fecha-ini').value;
  const fin    = document.getElementById('res-fecha-fin').value;
  const desc   = document.getElementById('res-desc').value.trim();

  if (!nombre || !ini || !fin) {
    alert('Por favor completa los campos requeridos.');
    return;
  }

  const { error: errRes } = await sb.from('reservaciones').insert({
    unidad: selectedTruck.id, cliente: nombre, telefono: tel,
    fecha_ini: ini, fecha_fin: fin, descripcion: desc, estado: 'Activa'
  });
  if (errRes) { alert('Error al guardar la reserva.'); return; }

  await sb.from('camiones').update({ estado: 'ocupado' }).eq('id', selectedTruck.id);

  closeModal();
  await renderCamiones();
  showToast('✓ Reserva confirmada exitosamente');
}
