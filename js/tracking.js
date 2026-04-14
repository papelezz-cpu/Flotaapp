// ── SEGUIMIENTO DE RESERVA ────────────────────────────

const TRACKING_ESTADOS = [
  { key: 'Confirmado',      icon: '✅', label: 'Confirmado'       },
  { key: 'En camino',       icon: '🚛', label: 'En camino al puerto' },
  { key: 'En carga',        icon: '⚓', label: 'En carga'          },
  { key: 'En tránsito',     icon: '📍', label: 'En tránsito'       },
  { key: 'Entregado',       icon: '✓',  label: 'Entregado'         },
];

let trackingReservaId = null;
let trackingReserva   = null;

async function openTracking(reservaId) {
  trackingReservaId = reservaId;
  const { data } = await sb.from('reservaciones').select('*').eq('id', reservaId).single();
  trackingReserva = data;

  renderTrackingModal();
  document.getElementById('modal-tracking').classList.add('open');
}

function renderTrackingModal() {
  const r = trackingReserva;
  if (!r) return;

  const estadoActual = r.tracking_estado || 'Confirmado';
  const idx          = TRACKING_ESTADOS.findIndex(e => e.key === estadoActual);
  const canEdit      = ['admin', 'superadmin'].includes(currentUser.rol);

  document.getElementById('tracking-reserva-info').innerHTML =
    `<strong>${esc(r.unidad)}</strong> · ${esc(r.cliente)} · ${fmtFecha(r.fecha_ini)} – ${fmtFecha(r.fecha_fin)}`;

  const steps = TRACKING_ESTADOS.map((e, i) => {
    const done    = i < idx;
    const current = i === idx;
    const cls     = done ? 'step-done' : current ? 'step-current' : 'step-pending';
    return `
      <div class="tracking-step ${cls}">
        <div class="step-circle">${done ? '✓' : esc(e.icon)}</div>
        <div class="step-label">${esc(e.label)}</div>
      </div>
      ${i < TRACKING_ESTADOS.length - 1 ? `<div class="step-line ${done ? 'line-done' : ''}"></div>` : ''}`;
  }).join('');

  document.getElementById('tracking-steps').innerHTML = steps;

  // Botón avanzar (solo admin, y si no está entregado)
  const btnAvanzar = document.getElementById('tracking-btn-avanzar');
  if (canEdit && idx < TRACKING_ESTADOS.length - 1) {
    const siguiente = TRACKING_ESTADOS[idx + 1];
    btnAvanzar.textContent = `${siguiente.icon} Marcar: ${siguiente.label}`;
    btnAvanzar.style.display = 'block';
  } else {
    btnAvanzar.style.display = 'none';
  }
}

async function avanzarTracking() {
  if (!trackingReserva) return;
  const estadoActual = trackingReserva.tracking_estado || 'Confirmado';
  const idx  = TRACKING_ESTADOS.findIndex(e => e.key === estadoActual);
  const next = TRACKING_ESTADOS[idx + 1];
  if (!next) return;

  await sb.from('reservaciones')
    .update({ tracking_estado: next.key })
    .eq('id', trackingReservaId);

  trackingReserva = { ...trackingReserva, tracking_estado: next.key };
  renderTrackingModal();

  if (next.key === 'Entregado') {
    showToast('✓ Reserva marcada como entregada');
  }
  // Refrescar tabla de reservaciones en background
  if (document.getElementById('view-reservaciones').classList.contains('active')) renderReserv();
}

function closeTracking() {
  document.getElementById('modal-tracking').classList.remove('open');
}
