// ── Candado de paridad ────────────────────────────────────────────────────
//
// Ningún guion que siembre datos o corra un flujo tiene permitido arrancar
// sobre una base de pruebas que no sea, hoy, una copia de producción.
//
// El sello lo escribe supabase/verificar-paridad.sh en supabase/espejo/
// paridad.json. Aquí solo se lee y se decide si se sigue o no.
//
// POR QUÉ ES UN CANDADO Y NO UN AVISO: una prueba verde sobre una base que no
// es producción no es una prueba, es una anécdota. El 2026-08-27 pruebas tenía
// 82 permisos de función más abiertos y la publicación de Realtime vacía; todo
// "pasaba". Un aviso al inicio de la corrida se pierde entre cien líneas de
// salida; un candado no.
import { readFileSync, existsSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { RAIZ } from './api.mjs';

// PORTGO_SELLO_PARIDAD solo existe para poder probar este candado con sellos
// de mentira sin ensuciar el sello real. No sirve para saltárselo: apuntarlo a
// un sello inventado es tan válido como escribir el reporte a mano.
export const RUTA_SELLO = process.env.PORTGO_SELLO_PARIDAD
  || join(RAIZ, 'supabase', 'espejo', 'paridad.json');

// Cuánto puede haber envejecido la verificación. Seis horas es lo que dura una
// sesión de trabajo: más allá de eso, cualquiera pudo tocar cualquiera de las
// dos bases y el sello ya no describe lo que hay.
const HORAS_MAX = Number(process.env.PORTGO_PARIDAD_HORAS || 6);

const COMO_ARREGLARLO = [
  '  Cómo dejarlo listo:',
  '',
  '    PORTGO_DB_URL_PROD="postgresql://…xnyqsewaluezkkrlyhxg…" \\',
  '    PORTGO_DB_URL_PRUEBAS="postgresql://…xskgnudiznryhgagxadu…" \\',
  '    bash supabase/replicar-produccion-a-pruebas.sh',
  '',
  '  (para solo comprobar, sin tocar nada: bash supabase/verificar-paridad.sh)',
].join('\n');

function refDe(url) {
  return String(url || '').match(/https:\/\/([a-z0-9]+)\./)?.[1] || '';
}

export function leerSello() {
  if (!existsSync(RUTA_SELLO)) return null;
  try {
    const sello = JSON.parse(readFileSync(RUTA_SELLO, 'utf8'));
    sello._edadHoras = (Date.now() - statSync(RUTA_SELLO).mtimeMs) / 3600000;
    return sello;
  } catch {
    return null;
  }
}

// Devuelve el sello si las dos bases son la misma. Si no, lanza con el motivo
// exacto y con el comando que lo arregla.
export function exigirParidad(ambientePruebas) {
  if (process.env.PORTGO_SIN_PARIDAD === '1') {
    // Escotilla deliberadamente ruidosa: sirve para depurar el propio guion,
    // no para saltarse la verificación. Queda anotada en el reporte.
    console.log('\n\x1b[41m\x1b[97m  PARIDAD OMITIDA (PORTGO_SIN_PARIDAD=1)  \x1b[0m');
    console.log('\x1b[31m  Los resultados de esta corrida no dicen nada sobre producción.\x1b[0m\n');
    return { omitida: true, veredicto: 'omitida' };
  }

  const sello = leerSello();

  if (!sello) {
    throw new Error(
      'No hay verificación de paridad entre producción y pruebas.\n\n' +
      '  Falta supabase/espejo/paridad.json. Mientras no exista, no se sabe si\n' +
      '  esta base de pruebas se parece a producción, así que lo que salga de\n' +
      '  aquí no se puede usar para decidir nada.\n\n' + COMO_ARREGLARLO);
  }

  const refEsperado = refDe(ambientePruebas?.url);
  if (refEsperado && sello.destino_ref && sello.destino_ref !== refEsperado) {
    throw new Error(
      'La verificación de paridad es de OTRA base.\n\n' +
      `  El sello dice que se verificó ${sello.destino_ref}, pero estos guiones\n` +
      `  apuntan a ${refEsperado}. Alguna de las dos cadenas está cruzada.\n\n` + COMO_ARREGLARLO);
  }

  if (sello.veredicto !== 'identicas') {
    const dims = Object.entries(sello.dimensiones || {})
      .filter(([, v]) => v !== 'identica')
      .map(([k, v]) => `    · ${k}: ${v}`).join('\n');
    throw new Error(
      `Producción y pruebas NO son la misma base (veredicto: ${sello.veredicto}).\n\n` +
      (dims ? `  Lo que no cuadra:\n${dims}\n\n` : '') +
      '  Correr la prueba así daría un resultado que no se puede trasladar a\n' +
      '  producción, que es exactamente lo que se quiere evitar.\n\n' + COMO_ARREGLARLO);
  }

  if (sello._edadHoras > HORAS_MAX) {
    throw new Error(
      `La verificación de paridad tiene ${sello._edadHoras.toFixed(1)} horas ` +
      `(el límite son ${HORAS_MAX}).\n\n` +
      '  Un sello viejo describe cómo estaban las bases entonces, no ahora:\n' +
      '  entre medias pudo entrar una migración, una prueba anterior o un\n' +
      '  cambio hecho a mano en cualquiera de los dos proyectos.\n\n' + COMO_ARREGLARLO);
  }

  return sello;
}

// Una línea para el encabezado de la corrida y para el reporte guardado: la
// prueba tiene que llevar encima la prueba de que la base era la correcta.
export function resumenParidad(sello) {
  if (!sello || sello.omitida) return 'paridad NO verificada — resultados sin valor probatorio';
  return `paridad verificada ${sello.verificado_en} · ${sello.origen_ref} -> ${sello.destino_ref} ` +
         `· modo ${sello.modo} · única diferencia declarada: ${sello.excepcion_declarada}`;
}
