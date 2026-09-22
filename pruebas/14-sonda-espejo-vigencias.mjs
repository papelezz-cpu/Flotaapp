// ══════════════════════════════════════════════════════════════════════════
//  SONDA DEL ESPEJO — compara `vigencias` contra las 35 columnas de origen
//
//  H-04 Etapa 3 puso una doble escritura: cada vez que alguien escribe una
//  columna de documento o fecha, un trigger actualiza la fila de `vigencias`.
//  Las lecturas siguen en las columnas viejas, así que **si el espejo se
//  rompe, nadie se entera**: las pantallas siguen funcionando con la fuente
//  vieja mientras la nueva se queda atrás en silencio.
//
//  Esta sonda es lo que convierte esa etapa en algo con lo que se puede
//  vivir. Reimplementa el mismo mapeo y compara par a par:
//
//      <tabla>.<col_archivo> / <col_fecha>   contra   vigencias
//
//  y falla nombrando la entidad, el documento y los dos valores. Sin esto, la
//  Etapa 4 cambiaría las lecturas a una tabla que nadie comprobó.
//
//  ── Lo que NO puede comprobar ────────────────────────────────────────────
//
//  Que el trigger se dispare. Compara ESTADOS, no eventos: si el espejo
//  estuviera roto pero nadie hubiera escrito desde la Etapa 2, las dos
//  fuentes coincidirían igual y esto saldría en verde. Por eso la prueba de
//  que el trigger funciona vive en pruebas/banco-local/h04-etapa3.sql, que sí
//  escribe y mira qué pasa. Las dos hacen falta.
//
//  Correr:  node pruebas/14-sonda-espejo-vigencias.mjs
//           PORTGO_SONDA_PRODUCCION=1 node pruebas/14-sonda-espejo-vigencias.mjs
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

// El MISMO mapeo de la migración, copiado a propósito: si alguien cambia uno
// sin el otro, esta sonda lo delata en vez de seguirle la corriente.
const MAPEO = [
  ['perfiles',   'perfil',   'permiso_sct',         'doc_permiso_sct',            'fecha_vencimiento_permiso_sct',            'vigente'],
  ['perfiles',   'perfil',   'seguro_rc',           'doc_seguro_rc',              'fecha_vencimiento_seguro_rc',              'vigente'],
  ['perfiles',   'perfil',   'seguro_carga',        'doc_seguro_carga',           'fecha_vencimiento_seguro_carga',           'vigente'],
  ['perfiles',   'perfil',   'permiso_sct',         'doc_permiso_sct_pendiente',  'fecha_vencimiento_permiso_sct_pendiente',  'pendiente'],
  ['perfiles',   'perfil',   'seguro_rc',           'doc_seguro_rc_pendiente',    'fecha_vencimiento_seguro_rc_pendiente',    'pendiente'],
  ['perfiles',   'perfil',   'seguro_carga',        'doc_seguro_carga_pendiente', 'fecha_vencimiento_seguro_carga_pendiente', 'pendiente'],
  ['camiones',   'camion',   'tarjeta_circulacion', 'imagen_tc',                  'fecha_vencimiento_tc',                     'vigente'],
  ['camiones',   'camion',   'seguro_unidad',       'doc_seguro',                 'fecha_vencimiento_seguro',                 'vigente'],
  ['camiones',   'camion',   'permiso_sct_unidad',  'doc_sct',                    'fecha_vencimiento_permiso_sct',            'vigente'],
  ['camiones',   'camion',   'verificacion',        'doc_verificacion',           'fecha_vencimiento_verificacion',           'vigente'],
  ['camiones',   'camion',   'permiso_peligrosa',   'doc_permiso_peligrosa',      'fecha_vencimiento_permiso_peligrosa',      'vigente'],
  ['camiones',   'camion',   'caat',                'doc_caat',                   'vigencia_caat',                            'vigente'],
  ['operadores', 'operador', 'licencia',            'foto_licencia',              'fecha_vencimiento',                        'vigente'],
  ['operadores', 'operador', 'licencia_peligrosa',  'doc_licencia_peligrosa',     'fecha_vencimiento_licencia_peligrosa',     'vigente'],
  ['operadores', 'operador', 'examen_medico',       'doc_examen_medico',          'fecha_examen_medico',                      'vigente'],
  ['operadores', 'operador', 'examen_toxicologico', 'doc_examen_toxicologico',    'fecha_examen_toxicologico',                'vigente'],
  ['operadores', 'operador', 'carta_antecedentes',  'doc_carta_antecedentes',     'fecha_carta_antecedentes',                 'vigente'],
  ['custodios',  'custodio', 'certificacion',       null,                         'fecha_vencimiento_cert',                   'vigente'],
  ['custodios',  'custodio', 'licencia_sedena',     'doc_licencia_sedena',        'fecha_vencimiento_licencia_sedena',        'vigente'],
  ['patios',     'patio',    'permiso_patio',       'doc_permiso',                'fecha_vencimiento_permiso',                'vigente'],
];

const PK = { perfiles: 'user_id', camiones: 'id', operadores: 'id', custodios: 'id', patios: 'id' };

console.log(`\n${C.neg}── Sonda del espejo de vigencias (H-04 etapa 3) ──${C.fin}`);
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

// Las filas de origen, una consulta por tabla.
const origen = {};
for (const tabla of Object.keys(PK)) {
  const cols = new Set([PK[tabla]]);
  MAPEO.filter(m => m[0] === tabla).forEach(m => { if (m[3]) cols.add(m[3]); cols.add(m[4]); });
  const r = await sa.select(tabla, `select=${[...cols].join(',')}&limit=1000`);
  if (!r.ok) { console.error(`${C.mal}No pude leer ${tabla} (HTTP ${r.status})${C.fin}\n`); process.exit(1); }
  origen[tabla] = r.data || [];
}

const rv = await sa.select('vigencias',
  'select=entidad_tipo,entidad_id,tipo_documento,archivo_path,fecha_documento,estado&limit=2000');
if (!rv.ok) { console.error(`${C.mal}No pude leer vigencias (HTTP ${rv.status})${C.fin}\n`); process.exit(1); }

const espejo = new Map();
(rv.data || []).forEach(v =>
  espejo.set(`${v.entidad_tipo}|${v.entidad_id}|${v.tipo_documento}|${v.estado}`, v));

// ── La comparación ────────────────────────────────────────────────────────
const faltan = [], sobran = [], difieren = [];
let pares = 0, iguales = 0;
const vistas = new Set();

for (const [tabla, ent_, tipo, colArch, colFecha, estado] of MAPEO) {
  for (const fila of origen[tabla]) {
    const id    = String(fila[PK[tabla]]);
    const arch  = colArch ? (fila[colArch] ?? null) : null;
    const fecha = fila[colFecha] ?? null;
    const clave = `${ent_}|${id}|${tipo}|${estado}`;

    if (arch === null && fecha === null) {
      // No hay dato: en el espejo NO debe haber fila.
      if (espejo.has(clave)) sobran.push({ clave, v: espejo.get(clave) });
      continue;
    }
    pares++;
    vistas.add(clave);
    const v = espejo.get(clave);
    if (!v) { faltan.push({ clave, arch, fecha }); continue; }
    if ((v.archivo_path ?? null) !== arch || (v.fecha_documento ?? null) !== fecha) {
      difieren.push({ clave, origen: { arch, fecha }, espejo: { arch: v.archivo_path, fecha: v.fecha_documento } });
    } else iguales++;
  }
}

// Filas del espejo que no corresponden a ningún par con dato del origen.
for (const [clave, v] of espejo) {
  if (!vistas.has(clave) && !sobran.some(s => s.clave === clave)) sobran.push({ clave, v });
}

const linea = (pasa, txt, det) => {
  console.log(`  ${pasa ? `${C.ok}  OK  ${C.fin}` : `${C.mal} FALLA${C.fin}`}  ${txt}`);
  if (det) console.log(`          ${C.dim}${det}${C.fin}`);
};

console.log(`   pares con dato en el origen: ${pares}   ·   filas en vigencias: ${espejo.size}\n`);

linea(faltan.length === 0, `Ninguna fila del origen falta en el espejo`,
  faltan.length ? faltan.slice(0, 8).map(f => `${f.clave} (${f.arch ?? '-'} / ${f.fecha ?? '-'})`).join('\n          ')
                : `las ${iguales} coinciden`);

linea(difieren.length === 0, `Ninguna fila difiere en archivo o fecha`,
  difieren.length ? difieren.slice(0, 8).map(d =>
      `${d.clave}\n            origen: ${d.origen.arch ?? '-'} / ${d.origen.fecha ?? '-'}` +
      `\n            espejo: ${d.espejo.arch ?? '-'} / ${d.espejo.fecha ?? '-'}`).join('\n          ')
    : '');

linea(sobran.length === 0, `El espejo no tiene filas de más`,
  sobran.length ? sobran.slice(0, 8).map(s => s.clave).join('\n          ')
                : 'ningún documento fantasma');

const fallos = faltan.length + difieren.length + sobran.length;
console.log('');
if (fallos === 0) {
  console.log(`${C.ok}${C.neg}  El espejo y las 35 columnas dicen lo mismo, en los ${pares} pares.${C.fin}`);
  console.log(`  ${C.dim}Lo que esto NO prueba: que el trigger dispare. Compara estados, no eventos —`);
  console.log(`  eso lo prueba pruebas/banco-local/h04-etapa3.sql, que escribe y mira.${C.fin}\n`);
  process.exit(0);
}
console.log(`${C.mal}${C.neg}  ${fallos} discrepancia(s): el espejo se separó del origen.${C.fin}`);
console.log(`  Mientras las lecturas sigan en las columnas viejas nadie lo nota, y por eso`);
console.log(`  la Etapa 4 no debe moverlas hasta que esto salga limpio.\n`);
process.exit(1);
