// ── SOLICITUDES FRECUENTES (plantillas del cliente) ────
// El formulario de solicitud tiene ~20 campos y muchos clientes repiten la
// misma ruta con la misma carga. Aquí se guardan como "frecuentes" para
// reutilizarlas con un toque. Las fechas nunca se guardan: son lo único que
// cambia siempre.

let _plantillas = [];

// Campos que viajan entre el formulario y la plantilla.
// [idDelCampo, columna, tipo] — el tipo define cómo leer/escribir el valor.
const PLANTILLA_CAMPOS = [
  // np-tipo ya no existe en el flujo de camión: la unidad la calcula el
  // sistema. La categoría de carga se restaura aparte, en usarPlantilla().
  ['np-carga',            'tipo_carga',       'txt'],
  ['np-peso',             'peso_carga',       'num'],
  ['np-tarimas',          'num_tarimas',      'num'],
  ['np-bultos',           'num_bultos',       'num'],
  ['np-contenedor',       'contenedor_1_tipo','txt'],
  ['np-cont1-peso',       'contenedor_1_peso','num'],
  ['np-contenedor-2',     'contenedor_2_tipo','txt'],
  ['np-cont2-peso',       'contenedor_2_peso','num'],
  ['np-largo',            'largo_m',          'num'],
  ['np-ancho',            'ancho_m',          'num'],
  ['np-alto',             'alto_m',           'num'],
  ['np-hazmat-clase',     'hazmat_clase',     'txt'],
  ['np-hazmat-un',        'hazmat_un',        'txt'],
  ['np-refrigerado',      'refrigerado',      'bool'],
  ['np-entra-puerto',     'entra_a_puerto',   'bool'],
  ['np-patio-externo',    'patio_externo',    'bool'],
  ['np-temp-min',         'temp_min',         'num'],
  ['np-temp-max',         'temp_max',         'num'],
  ['np-origen',           'origen',           'txt'],
  ['np-destino',          'destino',          'txt'],
  ['np-precio',           'precio_cliente',   'num'],
  ['np-plazo-pago',       'plazo_pago',       'txt'],
  ['np-desc',             'descripcion',      'txt'],
  // Otros tipos de servicio (hoy deshabilitados, la plantilla ya los soporta)
  ['np-num-custodios',    'num_custodios',    'num'],
  ['np-zona',             'zona_cobertura',   'txt'],
  ['np-horario',          'horario_servicio', 'txt'],
  ['np-num-vehiculos',    'num_vehiculos',    'num'],
  ['np-tipo-vehiculos',   'tipo_vehiculos',   'txt'],
  ['np-area',             'area_necesaria',   'num'],
];

// ── GUARDAR ────────────────────────────────────────────

// La casilla del formulario muestra u oculta el campo del nombre.
function togglePlantillaNombre() {
  const wrap = document.getElementById('np-plantilla-nombre-wrap');
  const chk  = document.getElementById('np-guardar-plantilla');
  if (!wrap || !chk) return;
  wrap.style.display = chk.checked ? '' : 'none';
  if (chk.checked) {
    const el = document.getElementById('np-plantilla-nombre');
    // Sugerir un nombre a partir de la ruta, para no obligar a escribirlo
    if (el && !el.value) el.value = _nombreSugerido();
    el?.focus();
  }
}

function _nombreSugerido() {
  const v = id => document.getElementById(id)?.value?.trim() || '';
  const corto = s => s.split(',')[0].trim();   // "Veracruz, Veracruz" → "Veracruz"
  const o = v('np-origen'), d = v('np-destino');
  if (o && d) return `${corto(o)} → ${corto(d)}`;
  if (o) return corto(o);
  return v('np-tipo') || 'Mi solicitud frecuente';
}

// Se llama desde crearPedido() cuando el cliente marcó la casilla.
async function guardarPlantillaDesdeFormulario() {
  const chk = document.getElementById('np-guardar-plantilla');
  if (!chk?.checked) return;

  const nombre = document.getElementById('np-plantilla-nombre')?.value.trim() || _nombreSugerido();
  const fila = { cliente_id: currentUser.id, nombre };

  PLANTILLA_CAMPOS.forEach(([id, col, tipo]) => {
    const el = document.getElementById(id);
    if (!el) { if (tipo === 'bool') fila[col] = false; return; }
    if (tipo === 'bool')      fila[col] = !!el.checked;
    else if (tipo === 'num')  fila[col] = el.value !== '' ? Number(el.value) : null;
    else                      fila[col] = el.value?.trim() || null;
  });

  // La categoría de carga y el número de contenedores no son inputs con id
  // fijo (una es estado del módulo, el otro un radio), así que van aparte.
  if (typeof _npCategoria !== 'undefined') fila.categoria_carga = _npCategoria;
  fila.num_contenedores = Number(document.querySelector('input[name="np-num-cont"]:checked')?.value) || null;
  // Se guarda la unidad que el sistema propuso, para que la plantilla siga
  // sirviendo aunque cambien las reglas de recomendación.
  if (typeof _recomendarCamion === 'function' && typeof _cargaDatosActuales === 'function') {
    fila.tipo_camion = _npUnidadManual || _recomendarCamion(_cargaDatosActuales()).tipo || null;
  }

  const { error } = await sb.from('plantillas_pedido').insert(fila);
  if (error) {
    // El trigger de la BD limita a 12; ese mensaje sí le sirve al usuario.
    showToast(error.message?.includes('maximo') || error.message?.includes('máximo')
      ? error.message
      : 'La solicitud se creó, pero no se pudo guardar como frecuente.', 'error');
    return;
  }
  showToast(`✓ Guardada como frecuente: ${esc(nombre)}`);
  await cargarPlantillas();
}

// ── USAR ───────────────────────────────────────────────

async function usarPlantilla(id) {
  const p = _plantillas.find(x => x.id === id);
  if (!p) { showToast('No se encontró la solicitud frecuente', 'error'); return; }

  // Abrir el modal ya con el tipo de servicio correcto, y luego rellenar.
  openNuevoPedido(_servicioDePlantilla(p));

  PLANTILLA_CAMPOS.forEach(([campoId, col, tipo]) => {
    const el = document.getElementById(campoId);
    if (!el) return;
    const val = p[col];
    if (tipo === 'bool')      el.checked = !!val;
    else if (val === null || val === undefined) el.value = '';
    else                      el.value = val;
  });

  // La categoría de carga manda el resto del formulario, así que se restaura
  // antes que nada. Si la plantilla es vieja (de cuando se guardaba el tipo de
  // camión y no la carga), se cae a General y el sistema recalcula la unidad:
  // es mejor recomendarle algo coherente con el peso que restaurar un tipo que
  // quizá ya ni exista.
  let tipoNoDisponible = false;
  if (typeof _npCategoria !== 'undefined') {
    if (p.categoria_carga && NP_CARGA[p.categoria_carga]) {
      _npCategoria = p.categoria_carga;
    } else {
      _npCategoria = 'General';
      tipoNoDisponible = !!p.tipo_camion && !p.categoria_carga;
    }
    _npUnidadManual = null;
  }

  // Número de contenedores, que es un radio y no entra en PLANTILLA_CAMPOS.
  const nCont = Number(p.num_contenedores) || 1;
  const radio = document.querySelector(`input[name="np-num-cont"][value="${nCont >= 2 ? 2 : 1}"]`);
  if (radio) radio.checked = true;

  actualizarSubtipoPedido();

  // No se precargan fechas a propósito: son lo que el cliente debe elegir.
  const aviso = document.getElementById('np-plantilla-aviso');
  if (aviso) {
    aviso.innerHTML = `✨ Precargado desde <strong>${esc(p.nombre)}</strong>. Solo elige las fechas y revisa los datos.`
      + (tipoNoDisponible
          ? `<br><span style="color:var(--amber)">⚠ Esta solicitud frecuente se guardó con el formulario anterior. Revisa el tipo de carga: el sistema recalculó la unidad.</span>`
          : '');
    aviso.style.display = '';
  }
  // Al reusar no se vuelve a guardar como frecuente
  const chk = document.getElementById('np-guardar-plantilla');
  if (chk) { chk.checked = false; togglePlantillaNombre(); }

  // Contador de uso: sirve para ordenar por utilidad real (fire-and-forget)
  sb.from('plantillas_pedido').update({
    veces_usada: (p.veces_usada || 0) + 1,
    ultima_vez_usada: new Date().toISOString(),
  }).eq('id', id).then(() => {});
}

function _servicioDePlantilla(p) {
  const t = p.tipo_camion || '';
  if (t.startsWith('Custodio') || t === 'Supervisión remota') return 'custodio';
  if (t.startsWith('Patio') || t === 'Bodega')                return 'patio';
  if (t.startsWith('Lavado') || t === 'Desinfección' || t === 'Lavado Contenedor') return 'lavado';
  return 'camion';
}

function eliminarPlantilla(id) {
  const p = _plantillas.find(x => x.id === id);
  showConfirm(`¿Eliminar "${p?.nombre || 'esta solicitud frecuente'}"? Tus solicitudes ya enviadas no se afectan.`, async () => {
    const { error } = await sb.from('plantillas_pedido').delete().eq('id', id);
    if (error) { showToast('Error al eliminar: ' + error.message, 'error'); return; }
    showToast('Solicitud frecuente eliminada');
    await cargarPlantillas();
  }, { danger: true, confirmLabel: 'Eliminar' });
}

// ── LISTAR ─────────────────────────────────────────────

async function cargarPlantillas() {
  if (!currentUser.id || currentUser.rol !== 'cliente') { _plantillas = []; _renderPlantillas(); return; }
  const { data, error } = await sb.from('plantillas_pedido')
    .select('*')
    .eq('cliente_id', currentUser.id)
    .order('veces_usada', { ascending: false })
    .order('created_at',  { ascending: false });
  if (error) { console.error('Error al cargar frecuentes:', error); _plantillas = []; }
  else _plantillas = data || [];
  _renderPlantillas();
}

function _renderPlantillas() {
  const cont = document.getElementById('ped-plantillas');
  if (!cont) return;
  if (!_plantillas.length) { cont.innerHTML = ''; cont.style.display = 'none'; return; }

  cont.style.display = '';
  cont.innerHTML = `
    <div class="plant-titulo">⭐ Tus solicitudes frecuentes</div>
    <div class="plant-grid">
      ${_plantillas.map(p => {
        const ruta = p.origen
          ? `${esc(p.origen.split(',')[0])}${p.destino ? ' → ' + esc(p.destino.split(',')[0]) : ''}`
          : esc(p.tipo_camion || '—');
        const detalles = [
          p.tipo_camion ? esc(p.tipo_camion) : '',
          p.peso_carga  ? `${p.peso_carga} ton` : '',
          p.tipo_carga  ? esc(p.tipo_carga) : '',
        ].filter(Boolean).join(' · ');
        return `
          <div class="plant-card">
            <button class="plant-usar" onclick="usarPlantilla('${p.id}')" title="Usar esta solicitud">
              <span class="plant-nombre">${esc(p.nombre)}</span>
              <span class="plant-ruta">${ruta}</span>
              ${detalles ? `<span class="plant-detalle">${detalles}</span>` : ''}
              ${p.veces_usada ? `<span class="plant-veces">Usada ${p.veces_usada} ${p.veces_usada === 1 ? 'vez' : 'veces'}</span>` : ''}
            </button>
            <button class="plant-borrar" onclick="eliminarPlantilla('${p.id}')" title="Eliminar">🗑</button>
          </div>`;
      }).join('')}
    </div>`;
}
