// ══════════════════════════════════════════════════════════════════════════
//  PRUEBA 1 — DIAGNÓSTICO (SOLO LECTURA)
//  No inserta, no actualiza y no borra nada. Entra con las dos cuentas
//  reales, revisa qué ve cada rol y busca incoherencias en los datos que ya
//  existen en producción.
//  Correr:  node pruebas/01-diagnostico.mjs
// ══════════════════════════════════════════════════════════════════════════
import { Sesion, sesionAnonima, leerCredenciales, exigirCuentas, leerAmbientePruebas, CONFIG, RAIZ } from './lib/api.mjs';
import { exigirParidad, resumenParidad } from './lib/paridad.mjs';
import { Reporte, hoyISO, diasDesde } from './lib/reporte.mjs';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const R = new Reporte('PortGo — Diagnóstico de solo lectura');
const HOY = hoyISO();
const AHORA = new Date().toISOString();
// Por omisión corre contra producción, que es seguro porque este archivo solo
// lee. Con --pruebas apunta al proyecto portgo-pruebas.
const CONTRA_PRUEBAS = process.argv.includes('--pruebas');
let cred, AMB, PARIDAD = null;
try {
  cred = exigirCuentas(leerCredenciales(), ['superadmin', 'empresa']);
  AMB = CONTRA_PRUEBAS ? leerAmbientePruebas() : CONFIG;
  // Contra producción no hace falta: se está leyendo la fuente de verdad. Con
  // --pruebas sí, porque un diagnóstico sobre una copia desfasada describe una
  // base que no existe en ningún lado.
  if (CONTRA_PRUEBAS) PARIDAD = exigirParidad(AMB);
} catch (e) { console.error(`\n${e.message}\n`); process.exit(1); }
console.log(`\nAmbiente: ${AMB.nombre} · ${AMB.url}`);
if (PARIDAD) console.log(`Paridad: ${resumenParidad(PARIDAD)}`);

const lista = (r) => (Array.isArray(r.data) ? r.data : []);
const corta = (arr, n = 8) => arr.slice(0, n);
const id8 = (x) => String(x || '').slice(0, 8);

// ── 1. SESIÓN Y ROLES ─────────────────────────────────────────────────────
R.seccion('1. Sesión y roles');

const sa = new Sesion('superadmin', AMB);
const emp = new Sesion('empresa', AMB);

for (const [ses, datos, rolEsperado] of [[sa, cred.superadmin, 'superadmin'], [emp, cred.empresa, 'admin']]) {
  const r = await ses.login(datos.email, datos.password);
  if (!r.ok) { R.falla(`No pude entrar como ${ses.etiqueta} (${datos.email})`, r.error); continue; }
  R.ok(`Login ${ses.etiqueta}: ${ses.email}`);
  if (!ses.perfil) {
    R.falla(`${ses.etiqueta} entró pero NO tiene fila en perfiles`,
      'La app arma la UI con currentUser.rol; sin perfil el rol queda indefinido y la interfaz se rompe.');
  } else {
    if (ses.perfil.rol !== rolEsperado) R.aviso(`${ses.etiqueta} tiene rol "${ses.perfil.rol}", esperaba "${rolEsperado}"`);
    else R.ok(`Rol correcto: ${ses.perfil.rol}`);
    if (ses.perfil.aprobacion_cuenta) R.aviso(`Cuenta ${ses.etiqueta} en estado "${ses.perfil.aprobacion_cuenta}" (no activa)`);
  }
}
if (!sa.autenticada || !emp.autenticada) {
  R.falla('Sin las dos sesiones no puedo seguir. Revisa las credenciales.');
  R.resumen(); R.guardar('01-diagnostico'); process.exit(1);
}

// ── 2. FRONTERA ANÓNIMA ───────────────────────────────────────────────────
R.seccion('2. Qué ve alguien sin iniciar sesión');

const anon = sesionAnonima(AMB);
const TABLAS_PRIVADAS = ['perfiles', 'pedidos', 'reservaciones', 'mensajes', 'notificaciones',
  'ofertas', 'solicitudes_cuenta', 'solicitudes_arco', 'consentimientos',
  'calificaciones', 'operadores', 'expedientes', 'expediente_documentos'];
for (const t of TABLAS_PRIVADAS) {
  const r = await anon.select(t, 'select=*&limit=3');
  const filas = lista(r);
  if (r.ok && filas.length > 0) {
    R.falla(`anon LEE ${t} (${filas.length} filas de muestra)`,
      `Columnas expuestas: ${Object.keys(filas[0]).slice(0, 14).join(', ')}`);
  } else {
    R.ok(`${t} cerrada a anon${r.ok ? '' : ` (HTTP ${r.status})`}`);
  }
}
for (const t of ['catalogos', 'app_config', 'documentos_catalogo']) {
  const r = await anon.select(t, 'select=*&limit=3');
  R.info(r.ok && lista(r).length
    ? `${t}: legible por anon — aceptable si el formulario de registro necesita los combos`
    : `${t}: no legible por anon (HTTP ${r.status})`);
}

// ── 3. CONSISTENCIA CÓDIGO ↔ BASE DE DATOS ────────────────────────────────
R.seccion('3. Consistencia entre el cliente web y la base');

const jsDir = join(RAIZ, 'js');
const todoJS = readdirSync(jsDir).filter(f => f.endsWith('.js'))
  .map(f => readFileSync(join(jsDir, f), 'utf8')).join('\n');
const appHtml = readFileSync(join(RAIZ, 'app.html'), 'utf8');

// 3.1 tracking: TRACKING_POR_TIPO (js) vs tracking_pasos() (sql)
const srcTracking = readFileSync(join(jsDir, 'tracking.js'), 'utf8');
const bloque = srcTracking.slice(srcTracking.indexOf('TRACKING_POR_TIPO'), srcTracking.indexOf('let trackingReservaId'));
const pasosJS = {};
for (const m of bloque.matchAll(/(\w+):\s*\[([\s\S]*?)\]/g)) {
  pasosJS[m[1]] = [...m[2].matchAll(/key:\s*'([^']+)'/g)].map(x => x[1]);
}
for (const tipo of ['camion', 'custodio', 'patio', 'lavado']) {
  const r = await sa.rpc('tracking_pasos', { p_recurso_tipo: tipo });
  if (!r.ok) { R.falla(`No pude llamar tracking_pasos('${tipo}')`, r.error); continue; }
  const sql = Array.isArray(r.data) ? r.data : [];
  const js = pasosJS[tipo] || [];
  if (JSON.stringify(sql) === JSON.stringify(js)) R.ok(`tracking ${tipo}: JS y SQL coinciden (${sql.length} pasos)`);
  else R.falla(`tracking ${tipo}: JS y SQL NO coinciden`, { js, sql });
}

// 3.2 catálogos que existen en la base pero nadie lee
const cats = await sa.select('catalogos', 'select=clave&limit=1000');
if (cats.ok) {
  const claves = [...new Set(lista(cats).map(c => c.clave))];
  const clienteLee = /from\(['"]catalogos['"]\)/.test(todoJS + appHtml);
  if (claves.length && !clienteLee) {
    R.falla(`catalogos tiene ${claves.length} claves sembradas y ningún archivo del cliente la consulta`,
      `Claves: ${claves.join(', ')}\n` +
      'La promesa era "editar un catálogo ya no requiere deploy", pero los combos siguen escritos a mano en app.html. Cambiar la tabla hoy no cambia nada en la app, y peor: los valores pueden divergir sin que nadie se entere.');
  } else if (claves.length) {
    R.ok(`catalogos con ${claves.length} claves y el cliente sí las lee`);
  }
} else R.aviso('No pude leer catalogos', cats.error);

const cfg = await sa.select('app_config', 'select=clave&limit=100');
if (cfg.ok && lista(cfg).length && !/from\(['"]app_config['"]\)/.test(todoJS + appHtml))
  R.aviso(`app_config tiene ${lista(cfg).length} claves y tampoco se lee desde el cliente`,
    lista(cfg).map(c => c.clave).join(', '));

// 3.3 RPC transaccionales sin usar en el cliente
const RPCS = ['enviar_oferta', 'responder_oferta', 'responder_contraoferta', 'cancelar_reservacion',
  'solicitar_cancelacion', 'registrar_evidencias', 'avanzar_tracking', 'abrir_expediente',
  'calificar_servicio', 'enviar_mensaje', 'recomendar_unidad'];
const sinUsar = [];
for (const fn of RPCS) {
  const r = await sa.rpc(fn, {});                 // esperamos error de argumentos, no 404
  const hayEnDB = r.status !== 404;
  const hayEnJS = new RegExp(`rpc\\(['"]${fn}['"]`).test(todoJS);
  if (hayEnDB && !hayEnJS) sinUsar.push(fn);
  if (!hayEnDB) R.aviso(`La RPC ${fn} no responde en la base (HTTP ${r.status})`, r.error);
}
if (sinUsar.length)
  R.falla(`${sinUsar.length} RPC transaccionales existen en la base y el cliente web no llama ninguna`,
    `${sinUsar.join(', ')}\n` +
    'Cada flujo se sigue haciendo con varias escrituras encadenadas desde el navegador. Si la pestaña se cierra a media secuencia el estado queda partido: unidad ocupada, pedido colgado, oferta aceptada sin reservación.');

// 3.4 el bloqueo de teléfonos del chat
if (/_contieneTelefono/.test(todoJS) && !/rpc\(['"]enviar_mensaje['"]/.test(todoJS))
  R.aviso('El bloqueo de teléfonos del chat vive solo en el navegador',
    'js/chat.js filtra con _contieneTelefono(), pero el insert va directo a la tabla mensajes. Un POST a /rest/v1/mensajes se salta el filtro. La versión servidor está en la RPC enviar_mensaje, que nadie llama.');

// ── 4. SALUD DE LA MÁQUINA DE ESTADOS ─────────────────────────────────────
R.seccion('4. Máquina de estados y datos colgados');

const pedidos = lista(await sa.select('pedidos',
  'select=id,estado,fecha_ini,fecha_fin,created_at,cliente_nombre,cliente_email,tipo_camion,oferta_pendiente_id&limit=2000'));
const cuentaPor = (arr, campo) => Object.entries(arr.reduce((a, x) => (a[x[campo]] = (a[x[campo]] || 0) + 1, a), {}))
  .map(([k, v]) => `${k}: ${v}`).join(' · ');
R.info(`Pedidos en la base: ${pedidos.length}`, cuentaPor(pedidos, 'estado'));

const vencidosSinExpirar = pedidos.filter(p => p.estado === 'acordado' && p.fecha_fin && p.fecha_fin < HOY);
if (vencidosSinExpirar.length)
  R.falla(`${vencidosSinExpirar.length} pedidos siguen "acordado" con fecha_fin ya pasada (deberían ser "expirado")`,
    corta(vencidosSinExpirar).map(p => `${id8(p.id)} fin=${p.fecha_fin} (${diasDesde(p.fecha_fin)} días)`).join('\n') +
    '\nrenderPedidos() solo los expira cuando alguien abre "Solicitudes" en la web. La migración que lo automatiza (20260810130000) está marcada OPCIONAL y no está aplicada.');
else R.ok('Ningún pedido "acordado" con fecha vencida');

const ofertas = lista(await sa.select('ofertas',
  'select=id,pedido_id,estado,expira_en,precio_oferta,contra_precio,ronda,admin_id,created_at&limit=2000'));
R.info(`Ofertas en la base: ${ofertas.length}`, cuentaPor(ofertas, 'estado'));

const ofVencidas = ofertas.filter(o => ['enviada', 'contra_oferta'].includes(o.estado) && o.expira_en && o.expira_en < AHORA);
if (ofVencidas.length)
  R.falla(`${ofVencidas.length} ofertas siguen vivas con expira_en ya pasado`,
    corta(ofVencidas).map(o => `${id8(o.id)} estado=${o.estado} venció hace ${diasDesde(o.expira_en)} días`).join('\n'));
else R.ok('Ninguna oferta vencida sin cerrar');

const conOfertaViva = new Set(ofertas
  .filter(o => ['enviada', 'contra_oferta'].includes(o.estado) && (!o.expira_en || o.expira_en >= AHORA))
  .map(o => o.pedido_id));
const negocSinOfertas = pedidos.filter(p => p.estado === 'en_negociacion' && !conOfertaViva.has(p.id));
if (negocSinOfertas.length)
  R.falla(`${negocSinOfertas.length} pedidos en "en_negociacion" sin ninguna oferta viva (deberían volver a "abierto")`,
    corta(negocSinOfertas).map(p => id8(p.id)).join(', ') +
    '\nMientras tanto ninguna empresa los ve en el listado de ofertables: el cliente espera propuestas que nadie puede mandar.');
else R.ok('Todo pedido en negociación tiene al menos una oferta viva');

const revisionVieja = pedidos.filter(p => p.estado === 'pendiente_revision' && diasDesde(p.created_at) > 2);
if (revisionVieja.length)
  R.aviso(`${revisionVieja.length} pedidos llevan más de 2 días esperando revisión del superadmin`,
    corta(revisionVieja).map(p => `${id8(p.id)} — ${diasDesde(p.created_at)} días — ${p.cliente_nombre || ''}`).join('\n') +
    '\nEl cliente no ve por qué su solicitud no avanza: no hay aviso automático ni tiempo comprometido.');

const acuerdoPend = pedidos.filter(p => p.estado === 'pendiente_acuerdo' && diasDesde(p.created_at) > 2);
if (acuerdoPend.length)
  R.aviso(`${acuerdoPend.length} acuerdos esperan aprobación del superadmin`, corta(acuerdoPend).map(p => id8(p.id)).join(', '));

const reservas = lista(await sa.select('reservaciones',
  'select=id,pedido_id,estado,tracking_estado,recurso_tipo,unidad,propietario_id,cliente_user_id,fecha_ini,fecha_fin,completado_en,calificado,pagado,fecha_vencimiento_pago,plazo_pago,precio_acordado,evidencias,evidencias_cliente&limit=2000'));
R.info(`Reservaciones en la base: ${reservas.length}`, cuentaPor(reservas, 'estado'));

const mapaPedido = Object.fromEntries(pedidos.map(p => [p.id, p]));
const reservaIncoherente = reservas.filter(r => r.pedido_id && mapaPedido[r.pedido_id] &&
  ['Pendiente', 'Activa'].includes(r.estado) && mapaPedido[r.pedido_id].estado !== 'acordado');
if (reservaIncoherente.length)
  R.falla(`${reservaIncoherente.length} reservaciones vivas cuyo pedido NO está "acordado"`,
    corta(reservaIncoherente).map(r => `reserva ${id8(r.id)} (${r.estado}) → pedido ${id8(r.pedido_id)} está "${mapaPedido[r.pedido_id].estado}"`).join('\n'));
else R.ok('Reservaciones vivas coherentes con el estado de su pedido');

const compSinFecha = reservas.filter(r => r.estado === 'Completada' && !r.completado_en);
if (compSinFecha.length)
  R.falla(`${compSinFecha.length} reservaciones "Completada" sin completado_en`, corta(compSinFecha).map(r => id8(r.id)).join(', '));

const trackingRaro = reservas.filter(r => {
  const pasos = pasosJS[r.recurso_tipo] || pasosJS.camion || [];
  return r.tracking_estado && !pasos.includes(r.tracking_estado);
});
if (trackingRaro.length)
  R.falla(`${trackingRaro.length} reservaciones con tracking_estado fuera de la secuencia de su recurso_tipo`,
    corta(trackingRaro).map(r => `${id8(r.id)} tipo=${r.recurso_tipo} estado="${r.tracking_estado}"`).join('\n') +
    '\nPasa cuando se cambia el recurso_tipo después de avanzar el seguimiento: la barra de progreso no encuentra el paso y se queda en cero.');
else R.ok('Todos los tracking_estado pertenecen a la secuencia de su tipo');

// Unidades ocupadas sin reserva viva — la fuga clásica del cancelar no atómico
const VIVAS = ['Pendiente', 'Activa', 'PorAprobar', 'CancelacionSolicitada'];
const ocupadasLegitimas = new Set(reservas.filter(r => VIVAS.includes(r.estado)).map(r => r.unidad));
for (const tabla of ['camiones', 'custodios', 'patios', 'lavados']) {
  const r = await sa.select(tabla, 'select=id,estado,aprobacion,propietario_id&limit=2000');
  if (!r.ok) { R.aviso(`No pude leer ${tabla}`, r.error); continue; }
  const rec = lista(r);
  const fugados = rec.filter(x => x.estado === 'ocupado' && !ocupadasLegitimas.has(x.id));
  if (fugados.length)
    R.falla(`${tabla}: ${fugados.length} recursos en "ocupado" sin ninguna reservación viva`,
      corta(fugados).map(x => x.id).join(', ') +
      '\nQuedan invisibles para nuevas ofertas hasta que alguien los libere a mano. Es exactamente lo que deja cortar a media secuencia cancelarReserva() o cerrarAcuerdo().');
  else if (rec.length) R.ok(`${tabla}: sin ocupados huérfanos (${rec.length} recursos)`);
}

// ── 5. LA VISTA DE LA EMPRESA ─────────────────────────────────────────────
R.seccion('5. Operación de la empresa');

const misCamiones = lista(await emp.select('camiones', `select=id,tipo,estado,aprobacion&propietario_id=eq.${emp.userId}&limit=500`));
const misOperadores = lista(await emp.select('operadores', `select=id,nombre,aprobacion&propietario_id=eq.${emp.userId}&limit=500`));
const camAprob = misCamiones.filter(c => c.aprobacion === 'aprobada');
const opAprob = misOperadores.filter(o => o.aprobacion === 'aprobada');
R.info(`Flota: ${misCamiones.length} camiones (${camAprob.length} aprobados) · ${misOperadores.length} operadores (${opAprob.length} aprobados)`);
if (!camAprob.length) R.aviso('La empresa no tiene ningún camión aprobado: no puede ofertar en servicios de camión');
if (!opAprob.length) R.aviso('La empresa no tiene ningún operador aprobado: enviar_oferta rechaza toda oferta de camión sin chofer asignado');

const ofertables = lista(await emp.select('pedidos',
  'select=id,estado,tipo_camion,cliente_nombre,cliente_email,origen,destino&estado=in.(abierto,en_negociacion)&limit=500'));
R.info(`Pedidos ofertables que ve la empresa: ${ofertables.length}`);

const conEmail = ofertables.filter(p => p.cliente_email);
if (conEmail.length)
  R.falla(`La empresa lee cliente_email en ${conEmail.length} pedidos que todavía no le fueron adjudicados`,
    `Ejemplo: pedido ${id8(conEmail[0].id)} → ${conEmail[0].cliente_email}\n` +
    'El chat bloquea números de teléfono para que no se salten la plataforma, pero el correo del cliente viaja en claro en el propio listado de solicitudes. La protección anti-desintermediación se cae por ahí.');
else R.ok('La empresa no ve el correo del cliente en pedidos abiertos');

const tiposPedidos = new Set(ofertables.map(p => p.tipo_camion).filter(Boolean));
const tiposFlota = new Set(camAprob.map(c => c.tipo));
const sinMatch = [...tiposPedidos].filter(t => !tiposFlota.has(t));
if (sinMatch.length && camAprob.length)
  R.info(`Tipos solicitados que la flota aprobada no cubre: ${sinMatch.join(', ')}`,
    'enviar_oferta exige que el tipo del camión sea idéntico al tipo_camion del pedido. Sin equivalencias, la empresa ve solicitudes en las que no puede participar y no se le explica por qué.');

// ¿Puede la empresa ver pedidos de otras empresas ya adjudicados?
const ajenos = lista(await emp.select('reservaciones', `select=id,propietario_id,cliente,precio_acordado&propietario_id=neq.${emp.userId}&limit=50`));
if (ajenos.length)
  R.falla(`La empresa lee ${ajenos.length} reservaciones que no son suyas`,
    `Ejemplo: ${id8(ajenos[0].id)} de ${id8(ajenos[0].propietario_id)} — precio $${ajenos[0].precio_acordado}\n` +
    'Ve los precios cerrados por la competencia.');
else R.ok('La empresa solo ve sus propias reservaciones');

// ── 6. COBROS Y EXPEDIENTES ───────────────────────────────────────────────
R.seccion('6. Cobros y expedientes');

const completadas = reservas.filter(r => r.estado === 'Completada');
R.info(`Reservaciones completadas: ${completadas.length} · pagadas: ${completadas.filter(r => r.pagado).length}`);

const sinVencimiento = completadas.filter(r => !r.pagado && !r.fecha_vencimiento_pago);
if (sinVencimiento.length)
  R.aviso(`${sinVencimiento.length} reservaciones completadas y sin pagar no tienen fecha_vencimiento_pago`,
    corta(sinVencimiento).map(r => `${id8(r.id)} plazo="${r.plazo_pago || '—'}" $${r.precio_acordado}`).join('\n') +
    '\nestadoCobro() deriva todo de esa fecha: sin ella el cobro nunca aparece como vencido y no entra en el badge de la portada.');

const vencidasSinPagar = completadas.filter(r => !r.pagado && r.fecha_vencimiento_pago && r.fecha_vencimiento_pago < HOY);
if (vencidasSinPagar.length)
  R.info(`${vencidasSinPagar.length} cobros vencidos sin pagar`,
    corta(vencidasSinPagar).map(r => `${id8(r.id)} venció hace ${diasDesde(r.fecha_vencimiento_pago)} días — $${r.precio_acordado}`).join('\n'));

const sinCalificar = completadas.filter(r => !r.calificado && r.completado_en && diasDesde(r.completado_en) > 7);
if (sinCalificar.length)
  R.aviso(`${sinCalificar.length} servicios completados hace más de una semana siguen sin calificar`,
    'La calificación es voluntaria y no se recuerda: la reputación de las empresas se construye con muy pocos datos.');

const porAprobar = reservas.filter(r => r.estado === 'PorAprobar');
const faltaEvidencia = porAprobar.filter(r => !(r.evidencias || []).length || !(r.evidencias_cliente || []).length);
if (faltaEvidencia.length)
  R.aviso(`${faltaEvidencia.length} cierres "PorAprobar" sin evidencia de las dos partes`,
    corta(faltaEvidencia).map(r => `${id8(r.id)} empresa=${(r.evidencias || []).length} cliente=${(r.evidencias_cliente || []).length}`).join('\n') +
    '\nEl superadmin no debería poder aprobar el cierre hasta que ambas suban evidencia.');

const exp = lista(await sa.select('expedientes', 'select=id,reserva_id,etapa,estado,fecha_limite_vacios,solicitado_en&limit=1000'));
R.info(`Expedientes: ${exp.length}`, exp.length ? cuentaPor(exp, 'estado') : '');
const demoras = exp.filter(e => e.etapa === 'entrega_vacios' && e.fecha_limite_vacios && e.fecha_limite_vacios < HOY && e.estado !== 'completo');
if (demoras.length)
  R.falla(`${demoras.length} expedientes de entrega de vacíos pasados de la fecha límite y sin cerrar`,
    corta(demoras).map(e => `${id8(e.id)} límite=${e.fecha_limite_vacios} → ${diasDesde(e.fecha_limite_vacios)} días de demora acumulada`).join('\n') +
    '\nAhí es donde corre el dinero. La app guarda la fecha pero no avisa, no cuenta los días ni calcula el cargo.');

// ── 7. CUENTAS, PRIVACIDAD Y VIGENCIAS ────────────────────────────────────
R.seccion('7. Cuentas, privacidad y vigencias');

const solic = lista(await sa.select('solicitudes_cuenta', 'select=id,estado,created_at,email&limit=500'));
const solPend = solic.filter(s => s.estado === 'pendiente');
if (solPend.length)
  R.aviso(`${solPend.length} solicitudes de cuenta pendientes`,
    corta(solPend).map(s => `${s.email || id8(s.id)} — ${diasDesde(s.created_at)} días esperando`).join('\n'));
else R.ok('Sin solicitudes de cuenta pendientes');

const arco = lista(await sa.select('solicitudes_arco', 'select=id,tipo,estado,created_at&limit=500'));
const arcoTarde = arco.filter(a => ['pendiente', 'en_proceso'].includes(a.estado) && diasDesde(a.created_at) > 20);
if (arcoTarde.length)
  R.falla(`${arcoTarde.length} solicitudes ARCO llevan más de 20 días sin resolver`,
    corta(arcoTarde).map(a => `${a.tipo} — ${diasDesde(a.created_at)} días`).join('\n') +
    '\nLa ley da 20 días para responder. La app no lleva ese reloj en ninguna pantalla.');
else if (arco.length) R.ok(`${arco.length} solicitudes ARCO, ninguna fuera de plazo`);
else R.info('Sin solicitudes ARCO registradas');

const empresas = lista(await sa.select('perfiles',
  'select=user_id,nombre,rol,fecha_vencimiento_permiso_sct,fecha_vencimiento_seguro_rc,fecha_vencimiento_seguro_carga&rol=eq.admin&limit=500'));
const problemasDoc = [];
for (const e of empresas) {
  for (const [col, etiqueta] of [['fecha_vencimiento_permiso_sct', 'Permiso SCT'],
    ['fecha_vencimiento_seguro_rc', 'Seguro RC'],
    ['fecha_vencimiento_seguro_carga', 'Seguro de carga']]) {
    if (!e[col]) problemasDoc.push(`${e.nombre}: ${etiqueta} sin fecha registrada`);
    else if (e[col] < HOY) problemasDoc.push(`${e.nombre}: ${etiqueta} venció hace ${diasDesde(e[col])} días`);
  }
}
if (problemasDoc.length)
  R.aviso(`${problemasDoc.length} documentos de empresa vencidos o sin fecha (sobre ${empresas.length} empresas)`,
    corta(problemasDoc, 12).join('\n') +
    '\nNada impide que una empresa con papeles vencidos siga ofertando y ganando viajes: vigencias.js solo lo pinta en una pantalla que hay que ir a ver.');
else R.ok(`Documentos vigentes en las ${empresas.length} empresas`);

R.resumen();
R.guardar('01-diagnostico');
