// ══════════════════════════════════════════════════════════════════════════
//  PRUEBA 3 — FLUJO COMPLETO CON REGISTROS SIMULADOS
//
//  Recorre el ciclo entero como lo haría gente real: el cliente publica, el
//  superadmin revisa, dos empresas compiten, hay contraoferta, se cierra el
//  acuerdo, se sigue el viaje, se suben evidencias, se cobra y se califica.
//
//  Además de comprobar que el camino feliz funciona, prueba lo que NO debería
//  poder hacerse (sección 9). Ahí es donde suelen aparecer los agujeros: una
//  empresa tocando la reservación de otra, un cliente aprobando su propio
//  acuerdo, ofertar con una unidad ajena.
//
//  ⚠ Solo corre contra el proyecto de pruebas. Nunca contra producción.
//  Antes:  node pruebas/02-sembrar.mjs
//  Correr: node pruebas/03-flujo-completo.mjs
// ══════════════════════════════════════════════════════════════════════════
import { Sesion, leerAmbientePruebas } from './lib/api.mjs';
import { exigirParidad, resumenParidad } from './lib/paridad.mjs';
import { Reporte } from './lib/reporte.mjs';
import { CUENTAS, CLAVE, cuenta } from './lib/cuentas.mjs';

const R = new Reporte('PortGo — Flujo completo con registros simulados');

// Lo que este guion mide solo vale si la base de abajo es la de producción.
// exigirParidad() aborta si el sello de supabase/verificar-paridad.sh falta,
// está viejo o dice que las bases divergen.
let AMB, PARIDAD;
try {
  AMB = leerAmbientePruebas();
  PARIDAD = exigirParidad(AMB);
} catch (e) { console.error(`\n${e.message}\n`); process.exit(1); }

console.log(`\nAmbiente: ${AMB.url}`);
console.log(`Paridad: ${resumenParidad(PARIDAD)}\n`);

R.seccion('0. Ambiente');
R[PARIDAD.omitida ? 'aviso' : 'info'](resumenParidad(PARIDAD));

const MARCA = `PRUEBA-${new Date().toISOString().slice(0, 16).replace(/[-:T]/g, '')}`;

// Copia exacta de PLAZO_PAGO_DIAS y calcularVencimientoPago (js/cobros.js).
// Se replica en vez de inventar el cálculo: así la prueba mide lo que la app
// hace de verdad, incluidos sus huecos.
const PLAZO_PAGO_DIAS = {
  'Anticipado': 0, 'Contra entrega': 0, '3 días': 3, '7 días': 7,
  '15 días': 15, '30 días': 30, '45 días': 45, '60 días': 60,
};
function plazoADias(plazo) {
  if (!plazo) return null;
  if (PLAZO_PAGO_DIAS[plazo] !== undefined) return PLAZO_PAGO_DIAS[plazo];
  const m = String(plazo).match(/\d+/);
  return m ? parseInt(m[0], 10) : null;
}
function calcularVencimiento(plazo, desdeISO) {
  const dias = plazoADias(plazo);
  if (dias === null) return null;
  const d = new Date(desdeISO);
  d.setDate(d.getDate() + dias);
  return d.toISOString().split('T')[0];
}
const dia = (n) => new Date(Date.now() + n * 86400000).toISOString().slice(0, 10);
const uno = (r) => (Array.isArray(r.data) ? r.data[0] : r.data);

// ── Helpers de aserción ───────────────────────────────────────────────────
let cortado = false;

// Un paso del camino feliz: si falla, lo que venga después ya no tiene
// sentido, así que se marca la corrida como cortada.
async function paso(desc, fn, { critico = true } = {}) {
  if (cortado) return null;
  try {
    const r = await fn();
    if (r && r.ok === false) {
      R.falla(desc, r.error);
      if (critico) cortado = true;
      return null;
    }
    R.ok(desc);
    return r;
  } catch (e) {
    R.falla(desc, e.message);
    if (critico) cortado = true;
    return null;
  }
}

function verificar(desc, condicion, detalle) {
  if (condicion) R.ok(desc);
  else R.falla(desc, detalle);
  return condicion;
}

// Una prueba negativa: lo esperado es que la operación sea RECHAZADA. Si pasa,
// es un hallazgo, no un éxito.
//
// OJO con el estado HTTP: cuando RLS bloquea un UPDATE, PostgREST responde
// 200 con error null y CERO filas afectadas. Creerle al código de respuesta
// hace que la prueba acuse en falso. Como todas las escrituras van con
// `return=representation`, una lista vacía significa "no cambió nada", o sea
// rechazado. Para los casos que no se pueden juzgar así, se pasa `comprobar`,
// que consulta la fila de verdad y manda sobre todo lo demás.
async function debeFallar(desc, fn, consecuencia, comprobar) {
  // Con la corrida cortada, el estado de la base ya no es el que esta prueba
  // supone: la reservación que debería existir no existe, el acuerdo no se
  // cerró. Evaluarla igual da resultados inventados en las dos direcciones —
  // un "SE PERMITIÓ el doble booking" que en realidad era la primera reserva,
  // y peor, un "Rechazado correctamente" que solo falló porque el id era nulo.
  // El falso aprobado es el más dañino: da confianza donde no la hay.
  if (cortado) { R.aviso(`No evaluado (la corrida se cortó antes): ${desc}`); return; }

  let tuvoEfecto;
  try {
    const r = await fn();
    tuvoEfecto = r && r.ok !== false && !(Array.isArray(r.data) && r.data.length === 0);
  } catch {
    tuvoEfecto = false;
  }
  if (comprobar) tuvoEfecto = await comprobar();
  if (tuvoEfecto) R.falla(`SE PERMITIÓ: ${desc}`, consecuencia);
  else R.ok(`Rechazado correctamente: ${desc}`);
}

// ── 0. SESIONES ───────────────────────────────────────────────────────────
R.seccion('0. Entrar con las cuentas sembradas');

const S = {};
for (const c of CUENTAS) {
  const s = new Sesion(c.llave, AMB);
  const r = await s.login(c.email, CLAVE);
  if (!r.ok) { R.falla(`No pude entrar como ${c.email}`, `${r.error}\n¿Corriste antes node pruebas/02-sembrar.mjs?`); cortado = true; }
  else { R.ok(`${c.rol.padEnd(11)} ${c.email}`); S[c.llave] = s; }
}
if (cortado) { R.resumen(); R.guardar('03-flujo'); process.exit(1); }

const { superadmin: sa, delta, omega, importadora: cli, naviera: cli2 } = S;

// ── 1. EL CLIENTE PUBLICA ─────────────────────────────────────────────────
R.seccion('1. El cliente publica una solicitud');

let pedido = null;
await paso('Cliente crea el pedido (queda en pendiente_revision)', async () => {
  const r = await cli.insert('pedidos', {
    cliente_id: cli.userId,
    cliente_nombre: cuenta('importadora').nombre,
    cliente_email: cuenta('importadora').email,
    tipo_camion: 'Torton caja seca',
    tipo_carga: 'Contenerizada',
    categoria_carga: 'Contenerizada',
    peso_carga: 18000,
    origen: 'Puerto de Veracruz, Ver.',
    destino: 'Parque Industrial Toluca, Edo. Méx.',
    fecha_ini: dia(0),
    fecha_fin: dia(2),
    precio_cliente: 9000,
    plazo_pago: '30 días',
    descripcion: `${MARCA} — contenedor 40' de refacciones`,
    estado: 'pendiente_revision',
  });
  pedido = uno(r);
  return r;
});

if (pedido) verificar('El pedido nace en pendiente_revision, no publicado',
  pedido.estado === 'pendiente_revision',
  `Nació como "${pedido.estado}": se saltaría la revisión del superadmin.`);

await debeFallar('Una empresa ve un pedido que aún no ha sido aprobado',
  async () => {
    const r = await delta.select('pedidos', `select=id&id=eq.${pedido?.id}`);
    return { ok: (r.data || []).length > 0 };
  },
  'Las empresas alcanzan solicitudes que el superadmin todavía no revisa.');

// ── 2. EL SUPERADMIN PUBLICA ──────────────────────────────────────────────
R.seccion('2. El superadmin revisa y publica');

await paso('Superadmin aprueba el pedido → abierto', () =>
  sa.update('pedidos', `id=eq.${pedido.id}`, { estado: 'abierto' }));

await paso('Ahora sí, la empresa lo ve en el listado de ofertables', async () => {
  const r = await delta.select('pedidos', `select=id,estado&id=eq.${pedido.id}`);
  return { ok: (r.data || []).length === 1, error: 'La empresa no ve el pedido ya publicado' };
});

// ── 3. LAS EMPRESAS OFERTAN ───────────────────────────────────────────────
R.seccion('3. Dos empresas compiten');

// Delta oferta por la RPC (el camino atómico que los clientes nativos usarán).
let ofertaDelta = null;
await paso('Delta oferta usando la RPC enviar_oferta', async () => {
  const r = await delta.rpc('enviar_oferta', {
    p_pedido_id: pedido.id,
    p_camion_id: 'DELTA-01',
    p_precio: 8800,
    p_operador_id: 'OP-DELTA-01',
    p_operador_nombre: 'Ramiro Cárdenas',
    p_mensaje: 'Unidad disponible desde hoy.',
  });
  if (r.ok) ofertaDelta = { id: r.data };
  return r;
});

// Omega oferta como lo hace hoy el navegador: insert directo, sin RPC.
let ofertaOmega = null;
await paso('Omega oferta con insert directo (el camino que usa hoy la web)', async () => {
  const r = await omega.insert('ofertas', {
    pedido_id: pedido.id,
    admin_id: omega.userId,
    admin_nombre: cuenta('omega').nombre,
    camion_id: 'OMEGA-01',
    operador_id: 'OP-OMEGA-01',
    precio_oferta: 9400,
  });
  ofertaOmega = uno(r);
  return r;
}, { critico: false });

await paso('El pedido pasó solo a en_negociacion', async () => {
  const r = await sa.select('pedidos', `select=estado&id=eq.${pedido.id}`);
  const est = uno(r)?.estado;
  return { ok: est === 'en_negociacion', error: `Quedó en "${est}" en vez de en_negociacion` };
}, { critico: false });

// El insert directo se salta la transición de estado que sí hace la RPC.
if (ofertaOmega) {
  const r = await sa.select('ofertas', `select=id,expira_en,ronda,estado&id=eq.${ofertaOmega.id}`);
  const o = uno(r);
  verificar('La oferta por insert directo trae fecha de expiración',
    !!o?.expira_en,
    'expira_en quedó vacío: esa oferta no caduca nunca y expire_stale_offers no la va a tocar. La RPC sí la pone.');
}

// ── 4. NEGOCIACIÓN ────────────────────────────────────────────────────────
R.seccion('4. Contraoferta');

await paso('El cliente contraoferta a Delta', () =>
  cli.update('ofertas', `id=eq.${ofertaDelta.id}`, { estado: 'contra_oferta', contra_precio: 8300 }));

await paso('Delta acepta la contraoferta (RPC responder_contraoferta)', () =>
  delta.rpc('responder_contraoferta', { p_oferta_id: ofertaDelta.id, p_accion: 'aceptar' }));

let ofertaFinal = null;
await paso('El precio acordado quedó en el de la contraoferta, no en el original', async () => {
  const r = await sa.select('ofertas', `select=*&id=eq.${ofertaDelta.id}`);
  ofertaFinal = uno(r);
  return {
    ok: Number(ofertaFinal?.precio_oferta) === 8300,
    error: `precio_oferta = ${ofertaFinal?.precio_oferta}, se esperaba 8300 (la contraoferta). ` +
           'Si se queda el precio viejo, se le cobra al cliente lo que no acordó.',
  };
});

await paso('El pedido quedó en pendiente_acuerdo, esperando al superadmin', async () => {
  const r = await sa.select('pedidos', `select=estado,oferta_pendiente_id&id=eq.${pedido.id}`);
  const p = uno(r);
  return { ok: p?.estado === 'pendiente_acuerdo', error: `Estado "${p?.estado}"` };
});

// ── 5. EL SUPERADMIN APRUEBA EL ACUERDO ───────────────────────────────────
R.seccion('5. Cierre del acuerdo y alta de la reservación');

// Se reproduce cerrarAcuerdo() de js/pedidos.js paso por paso: son escrituras
// encadenadas sin transacción, justo lo que la RPC vendría a resolver.
await paso('Superadmin marca el pedido como acordado', () =>
  sa.update('pedidos', `id=eq.${pedido.id}`, { estado: 'acordado' }));

let reserva = null;
await paso('Se crea la reservación', async () => {
  const r = await sa.insert('reservaciones', {
    pedido_id: pedido.id,
    unidad: 'DELTA-01',
    recurso_tipo: 'camion',
    cliente: cuenta('importadora').nombre,
    cliente_email: cuenta('importadora').email,
    cliente_user_id: cli.userId,
    propietario_id: delta.userId,
    fecha_ini: pedido.fecha_ini,
    fecha_fin: pedido.fecha_fin,
    descripcion: pedido.descripcion,
    estado: 'Activa',
    precio_acordado: ofertaFinal?.precio_oferta,
    plazo_pago: pedido.plazo_pago,
  });
  reserva = uno(r);
  return r;
});

await paso('La unidad quedó marcada como ocupada', async () => {
  await sa.update('camiones', `id=eq.DELTA-01`, { estado: 'ocupado' });
  const r = await sa.select('camiones', 'select=estado&id=eq.DELTA-01');
  return { ok: uno(r)?.estado === 'ocupado', error: 'La unidad sigue disponible con una reserva activa' };
}, { critico: false });

await debeFallar('Reservar la MISMA unidad en fechas encimadas',
  () => sa.insert('reservaciones', {
    pedido_id: pedido.id, unidad: 'DELTA-01', recurso_tipo: 'camion',
    cliente: 'Otro cliente', cliente_user_id: cli2.userId, propietario_id: delta.userId,
    fecha_ini: pedido.fecha_ini, fecha_fin: pedido.fecha_fin,
    estado: 'Activa', precio_acordado: 1000,
  }),
  'check_reservacion_disponibilidad no está frenando el doble booking: la misma unidad queda comprometida en dos viajes a la vez.');

// ── 6. SEGUIMIENTO DEL VIAJE ──────────────────────────────────────────────
R.seccion('6. Seguimiento');

const PASOS = ['Confirmado', 'En camino', 'En carga', 'En tránsito', 'Entregado'];
for (let i = 1; i < PASOS.length && !cortado; i++) {
  await paso(`Avanzar a "${PASOS[i]}"`, async () => {
    const r = await delta.rpc('avanzar_tracking', { p_reserva_id: reserva.id });
    if (!r.ok) return r;
    const v = await sa.select('reservaciones', `select=tracking_estado&id=eq.${reserva.id}`);
    const est = uno(v)?.tracking_estado;
    return { ok: est === PASOS[i], error: `Quedó en "${est}", se esperaba "${PASOS[i]}"` };
  }, { critico: false });
}

await debeFallar('Que el CLIENTE mueva el seguimiento del viaje',
  () => cli.rpc('avanzar_tracking', { p_reserva_id: reserva.id }),
  'El cliente puede declarar entregado un viaje que no ha llegado.');

// ── 7. CHAT Y ANTI-DESINTERMEDIACIÓN ──────────────────────────────────────
R.seccion('7. Chat y bloqueo de teléfonos');

const CON_TELEFONO = 'Háblame directo al 55 1234 5678 y lo arreglamos por fuera';

await debeFallar('Mandar un teléfono por la RPC enviar_mensaje',
  () => delta.rpc('enviar_mensaje', {
    p_texto: CON_TELEFONO,
    p_participantes: [delta.userId, cli.userId],
    p_reserva_id: reserva.id,
  }),
  'La RPC debería filtrar números de teléfono y no lo hizo.');

await debeFallar('Mandar un teléfono por insert directo a mensajes (saltándose el filtro del navegador)',
  () => delta.insert('mensajes', {
    de_user_id: delta.userId,
    de_nombre: cuenta('delta').nombre,
    texto: CON_TELEFONO,
    reserva_id: reserva.id,
    participantes: [delta.userId, cli.userId],
  }),
  'El filtro _contieneTelefono() de js/chat.js es solo del navegador: por REST el teléfono entra igual. ' +
  'Cualquiera con la anon key puede saltarse la plataforma. La versión servidor existe en la RPC enviar_mensaje, pero el cliente no la usa.');

await paso('Un mensaje normal sí pasa', () =>
  delta.rpc('enviar_mensaje', {
    p_texto: 'Vamos llegando a la terminal, todo en orden.',
    p_participantes: [delta.userId, cli.userId],
    p_reserva_id: reserva.id,
  }), { critico: false });

await debeFallar('Que una empresa ajena lea el chat de esta reserva',
  async () => {
    const r = await omega.select('mensajes', `select=texto&reserva_id=eq.${reserva.id}`);
    return { ok: (r.data || []).length > 0 };
  },
  'Fletes Omega lee la conversación entre Delta y su cliente.');

// ── 8. EXPEDIENTE, EVIDENCIAS Y CIERRE ────────────────────────────────────
R.seccion('8. Expediente, evidencias y cierre');

await paso('Delta abre el expediente de ingreso a puerto', () =>
  delta.rpc('abrir_expediente', { p_reserva_id: reserva.id, p_etapa: 'ingreso_puerto' }),
  { critico: false });

await paso('El expediente copió la lista de documentos del catálogo', async () => {
  const e = await sa.select('expedientes', `select=id,estado&reserva_id=eq.${reserva.id}&etapa=eq.ingreso_puerto`);
  const exp = uno(e);
  if (!exp) return { ok: false, error: 'No se creó el expediente' };
  const d = await sa.select('expediente_documentos', `select=id,nombre,obligatorio&expediente_id=eq.${exp.id}`);
  return { ok: (d.data || []).length > 0, error: 'El expediente nació sin documentos: el catálogo está vacío o no se copió' };
}, { critico: false });

await paso('La empresa registra sus evidencias de cierre', () =>
  delta.rpc('registrar_evidencias', { p_reserva_id: reserva.id, p_paths: [`${delta.userId}/${MARCA}-entrega.jpg`] }),
  { critico: false });

await paso('El cliente registra las suyas', () =>
  cli.rpc('registrar_evidencias', { p_reserva_id: reserva.id, p_paths: [`${cli.userId}/${MARCA}-recibido.jpg`] }),
  { critico: false });

await paso('Con las dos evidencias, la reserva quedó PorAprobar', async () => {
  const r = await sa.select('reservaciones', `select=estado,evidencias,evidencias_cliente&id=eq.${reserva.id}`);
  const v = uno(r);
  return {
    ok: v?.estado === 'PorAprobar',
    error: `Estado "${v?.estado}". empresa=${(v?.evidencias || []).length} cliente=${(v?.evidencias_cliente || []).length}`,
  };
}, { critico: false });

await debeFallar('Que la empresa se dé por cerrada sola, sin el superadmin',
  () => delta.update('reservaciones', `id=eq.${reserva.id}`, { estado: 'Completada', completado_en: new Date().toISOString() }),
  'La empresa cierra su propio servicio y se salta la aprobación: nadie verifica la evidencia.');

// Se replica aprobarFinalizacion() de js/aprobaciones.js tal cual: además de
// marcar Completada, arranca el reloj del cobro y libera el recurso. Hacer un
// update pelón aquí acusaría a la app de cosas que sí hace.
const AHORA = new Date().toISOString();
const vencimiento = calcularVencimiento(pedido.plazo_pago, AHORA);

await paso('El superadmin aprueba el cierre (con fecha de cobro y liberación)', () =>
  sa.update('reservaciones', `id=eq.${reserva.id}`, {
    estado: 'Completada',
    completado_en: AHORA,
    finalizacion_aprobada_por: sa.userId,
    finalizacion_aprobada_en: AHORA,
    plazo_pago: pedido.plazo_pago,
    fecha_vencimiento_pago: vencimiento,
  }));

await paso('El pedido quedó finalizado', async () => {
  await sa.update('pedidos', `id=eq.${pedido.id}`, { estado: 'finalizado' });
  const r = await sa.select('pedidos', `select=estado&id=eq.${pedido.id}`);
  return { ok: uno(r)?.estado === 'finalizado', error: `Estado "${uno(r)?.estado}"` };
}, { critico: false });

await paso('La unidad volvió a quedar disponible', async () => {
  await sa.update('camiones', 'id=eq.DELTA-01', { estado: 'disponible' });
  const r = await sa.select('camiones', 'select=estado&id=eq.DELTA-01');
  const est = uno(r)?.estado;
  return { ok: est === 'disponible', error: `La unidad quedó en "${est}"` };
}, { critico: false });

// ── 9. COBRO Y CALIFICACIÓN ───────────────────────────────────────────────
R.seccion('9. Cobro y calificación');

await paso('La reserva tiene fecha de vencimiento de pago según el plazo pactado', async () => {
  const r = await sa.select('reservaciones', `select=plazo_pago,fecha_vencimiento_pago,pagado&id=eq.${reserva.id}`);
  const v = uno(r);
  return {
    ok: !!v?.fecha_vencimiento_pago,
    error: `plazo_pago="${v?.plazo_pago}" pero fecha_vencimiento_pago está vacía. ` +
           'estadoCobro() se apoya en esa fecha: sin ella el cobro nunca se marca vencido y no entra en el aviso de la portada.',
  };
}, { critico: false });

// Que la empresa dueña registre su propio cobro es deliberado: lo dice
// js/reservaciones.js:327 — "quien recibe el dinero (la empresa) o el
// superadmin lo registra". Lo que no debe poder es que lo haga un tercero.
await debeFallar('Que una empresa AJENA registre el cobro de otra',
  () => omega.update('reservaciones', `id=eq.${reserva.id}`, { pagado: true, pagado_en: new Date().toISOString() }),
  'Cualquier proveedor podría declarar cobrados los servicios de la competencia.',
  async () => uno(await sa.select('reservaciones', `select=pagado&id=eq.${reserva.id}`))?.pagado === true);

await paso('El superadmin registra el pago', () =>
  sa.update('reservaciones', `id=eq.${reserva.id}`, {
    pagado: true, pagado_en: new Date().toISOString(), pagado_por: sa.userId,
    pago_metodo: 'Transferencia', pago_referencia: MARCA,
  }), { critico: false });

await paso('El cliente califica el servicio', () =>
  cli.rpc('calificar_servicio', { p_reserva_id: reserva.id, p_rating: 5, p_comentario: `${MARCA} — entrega puntual` }),
  { critico: false });

await debeFallar('Calificar dos veces la misma reserva',
  () => cli.rpc('calificar_servicio', { p_reserva_id: reserva.id, p_rating: 1, p_comentario: 'segunda' }),
  'Se puede inflar o hundir la reputación de una empresa calificando en repetido.');

await debeFallar('Que un tercero califique un servicio que no fue suyo',
  () => cli2.rpc('calificar_servicio', { p_reserva_id: reserva.id, p_rating: 1, p_comentario: 'ajeno' }),
  'Cualquier cliente puede calificar viajes de otros.');

// ── 10. LO QUE NO DEBERÍA PODERSE ─────────────────────────────────────────
R.seccion('10. Fronteras entre cuentas');

await debeFallar('Ofertar con una unidad que no es tuya',
  () => omega.rpc('enviar_oferta', {
    p_pedido_id: pedido.id, p_camion_id: 'DELTA-01', p_precio: 5000,
    p_operador_id: 'OP-DELTA-01', p_operador_nombre: 'Ramiro',
  }),
  'Una empresa oferta con el camión de la competencia.');

await debeFallar('Ofertar con un camión de tipo distinto al solicitado',
  () => delta.rpc('enviar_oferta', {
    p_pedido_id: pedido.id, p_camion_id: 'DELTA-02', p_precio: 5000,
    p_operador_id: 'OP-DELTA-01', p_operador_nombre: 'Ramiro',
  }),
  'Se acepta una unidad que no sirve para la carga solicitada.');

await debeFallar('Que una empresa modifique la reservación de otra',
  () => omega.update('reservaciones', `id=eq.${reserva.id}`, { precio_acordado: 1 }),
  'Fletes Omega edita el trato cerrado por Transportes Delta.',
  async () => Number(uno(await sa.select('reservaciones', `select=precio_acordado&id=eq.${reserva.id}`))?.precio_acordado) === 1);

await debeFallar('Que el cliente se apruebe su propio acuerdo',
  async () => {
    const r = await cli.insert('pedidos', {
      cliente_id: cli.userId, cliente_nombre: cuenta('importadora').nombre,
      cliente_email: cuenta('importadora').email, tipo_camion: 'Torton caja seca',
      origen: 'A', destino: 'B', fecha_ini: dia(5), fecha_fin: dia(6),
      descripcion: `${MARCA} — autoaprobación`, estado: 'acordado',
    });
    return r;
  },
  'Un cliente publica un pedido ya "acordado" y se salta por completo la revisión del superadmin.');

await debeFallar('Que un cliente lea los datos fiscales de una empresa',
  async () => {
    const r = await cli.select('perfiles', `select=rfc,razon_social,telefono&user_id=eq.${delta.userId}`);
    const p = uno(r);
    return { ok: !!(p?.rfc || p?.razon_social) };
  },
  'La política de perfiles deja leer la fila completa a cualquier usuario autenticado.\n' +
  'Está documentado así, con el fin de poder mostrar nombres, pero la misma fila lleva\n' +
  'RFC, razón social y teléfono. El permiso alcanza bastante más de lo que el propósito\n' +
  'declarado necesita: bastaría una vista con nombre y rol.');

// La escalada que de verdad importa del punto anterior: si el cliente puede
// crear un pedido ya "acordado", ¿puede además fabricarse la reservación y
// saltarse por completo ofertas y aprobación?
await debeFallar('Que el cliente se fabrique una reservación sin oferta ni aprobación',
  () => cli.insert('reservaciones', {
    pedido_id: null, unidad: 'OMEGA-01', recurso_tipo: 'camion',
    cliente: cuenta('importadora').nombre, cliente_email: cuenta('importadora').email,
    cliente_user_id: cli.userId, propietario_id: omega.userId,
    fecha_ini: dia(20), fecha_fin: dia(21),
    descripcion: `${MARCA} — reserva fabricada`,
    estado: 'Activa', precio_acordado: 1,
  }),
  'Un cliente compromete la unidad de una empresa al precio que él decida, sin que la\n' +
  'empresa oferte ni el superadmin apruebe nada. La empresa se entera cuando ya tiene\n' +
  'el viaje encima.');

await debeFallar('Que un cliente vea los pedidos de otro cliente',
  async () => {
    const r = await cli2.select('pedidos', `select=id,cliente_email&id=eq.${pedido.id}`);
    return { ok: (r.data || []).length > 0 };
  },
  'Los clientes ven las rutas, precios y correos de los demás.');

await debeFallar('Que una empresa se apruebe sola una unidad nueva',
  async () => {
    const r = await delta.insert('camiones', {
      id: `TRAMPA-${MARCA}`, propietario_id: delta.userId, tipo: 'Torton caja seca',
      estado: 'disponible', aprobacion: 'aprobada',
    });
    return r;
  },
  'Entran unidades al catálogo sin que el superadmin revise sus papeles.');

// ── 11. SERVICIOS QUE NO SON DE CAMIÓN ────────────────────────────────────
R.seccion('11. Servicios de lavado, patio y custodia');

// El cliente deriva la tabla de flota con un ternario escrito tres veces.
// aprobaciones.js:1207 cubre los cuatro tipos; aprobaciones.js:1124 y
// reservaciones.js:462 se saltan 'lavado' y caen en 'camiones'. Aquí se
// reproduce ese camino tal cual para ver qué le pasa al recurso.
const tablaComoEnCierre = (tipo) =>
  tipo === 'custodio' ? 'custodios' : tipo === 'patio' ? 'patios' : 'camiones';

let reservaLavado = null;
await paso('Se crea una reservación de lavado', async () => {
  const r = await sa.insert('reservaciones', {
    unidad: 'LAV-OMEGA-01',
    recurso_tipo: 'lavado',
    cliente: cuenta('importadora').nombre,
    cliente_email: cuenta('importadora').email,
    cliente_user_id: cli.userId,
    propietario_id: omega.userId,
    fecha_ini: dia(10),
    fecha_fin: dia(11),
    descripcion: `${MARCA} — lavado de contenedor`,
    estado: 'Activa',
    precio_acordado: 900,
  });
  reservaLavado = uno(r);
  return r;
}, { critico: false });

if (reservaLavado) {
  await paso('El lavado se marca ocupado', () =>
    sa.update('lavados', 'id=eq.LAV-OMEGA-01', { estado: 'ocupado' }), { critico: false });

  await paso('Al cerrar el servicio, el lavado vuelve a estar disponible', async () => {
    // Exactamente lo que hace aprobarFinalizacion() hoy:
    const tabla = tablaComoEnCierre('lavado');
    await sa.update('reservaciones', `id=eq.${reservaLavado.id}`, {
      estado: 'Completada', completado_en: new Date().toISOString(),
    });
    await sa.update(tabla, 'id=eq.LAV-OMEGA-01', { estado: 'disponible' });

    const r = await sa.select('lavados', 'select=estado&id=eq.LAV-OMEGA-01');
    const est = uno(r)?.estado;
    return {
      ok: est === 'disponible',
      error: `El lavado quedó en "${est}" con el servicio ya cerrado.\n` +
        `El código derivó la tabla "${tabla}" para un recurso_tipo "lavado": el ternario de\n` +
        'js/aprobaciones.js:1124 y js/reservaciones.js:462 no contempla lavado y cae en camiones,\n' +
        'así que el UPDATE se va contra una unidad que no existe y no libera nada. El lavado\n' +
        'queda ocupado para siempre y desaparece del catálogo. El mismo ternario en\n' +
        'js/aprobaciones.js:1207 sí lo cubre, y la función SQL tabla_recurso() también:\n' +
        'es un olvido en dos de los tres lugares, no una decisión.',
    };
  }, { critico: false });
}

// Plazos de pago: el catálogo de la base y la tabla del JS no coinciden.
await paso('Todo plazo de pago del catálogo produce una fecha de vencimiento', async () => {
  const r = await sa.select('catalogos', 'select=valor&clave=eq.plazo_pago&activo=is.true');
  const valores = (r.data || []).map(x => x.valor);
  if (!valores.length) return { ok: false, error: 'No hay plazos en el catálogo' };
  const sinFecha = valores.filter(v => calcularVencimiento(v, new Date().toISOString()) === null);
  return {
    ok: sinFecha.length === 0,
    error: `Plazos del catálogo que NO generan fecha de vencimiento: ${sinFecha.join(', ')}\n` +
      'PLAZO_PAGO_DIAS (js/cobros.js) no los contempla y el respaldo por expresión regular\n' +
      'tampoco encuentra dígitos, así que fecha_vencimiento_pago queda en null. Ese cobro\n' +
      'nunca se marca vencido ni entra en el aviso de la portada: se cobra solo si alguien\n' +
      'se acuerda. Es la misma grieta de fondo que el catálogo que nadie lee.',
  };
}, { critico: false });

// ── Cierre ────────────────────────────────────────────────────────────────
R.seccion('Rastro dejado por esta corrida');

R.info(`Marca de la corrida: ${MARCA}`,
  [`pedido: ${pedido?.id || '—'}`,
   `reservación: ${reserva?.id || '—'}`,
   `oferta Delta: ${ofertaDelta?.id || '—'}`,
   `oferta Omega: ${ofertaOmega?.id || '—'}`,
   '',
   'Todo esto vive en el proyecto de PRUEBAS. Se puede dejar ahí sin problema;',
   'para volver a empezar limpio se resiembra la base, no hace falta borrar a mano.'].join('\n'));

R.resumen();
R.guardar('03-flujo');
