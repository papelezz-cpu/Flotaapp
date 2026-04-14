// ── MODO CLARO / OSCURO ───────────────────────────────

function toggleTheme() {
  const isLight = document.body.classList.toggle('light');
  document.getElementById('btn-theme').textContent = isLight ? '☀️' : '🌙';
  localStorage.setItem('flotapro-theme', isLight ? 'light' : 'dark');
}

// Aplicar tema guardado inmediatamente al cargar
(function () {
  if (localStorage.getItem('flotapro-theme') === 'light') {
    document.body.classList.add('light');
  }
})();
