// ══════════════════════════════════════════════════════════════════════════
//  SONDA DE REPORTES — comprueba H-07 con una sesión de verdad
//
//  H-07 (cuarta auditoría): dos pantallas se descargaban el conjunto entero
//  de un rango y calculaban COUNT, SUM, media y agrupación en JavaScript, sin
//  .limit(). La migración 20260918150000 mueve esos agregados a la base con
//  reporte_kpis(desde, hasta) y desempeno_empresa().
//
//  ── Por qué esta sonda, si la migración ya lleva su bloque de comprobación ─
//
//  Porque ese bloque corre en psql, y psql conecta SIN JWT. Puede comprobar
//  que las funciones existen, que declaran search_path y que anon no las
//  ejecuta. NO puede comprobar lo único que importa en producción: que
//  is_superadmin() las abra a quien debe y las cierre a quien no, y que los
//  números que devuelven con una sesión real sean los mismos que hoy pinta el
//  navegador. Eso solo se ve empujando la puerta.
//
//  ── Qué compara, exactamente ──────────────────────────────────────────────
//
//  Reimplementa aquí la aritmética VIEJA —la de js/reportes.js y js/views.js
//  tal como estaban en main— sobre las mismas filas que la función agrega, y
//  exige que cada cifra coincida. No compara contra números escritos a mano:
//  un número esperado escrito a mano solo prueba que quien lo escribió y quien
//  escribió la función pensaron igual.
//
//  Salvedad deliberada en top_admins: el desempate cambió a propósito (antes
//  lo decidía el orden de descarga, que no significaba nada; ahora es ingreso
//  y luego nombre). Así que se compara contra la aritmética vieja REORDENADA
//  por la regla nueva, y se avisa aparte si el orden viejo habría sacado a
//  otra empresa — que es información, no un fallo.
//
//  ── Por qué no exige sello de paridad ─────────────────────────────────────
//
//  No siembra ni recorre un flujo: compara la función contra la aritmética
//  vieja sobre LAS MISMAS filas, sean las que sean. Si pruebas divergiera de
//  producción, las dos mitades de la comparación divergirían igual y la
//  igualdad seguiría significando lo mismo. Aun así imprime el sello, porque
//  al reportar algo medido en pruebas hay que decir con qué sello se midió.
//
//  ── Contra produccion ─────────────────────────────────────────────────────
//
//  PORTGO_SONDA_PRODUCCION=1 la apunta al proyecto de produccion. Es seguro y
//  esta puesto a proposito: esta sonda NO ESCRIBE NADA. Las dos funciones son
//  `stable` y lo demas son SELECT. No hay insert, update, delete ni rpc que
//  mute. Por eso no lleva el candado exigirNoProduccion(), que existe para los
//  guiones que si escriben.
//
//  Y hace falta: aplicar una migracion a produccion no prueba que alli haga lo
//  mismo. Los permisos y el volumen son suyos. Una funcion puede crearse bien y
//  negarle el paso al superadmin porque is_superadmin() se apoya en un GRANT
//  que alli quedo de otra forma — y eso no se ve hasta que se pide.
//
//  Correr:  node pruebas/09-sonda-reportes.mjs
//           PORTGO_SONDA_PRODUCCION=1 node pruebas/09-sonda-reportes.mjs
// ══════════════════════════════════════════════════════════════════════════
import { Sesion, leerAmbientePruebas, leerCredenciales, exigirCuentas, CONFIG } from './lib/api.mjs';
import { leerSello, resumenParidad } from './lib/paridad.mjs';

const A_PRODUCCION = process.env.PORTGO_SONDA_PRODUCCION === '1';

let AMB, cred;
try {
  AMB  = A_PRODUCCION ? CONFIG : leerAmbientePruebas();
  cred = exigirCuentas(leerCredenciales(), ['superadmin', 'empresa']);
} catch (e) { console.error(`\n${e.message}\n`); process.exit(1); }

const C = { ok:'\x1b[32m', mal:'\x1b[31m', dim:'\x1b[90m', neg:'\x1b[1m', am:'\x1b[33m', fin:'\x1b[0m' };
const resultados = [];
const avisos = [];

function anotar(nombre, pasa, detalle) {
  resultados.push({ nombre, pasa, detalle });
  console.log(`  ${pasa ? `${C.ok}  OK  ${C.fin}` : `${C.mal} FALLA${C.fin}`}  ${nombre}`);
  if (detalle) console.log(`          ${C.dim}${detalle}${C.fin}`);
}
const avisar = t => { avisos.push(t); console.log(`  ${C.am} AVISO${C.fin}  ${t}`); };

// Las claves que LEE el cliente, una por una. Si la función deja de devolver
// alguna, la pantalla no da error: pinta undefined o NaN, que es peor.
const CLAVES_KPIS = ['total_pedidos','acordados','cancelados','abiertos',
                     'total_reservas','ingreso','meses','top_admins','top_tipos'];
const CLAVES_DESEMP = ['total_ofertas','aceptadas','total_reservas','completadas',
                       'ingreso_total','rating_n','rating_suma','meses'];

const num = v => Number(v) || 0;
const mesUTC = iso => String(iso || '').substring(0, 7);   // lo que hacía el cliente viejo

console.log(`\n${C.neg}── Sonda de reportes (H-07) ──${C.fin}`);
if (A_PRODUCCION) {
  console.log(`   ${C.am}${C.neg}PRODUCCION${C.fin} — solo lectura: ningun insert, update, delete ni rpc que mute.`);
}
console.log(`   proyecto: ${AMB.url}`);
if (A_PRODUCCION) {
  // El sello compara pruebas contra produccion. Midiendo EN produccion no dice
  // nada, y ensenarlo aqui invitaria a leerlo como respaldo de este resultado.
  console.log(`   paridad:  no aplica — se esta midiendo produccion, no pruebas\n`);
} else {
  const sello = leerSello();
  console.log(`   paridad:  ${sello ? resumenParidad(sello) : 'sin sello'}\n`);
}

// ── Sesiones ──────────────────────────────────────────────────────────────
const sa = new Sesion('superadmin', AMB);
const ent1 = await sa.login(cred.superadmin.email, cred.superadmin.password);
if (!ent1.ok) { console.error(`\n${C.mal}No se pudo entrar como superadmin: ${ent1.error}${C.fin}\n`); process.exit(1); }
console.log(`   superadmin: ${sa.email} (rol ${sa.perfil?.rol || '?'})`);

const emp = new Sesion('empresa', AMB);
const ent2 = await emp.login(cred.empresa.email, cred.empresa.password);
if (!ent2.ok) { console.error(`\n${C.mal}No se pudo entrar como empresa: ${ent2.error}${C.fin}\n`); process.exit(1); }
console.log(`   empresa:    ${emp.email} (rol ${emp.perfil?.rol || '?'})\n`);

// ══════════════════════════════════════════════════════════════════════════
//  1 · Quién puede llamar
// ══════════════════════════════════════════════════════════════════════════
console.log(`${C.neg}  1 · Quién puede llamar${C.fin}`);

const hoyISO = new Date().toISOString().split('T')[0];
const negada = await emp.rpc('reporte_kpis', { p_desde: '2026-01-01', p_hasta: hoyISO });
anotar('Una EMPRESA no puede llamar a reporte_kpis()',
  !negada.ok, `HTTP ${negada.status}${negada.data?.message ? ' — ' + negada.data.message : ''}`);

const anon = new Sesion('anon', AMB);
const anonKpis = await anon.rpc('reporte_kpis', { p_desde: '2026-01-01', p_hasta: hoyISO });
anotar('Sin sesión tampoco', !anonKpis.ok, `HTTP ${anonKpis.status}`);
const anonDes = await anon.rpc('desempeno_empresa', {});
anotar('Sin sesión no hay desempeño', !anonDes.ok, `HTTP ${anonDes.status}`);

// El id no se recibe: se deriva de auth.uid(). Si alguien añadiera el
// parámetro, una empresa podría pedir los ingresos de otra.
const conParam = await emp.rpc('desempeno_empresa', { p_uid: '00000000-0000-0000-0000-000000000000' });
anotar('desempeno_empresa() NO acepta un id por parámetro',
  !conParam.ok, `HTTP ${conParam.status} — la firma con parámetro no existe, que es lo correcto`);

// Y los dos guardarraíles del rango.
const alReves = await sa.rpc('reporte_kpis', { p_desde: '2026-06-01', p_hasta: '2026-01-01' });
anotar('Un rango al revés se rechaza', !alReves.ok, `HTTP ${alReves.status}`);
const sinFecha = await sa.rpc('reporte_kpis', { p_desde: null, p_hasta: hoyISO });
anotar('Un rango incompleto se rechaza', !sinFecha.ok, `HTTP ${sinFecha.status}`);

// ══════════════════════════════════════════════════════════════════════════
//  2 · Las cifras del panel de Reportes
// ══════════════════════════════════════════════════════════════════════════
console.log(`\n${C.neg}  2 · Las cifras del panel de Reportes${C.fin}`);

// Los nombres de empresa, como los resolvía el cliente viejo.
const { data: empresas } = await sa.select('empresas_publico', 'select=user_id,nombre');
const nombreDe = {};
(empresas || []).forEach(e => { nombreDe[e.user_id] = e.nombre; });

async function viejaKpis(desde, hasta) {
  // Exactamente las dos consultas que hacía js/reportes.js:31-34.
  const q = `&created_at=gte.${desde}&created_at=lte.${hasta}T23:59:59`;
  const { data: peds } = await sa.select('pedidos',
    `select=id,estado,created_at,tipo_camion,cliente_id${q}`);
  const { data: ress } = await sa.select('reservaciones',
    `select=id,precio_acordado,propietario_id,created_at,estado${q}`);
  const P = peds || [], R = ress || [];

  const meses = {};
  P.forEach(p => { const k = mesUTC(p.created_at); meses[k] = (meses[k] || 0) + 1; });

  const porAdmin = {};
  R.forEach(r => {
    if (!r.propietario_id) return;
    const a = porAdmin[r.propietario_id] || (porAdmin[r.propietario_id] = { n: 0, ing: 0 });
    a.n++; a.ing += num(r.precio_acordado);
  });
  const filas = Object.entries(porAdmin).map(([uid, a]) => ({
    nombre: nombreDe[uid] ?? 'Empresa', reservas: a.n, ingreso: a.ing }));

  const tipos = {};
  P.forEach(p => { const t = (p.tipo_camion || '') === '' ? 'Otro' : p.tipo_camion;
                   tipos[t] = (tipos[t] || 0) + 1; });

  return {
    total_pedidos:  P.length,
    acordados:      P.filter(p => ['acordado','finalizado','expirado'].includes(p.estado)).length,
    cancelados:     P.filter(p => p.estado === 'cancelado').length,
    abiertos:       P.filter(p => p.estado === 'abierto').length,
    total_reservas: R.length,
    ingreso:        R.reduce((s, r) => s + num(r.precio_acordado), 0),
    meses,
    // Reordenado por la regla NUEVA (n desc, ingreso desc, nombre asc).
    top_admins: filas.slice().sort((a, b) =>
      b.reservas - a.reservas || b.ingreso - a.ingreso || a.nombre.localeCompare(b.nombre)).slice(0, 5),
    top_tipos: Object.entries(tipos).map(([tipo, n]) => ({ tipo, n }))
      .sort((a, b) => b.n - a.n || a.tipo.localeCompare(b.tipo)).slice(0, 5),
    _filas: filas,
  };
}

const RANGOS = [
  ['seis meses (lo que abre la pantalla)',
   (() => { const d = new Date(); d.setMonth(d.getMonth() - 5); d.setDate(1);
            return d.toISOString().split('T')[0]; })(), hoyISO],
  ['un mes',        `${hoyISO.substring(0, 7)}-01`, hoyISO],
  ['el año entero', '2026-01-01', '2026-12-31'],
  ['vacío',         '2027-01-01', '2027-01-31'],
];

for (const [etiqueta, desde, hasta] of RANGOS) {
  const r = await sa.rpc('reporte_kpis', { p_desde: desde, p_hasta: hasta });
  if (!r.ok) {
    anotar(`Rango ${etiqueta}: la función responde`, false,
      `HTTP ${r.status} — ${r.data?.message || r.error}`);
    continue;
  }
  const k = r.data, v = await viejaKpis(desde, hasta);

  const faltan = CLAVES_KPIS.filter(c => !(c in k));
  anotar(`Rango ${etiqueta}: devuelve las ${CLAVES_KPIS.length} claves que lee el cliente`,
    faltan.length === 0, faltan.length ? `faltan: ${faltan.join(', ')}` : `${desde} → ${hasta}`);

  const escalares = ['total_pedidos','acordados','cancelados','abiertos','total_reservas','ingreso'];
  const mal = escalares.filter(c => num(k[c]) !== num(v[c]));
  anotar(`Rango ${etiqueta}: los seis escalares coinciden con la aritmética vieja`,
    mal.length === 0,
    mal.length ? mal.map(c => `${c}: base=${k[c]} navegador=${v[c]}`).join(' · ')
               : `pedidos ${v.total_pedidos} · acordados ${v.acordados} · reservas ${v.total_reservas} · ingreso ${v.ingreso}`);

  const mBase  = JSON.stringify(Object.fromEntries(Object.entries(k.meses || {}).map(([a, b]) => [a, num(b)]).sort()));
  const mVieja = JSON.stringify(Object.fromEntries(Object.entries(v.meses).sort()));
  anotar(`Rango ${etiqueta}: el mapa de meses coincide`, mBase === mVieja,
    mBase === mVieja ? `${Object.keys(v.meses).length} mes(es) con datos`
                     : `base=${mBase} navegador=${mVieja}`);

  const norm = a => JSON.stringify((a || []).map(x => [x.nombre ?? x.tipo, num(x.reservas ?? x.n), num(x.ingreso ?? 0)]));
  anotar(`Rango ${etiqueta}: top_admins coincide, en contenido y en orden`,
    norm(k.top_admins) === norm(v.top_admins),
    norm(k.top_admins) === norm(v.top_admins)
      ? `${(k.top_admins || []).length} empresa(s)`
      : `base=${norm(k.top_admins)} navegador=${norm(v.top_admins)}`);
  anotar(`Rango ${etiqueta}: top_tipos coincide, en contenido y en orden`,
    norm(k.top_tipos) === norm(v.top_tipos),
    norm(k.top_tipos) === norm(v.top_tipos)
      ? `${(k.top_tipos || []).length} tipo(s)`
      : `base=${norm(k.top_tipos)} navegador=${norm(v.top_tipos)}`);

  // Informativo: ¿el desempate cambia quién sale, no solo el orden?
  if (v._filas.length > 5) {
    const viejosCinco = new Set(v._filas.slice(0, 5).map(f => f.nombre));
    const nuevosCinco = new Set(v.top_admins.map(f => f.nombre));
    const distintos = [...nuevosCinco].filter(n => !viejosCinco.has(n));
    if (distintos.length) {
      avisar(`Rango ${etiqueta}: el desempate nuevo saca a ${distintos.join(', ')}, que el orden de descarga dejaba fuera.`);
    }
  }

  // La tasa de cierre se sigue redondeando en el navegador, a propósito.
  const tasa = num(k.total_pedidos) ? Math.round((num(k.acordados) / num(k.total_pedidos)) * 100) : 0;
  console.log(`          ${C.dim}tasa de cierre que pintaría: ${tasa}%${C.fin}`);
}

// ══════════════════════════════════════════════════════════════════════════
//  3 · «Mi desempeño» de la empresa
// ══════════════════════════════════════════════════════════════════════════
console.log(`\n${C.neg}  3 · «Mi desempeño» de la empresa${C.fin}`);

const rd = await emp.rpc('desempeno_empresa', {});
if (!rd.ok) {
  anotar('La empresa obtiene su desempeño', false, `HTTP ${rd.status} — ${rd.data?.message || rd.error}`);
} else {
  const d = rd.data;
  const faltan = CLAVES_DESEMP.filter(c => !(c in d));
  anotar(`Devuelve las ${CLAVES_DESEMP.length} claves que lee el cliente`,
    faltan.length === 0, faltan.length ? `faltan: ${faltan.join(', ')}` : '');

  // La aritmética vieja de js/views.js:246-270, sobre las filas de ESTA empresa.
  const uid = emp.userId;
  const { data: ofs }  = await emp.select('ofertas', `select=id,estado,created_at&admin_id=eq.${uid}`);
  const { data: rss }  = await emp.select('reservaciones',
    `select=id,precio_acordado,estado,created_at&propietario_id=eq.${uid}`);
  const { data: cals } = await emp.select('calificaciones', `select=rating&admin_id=eq.${uid}`);
  const O = ofs || [], R = rss || [], K = cals || [];

  const mesesV = {};
  R.forEach(r => { const k = mesUTC(r.created_at); mesesV[k] = (mesesV[k] || 0) + num(r.precio_acordado); });

  const v = {
    total_ofertas:  O.length,
    aceptadas:      O.filter(o => o.estado === 'aceptada').length,
    total_reservas: R.length,
    completadas:    R.filter(r => r.estado === 'Completada').length,
    ingreso_total:  R.reduce((s, r) => s + num(r.precio_acordado), 0),
    rating_n:       K.length,
    rating_suma:    K.reduce((s, c) => s + num(c.rating), 0),
  };
  const mal = Object.keys(v).filter(c => num(d[c]) !== num(v[c]));
  anotar('Los siete escalares coinciden con la aritmética vieja', mal.length === 0,
    mal.length ? mal.map(c => `${c}: base=${d[c]} navegador=${v[c]}`).join(' · ')
      : `ofertas ${v.total_ofertas} · aceptadas ${v.aceptadas} · reservas ${v.total_reservas} · ingreso ${v.ingreso_total} · calificaciones ${v.rating_n}`);

  const mB = JSON.stringify(Object.fromEntries(Object.entries(d.meses || {}).map(([a, b]) => [a, num(b)]).sort()));
  const mV = JSON.stringify(Object.fromEntries(Object.entries(mesesV).sort()));
  anotar('El mapa de ingresos por mes coincide', mB === mV,
    mB === mV ? `${Object.keys(mesesV).length} mes(es) con datos` : `base=${mB} navegador=${mV}`);

  const avg  = num(d.rating_n) ? (num(d.rating_suma) / num(d.rating_n)).toFixed(1) : '—';
  const tasa = num(d.total_ofertas) ? Math.round((num(d.aceptadas) / num(d.total_ofertas)) * 100) : 0;
  console.log(`          ${C.dim}pintaría: tasa ${tasa}% · calificación ${avg} ⭐${C.fin}`);

  // Un superadmin también es `authenticated`: la función tiene que darle LO
  // SUYO, no lo de la empresa. Si devolviera lo mismo con dos sesiones
  // distintas, el id no estaría saliendo de auth.uid().
  const rsa = await sa.rpc('desempeno_empresa', {});
  const suyo = rsa.ok
    && num(rsa.data?.total_reservas) === 0
    && num(rsa.data?.ingreso_total) === 0;
  anotar('El superadmin recibe SU desempeño (vacío), no el de la empresa',
    suyo || !rsa.ok,
    rsa.ok ? `superadmin: ${num(rsa.data?.total_reservas)} reservas / ${num(rsa.data?.ingreso_total)} ingreso · empresa: ${v.total_reservas} / ${v.ingreso_total}`
           : `HTTP ${rsa.status}`);
}

// ── Veredicto ─────────────────────────────────────────────────────────────
const fallan = resultados.filter(r => !r.pasa);
console.log('');
if (avisos.length) console.log(`${C.am}  ${avisos.length} aviso(s) — información, no fallo.${C.fin}`);
if (fallan.length === 0) {
  console.log(`${C.ok}${C.neg}  Las ${resultados.length} comprobaciones pasan.${C.fin}`);
  console.log(`  Las dos funciones devuelven, con sesión real, las claves que el cliente lee`);
  console.log(`  y las mismas cifras que hoy suma el navegador.\n`);
  console.log(`  ${C.dim}Lo que esta sonda NO prueba: que las pantallas PINTEN. Eso pide un navegador.${C.fin}\n`);
  process.exit(0);
}
console.log(`${C.mal}${C.neg}  ${fallan.length} de ${resultados.length} comprobaciones FALLAN:${C.fin}`);
for (const f of fallan) console.log(`${C.mal}    · ${f.nombre}${C.fin}\n      ${f.detalle}`);
console.log('');
process.exit(1);
