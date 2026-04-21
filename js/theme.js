// ── MODO CLARO / OSCURO ───────────────────────────────

function _aplicarLogo(isLight) {
  document.querySelectorAll('.logo-icon').forEach(el => {
    el.src = isLight ? 'icon-light.svg' : 'icon.svg';
  });
}

function toggleTheme() {
  const isLight = document.body.classList.toggle('light');
  document.getElementById('btn-theme').textContent = isLight ? '☀️' : '🌙';
  localStorage.setItem('portgo-theme', isLight ? 'light' : 'dark');
  _aplicarLogo(isLight);
}

// Aplicar tema guardado; default = claro
(function () {
  const saved = localStorage.getItem('portgo-theme');
  if (saved !== 'dark') {
    document.body.classList.add('light');
  }
  document.addEventListener('DOMContentLoaded', () => {
    const isLight = document.body.classList.contains('light');
    const btn = document.getElementById('btn-theme');
    if (btn) btn.textContent = isLight ? '☀️' : '🌙';
    _aplicarLogo(isLight);
  });
})();
