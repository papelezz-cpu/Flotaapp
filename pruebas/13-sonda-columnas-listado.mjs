// ══════════════════════════════════════════════════════════════════════════
//  SONDA DE COLUMNAS DEL LISTADO — vigila H-08
//
//  H-08: las consultas de listado pedían select('*') sobre tablas de 50 y 63
//  columnas. Ahora piden una lista explícita —PED_COLS_LISTA en pedidos.js y
//  RES_COLS_LISTA en reservaciones.js— y eso introduce un modo de fallar que
//  no existía: **olvidar una columna no da error**. La consulta funciona, la
//  fila llega sin ese campo, y la interfaz pinta un hueco. Nadie se entera
//  hasta que un usuario pregunta por qué falta un dato.
//
//  ── Qué comprueba ────────────────────────────────────────────────────────
//
//  Para cada tabla, cruza tres cosas:
//
//    1. las columnas REALES del esquema (del volcado de producción),
//    2. la lista que pide el código (leída del propio fichero, no copiada),
//    3. los accesos `algo.columna` en TODOS los ficheros de js/.
//
//  y falla si alguna columna que el código usa no está en la lista.
//
//  ── Las excepciones, y por qué se enumeran ───────────────────────────────
//
//  Trece nombres de columna de `pedidos` aparecen en js/plantillas.js sin ser
//  lecturas de una fila: son las cadenas de PLANTILLA_CAMPOS, que mapea id de
//  formulario -> columna y lee de document.getElementById, nunca del pedido
//  descargado. Comprobado a mano el 2026-09-18. Se enumeran una a una con su
//  motivo en vez de relajar la busqueda: si mañana aparece una catorceava,
//  esta sonda tiene que pararse, no encogerse de hombros.
//
//  ── Qué NO comprueba ─────────────────────────────────────────────────────
//
//  El acceso dinámico `fila[variable]`. Hoy solo existe en dos sitios
//  (abrirEvidencias, con 'evidencias' y 'evidencias_cliente', las dos en la
//  lista y además re-consultando la fila por su cuenta), pero un `fila[x]`
//  nuevo se le escaparía. Por eso también busca ese patrón y avisa.
//
//  Correr:  node pruebas/13-sonda-columnas-listado.mjs
//  No toca ninguna base de datos ni la red.
// ══════════════════════════════════════════════════════════════════════════
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..');
const C = { ok:'\x1b[32m', mal:'\x1b[31m', dim:'\x1b[90m', neg:'\x1b[1m', am:'\x1b[33m', fin:'\x1b[0m' };

const ESPEJO = join(RAIZ, 'supabase', 'espejo', '01-esquema-public.sql');
if (!existsSync(ESPEJO)) {
  console.error(`\n${C.mal}Falta ${ESPEJO}.${C.fin}`);
  console.error(`Es el volcado de producción y está en .gitignore, así que en una copia`);
  console.error(`recién clonada no existe. Regenéralo con la réplica antes de correr esto.\n`);
  process.exit(2);
}
const esquema = readFileSync(ESPEJO, 'utf8');

function columnasDelEsquema(tabla) {
  const m = esquema.match(new RegExp(`CREATE TABLE public\\.${tabla} \\(([\\s\\S]*?)\\n\\);`, 'm'));
  if (!m) return null;
  return m[1].split('\n').map(l => l.trim())
    .filter(l => l && !/^(CONSTRAINT|PRIMARY|FOREIGN|UNIQUE|CHECK)/i.test(l))
    .map(l => l.split(/\s+/)[0])
    .filter(c => /^[a-z_][a-z0-9_]*$/.test(c));
}

// La lista se LEE del fichero, no se copia aquí: una copia se desincroniza y
// entonces la sonda vigila algo que ya no es lo que corre.
function listaDelCodigo(fichero, constante) {
  const ctx = vm.createContext({ console: { log(){}, warn(){}, error(){} } });
  try { vm.runInContext(readFileSync(join(RAIZ, fichero), 'utf8'), ctx, { filename: fichero }); }
  catch { /* muere por falta de DOM despues de asignar la constante */ }
  try {
    const v = vm.runInContext(constante, ctx);
    return typeof v === 'string' ? v.split(',').map(s => s.trim()).filter(Boolean) : null;
  } catch { return null; }
}

const FUENTES = readdirSync(join(RAIZ, 'js')).filter(f => f.endsWith('.js'))
  .map(f => [f, readFileSync(join(RAIZ, 'js', f), 'utf8')]);

// Excepciones justificadas: el nombre aparece, pero no es una lectura de fila.
const EXCEPCIONES = {
  pedidos: {
    ficheros: ['plantillas.js'],
    motivo: 'cadenas de PLANTILLA_CAMPOS: mapean id de formulario -> columna y leen de document.getElementById, nunca del pedido descargado',
    columnas: ['num_bultos','temp_min','temp_max','contenedor_1_tipo','contenedor_1_peso',
               'contenedor_2_tipo','contenedor_2_peso','largo_m','ancho_m','alto_m',
               'hazmat_clase','hazmat_un','num_tarimas'],
  },
};

const CASOS = [
  { tabla: 'pedidos',       fichero: 'js/pedidos.js',       constante: 'PED_COLS_LISTA' },
  { tabla: 'reservaciones', fichero: 'js/reservaciones.js', constante: 'RES_COLS_LISTA' },
];

console.log(`\n${C.neg}── Sonda de columnas del listado (H-08) ──${C.fin}\n`);

let fallos = 0, avisos = 0;
for (const { tabla, fichero, constante } of CASOS) {
  const todas = columnasDelEsquema(tabla);
  const pedidas = listaDelCodigo(fichero, constante);
  if (!todas)   { console.log(`  ${C.mal} FALLA${C.fin}  ${tabla}: no pude leer el esquema`); fallos++; continue; }
  if (!pedidas) { console.log(`  ${C.mal} FALLA${C.fin}  ${tabla}: no pude leer ${constante} de ${fichero}`); fallos++; continue; }

  // Nombres inventados: una columna en la lista que el esquema no tiene es un
  // error 400 en cuanto alguien abra la pantalla.
  const fantasmas = pedidas.filter(c => !todas.includes(c));
  if (fantasmas.length) {
    console.log(`  ${C.mal} FALLA${C.fin}  ${tabla}: ${constante} pide columnas que no existen: ${fantasmas.join(', ')}`);
    fallos++;
  }

  const exc = EXCEPCIONES[tabla];
  const omitidas = todas.filter(c => !pedidas.includes(c));
  const enUso = [];
  for (const c of omitidas) {
    const re = new RegExp(`[.\\['"\`]${c}\\b`);
    let donde = FUENTES.filter(([, s]) => re.test(s)).map(([f]) => f);
    if (exc && exc.columnas.includes(c)) donde = donde.filter(f => !exc.ficheros.includes(f));
    if (donde.length) enUso.push({ c, donde });
  }

  if (enUso.length) {
    fallos++;
    console.log(`  ${C.mal} FALLA${C.fin}  ${tabla}: ${enUso.length} columna(s) omitidas que el código SÍ usa`);
    enUso.forEach(({ c, donde }) => console.log(`          ${C.mal}${c}${C.fin} en ${donde.join(', ')}`));
    console.log(`          ${C.dim}añádelas a ${constante}, o justifica la excepción en esta sonda${C.fin}`);
  } else {
    console.log(`  ${C.ok}  OK  ${C.fin}  ${tabla}: pide ${pedidas.length} de ${todas.length}; ninguna de las ${omitidas.length} omitidas se usa`);
    if (exc) console.log(`          ${C.dim}${exc.columnas.length} excepciones declaradas en ${exc.ficheros.join(', ')} — ${exc.motivo}${C.fin}`);
  }
}

// Acceso dinamico: lo que esta sonda no puede resolver, lo enseña.
const DINAMICO = /\b(?:p|r|ped|res|row|fila)\[([A-Za-z_$][\w$]*)\]/g;
const hallados = [];
FUENTES.forEach(([f, s]) => { for (const m of s.matchAll(DINAMICO)) hallados.push(`${f}: [${m[1]}]`); });
if (hallados.length) {
  avisos++;
  console.log(`\n  ${C.am} AVISO${C.fin}  ${hallados.length} acceso(s) por variable, que esta sonda NO puede comprobar:`);
  [...new Set(hallados)].forEach(h => console.log(`          ${h}`));
  console.log(`          ${C.dim}revisa a mano que la columna que resuelvan esté en la lista${C.fin}`);
}

console.log('');
if (fallos === 0) {
  console.log(`${C.ok}${C.neg}  Las listas cubren todo lo que el código lee.${C.fin}`);
  if (avisos) console.log(`  ${C.am}Con ${avisos} aviso(s) que piden ojo humano.${C.fin}`);
  console.log('');
  process.exit(0);
}
console.log(`${C.mal}${C.neg}  ${fallos} problema(s). Una columna que falta no da error: deja un hueco.${C.fin}\n`);
process.exit(1);
