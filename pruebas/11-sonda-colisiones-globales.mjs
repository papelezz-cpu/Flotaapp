// ══════════════════════════════════════════════════════════════════════════
//  SONDA DE COLISIONES GLOBALES — carga los JS como los carga el navegador
//
//  Este proyecto no usa modulos: son <script> clasicos que comparten un unico
//  ambito lexico global, y el orden lo fija app.html. Eso significa que dos
//  archivos distintos NO pueden declarar `let`, `const` o `class` con el mismo
//  nombre: es un SyntaxError, y el archivo entero deja de ejecutarse. No la
//  funcion — el archivo.
//
//  ── Por que no basta `node --check` ──────────────────────────────────────
//
//  Porque comprueba cada archivo AISLADO, y la colision solo existe al
//  juntarlos. El 2026-09-18 se metio `let _geoTimer` en js/pedidos.js sin ver
//  que js/utils.js:168 ya lo declaraba. `node --check js/pedidos.js` paso en
//  verde; en el navegador, pedidos.js no se ejecuto entero y la pantalla de
//  Solicitudes se quedo muerta en el preview. Es el mismo error de metodo que
//  R-08: comprobar algo PARECIDO a lo que quieres comprobar.
//
//  ── Como lo comprueba ────────────────────────────────────────────────────
//
//  No con expresiones regulares: carga los archivos de verdad, en el orden de
//  app.html, en un unico contexto compartido — que es exactamente lo que hace
//  el navegador. Las declaraciones se instancian ANTES de ejecutar nada, asi
//  que la colision salta aunque el codigo despues falle por no haber DOM.
//
//  Los errores de ejecucion se ignoran a proposito y se cuentan aparte: aqui
//  no hay document, ni window, ni sb. Lo unico que se persigue es el
//  SyntaxError, que es el que rompe el archivo completo.
//
//  Correr:  node pruebas/11-sonda-colisiones-globales.mjs
//  No toca ninguna base de datos ni la red.
// ══════════════════════════════════════════════════════════════════════════
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..');
const C = { ok:'\x1b[32m', mal:'\x1b[31m', dim:'\x1b[90m', neg:'\x1b[1m', am:'\x1b[33m', fin:'\x1b[0m' };

// El orden lo manda app.html, no el alfabeto ni el sistema de archivos.
const html = readFileSync(join(RAIZ, 'app.html'), 'utf8');
const orden = [...html.matchAll(/<script\s+src="(js\/[^"?]+\.js)(\?[^"]*)?"/g)].map(m => m[1]);

console.log(`\n${C.neg}── Sonda de colisiones globales ──${C.fin}`);
console.log(`   ${orden.length} scripts, en el orden que los declara app.html\n`);

if (!orden.length) {
  console.error(`${C.mal}No se encontro ningun <script src="js/...">. ¿Cambio el formato de app.html?${C.fin}\n`);
  process.exit(1);
}

// El error nace DENTRO del contexto del vm, que tiene su propio SyntaxError.
// `e instanceof SyntaxError` compara contra el del host y da false siempre:
// la primera version de esta sonda usaba instanceof y daba «sin colisiones»
// con la colision puesta, contando el SyntaxError como un error de ejecucion
// mas. Se comprueba por nombre, que no depende del realm.
const esSyntaxError = e => e && e.name === 'SyntaxError';

// ── Autocomprobacion ──────────────────────────────────────────────────────
// Un detector que nunca ha fallado no ha demostrado que sepa fallar. Antes de
// mirar los archivos de verdad, se le da una colision sintetica por el MISMO
// camino de codigo; si no la caza, la sonda se niega a dar un veredicto en
// vez de dar uno tranquilizador.
{
  const prueba = vm.createContext({});
  let cazada = false;
  vm.runInContext('let __colision_de_prueba = 1;', prueba, { filename: 'a.js' });
  try {
    vm.runInContext('let __colision_de_prueba = 2;', prueba, { filename: 'b.js' });
  } catch (e) { cazada = esSyntaxError(e); }
  if (!cazada) {
    console.error(`${C.mal}${C.neg}  La sonda no detecta una colision que ella misma provoca.${C.fin}`);
    console.error(`  No se emite veredicto: un "sin colisiones" de esta sonda no valdria nada.\n`);
    process.exit(2);
  }
}

const ctx = vm.createContext({ console: { log(){}, warn(){}, error(){} } });
const colisiones = [];
const faltan = [];
let conErrorDeEjecucion = 0;

for (const rel of orden) {
  const abs = join(RAIZ, rel);
  if (!existsSync(abs)) { faltan.push(rel); continue; }
  try {
    vm.runInContext(readFileSync(abs, 'utf8'), ctx, { filename: rel });
  } catch (e) {
    if (esSyntaxError(e)) {
      colisiones.push({ rel, msg: e.message });
      console.log(`  ${C.mal} FALLA${C.fin}  ${rel}`);
      console.log(`          ${C.mal}SyntaxError: ${e.message}${C.fin}`);
      console.log(`          ${C.dim}este archivo NO se ejecuta en el navegador, entero${C.fin}`);
    } else {
      // Esperado: no hay DOM. La ejecucion muere pronto y no importa.
      conErrorDeEjecucion++;
    }
  }
}

if (faltan.length) {
  console.log(`  ${C.am} AVISO${C.fin}  ${faltan.length} script(s) de app.html no existen en disco:`);
  faltan.forEach(f => console.log(`          ${f}`));
}

console.log('');
if (colisiones.length === 0) {
  console.log(`${C.ok}${C.neg}  Sin colisiones: los ${orden.length} scripts conviven en el mismo ambito global.${C.fin}`);
  console.log(`  ${C.dim}${conErrorDeEjecucion} pararon por falta de DOM, que es lo esperado y no se comprueba aqui.${C.fin}\n`);
  process.exit(faltan.length ? 1 : 0);
}
console.log(`${C.mal}${C.neg}  ${colisiones.length} archivo(s) no se ejecutarian en el navegador.${C.fin}`);
console.log(`  Renombra el identificador duplicado. Un prefijo por modulo -_ped, _res, _adm-`);
console.log(`  evita la siguiente sin tener que recordar esta.\n`);
process.exit(1);
