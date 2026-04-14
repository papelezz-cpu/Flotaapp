// ── NAVEGACIÓN ENTRE VISTAS ───────────────────────────

function showView(v, btn) {
  document.querySelectorAll('.view').forEach(el => el.classList.remove('active'));
  document.querySelectorAll('.nav-tab').forEach(el => el.classList.remove('active'));

  document.getElementById('view-' + v).classList.add('active');
  if (btn) btn.classList.add('active');

  // Cerrar menú hamburguesa al navegar
  document.getElementById('btn-hamburger')?.classList.remove('open');
  document.querySelector('.nav-tabs')?.classList.remove('open');
  document.getElementById('menu-backdrop')?.classList.remove('open');

  if (v === 'cliente')       filtrarRecursos();
  if (v === 'reservaciones') renderReserv();
  if (v === 'admin')         renderAdmin();
  if (v === 'pedidos')       renderPedidos();
  if (v === 'usuarios')      renderUsuarios();
}

function toggleMenu() {
  document.getElementById('btn-hamburger').classList.toggle('open');
  document.querySelector('.nav-tabs').classList.toggle('open');
  document.getElementById('menu-backdrop').classList.toggle('open');
}
