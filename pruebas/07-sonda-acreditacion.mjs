// ══════════════════════════════════════════════════════════════════════════
//  SONDA DE ACREDITACIÓN — comprueba H-02 con una sesión de empresa real
//
//  H-02 (cuarta auditoría, 2026-09-15): el chip «Seg. RC ✓» que veía el cliente
//  salía de una casilla que la empresa marcaba sola. Significaba «marcó una
//  casilla», no «alguien vio la póliza», y las dos cosas se veían idénticas.
//
//  Lo arregla 20260915120000_los_seguros_se_acreditan_no_se_declaran, que mueve
//  la fuente de verdad a la fecha de vigencia y se la quita a la empresa.
//
//  ── Qué se comprueba, y por qué esto y no otra cosa ─────────────────────
//
//  Que la interfaz ya no tenga la casilla no demuestra nada: RLS deja a la
//  empresa actualizar su propia fila de perfiles, así que la pregunta real es
//  si puede hacerlo por el API sin pasar por ninguna pantalla. Eso es lo que
//  mide esta sonda, y por eso usa PostgREST directamente en vez de la app.
//
//  La cuarta comprobación es la contraria y también importa: el guard NO debe
//  bloquear las columnas *_pendiente, que son donde la empresa propone lo que
//  quiere que le revisen. Un guard que cierre de más deja a la empresa sin
//  forma de acreditarse nunca.
//
//  ── Por qué es pruebas y no producción ──────────────────────────────────
//
//  Porque la cuarta escribe de verdad. Se restaura al valor anterior al
//  terminar, pero una escritura es una escritura: contra producción esto no
//  corre. Ahí, después de promover, se comprueba leyendo — que ninguna empresa
//  tenga acreditación sin documento.
//
//  Correr:  node pruebas/07-sonda-acreditacion.mjs
// ══════════════════════════════════════════════════════════════════════════
import { Sesion, leerAmbientePruebas, leerCredenciales, exigirCuentas } from './lib/api.mjs';

let AMB, cred;
try {
  AMB  = leerAmbientePruebas();
  cred = exigirCuentas(leerCredenciales(), ['empresa']);
} catch (e) { console.error(`\n${e.message}\n`); process.exit(1); }

const C = { ok: '\x1b[32m', mal: '\x1b[31m', dim: '\x1b[90m', neg: '\x1b[1m', fin: '\x1b[0m' };
let fallos = 0;

function anotar(nombre, pasa, detalle) {
  if (!pasa) fallos++;
  console.log(`  ${pasa ? `${C.ok}  OK  ` : `${C.mal} FALLA`}${C.fin}  ${nombre}`);
  if (detalle) console.log(`          ${C.dim}${detalle}${C.fin}`);
}

// El guard responde con RAISE EXCEPTION, que PostgREST traduce a 403/400 con
// el texto dentro. Se acepta cualquiera de las dos formas.
const bloqueado = r => !r.ok && /No autorizado|acreditan con documento/i.test(String(r.error || ''));

console.log(`\n${C.neg}── Sonda de acreditación ──${C.fin}`);
console.log(`   proyecto: ${AMB.url}\n`);

const s = new Sesion('empresa', AMB);
const entrada = await s.login(cred.empresa.email, cred.empresa.password);
if (!entrada.ok) {
  console.error(`${C.mal}No se pudo iniciar sesión: ${entrada.error}${C.fin}\n`);
  process.exit(1);
}
console.log(`   sesión: ${s.email} (rol ${s.perfil?.rol || '?'})\n`);

const mio = `user_id=eq.${s.userId}`;

// ── 1-3. Lo que la empresa YA NO puede hacerse a sí misma ─────────────────
const r1 = await s.update('perfiles', mio, { seguro_rc: true });
anotar('No puede marcarse el seguro RC', bloqueado(r1),
  bloqueado(r1) ? `HTTP ${r1.status} — el guard lo rechaza`
                : `HTTP ${r1.status} — ¡pasó! el guard no está puesto`);

const r2 = await s.update('perfiles', mio, { fecha_vencimiento_seguro_rc: '2030-01-01' });
anotar('No puede inventarse una vigencia', bloqueado(r2),
  bloqueado(r2) ? `HTTP ${r2.status} — el guard lo rechaza`
                : `HTTP ${r2.status} — ¡pasó! y el catálogo confía en esa fecha`);

const r3 = await s.update('perfiles', mio, { permiso_sct: 'SCT/INVENTADO/2026' });
anotar('No puede ponerse un permiso SCT', bloqueado(r3),
  bloqueado(r3) ? `HTTP ${r3.status} — el guard lo rechaza`
                : `HTTP ${r3.status} — ¡pasó!`);

// ── 4. Lo que SÍ debe poder: proponer ─────────────────────────────────────
// Se guarda el valor anterior y se restaura, pase lo que pase.
const antes = (await s.select('perfiles', `${mio}&select=permiso_sct_pendiente`)).data?.[0]?.permiso_sct_pendiente ?? null;
const r4 = await s.update('perfiles', mio, { permiso_sct_pendiente: 'SONDA/H-02/TEMPORAL' });
const propuso = r4.ok && r4.data?.[0]?.permiso_sct_pendiente === 'SONDA/H-02/TEMPORAL';
anotar('SÍ puede proponer en las columnas _pendiente', propuso,
  propuso ? 'el guard no cierra de más: la empresa puede pedir revisión'
          : `HTTP ${r4.status} — ${r4.error || 'no escribió'} · el guard cerró de más`);

const rest = await s.update('perfiles', mio, { permiso_sct_pendiente: antes });
anotar('Restaurado el valor anterior', rest.ok,
  rest.ok ? `permiso_sct_pendiente vuelve a ${antes === null ? 'NULL' : `«${antes}»`}`
          : `⚠ NO se pudo restaurar: ${rest.error} — revísalo a mano`);

// ── 5. La limpieza dejó el terreno consistente ────────────────────────────
const sinRespaldo = await s._pedir('GET',
  '/rest/v1/perfiles?select=user_id&rol=eq.admin' +
  '&or=(and(seguro_rc.is.true,doc_seguro_rc.is.null),' +
     'and(seguro_carga.is.true,doc_seguro_carga.is.null),' +
     'and(permiso_sct.not.is.null,doc_permiso_sct.is.null))');
const n = Array.isArray(sinRespaldo.data) ? sinRespaldo.data.length : -1;
anotar('Ninguna empresa acreditada sin documento', n === 0,
  n === 0 ? 'la limpieza del bloque 3 dejó el terreno consistente'
          : `quedan ${n} — la limpieza no alcanzó`);

console.log('');
if (fallos === 0) {
  console.log(`${C.ok}${C.neg}  Las 5 comprobaciones pasan. La acreditación ya no se autodeclara.${C.fin}\n`);
  process.exit(0);
}
console.log(`${C.mal}${C.neg}  ${fallos} comprobación(es) fallan.${C.fin}\n`);
process.exit(1);
