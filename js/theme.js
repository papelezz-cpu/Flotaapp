// ── MODO CLARO / OSCURO ───────────────────────────────

function toggleTheme() {
  const isLight = document.body.classList.toggle('light');
  document.getElementById('btn-theme').textContent = isLight ? '☀️' : '🌙';
  localStorage.setItem('flotapro-theme', isLight ? 'light' : 'dark');
}

// Aplicar tema guardado; default = claro
(function () {
  const saved = localStorage.getItem('flotapro-theme');
  if (saved !== 'dark') {
    document.body.classList.add('light');
  }
  // Sincronizar ícono en cuanto el DOM esté listo
  document.addEventListener('DOMContentLoaded', () => {
    const btn = document.getElementById('btn-theme');
    if (btn) btn.textContent = document.body.classList.contains('light') ? '☀️' : '🌙';
  });
})();
