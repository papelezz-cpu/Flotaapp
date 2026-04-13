// ── TOAST ─────────────────────────────────────────────

function showToast(msg) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.classList.add('show');
  setTimeout(() => t.classList.remove('show'), 3000);
}

// ── INICIALIZACIÓN ────────────────────────────────────

async function init() {
  const today    = new Date().toISOString().split('T')[0];
  const tomorrow = new Date(Date.now() + 86400000).toISOString().split('T')[0];

  document.getElementById('fecha-inicio').value  = today;
  document.getElementById('fecha-fin').value     = tomorrow;
  document.getElementById('res-fecha-ini').value = today;
  document.getElementById('res-fecha-fin').value = tomorrow;

  await renderCamiones();
}

// ── EVENT LISTENERS ───────────────────────────────────

document.getElementById('modal-reserva').addEventListener('click', function (e) {
  if (e.target === this) closeModal();
});
