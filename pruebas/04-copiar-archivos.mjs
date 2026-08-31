// ══════════════════════════════════════════════════════════════════════════
//  COPIAR LOS ARCHIVOS DE STORAGE — producción → pruebas
//
//  Los bytes de los documentos, evidencias y fotos no viven en Postgres: viven
//  en el Storage (S3). El volcado de la base copia las RUTAS, no los archivos,
//  así que sin este paso pruebas queda con filas que apuntan a archivos que
//  ahí no existen: cada documento de viaje, cada evidencia de cierre y cada
//  foto de verificación abre un 404. Una prueba de expedientes sobre eso no
//  prueba nada.
//
//  De dónde sale la lista: supabase/espejo/10-objetos.tsv, que escribe
//  supabase/replicar-produccion-a-pruebas.sh leyendo storage.objects.
//
//  ⚠ Necesita la llave de servicio de PRODUCCIÓN para poder BAJAR los archivos
//    (los buckets privados no se leen de otra forma). Ponla en
//    pruebas/credenciales.local.json, que está en .gitignore:
//
//      "produccion": { "service_role": "eyJ..." }
//
//    Si no está, este guion no corre. De producción solo hace GET.
//
//  Correr:  node pruebas/04-copiar-archivos.mjs [--forzar]
//    --forzar  vuelve a subir incluso los que ya están del mismo tamaño
// ══════════════════════════════════════════════════════════════════════════
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { leerAmbientePruebas, leerCredenciales, CONFIG, RAIZ } from './lib/api.mjs';

const FORZAR = process.argv.includes('--forzar');
const LISTA = join(RAIZ, 'supabase', 'espejo', '10-objetos.tsv');

let AMB, cred;
try {
  AMB = leerAmbientePruebas();
  cred = leerCredenciales();
} catch (e) { console.error(`\n${e.message}\n`); process.exit(1); }

const LLAVE_PROD = cred.produccion?.service_role;
if (!LLAVE_PROD || /PENDIENTE|PON-AQUI/.test(LLAVE_PROD)) {
  console.error('\nFalta la llave de servicio de PRODUCCIÓN.\n');
  console.error('  Los buckets privados (unidades, registros, documentos-viaje) no se');
  console.error('  pueden leer sin ella, así que sin esto no hay forma de copiar los');
  console.error('  archivos y pruebas seguirá dando 404 en cada documento.\n');
  console.error('  En pruebas/credenciales.local.json (que git nunca ve) agrega:\n');
  console.error('    "produccion": { "service_role": "eyJ..." }\n');
  console.error('  Supabase → proyecto de producción → Settings → API → service_role.');
  console.error('  Este guion solo hace GET contra producción; nunca escribe ahí.\n');
  process.exit(2);
}

if (!existsSync(LISTA)) {
  console.error(`\nFalta ${LISTA}.\n`);
  console.error('  La escribe la réplica al leer storage.objects de producción:');
  console.error('    bash supabase/replicar-produccion-a-pruebas.sh\n');
  process.exit(1);
}

const objetos = readFileSync(LISTA, 'utf8')
  .split('\n')
  .map((l) => l.replace(/\r$/, ''))
  .filter(Boolean)
  .map((l) => {
    const i = l.indexOf('\t');
    return { bucket: l.slice(0, i), ruta: l.slice(i + 1) };
  })
  .filter((o) => o.bucket && o.ruta);

console.log(`\nCopiando ${objetos.length} archivos`);
console.log(`  de : ${CONFIG.url}  (solo lectura)`);
console.log(`  a  : ${AMB.url}\n`);

// Las rutas llevan barras que deben seguir siendo barras, y nombres de archivo
// con acentos o espacios que sí hay que codificar.
const rutaUrl = (r) => r.split('/').map(encodeURIComponent).join('/');

const cabecerasProd = { apikey: LLAVE_PROD, Authorization: `Bearer ${LLAVE_PROD}` };
const cabecerasPrue = { apikey: AMB.service_role, Authorization: `Bearer ${AMB.service_role}` };

async function copiar(o) {
  const src = `${CONFIG.url}/storage/v1/object/${o.bucket}/${rutaUrl(o.ruta)}`;
  const dst = `${AMB.url}/storage/v1/object/${o.bucket}/${rutaUrl(o.ruta)}`;

  if (!FORZAR) {
    // Si ya está y pesa lo mismo, no se vuelve a bajar: en una segunda corrida
    // eso es la diferencia entre segundos y varios minutos.
    const ya = await fetch(dst, { method: 'HEAD', headers: cabecerasPrue }).catch(() => null);
    if (ya?.ok) {
      const orig = await fetch(src, { method: 'HEAD', headers: cabecerasProd }).catch(() => null);
      if (orig?.ok && orig.headers.get('content-length') === ya.headers.get('content-length')) {
        return 'igual';
      }
    }
  }

  const bajada = await fetch(src, { headers: cabecerasProd });
  if (!bajada.ok) return `no se pudo bajar (HTTP ${bajada.status})`;
  const cuerpo = await bajada.arrayBuffer();

  const subida = await fetch(dst, {
    method: 'POST',
    headers: {
      ...cabecerasPrue,
      'Content-Type': bajada.headers.get('content-type') || 'application/octet-stream',
      'x-upsert': 'true',
    },
    body: cuerpo,
  });
  if (!subida.ok) return `no se pudo subir (HTTP ${subida.status}) ${(await subida.text()).slice(0, 120)}`;
  return 'copiado';
}

// De cuatro en cuatro: en serie tarda demasiado con cientos de archivos, y sin
// límite el Storage empieza a devolver 429.
const CONCURRENCIA = 4;
const cuenta = { copiado: 0, igual: 0, error: 0 };
const errores = [];
let hechos = 0;

async function trabajador(cola) {
  for (;;) {
    const o = cola.shift();
    if (!o) return;
    let r;
    try { r = await copiar(o); } catch (e) { r = `excepción: ${e.message}`; }
    if (r === 'copiado' || r === 'igual') cuenta[r]++;
    else { cuenta.error++; errores.push(`${o.bucket}/${o.ruta} — ${r}`); }
    hechos++;
    if (hechos % 10 === 0 || hechos === objetos.length) {
      process.stdout.write(`\r  ${hechos}/${objetos.length}  copiados ${cuenta.copiado} · ya estaban ${cuenta.igual} · fallos ${cuenta.error}   `);
    }
  }
}

const cola = [...objetos];
await Promise.all(Array.from({ length: CONCURRENCIA }, () => trabajador(cola)));

console.log('\n');

// ── Los que sobran ────────────────────────────────────────────────────────
// Copiar los 357 de producción no basta: si en pruebas quedan archivos que
// producción no tiene, los dos Storage siguen siendo distintos y la dimensión
// "objetos en Storage" seguirá divergiendo, con razón.
const LISTA_PRUEBAS = join(RAIZ, 'supabase', 'espejo', '12-objetos-pruebas.tsv');
if (existsSync(LISTA_PRUEBAS)) {
  const enProd = new Set(objetos.map((o) => `${o.bucket}\t${o.ruta}`));
  const sobran = readFileSync(LISTA_PRUEBAS, 'utf8')
    .split('\n').map((l) => l.replace(/\r$/, '')).filter(Boolean)
    .filter((l) => !enProd.has(l))
    .map((l) => { const i = l.indexOf('\t'); return { bucket: l.slice(0, i), ruta: l.slice(i + 1) }; });

  if (sobran.length && !process.argv.includes('--limpiar-sobrantes')) {
    console.log(`⚠ ${sobran.length} archivo(s) están en pruebas y NO en producción:`);
    sobran.slice(0, 30).forEach((o) => console.log(`   ${o.bucket}/${o.ruta}`));
    if (sobran.length > 30) console.log(`   … y ${sobran.length - 30} más`);
    console.log('\n  Mientras estén, los dos Storage no son iguales y la verificación');
    console.log('  va a seguir marcando divergencia. Para borrarlos —y solo si estás');
    console.log('  de acuerdo con borrarlos— vuelve a correr con:');
    console.log('    node pruebas/04-copiar-archivos.mjs --limpiar-sobrantes\n');
  } else if (sobran.length) {
    process.stdout.write(`Borrando ${sobran.length} archivo(s) que producción no tiene… `);
    let borrados = 0;
    for (const o of sobran) {
      const r = await fetch(`${AMB.url}/storage/v1/object/${o.bucket}/${rutaUrl(o.ruta)}`,
                            { method: 'DELETE', headers: cabecerasPrue });
      if (r.ok) borrados++;
    }
    console.log(`${borrados} borrados.\n`);
  } else {
    console.log('✓ En pruebas no sobra ningún archivo.\n');
  }
}

if (errores.length) {
  console.log(`⚠ ${errores.length} archivo(s) no se pudieron copiar:`);
  errores.slice(0, 20).forEach((e) => console.log(`   ${e}`));
  if (errores.length > 20) console.log(`   … y ${errores.length - 20} más`);
  console.log('\n  Mientras falten, esas rutas darán 404 en pruebas y cualquier prueba');
  console.log('  que abra un documento va a fallar por una razón que no es el código.\n');
  process.exit(1);
}
console.log(`✅ Storage replicado: ${cuenta.copiado} copiados, ${cuenta.igual} ya estaban.\n`);
