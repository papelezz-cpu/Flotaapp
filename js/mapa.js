// ── MARCAR ORIGEN Y DESTINO EN EL MAPA ──────────────────
//
// La dirección se escribe libre (ya no se sugiere), y aparte se puede marcar
// el punto exacto de la maniobra. Guardar lat/lng resuelve dos cosas que el
// texto libre no puede: que el operador llegue al andén correcto y no solo a
// la calle, y poder calcular distancias más adelante.
//
// Leaflet + OpenStreetMap en vez de Google Maps: no requiere API key ni
// tarjeta, y el proyecto ya usa Nominatim (mismo ecosistema) para geocodificar.
// Cambiar a Google después es contenido de este archivo, nada más.

const MAPA_CENTRO_MX = [19.1138, -104.3389];  // Manzanillo
const MAPA_ZOOM_INICIAL = 6;

let _mapa = null;
let _mapaMarcador = null;
let _mapaCampo = null;      // 'origen' | 'destino'
let _mapaPunto = null;      // { lat, lng, etiqueta }

// Lo que quedó marcado para cada campo. Se lee al publicar la solicitud.
const _mapaPuntos = { origen: null, destino: null };

function abrirMapa(campo) {
  if (typeof L === 'undefined') {
    showToast('El mapa no cargó. Revisa tu conexión e intenta de nuevo.', 'error');
    return;
  }
  _mapaCampo = campo;
  _mapaPunto = _mapaPuntos[campo] || null;

  document.getElementById('mapa-titulo').textContent =
    campo === 'origen' ? 'Asignar ubicación de origen' : 'Asignar ubicación de destino';
  document.getElementById('mapa-buscar-input').value =
    document.getElementById(`np-${campo}`)?.value || '';
  document.getElementById('modal-mapa').classList.add('open');

  // Leaflet necesita que el contenedor ya esté visible y con tamaño para
  // calcular los tiles: si se inicializa con el modal cerrado, el mapa sale
  // gris y a medias.
  setTimeout(() => {
    if (!_mapa) {
      // Zoom control abajo a la derecha: arriba va la barra de búsqueda
      // flotando sobre el mapa, y ahí chocaría con los botones +/-.
      _mapa = L.map('mapa-canvas', { zoomControl: false }).setView(MAPA_CENTRO_MX, MAPA_ZOOM_INICIAL);
      L.control.zoom({ position: 'bottomright' }).addTo(_mapa);
      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        maxZoom: 19,
        attribution: '&copy; OpenStreetMap',
      }).addTo(_mapa);
      _mapa.on('click', e => _ponerPin(e.latlng.lat, e.latlng.lng));
    }
    _mapa.invalidateSize();

    if (_mapaPunto) {
      _ponerPin(_mapaPunto.lat, _mapaPunto.lng, _mapaPunto.etiqueta);
      _mapa.setView([_mapaPunto.lat, _mapaPunto.lng], 15);
    } else {
      _pintarSeleccion();
      // Si ya escribió una dirección, se centra el mapa ahí de entrada.
      const txt = document.getElementById(`np-${campo}`)?.value?.trim();
      if (txt) buscarEnMapa(txt);
    }
  }, 60);
}

function cerrarMapa() {
  document.getElementById('modal-mapa').classList.remove('open');
}

function _ponerPin(lat, lng, etiqueta) {
  _mapaPunto = { lat, lng, etiqueta: etiqueta || null };
  if (_mapaMarcador) {
    _mapaMarcador.setLatLng([lat, lng]);
  } else {
    // Arrastrable: buscar solo acerca al lugar, el pin fino lo ajusta el
    // usuario arrastrando en vez de tener que volver a tocar el mapa.
    _mapaMarcador = L.marker([lat, lng], { draggable: true }).addTo(_mapa);
    _mapaMarcador.on('dragend', () => {
      const p = _mapaMarcador.getLatLng();
      _ponerPin(p.lat, p.lng);
    });
  }
  _pintarSeleccion();
  if (!etiqueta) _reverseGeocode(lat, lng);
}

function _pintarSeleccion() {
  const el = document.getElementById('mapa-sel');
  if (!el) return;
  if (!_mapaPunto) { el.textContent = 'Aún no has marcado un punto.'; return; }
  el.innerHTML = `📍 <strong>${esc(_mapaPunto.etiqueta || 'Punto marcado')}</strong>`
    + `<span class="mapa-sel-coord">${_mapaPunto.lat.toFixed(5)}, ${_mapaPunto.lng.toFixed(5)}</span>`;
}

// Nombre legible del punto. Es solo informativo: si falla, el punto sigue
// siendo válido porque lo que importa son las coordenadas.
async function _reverseGeocode(lat, lng) {
  try {
    const url = `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lng}&format=json&accept-language=es`;
    const r = await fetch(url, { headers: { 'Accept': 'application/json' } });
    const d = await r.json();
    if (d?.display_name && _mapaPunto && _mapaPunto.lat === lat) {
      _mapaPunto.etiqueta = d.display_name;
      _pintarSeleccion();
    }
  } catch (e) { console.warn('Reverse geocode falló:', e); }
}

async function buscarEnMapa(texto) {
  const q = String(texto ?? document.getElementById('mapa-buscar-input')?.value ?? '').trim();
  if (!q || !_mapa) return;
  try {
    const url = `https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(q)}&format=json&limit=1&countrycodes=mx&accept-language=es`;
    const r = await fetch(url, { headers: { 'Accept': 'application/json' } });
    const d = await r.json();
    if (!d?.length) {
      if (texto === undefined) showToast('No se encontró ese lugar. Marca el punto directo en el mapa.', 'error');
      return;
    }
    const lat = +d[0].lat, lng = +d[0].lon;
    _mapa.setView([lat, lng], 15);
    // Buscar ya deja el pin puesto ahí — el usuario solo lo arrastra si el
    // resultado no cayó exacto, en vez de tener que tocar el mapa aparte.
    _ponerPin(lat, lng, d[0].display_name);
  } catch (e) {
    console.warn('Búsqueda en mapa falló:', e);
  }
}

function confirmarMapa() {
  if (!_mapaPunto) { showToast('Toca el mapa para marcar el punto.', 'error'); return; }
  _mapaPuntos[_mapaCampo] = { ..._mapaPunto };

  // El campo es de solo lectura: ya no se escribe a mano, lo llena el punto
  // elegido en el mapa. Si el nombre del lugar no llegó a tiempo (reverse
  // geocode es async), se usa la coordenada como referencia mientras tanto.
  const input = document.getElementById(`np-${_mapaCampo}`);
  if (input) {
    input.value = _mapaPunto.etiqueta || `${_mapaPunto.lat.toFixed(5)}, ${_mapaPunto.lng.toFixed(5)}`;
  }

  _pintarCoordEnFormulario(_mapaCampo);
  cerrarMapa();
  showToast('✓ Punto marcado en el mapa');
}

function _pintarCoordEnFormulario(campo) {
  const el = document.getElementById(`np-${campo}-coord`);
  if (!el) return;
  const p = _mapaPuntos[campo];
  el.innerHTML = p
    ? `✓ ${p.lat.toFixed(4)}, ${p.lng.toFixed(4)} <button type="button" class="mapa-quitar" onclick="quitarPuntoMapa('${campo}')">quitar</button>`
    : '';
}

function quitarPuntoMapa(campo) {
  _mapaPuntos[campo] = null;
  _pintarCoordEnFormulario(campo);
}

// Estado limpio al abrir una solicitud nueva.
function resetPuntosMapa() {
  _mapaPuntos.origen = null;
  _mapaPuntos.destino = null;
  _mapaMarcador = null;
  _mapaPunto = null;
  if (_mapa) { _mapa.eachLayer(l => { if (l instanceof L.Marker) _mapa.removeLayer(l); }); }
  ['origen', 'destino'].forEach(_pintarCoordEnFormulario);
}
