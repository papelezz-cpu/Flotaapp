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

// ── CONFIRM MODAL (reemplaza window.confirm) ───────────

let _confirmCb = null;

function showConfirm(msg, onConfirm, { danger = false, confirmLabel = 'Confirmar', cancelLabel = 'Cancelar' } = {}) {
  const btn = document.getElementById('sc-confirm');
  document.getElementById('sc-msg').textContent = msg;
  btn.textContent = confirmLabel;
  btn.style.cssText = danger
    ? 'background:#ef4444;border-color:#ef4444;color:#fff'
    : 'background:#2563eb;border-color:#2563eb;color:#fff';
  _confirmCb = onConfirm;
  document.getElementById('modal-confirm').classList.add('open');
}

function _scCancel() {
  document.getElementById('modal-confirm').classList.remove('open');
  _confirmCb = null;
}

function _scConfirm() {
  document.getElementById('modal-confirm').classList.remove('open');
  const cb = _confirmCb;
  _confirmCb = null;
  if (cb) cb();
}

// ── GEO AUTOCOMPLETE (Nominatim OpenStreetMap) ─────────
let _geoTimer = null;

function setupGeoAutocomplete(inputEl) {
  if (!inputEl || inputEl.dataset.geoSetup) return;
  inputEl.dataset.geoSetup = '1';

  const wrap = inputEl.closest('.form-group') || inputEl.parentNode;
  wrap.style.position = 'relative';

  const dd = document.createElement('div');
  dd.className = 'geo-dropdown';
  wrap.appendChild(dd);

  inputEl.addEventListener('input', () => {
    clearTimeout(_geoTimer);
    dd.innerHTML = '';
    dd.style.display = 'none';
    const q = inputEl.value.trim();
    if (q.length < 3) return;
    _geoTimer = setTimeout(() => _geoFetch(q, inputEl, dd), 420);
  });

  document.addEventListener('click', e => {
    if (!wrap.contains(e.target)) dd.style.display = 'none';
  }, true);
}

async function _geoFetch(query, inputEl, dd) {
  try {
    const url = `https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(query)}&format=json&limit=5&countrycodes=mx&accept-language=es`;
    const res  = await fetch(url, { headers: { 'User-Agent': 'PortGo/1.0' } });
    const data = await res.json();
    if (!data.length) return;
    dd.innerHTML = data.map(r => {
      const label = r.display_name.split(',').slice(0, 3).join(',');
      return `<div class="geo-item" onclick="_geoSelect(this, '${label.replace(/'/g,"&#39;")}', event)">${esc(label)}</div>`;
    }).join('');
    dd.style.display = 'block';
    // Store reference to input
    dd._input = inputEl;
  } catch (_) {}
}

function _geoSelect(itemEl, value, e) {
  e.stopPropagation();
  const dd = itemEl.closest('.geo-dropdown');
  if (dd?._input) dd._input.value = value;
  if (dd) dd.style.display = 'none';
}

function setupAllGeoInputs() {
  document.querySelectorAll('[id="np-origen"],[id="np-destino"],[id="np-ubic-lav"],[id="np-zona-cust"],[id="np-ubic-patio"]').forEach(el => {
    setupGeoAutocomplete(el);
  });
}
