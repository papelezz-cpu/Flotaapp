// ── NAVEGACIÓN ENTRE VISTAS ───────────────────────────

function showView(v, btn) {
  document.querySelectorAll('.view').forEach(el => el.classList.remove('active'));
  document.querySelectorAll('.nav-tab').forEach(el => el.classList.remove('active'));

  document.getElementById('view-' + v).classList.add('active');
  if (btn) btn.classList.add('active');

  if (v === 'cliente')       renderCamiones();
  if (v === 'reservaciones') renderReserv();
  if (v === 'admin')         renderAdmin();
  if (v === 'usuarios')      renderUsuarios();
}
