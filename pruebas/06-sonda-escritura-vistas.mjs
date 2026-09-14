// ══════════════════════════════════════════════════════════════════════════
//  SONDA DE ESCRITURA EN VISTAS — comprueba H-01 con una sesión de verdad
//
//  H-01 (cuarta auditoría, 2026-09-14): empresas_publico tenía concedidos
//  INSERT, UPDATE y DELETE a `authenticated`. Como es una vista simple sobre
//  una sola tabla, PostgreSQL la considera auto-actualizable, y como corre con
//  security_invoker en false (a propósito, para poder leer fichas ajenas), esas
//  escrituras llegaban a `perfiles` SIN pasar por ninguna política RLS.
//
//  Lo arregla la migración 20260914130000_la_vista_no_se_escribe.
//
//  ── Por qué esta sonda y no solo la de SQL ──────────────────────────────
//
//  supabase/sondas/escritura-en-vistas.sql lee el catálogo de permisos y dice
//  qué DEBERÍA pasar. Esta lo comprueba por el camino real: con la clave anon
//  pública, una sesión iniciada como cualquier empresa, y peticiones a
//  PostgREST. Es la diferencia entre leer el plano de una cerradura y empujar
//  la puerta.
//
//  ── Por qué es seguro contra datos reales ───────────────────────────────
//
//  La base de pruebas lleva copiadas las filas REALES de producción. Una sonda
//  que intente escribir sobre ellas para ver si puede es exactamente el
//  accidente que hay que evitar. Así que los tres intentos están construidos
//  para no poder cambiar nada, pase lo que pase:
//
//    · UPDATE y DELETE filtran por un user_id de ceros, que no existe.
//      PostgreSQL comprueba el PRIVILEGIO antes de buscar las filas, así que
//      sin permiso sale 42501, y CON permiso afecta a cero filas. Las dos
//      ramas son inofensivas, y se distinguen sin ambigüedad.
//
//    · El INSERT usa ese mismo user_id de ceros, que viola la clave foránea
//      contra auth.users. Sin permiso sale 42501; con permiso, falla la FK.
//      Tampoco escribe en ninguna de las dos ramas.
//
//  ── Por qué no depende del sello de paridad ─────────────────────────────
//
//  Porque no siembra datos ni recorre un flujo: afirma un invariante que debe
//  cumplirse por sí solo, mire lo que mire producción. Y sobre todo, porque
//  mientras H-01 esté arreglado en pruebas y no en producción, el sello dice
//  `diverge` A PROPÓSITO — si esta sonda exigiera paridad, no se podría usar
//  justo en la ventana para la que existe.
//
//  Para comprobar PRODUCCIÓN después de promover, usar la sonda de SQL, que
//  solo lee:  psql "<cadena>" -f supabase/sondas/escritura-en-vistas.sql
//
//  Correr:  node pruebas/06-sonda-escritura-vistas.mjs
// ══════════════════════════════════════════════════════════════════════════
import { Sesion, leerAmbientePruebas, leerCredenciales, exigirCuentas } from './lib/api.mjs';

const NADIE = '00000000-0000-0000-0000-000000000000';
const VISTA = 'empresas_publico';

let AMB, cred;
try {
  AMB  = leerAmbientePruebas();
  cred = exigirCuentas(leerCredenciales(), ['empresa']);
} catch (e) { console.error(`\n${e.message}\n`); process.exit(1); }

const C = { ok: '\x1b[32m', mal: '\x1b[31m', dim: '\x1b[90m', neg: '\x1b[1m', fin: '\x1b[0m' };
const resultados = [];

function anotar(nombre, pasa, detalle) {
  resultados.push({ nombre, pasa, detalle });
  const marca = pasa ? `${C.ok}  OK  ${C.fin}` : `${C.mal} FALLA${C.fin}`;
  console.log(`  ${marca}  ${nombre}`);
  if (detalle) console.log(`          ${C.dim}${detalle}${C.fin}`);
}

// PostgREST devuelve 401/403 y el código 42501 de PostgreSQL cuando falta el
// privilegio. Se acepta cualquiera de las dos señales.
function esPermisoDenegado(r) {
  const cod = r.data?.code || '';
  const msg = String(r.error || '');
  return r.status === 401 || r.status === 403 || cod === '42501'
      || /permission denied|denegado/i.test(msg);
}

console.log(`\n${C.neg}── Sonda de escritura en vistas ──${C.fin}`);
console.log(`   proyecto: ${AMB.url}`);
console.log(`   vista:    ${VISTA}\n`);

// ── 1. Una sesión de empresa, que es un `authenticated` cualquiera ────────
const s = new Sesion('empresa', AMB);
const entrada = await s.login(cred.empresa.email, cred.empresa.password);
if (!entrada.ok) {
  console.error(`\n${C.mal}No se pudo iniciar sesión como empresa: ${entrada.error}${C.fin}`);
  console.error(`Revisa el bloque "empresa" de pruebas/credenciales.local.json.\n`);
  process.exit(1);
}
console.log(`   sesión iniciada: ${s.email} (rol ${s.perfil?.rol || '?'})\n`);

// ── 2. Lo que NO debe romperse: la lectura ────────────────────────────────
// Va primero a propósito. Si el arreglo se pasó de frenada y retiró también el
// SELECT, el Catálogo y la ficha de empresa se quedan en blanco — y ese
// síntoma (nombres como «—») no apunta al permiso por ningún lado.
const lectura = await s.select(VISTA, 'select=user_id,nombre&limit=5');
anotar(
  'La empresa SIGUE LEYENDO la vista (Catálogo, ficha, Reservaciones)',
  lectura.ok && Array.isArray(lectura.data) && lectura.data.length > 0,
  lectura.ok
    ? `devuelve ${lectura.data?.length ?? 0} fila(s)`
    : `HTTP ${lectura.status}: ${lectura.error}`);

// ── 3. Los tres intentos de escritura ─────────────────────────────────────
const upd = await s.update(VISTA, `user_id=eq.${NADIE}`, { rfc: 'SONDA-NO-DEBE-ESCRIBIR' });
anotar(
  'UPDATE a través de la vista queda DENEGADO',
  esPermisoDenegado(upd),
  esPermisoDenegado(upd)
    ? `HTTP ${upd.status} — permiso denegado, que es lo correcto`
    : `HTTP ${upd.status} — ¡el permiso sigue concedido! (no se escribió nada: el filtro no casa con ninguna fila)`);

const del = await s._pedir('DELETE', `/rest/v1/${VISTA}?user_id=eq.${NADIE}`);
anotar(
  'DELETE a través de la vista queda DENEGADO',
  esPermisoDenegado(del),
  esPermisoDenegado(del)
    ? `HTTP ${del.status} — permiso denegado, que es lo correcto`
    : `HTTP ${del.status} — ¡el permiso sigue concedido! Era el ÚNICO camino de borrado: perfiles no tiene política FOR DELETE`);

const ins = await s.insert(VISTA, [{ user_id: NADIE, nombre: 'Sonda', rfc: 'X' }]);
anotar(
  'INSERT a través de la vista queda DENEGADO',
  esPermisoDenegado(ins),
  esPermisoDenegado(ins)
    ? `HTTP ${ins.status} — permiso denegado, que es lo correcto`
    : `HTTP ${ins.status} — el permiso sigue concedido (la fila no entró: viola la FK contra auth.users)`);

// ── 4. Y sin sesión, nada de nada ─────────────────────────────────────────
const anon = new Sesion('anon', AMB);
const lecturaAnon = await anon.select(VISTA, 'select=user_id&limit=1');
anotar(
  'Sin sesión (anon) la vista no se lee',
  !lecturaAnon.ok || (Array.isArray(lecturaAnon.data) && lecturaAnon.data.length === 0),
  `HTTP ${lecturaAnon.status}${lecturaAnon.error ? ' — ' + lecturaAnon.error : ''}`);

// ── Veredicto ─────────────────────────────────────────────────────────────
const fallan = resultados.filter(r => !r.pasa);
console.log('');
if (fallan.length === 0) {
  console.log(`${C.ok}${C.neg}  Las ${resultados.length} comprobaciones pasan.${C.fin}`);
  console.log(`  ${VISTA} se lee y no se escribe. H-01 cerrado en este proyecto.\n`);
  process.exit(0);
}
console.log(`${C.mal}${C.neg}  ${fallan.length} de ${resultados.length} comprobaciones FALLAN:${C.fin}`);
for (const f of fallan) console.log(`${C.mal}    · ${f.nombre}${C.fin}\n      ${f.detalle}`);
console.log(`\n  Si falla una de escritura, la migración no está aplicada aquí:`);
console.log(`    bash supabase/aplicar-a-pruebas.sh supabase/migrations/20260914130000_la_vista_no_se_escribe.sql`);
console.log(`  Si falla la de lectura, se retiró de más — ver el bloque 3 de esa migración.\n`);
process.exit(1);
