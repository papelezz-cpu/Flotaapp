// ── MODO CLARO / OSCURO ───────────────────────────────

function _aplicarLogo(isLight) {
  document.querySelectorAll('.logo-icon').forEach(el => {
    el.src = isLight ? 'icon-light.svg' : 'icon.svg';
  });
}

function toggleTheme() {
  const isLight = document.body.classList.toggle('light');
  const icon = isLight ? '☀️' : '🌙';
  document.getElementById('btn-theme').textContent = icon;
  const mobileIcon = document.getElementById('mobile-theme-icon');
  if (mobileIcon) mobileIcon.textContent = icon;
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
    const icon = isLight ? '☀️' : '🌙';
    const btn = document.getElementById('btn-theme');
    if (btn) btn.textContent = icon;
    const mobileIcon = document.getElementById('mobile-theme-icon');
    if (mobileIcon) mobileIcon.textContent = icon;
    _aplicarLogo(isLight);
  });
})();
