// ── MODO CLARO / OSCURO ───────────────────────────────

function toggleTheme() {
  const isLight = document.body.classList.toggle('light');
  document.getElementById('btn-theme').textContent = isLight ? '☀️' : '🌙';
}
