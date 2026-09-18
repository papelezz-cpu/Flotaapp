// ══════════════════════════════════════════════════════════════════════════
//  SONDA DE FILTROS DE SOLICITUDES — comprueba H-11
//
//  H-11: renderPedidos() paginaba de 30 en 30 por keyset y aplicaba los
//  filtros de tipo de servicio y de zona en JavaScript, sobre lo acumulado.
//  Eso no filtra la lista: filtra la pagina. Ahora los dos filtros van en la
//  consulta (aplicarFiltrosPedidos, js/pedidos.js).
//
//  ── Que compara ──────────────────────────────────────────────────────────
//
//  Reimplementa el filtro VIEJO de JavaScript —el de main, literal— sobre
//  TODAS las filas, y exige que el conjunto de ids coincida exactamente con
//  el que devuelve la consulta filtrada en el servidor. No compara conteos:
//  dos conjuntos distintos pueden tener el mismo tamano.
//
//  Lo hace sin paginar a proposito. El defecto de H-11 es justo que paginar y
//  filtrar en ese orden pierde filas; comparar contra "todas las filas" es la
//  unica referencia que no arrastra el propio defecto.
//
//  ── Por que no exige sello de paridad ────────────────────────────────────
//
//  Compara las dos implementaciones sobre LAS MISMAS filas de la misma base.
//  Si pruebas divergiera de produccion, las dos mitades divergirian igual.
//  Imprime el sello igualmente, porque al reportar algo medido en pruebas hay
//  que decir con que sello se midio — y ahora mismo esta en `diverge`.
//
//  Correr:  node pruebas/10-sonda-filtros-pedidos.mjs
//           PORTGO_SONDA_PRODUCCION=1 node pruebas/10-sonda-filtros-pedidos.mjs
//
//  Solo lee: un login y SELECT sobre pedidos. Nada mas.
// ══════════════════════════════════════════════════════════════════════════
import { Sesion, leerAmbientePruebas, leerCredenciales, exigirCuentas, CONFIG } from './lib/api.mjs';
import { leerSello, resumenParidad } from './lib/paridad.mjs';

const A_PRODUCCION = process.env.PORTGO_SONDA_PRODUCCION === '1';

let AMB, cred;
try {
  AMB  = A_PRODUCCION ? CONFIG : leerAmbientePruebas();
  cred = exigirCuentas(leerCredenciales(), ['superadmin']);
} catch (e) { console.error(`\n${e.message}\n`); process.exit(1); }

const C = { ok:'\x1b[32m', mal:'\x1b[31m', dim:'\x1b[90m', neg:'\x1b[1m', am:'\x1b[33m', fin:'\x1b[0m' };
const resultados = [];
function anotar(nombre, pasa, detalle) {
  resultados.push({ nombre, pasa });
  console.log(`  ${pasa ? `${C.ok}  OK  ${C.fin}` : `${C.mal} FALLA${C.fin}`}  ${nombre}`);
  if (detalle) console.log(`          ${C.dim}${detalle}${C.fin}`);
}

// ── El filtro VIEJO, copiado literal de js/pedidos.js en main ─────────────
function filtroViejo(lista, tipo, geoRaw) {
  let r = lista;
  if (tipo !== 'todos') {
    r = r.filter(p => {
      const t = p.tipo_camion || '';
      if (tipo === 'camion')   return !t.startsWith('Lavado') && t !== 'Desinfección' && !t.startsWith('Custodio') && t !== 'Supervisión remota' && !t.startsWith('Patio') && t !== 'Bodega';
      if (tipo === 'custodio') return t.startsWith('Custodio') || t === 'Supervisión remota';
      if (tipo === 'patio')    return t.startsWith('Patio') || t === 'Bodega';
      if (tipo === 'lavado')   return t.startsWith('Lavado') || t === 'Desinfección';
      return true;
    });
  }
  if (geoRaw) {
    const geo = geoRaw.toLowerCase();
    r = r.filter(p =>
      (p.origen || '').toLowerCase().includes(geo) ||
      (p.destino || '').toLowerCase().includes(geo) ||
      (p.zona_cobertura || '').toLowerCase().includes(geo));
  }
  return r;
}

// ── El filtro NUEVO, copiado literal de js/pedidos.js en dev ──────────────
const PED_GRUPOS_POSITIVOS = {
  custodio: 'tipo_camion.like.Custodio*,tipo_camion.eq."Supervisión remota"',
  patio:    'tipo_camion.like.Patio*,tipo_camion.eq."Bodega"',
  lavado:   'tipo_camion.like.Lavado*,tipo_camion.eq."Desinfección"',
};
const PED_CAMION_NEGACIONES = [
  ['like', 'Lavado%'],   ['eq', 'Desinfección'],
  ['like', 'Custodio%'], ['eq', 'Supervisión remota'],
  ['like', 'Patio%'],    ['eq', 'Bodega'],
];
function geoLiteral(txt) {
  const paraLike = String(txt).replace(/[\\%_]/g, m => '\\' + m);
  return paraLike.replace(/[\\"]/g, m => '\\' + m);
}
// Traduce lo que el SDK construiria a una query string de PostgREST, que es
// lo que la Sesion de estas sondas sabe enviar.
function queryServidor(tipo, geoRaw) {
  const partes = ['select=id,tipo_camion,origen,destino,zona_cobertura', 'limit=1000'];
  if (tipo === 'camion') {
    PED_CAMION_NEGACIONES.forEach(([op, val]) =>
      partes.push(`tipo_camion=not.${op}.${encodeURIComponent(val)}`));
  } else if (PED_GRUPOS_POSITIVOS[tipo]) {
    partes.push(`or=(${encodeURIComponent(PED_GRUPOS_POSITIVOS[tipo])})`);
  }
  if (geoRaw) {
    const g = geoLiteral(geoRaw);
    partes.push(`or=(${encodeURIComponent(`origen.ilike."%${g}%",destino.ilike."%${g}%",zona_cobertura.ilike."%${g}%"`)})`);
  }
  return partes.join('&');
}

console.log(`\n${C.neg}── Sonda de filtros de solicitudes (H-11) ──${C.fin}`);
if (A_PRODUCCION) console.log(`   ${C.am}${C.neg}PRODUCCION${C.fin} — solo lectura`);
console.log(`   proyecto: ${AMB.url}`);
if (!A_PRODUCCION) {
  const s = leerSello();
  console.log(`   paridad:  ${s ? resumenParidad(s) : 'sin sello'}`);
  console.log(`   ${C.dim}(la comparacion es interna a esta base: las dos mitades leen las mismas filas)${C.fin}`);
}
console.log('');

const sa = new Sesion('superadmin', AMB);
const ent = await sa.login(cred.superadmin.email, cred.superadmin.password);
if (!ent.ok) { console.error(`${C.mal}No se pudo entrar: ${ent.error}${C.fin}\n`); process.exit(1); }

// El universo: TODAS las filas, sin filtrar ni paginar. Es la referencia.
const { data: todos, ok } = await sa.select('pedidos',
  'select=id,tipo_camion,origen,destino,zona_cobertura&limit=1000');
if (!ok) { console.error(`${C.mal}No se pudieron leer los pedidos${C.fin}\n`); process.exit(1); }
console.log(`   universo: ${todos.length} pedidos\n`);

// Los terminos geograficos salen de los DATOS, no de mi cabeza: trozos reales
// de origen y destino, mas los casos raros que rompen un LIKE sin escapar.
const trozos = new Set();
todos.forEach(p => {
  [p.origen, p.destino].forEach(v => {
    if (!v) return;
    trozos.add(String(v).slice(0, 4));
    const pal = String(v).split(/[\s,]+/).filter(x => x.length > 3)[0];
    if (pal) trozos.add(pal);
  });
});
const GEOS = ['', ...[...trozos].slice(0, 8), '%', '_', '%%', 'a_a', '"', 'no-existe-xyz', 'MANZ', 'manz'];
const TIPOS = ['todos', 'camion', 'custodio', 'patio', 'lavado'];

let casos = 0, fallos = 0;
for (const tipo of TIPOS) {
  for (const geo of GEOS) {
    casos++;
    const r = await sa.select('pedidos', queryServidor(tipo, geo));
    if (!r.ok) {
      fallos++;
      anotar(`tipo=${tipo} geo=${JSON.stringify(geo)}`, false,
        `HTTP ${r.status} — ${r.data?.message || r.error}`);
      continue;
    }
    const idsServidor = new Set((r.data || []).map(p => p.id));
    const idsViejo    = new Set(filtroViejo(todos, tipo, geo).map(p => p.id));
    const soloServ = [...idsServidor].filter(x => !idsViejo.has(x));
    const soloViej = [...idsViejo].filter(x => !idsServidor.has(x));
    const igual = soloServ.length === 0 && soloViej.length === 0;
    if (!igual) {
      fallos++;
      anotar(`tipo=${tipo} geo=${JSON.stringify(geo)}`, false,
        `servidor ${idsServidor.size} · navegador ${idsViejo.size} · solo-servidor ${soloServ.length} · solo-navegador ${soloViej.length}`);
    }
  }
}

if (fallos === 0) {
  anotar(`Los ${casos} casos devuelven EL MISMO CONJUNTO de ids`, true,
    `${TIPOS.length} tipos x ${GEOS.length} terminos, incluidos %, _, comilla y acentos`);
}

// El caso que da sentido al hallazgo: filtrar despues de paginar pierde filas.
//
// La primera pagina tiene que pedirse CON EL ORDEN REAL de renderPedidos
// -created_at desc, id desc-. La primera version de esta sonda reutilizaba
// las filas ya descargadas sin ordenar, y daba "25 de 36" donde lo cierto es
// "30 de 36". Peor: escondia los dos casos que de verdad ilustran el
// hallazgo, Custodia y Patio. Un universo sin ordenar no es la primera
// pagina de nada.
//
// OJO CON QUE ROL MODELA ESTO: "la pagina de 30" es la lista de la EMPRESA.
// El superadmin lanza ademas una consulta paralela de acuerdos con limit 100,
// asi que con poco volumen ya se trae el historico entero y el defecto no se
// le manifiesta — filtrar en memoria sobre lo acumulado le da lo mismo que
// filtrar en el servidor. Decir "Custodia salia vacia" sin decir para quien
// es afirmar de mas.
const PAG = 30;
const { data: pagina1 } = await sa.select('pedidos',
  `select=id,tipo_camion,origen,destino,zona_cobertura&order=created_at.desc,id.desc&limit=${PAG}`);
const perdidos = [];
for (const tipo of TIPOS.slice(1)) {
  const enLista   = filtroViejo(todos,      tipo, '').length;
  const enPagina1 = filtroViejo(pagina1 || [], tipo, '').length;
  if (enLista > enPagina1) perdidos.push({ tipo, enLista, enPagina1 });
}
console.log('');
if (perdidos.length) {
  const vacios = perdidos.filter(p => p.enPagina1 === 0);
  anotar('Se reproduce el defecto que H-11 describe', true,
    perdidos.map(p => `${p.tipo} ${p.enPagina1}/${p.enLista}`).join(' · ') +
    (vacios.length ? `  <- ${vacios.map(v => v.tipo).join(' y ')} se veian VACIOS` : ''));
} else {
  console.log(`  ${C.am} AVISO${C.fin}  Con ${todos.length} pedidos todo cabe en la primera pagina: aqui el defecto`);
  console.log(`          ${C.dim}de H-11 no se puede reproducir. La equivalencia de arriba si vale;${C.fin}`);
  console.log(`          ${C.dim}la prueba de que ARREGLA algo pide mas volumen del que hay.${C.fin}`);
}

console.log('');
const mal = resultados.filter(r => !r.pasa);
if (mal.length === 0) {
  console.log(`${C.ok}${C.neg}  Equivalencia comprobada en ${casos} casos.${C.fin}`);
  console.log(`  El filtro del servidor devuelve lo mismo que devolvia el del navegador.\n`);
  process.exit(0);
}
console.log(`${C.mal}${C.neg}  ${mal.length} caso(s) NO coinciden.${C.fin}\n`);
process.exit(1);
