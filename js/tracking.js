// ── SEGUIMIENTO DE RESERVA ────────────────────────────

const TRACKING_POR_TIPO = {
  camion: [
    { key: 'Confirmado',   icon: '✅', label: 'Confirmado'            },
    { key: 'En camino',    icon: '🚛', label: 'En camino al origen'   },
    { key: 'En carga',     icon: '⚓', label: 'En carga'              },
    { key: 'En tránsito',  icon: '📍', label: 'En tránsito'           },
    { key: 'Entregado',    icon: '✓',  label: 'Entregado'             },
  ],
  custodio: [
    { key: 'Confirmado',   icon: '✅', label: 'Confirmado'            },
    { key: 'Asignado',     icon: '👮', label: 'Custodio asignado'     },
    { key: 'En ruta',      icon: '🚗', label: 'En ruta al punto'      },
    { key: 'En servicio',  icon: '🛡️', label: 'En servicio'           },
    { key: 'Finalizado',   icon: '✓',  label: 'Servicio finalizado'   },
  ],
  patio: [
    { key: 'Confirmado',   icon: '✅', label: 'Confirmado'            },
    { key: 'Listo',        icon: '🏭', label: 'Patio listo'           },
    { key: 'Recibido',     icon: '🚗', label: 'Vehículo recibido'     },
    { key: 'En almacenaje',icon: '📦', label: 'En almacenaje'         },
    { key: 'Liberado',     icon: '✓',  label: 'Vehículo liberado'     },
  ],
  lavado: [
    { key: 'Confirmado',   icon: '✅', label: 'Confirmado'            },
    { key: 'Recibido',     icon: '🚗', label: 'Vehículo recibido'     },
    { key: 'En lavado',    icon: '🚿', label: 'En proceso de lavado'  },
    { key: 'Control',      icon: '🔍', label: 'Control de calidad'    },
    { key: 'Listo',        icon: '✓',  label: 'Listo para entrega'    },
  ],
};

let trackingReservaId = null;
let trackingReserva   = null;

function _getEstados(recurso_tipo) {
  return TRACKING_POR_TIPO[recurso_tipo] || TRACKING_POR_TIPO.camion;
}

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

  const TRACKING_ESTADOS = _getEstados(r.recurso_tipo);
  const estadoActual = r.tracking_estado || 'Confirmado';
  const idx          = Math.max(0, TRACKING_ESTADOS.findIndex(e => e.key === estadoActual));
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
  const TRACKING_ESTADOS = _getEstados(trackingReserva.recurso_tipo);
  const estadoActual = trackingReserva.tracking_estado || 'Confirmado';
  const idx  = Math.max(0, TRACKING_ESTADOS.findIndex(e => e.key === estadoActual));
  const next = TRACKING_ESTADOS[idx + 1];
  if (!next) return;

  await sb.from('reservaciones')
    .update({ tracking_estado: next.key })
    .eq('id', trackingReservaId);

  trackingReserva = { ...trackingReserva, tracking_estado: next.key };
  renderTrackingModal();

  const esUltimo = idx + 1 === TRACKING_ESTADOS.length - 1;
  if (esUltimo) showToast('✓ Servicio marcado como finalizado');
  if (document.getElementById('view-reservaciones').classList.contains('active')) renderReserv();
}

function closeTracking() {
  document.getElementById('modal-tracking').classList.remove('open');
}
