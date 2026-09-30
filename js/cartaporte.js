// ── CARTA PORTE DE REFERENCIA ──────────────────────────
//
// Documento de referencia interna, NO un Complemento Carta Porte del CFDI:
// no está timbrado, no pasa por un PAC, no tiene validez fiscal. Arma un PDF
// en el navegador (Imprimir → Guardar como PDF, sin librería nueva) con los
// datos que las Etapas 1-5 del plan ya reunieron. Lo que falte se imprime en
// blanco — nunca se inventa un dato.
//
// Antes esto hacía consultas directas a `perfiles` por cliente_user_id y por
// propietario_id — y desde 20260901120000_perfiles_cierra_leer_nombre_empresa
// (antes de esta sesión), `perfiles` solo se lee la fila propia o, siendo
// superadmin, cualquiera. Cuando quien generaba el documento era la EMPRESA,
// su consulta al perfil del CLIENTE la bloqueaba RLS en silencio: el
// remitente salía en blanco mientras el transportista —su propia fila—
// salía completo. Medido el 2026-09-30 contra portgo-pruebas: el perfil del
// cliente tenía todo el dato, y aun así no llegaba.
//
// Se corrige con la RPC datos_carta_porte (20260930120000): verifica que el
// llamador sea el cliente, el propietario o el superadmin de ESA
// reservación, y entrega los dos lados en una sola llamada — mismo patrón
// que registrar_evidencias/calificar_servicio. De paso resuelve el otro
// hueco: ahora cliente Y propietario pueden generarla, no solo el dueño.

const _CP_AVISO = 'Documento de referencia interna — no es un Complemento Carta Porte del CFDI y no tiene validez fiscal ante el SAT.';

async function generarCartaPorte(reservaId) {
  const { data, error } = await sb.rpc('datos_carta_porte', { p_reserva_id: reservaId });
  if (error || !data) { showToast('No se pudo generar el documento: ' + (error?.message || 'sin datos'), 'error'); return; }

  const html = _cartaPorteHTML({
    r: data.reservacion, pedido: data.pedido, cliente: data.cliente,
    transportista: data.transportista, camion: data.camion, operador: data.operador,
  });

  const w = window.open('', '_blank');
  if (!w) { showToast('El navegador bloqueó la ventana. Permite pop-ups para generar el documento.', 'error'); return; }
  w.document.write(html);
  w.document.close();
}

// '—' para lo que falta: nunca se inventa, y así queda visualmente claro qué
// dato hay que completar a mano antes de usar el documento en la carretera.
const _cp = v => {
  const s = (v ?? '').toString().trim();
  return s ? esc(s) : '<span class="cp-falta">—</span>';
};
const _cpDomicilio = (calle, colonia, cp, ciudad, estado) => {
  const partes = [calle, colonia, cp ? `C.P. ${cp}` : null, ciudad, estado].filter(Boolean);
  return partes.length ? esc(partes.join(', ')) : '<span class="cp-falta">— domicilio sin capturar —</span>';
};

function _cartaPorteHTML({ r, pedido, cliente, transportista, camion, operador }) {
  const operadorNombre = operador
    ? [operador.nombre, operador.primer_apellido, operador.segundo_apellido].filter(Boolean).join(' ')
    : r.operador_nombre;

  const mercancia = [];
  if (pedido?.tipo_carga)    mercancia.push(['Descripción', pedido.tipo_carga]);
  if (pedido?.categoria_carga) mercancia.push(['Categoría', pedido.categoria_carga]);
  if (pedido?.peso_carga)    mercancia.push(['Peso', `${pedido.peso_carga} kg`]);
  if (pedido?.num_contenedores) mercancia.push(['Contenedores', pedido.num_contenedores]);
  if (pedido?.hazmat_clase || pedido?.hazmat_un)
    mercancia.push(['Materiales peligrosos', [pedido?.hazmat_clase, pedido?.hazmat_un].filter(Boolean).join(' / ')]);
  mercancia.push(['Clave prod./serv. SAT', pedido?.clave_prod_serv_sat || null]);

  const filaDato = (label, val) => `<tr><td class="cp-label">${esc(label)}</td><td>${_cp(val)}</td></tr>`;

  return `<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<title>Carta Porte de referencia — ${esc(r.id)}</title>
<style>
  body { font-family: Arial, Helvetica, sans-serif; font-size: 13px; color: #111; max-width: 780px; margin: 24px auto; padding: 0 16px; }
  h1 { font-size: 18px; margin: 0 0 4px; }
  h2 { font-size: 13px; text-transform: uppercase; letter-spacing: .04em; color: #444; margin: 22px 0 8px; border-bottom: 1px solid #ccc; padding-bottom: 4px; }
  .cp-folio { color: #555; margin: 0 0 16px; }
  .cp-aviso { background: #fff3cd; border: 1.5px solid #e0a800; border-radius: 6px; padding: 10px 14px; font-weight: bold; font-size: 12.5px; margin-bottom: 18px; }
  table { width: 100%; border-collapse: collapse; }
  td { padding: 4px 6px; vertical-align: top; border-bottom: 1px solid #eee; }
  .cp-label { width: 220px; color: #555; font-weight: bold; }
  .cp-falta { color: #b91c1c; font-style: italic; }
  .cp-cols { display: flex; gap: 24px; }
  .cp-cols > div { flex: 1; }
  .cp-print-bar { text-align: right; margin-bottom: 14px; }
  .cp-print-bar button { font: inherit; padding: 8px 16px; border-radius: 6px; border: 1px solid #888; background: #f5f5f5; cursor: pointer; }
  @media print { .cp-print-bar { display: none; } }
</style></head>
<body>
  <div class="cp-print-bar"><button onclick="window.print()">🖨 Imprimir / Guardar como PDF</button></div>
  <h1>Carta Porte — Documento de referencia</h1>
  <p class="cp-folio">Reservación ${esc(r.id)} · Generado ${fmtFecha(new Date().toISOString())}</p>
  <div class="cp-aviso">⚠ ${esc(_CP_AVISO)}</div>

  <div class="cp-cols">
    <div>
      <h2>Remitente (cliente)</h2>
      <table>
        ${filaDato('Nombre / Razón social', cliente?.razon_social || cliente?.nombre || r.cliente)}
        ${filaDato('RFC', cliente?.rfc)}
        <tr><td class="cp-label">Domicilio</td><td>${_cpDomicilio(cliente?.calle, cliente?.colonia, cliente?.cp, cliente?.ciudad, cliente?.estado_mx)}</td></tr>
      </table>
    </div>
    <div>
      <h2>Transportista</h2>
      <table>
        ${filaDato('Razón social', transportista?.razon_social)}
        ${filaDato('RFC', transportista?.rfc)}
        ${filaDato('Permiso SCT (empresa)', transportista?.permiso_sct)}
        <tr><td class="cp-label">Domicilio</td><td>${_cpDomicilio(transportista?.calle, transportista?.colonia, transportista?.cp, transportista?.ciudad, transportista?.estado_mx)}</td></tr>
      </table>
    </div>
  </div>

  <h2>Ubicaciones</h2>
  <div class="cp-cols">
    <div>
      <strong>Origen</strong>
      <table>
        <tr><td class="cp-label">Dirección</td><td>${_cp(pedido?.origen)}</td></tr>
        <tr><td class="cp-label">Colonia / CP</td><td>${_cp([pedido?.origen_colonia, pedido?.origen_cp].filter(Boolean).join(' · '))}</td></tr>
        <tr><td class="cp-label">Ciudad / Estado</td><td>${_cp([pedido?.origen_ciudad, pedido?.origen_estado].filter(Boolean).join(', '))}</td></tr>
        <tr><td class="cp-label">Fecha</td><td>${_cp(r.fecha_ini ? fmtFecha(r.fecha_ini) : null)}</td></tr>
      </table>
    </div>
    <div>
      <strong>Destino</strong>
      <table>
        <tr><td class="cp-label">Dirección</td><td>${_cp(pedido?.destino)}</td></tr>
        <tr><td class="cp-label">Colonia / CP</td><td>${_cp([pedido?.destino_colonia, pedido?.destino_cp].filter(Boolean).join(' · '))}</td></tr>
        <tr><td class="cp-label">Ciudad / Estado</td><td>${_cp([pedido?.destino_ciudad, pedido?.destino_estado].filter(Boolean).join(', '))}</td></tr>
        <tr><td class="cp-label">Fecha</td><td>${_cp(r.fecha_fin ? fmtFecha(r.fecha_fin) : null)}</td></tr>
      </table>
    </div>
  </div>

  <h2>Mercancía</h2>
  <table>${mercancia.map(([l, v]) => filaDato(l, v)).join('')}</table>

  <h2>Autotransporte</h2>
  <table>
    ${filaDato('Unidad', r.unidad)}
    ${filaDato('Configuración vehicular (SAT)', camion?.configuracion_vehicular)}
    ${filaDato('Placas', camion?.placas)}
    ${filaDato('Permiso SCT (unidad)', camion?.numero_permiso_sct)}
  </table>

  <h2>Figura de transporte (operador)</h2>
  <table>
    ${filaDato('Nombre', operadorNombre)}
    ${filaDato('CURP', operador?.curp)}
    ${filaDato('RFC', operador?.rfc)}
    ${filaDato('Número de licencia', operador?.num_licencia)}
  </table>
</body></html>`;
}
