// ── UTILIDADES GLOBALES ────────────────────────────────

// #1 — Escapar HTML para prevenir XSS
function esc(str) {
  return String(str ?? '').replace(/[&<>"']/g, c =>
    ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])
  );
}

// Fecha de hoy YYYY-MM-DD
function today() {
  return new Date().toISOString().split('T')[0];
}

// Formatear fecha DD/MM/YYYY para mostrar
function fmtFecha(str) {
  if (!str) return '—';
  const [y, m, d] = str.split('-');
  return `${d}/${m}/${y}`;
}

// #6 — Skeleton loaders
function skeletonGrid(n = 6) {
  const card = `
    <div class="truck-card" style="pointer-events:none">
      <div class="truck-header">
        <div>
          <div class="skel" style="width:70px;height:18px;margin-bottom:6px"></div>
          <div class="skel" style="width:55px;height:12px"></div>
        </div>
        <div class="skel" style="width:90px;height:26px;border-radius:20px"></div>
      </div>
      <div class="skel" style="height:90px;margin:0 18px;border-radius:10px"></div>
      <div class="truck-specs">
        ${Array(4).fill('<div><div class="skel" style="width:40px;height:10px;margin-bottom:4px"></div><div class="skel" style="width:65px;height:14px"></div></div>').join('')}
      </div>
      <div class="truck-footer">
        <div class="skel" style="flex:1;height:36px;border-radius:9px"></div>
        <div class="skel" style="flex:2;height:36px;border-radius:9px"></div>
      </div>
    </div>`;
  return Array(n).fill(card).join('');
}

function skeletonRows(n = 4) {
  const row = `
    <div class="reserv-row" style="pointer-events:none">
      <div class="skel" style="width:50px;height:16px"></div>
      <div class="skel" style="width:90px;height:14px"></div>
      <div class="skel" style="width:130px;height:14px"></div>
      <div class="skel" style="width:75px;height:14px"></div>
      <div class="skel" style="width:75px;height:14px"></div>
      <div class="skel" style="width:60px;height:22px;border-radius:20px"></div>
    </div>`;
  return Array(n).fill(row).join('');
}

function skeletonList(n = 4) {
  const item = `
    <div class="truck-list-item" style="pointer-events:none">
      <div>
        <div class="skel" style="width:130px;height:15px;margin-bottom:6px"></div>
        <div class="skel" style="width:190px;height:12px"></div>
      </div>
      <div class="skel" style="width:110px;height:30px;border-radius:7px"></div>
    </div>`;
  return Array(n).fill(item).join('');
}

// Formatear precio en MXN
function formatPrecio(num) {
  if (!num) return null;
  return '$' + Number(num).toLocaleString('es-MX', { minimumFractionDigits: 0 }) + ' MXN/día';
}
