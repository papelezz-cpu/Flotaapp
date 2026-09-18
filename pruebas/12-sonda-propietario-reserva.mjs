// ══════════════════════════════════════════════════════════════════════════
//  SONDA DE PROPIETARIO EN RESERVACIONES — comprueba la premisa de H-06 (b)
//
//  H-06 (b): js/reservaciones.js resuelve la empresa de cada reservacion
//  dando la vuelta por la tabla del recurso -camiones_publico y sus tres
//  hermanas- cuando `reservaciones.propietario_id` ya esta en la propia fila.
//  Son hasta cuatro viajes de red por render de la pantalla mas usada.
//
//  Antes de sustituir una fuente de datos por otra hay que comprobar que
//  dicen lo mismo. Esta sonda compara, fila a fila:
//
//    reservaciones.propietario_id   contra   <tabla del recurso>.propietario_id
//
//  y cuenta por separado los tres modos de fallar que importan:
//
//    · la reservacion no tiene propietario_id  -> el reemplazo perderia el dato
//    · el recurso ya no existe                 -> hoy sale "—", con el cambio
//                                                 saldria el nombre correcto
//    · los dos existen y DIFIEREN              -> el recurso cambio de dueño;
//                                                 hay que decidir cual es el
//                                                 correcto, no elegirlo solo
//
//  El tercero no es un error: para una reservacion pasada, el dueño de
//  ENTONCES -el de la fila- es mas correcto que el de hoy. Pero es un cambio
//  de comportamiento y tiene que decirse, no colarse.
//
//  Correr:  node pruebas/12-sonda-propietario-reserva.mjs
//           PORTGO_SONDA_PRODUCCION=1 node pruebas/12-sonda-propietario-reserva.mjs
//
//  Solo lee.
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

console.log(`\n${C.neg}── Sonda de propietario en reservaciones (H-06 b) ──${C.fin}`);
if (A_PRODUCCION) console.log(`   ${C.am}${C.neg}PRODUCCION${C.fin} — solo lectura`);
console.log(`   proyecto: ${AMB.url}`);
if (!A_PRODUCCION) {
  const s = leerSello();
  console.log(`   paridad:  ${s ? resumenParidad(s) : 'sin sello'}`);
}
console.log('');

const sa = new Sesion('superadmin', AMB);
const ent = await sa.login(cred.superadmin.email, cred.superadmin.password);
if (!ent.ok) { console.error(`${C.mal}No se pudo entrar: ${ent.error}${C.fin}\n`); process.exit(1); }

const { data: reservas, ok } = await sa.select('reservaciones',
  'select=id,unidad,recurso_tipo,propietario_id&limit=1000');
if (!ok) { console.error(`${C.mal}No se pudieron leer las reservaciones${C.fin}\n`); process.exit(1); }

// tabla_recurso(recurso_tipo), tal como lo reparte js/reservaciones.js:158-161
const TABLA = { camion: 'camiones_publico', custodio: 'custodios_publico',
                patio: 'patios_publico',   lavado: 'lavados_publico' };

const duenoDelRecurso = {};
for (const [tipo, tabla] of Object.entries(TABLA)) {
  const ids = reservas
    .filter(r => (tipo === 'camion' ? (!r.recurso_tipo || r.recurso_tipo === 'camion') : r.recurso_tipo === tipo))
    .map(r => r.unidad).filter(Boolean);
  if (!ids.length) continue;
  const { data } = await sa.select(tabla,
    `select=id,propietario_id&id=in.(${ids.map(encodeURIComponent).join(',')})`);
  (data || []).forEach(x => { duenoDelRecurso[x.id] = x.propietario_id; });
}

let coinciden = 0;
const sinPropietario = [], recursoAusente = [], difieren = [];
for (const r of reservas) {
  const delRecurso = duenoDelRecurso[r.unidad];
  if (!r.propietario_id)                 { sinPropietario.push(r); continue; }
  if (delRecurso === undefined)          { recursoAusente.push(r); continue; }
  if (delRecurso !== r.propietario_id)   { difieren.push({ r, delRecurso }); continue; }
  coinciden++;
}

console.log(`   reservaciones: ${reservas.length}\n`);
const linea = (marca, txt, det) => {
  console.log(`  ${marca}  ${txt}`);
  if (det) console.log(`          ${C.dim}${det}${C.fin}`);
};

linea(coinciden === reservas.length ? `${C.ok}  OK  ${C.fin}` : `${C.am} PARTE${C.fin}`,
  `Coinciden los dos orígenes en ${coinciden} de ${reservas.length}`);

linea(sinPropietario.length ? `${C.mal} FALLA${C.fin}` : `${C.ok}  OK  ${C.fin}`,
  `Reservaciones SIN propietario_id: ${sinPropietario.length}`,
  sinPropietario.length
    ? `el reemplazo perderia la empresa en: ${sinPropietario.slice(0,5).map(r => r.id).join(', ')}`
    : 'ninguna — la columna esta poblada en todas');

linea(recursoAusente.length ? `${C.am} AVISO${C.fin}` : `${C.ok}  OK  ${C.fin}`,
  `Reservaciones cuyo recurso ya no se alcanza: ${recursoAusente.length}`,
  recursoAusente.length
    ? `hoy salen con empresa "—"; con propietario_id saldrian bien. Es una MEJORA, no una regresion.`
    : 'ninguna');

linea(difieren.length ? `${C.am} AVISO${C.fin}` : `${C.ok}  OK  ${C.fin}`,
  `Reservaciones donde los dos origenes DIFIEREN: ${difieren.length}`,
  difieren.length
    ? `el recurso cambio de dueño. Con el cambio se enseñaria el dueño DE ENTONCES: ${difieren.slice(0,3).map(d => d.r.id).join(', ')}`
    : 'ninguna — ningun recurso ha cambiado de dueño');

console.log('');
if (sinPropietario.length === 0) {
  console.log(`${C.ok}${C.neg}  La premisa de H-06 (b) se sostiene:${C.fin} propietario_id esta poblado`);
  console.log(`  en las ${reservas.length} filas, asi que puede sustituir a las cuatro consultas`);
  console.log(`  de recurso sin perder la empresa de ninguna.\n`);
  process.exit(0);
}
console.log(`${C.mal}${C.neg}  La premisa NO se sostiene: ${sinPropietario.length} fila(s) sin propietario_id.${C.fin}`);
console.log(`  Sustituir las consultas dejaria esas reservaciones sin empresa.\n`);
process.exit(1);
