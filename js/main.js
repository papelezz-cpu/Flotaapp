// ── TOAST ─────────────────────────────────────────────

function showToast(msg, tipo = 'ok') {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.className = 'toast show' + (tipo === 'error' ? ' toast-error' : '');
  clearTimeout(t._timer);
  t._timer = setTimeout(() => t.classList.remove('show'), 3500);
}

// ── INICIALIZACIÓN (llamada tras login) ───────────────
// Solo refresca la vista activa; el resto ya cargó en el arranque público
function init() {
  filtrarRecursos();
}

// ── ARRANQUE PÚBLICO ──────────────────────────────────
// Carga camiones sin requerir login, luego restaura sesión si existe
(async () => {
  const hoy    = today();
  const manana = new Date(Date.now() + 86400000).toISOString().split('T')[0];

  document.getElementById('fecha-inicio').value = hoy;
  document.getElementById('fecha-fin').value    = manana;
  document.getElementById('res-fecha-ini').min  = hoy;
  document.getElementById('res-fecha-fin').min  = hoy;
  document.getElementById('res-fecha-ini').addEventListener('change', e => {
    document.getElementById('res-fecha-fin').min = e.target.value;
    if (document.getElementById('res-fecha-fin').value < e.target.value) {
      document.getElementById('res-fecha-fin').value = e.target.value;
    }
  });

  // Cargar recursos públicamente (anon key con política RLS pública)
  filtrarRecursos();

  // Restaurar sesión guardada si el usuario ya había iniciado sesión
  await checkExistingSession();

  // Cargar notificaciones si hay sesión (el canal Realtime lo inicia auth.js)
  if (currentUser.id) loadNotificaciones();

  // #5 — Realtime: actualizar vistas cuando cambia la BD
  const clienteActivo = () => document.getElementById('view-cliente').classList.contains('active');
  const adminActivo   = () => document.getElementById('view-admin').classList.contains('active');

  sb.channel('flotapro-changes')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'camiones' }, () => {
      if (clienteActivo()) filtrarRecursos();
      if (adminActivo())   renderAdmin();
    })
    .on('postgres_changes', { event: '*', schema: 'public', table: 'custodios' }, () => {
      if (clienteActivo() && currentRecursoTipo === 'custodio') renderCustodios();
      if (adminActivo())   renderAdminCustodios();
    })
    .on('postgres_changes', { event: '*', schema: 'public', table: 'patios' }, () => {
      if (clienteActivo() && currentRecursoTipo === 'patio') renderPatios();
      if (adminActivo())   renderAdminPatios();
    })
    .on('postgres_changes', { event: '*', schema: 'public', table: 'reservaciones' }, () => {
      if (document.getElementById('view-reservaciones').classList.contains('active')) renderReserv();
    })
    .subscribe();
})();

// ── EVENT LISTENERS ───────────────────────────────────

document.getElementById('modal-reserva').addEventListener('click', function (e) {
  if (e.target === this) closeModal();
});

// #4 — Service Worker (PWA)
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/sw.js').catch(() => {});
}
