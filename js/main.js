// ── TOAST ─────────────────────────────────────────────

function showToast(msg, tipo = 'ok') {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.className = 'toast show' + (tipo === 'error' ? ' toast-error' : '');
  clearTimeout(t._timer);
  t._timer = setTimeout(() => t.classList.remove('show'), 3500);
}

// ── INICIALIZACIÓN ────────────────────────────────────

async function init() {
  const hoy     = today();
  const manana  = new Date(Date.now() + 86400000).toISOString().split('T')[0];

  document.getElementById('fecha-inicio').value  = hoy;
  document.getElementById('fecha-fin').value     = manana;

  // Fechas mínimas en el modal de reserva
  document.getElementById('res-fecha-ini').min = hoy;
  document.getElementById('res-fecha-fin').min = hoy;
  document.getElementById('res-fecha-ini').addEventListener('change', e => {
    document.getElementById('res-fecha-fin').min = e.target.value;
    if (document.getElementById('res-fecha-fin').value < e.target.value) {
      document.getElementById('res-fecha-fin').value = e.target.value;
    }
  });

  await renderCamiones();

  // #5 — Realtime: actualizar vistas cuando cambia la BD
  sb.channel('flotapro-changes')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'camiones' }, () => {
      if (document.getElementById('view-cliente').classList.contains('active'))      renderCamiones();
      if (document.getElementById('view-admin').classList.contains('active'))        renderAdmin();
    })
    .on('postgres_changes', { event: '*', schema: 'public', table: 'reservaciones' }, () => {
      if (document.getElementById('view-reservaciones').classList.contains('active')) renderReserv();
    })
    .subscribe();
}

// ── EVENT LISTENERS ───────────────────────────────────

document.getElementById('modal-reserva').addEventListener('click', function (e) {
  if (e.target === this) closeModal();
});

// #4 — Service Worker (PWA)
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/sw.js').catch(() => {});
}
