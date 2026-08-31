// ══════════════════════════════════════════════════════════════════════════
//  PRUEBA 2 — SEMBRAR EL AMBIENTE DE PRUEBAS
//  Crea usuarios, perfiles y flota aprobada en el proyecto portgo-pruebas
//  para que el flujo completo tenga con qué correr.
//
//  ⚠ Solo corre contra pruebas. leerAmbientePruebas() aborta si la URL es la
//    de producción, y la llave de servicio nunca sale de credenciales.local.json.
//
//  Es idempotente: correrlo dos veces no duplica nada.
//
//  Correr:  node pruebas/02-sembrar.mjs
// ══════════════════════════════════════════════════════════════════════════
import { leerAmbientePruebas, sesionServicio } from './lib/api.mjs';
import { exigirParidad, resumenParidad } from './lib/paridad.mjs';
import { Reporte } from './lib/reporte.mjs';
import { CUENTAS as USUARIOS, CLAVE } from './lib/cuentas.mjs';

const R = new Reporte('PortGo — Sembrado del ambiente de pruebas');

// Sembrar sobre una base que no es copia de producción produce un ambiente
// que solo se parece a sí mismo. El candado exige el sello de paridad antes
// de escribir la primera fila.
let AMB, PARIDAD;
try {
  AMB = leerAmbientePruebas();
  PARIDAD = exigirParidad(AMB);
} catch (e) { console.error(`\n${e.message}\n`); process.exit(1); }

console.log(`\nSembrando en: ${AMB.url}`);
console.log(`Paridad: ${resumenParidad(PARIDAD)}\n`);
const srv = sesionServicio(AMB);

R.seccion('0. Ambiente');
R[PARIDAD.omitida ? 'aviso' : 'info'](resumenParidad(PARIDAD));

R.seccion('1. Usuarios');

const ids = {};

// La API de admin no tiene "crear si no existe": se intenta crear y, si el
// correo ya está tomado, se busca el id en el listado.
const usuariosExistentes = async () => {
  const r = await srv._pedir('GET', '/auth/v1/admin/users?per_page=1000');
  return r.ok ? (r.data?.users || []) : [];
};

for (const u of USUARIOS) {
  const r = await srv._pedir('POST', '/auth/v1/admin/users', {
    body: { email: u.email, password: CLAVE, email_confirm: true, user_metadata: { nombre: u.nombre } },
  });
  if (r.ok && r.data?.id) {
    ids[u.llave] = r.data.id;
    R.ok(`Usuario creado: ${u.email} (${u.rol})`);
  } else {
    const previos = await usuariosExistentes();
    const ya = previos.find(x => x.email === u.email);
    if (ya) {
      ids[u.llave] = ya.id;
      R.info(`Usuario ya existía: ${u.email}`);
    } else {
      R.falla(`No pude crear ${u.email}`, r.error);
    }
  }
}

// ── Perfiles ──────────────────────────────────────────────────────────────
// Puede haber un trigger que ya cree la fila al dar de alta el usuario, así
// que se hace upsert en vez de insert.
R.seccion('2. Perfiles');

// PostgREST exige que todas las filas de un insert múltiple traigan
// exactamente las mismas claves ("All object keys must match"), así que los
// campos de empresa van explícitamente en null para clientes y superadmin.
const esEmpresa = (u) => u.rol === 'admin';
const soloEmpresa = (u, valor) => (esEmpresa(u) ? valor : null);

const PERFILES = USUARIOS.filter(u => ids[u.llave]).map(u => ({
  user_id: ids[u.llave],
  nombre: u.nombre,
  rol: u.rol,
  aprobacion_cuenta: null,        // null = cuenta activa
  rfc:           soloEmpresa(u, 'XAXX010101000'),
  razon_social:  soloEmpresa(u, `${u.nombre} SA de CV`),
  telefono:      soloEmpresa(u, '5555550000'),
  // Vigencias holgadas: si vencen, la empresa no debería poder operar, y no
  // es eso lo que queremos probar aquí.
  fecha_vencimiento_permiso_sct:  soloEmpresa(u, '2027-12-31'),
  fecha_vencimiento_seguro_rc:    soloEmpresa(u, '2027-12-31'),
  fecha_vencimiento_seguro_carga: soloEmpresa(u, '2027-12-31'),
}));

const rPerf = await srv._pedir('POST', '/rest/v1/perfiles', {
  body: PERFILES,
  headers: { Prefer: 'resolution=merge-duplicates,return=representation' },
});
if (rPerf.ok) R.ok(`${PERFILES.length} perfiles listos`);
else R.falla('No pude escribir los perfiles', rPerf.error);

// ── Flota ─────────────────────────────────────────────────────────────────
// Dos empresas con camiones del MISMO tipo, para que puedan competir por la
// misma solicitud y se pueda probar la contraoferta de verdad.
R.seccion('3. Flota');

const VIGENTE = {
  fecha_vencimiento_tc:            '2027-12-31',
  fecha_vencimiento_seguro:        '2027-12-31',
  fecha_vencimiento_permiso_sct:   '2027-12-31',
  fecha_vencimiento_verificacion:  '2027-12-31',
  vigencia_caat:                   '2027-12-31',
};

// capacidad es integer en la base (toneladas), no el texto "20 ton" que
// sugiere el formulario.
const camiones = [
  { id: 'DELTA-01', propietario_id: ids.delta, tipo: 'Torton caja seca',            capacidad: 20, placas: 'AAA-111-A', precio_dia: 8500,  emoji: '🚛', ...VIGENTE },
  { id: 'DELTA-02', propietario_id: ids.delta, tipo: 'Full porta contenedor 40/20', capacidad: 30, placas: 'AAA-222-B', precio_dia: 14500, emoji: '🚛', ...VIGENTE },
  { id: 'OMEGA-01', propietario_id: ids.omega, tipo: 'Torton caja seca',            capacidad: 20, placas: 'BBB-333-C', precio_dia: 9200,  emoji: '🚛', ...VIGENTE },
].filter(c => c.propietario_id)
 .map(c => ({ ...c, estado: 'disponible', aprobacion: 'aprobada' }));

const operadores = [
  { id: 'OP-DELTA-01', propietario_id: ids.delta, nombre: 'Ramiro',  primer_apellido: 'Cárdenas', num_licencia: 'LIC-D-001', clase_licencia: 'E' },
  { id: 'OP-DELTA-02', propietario_id: ids.delta, nombre: 'Beatriz', primer_apellido: 'Ontiveros', num_licencia: 'LIC-D-002', clase_licencia: 'E' },
  { id: 'OP-OMEGA-01', propietario_id: ids.omega, nombre: 'Nicolás', primer_apellido: 'Reséndiz', num_licencia: 'LIC-O-001', clase_licencia: 'E' },
].filter(o => o.propietario_id)
 .map(o => ({ ...o, aprobacion: 'aprobada',
   fecha_vencimiento: '2027-12-31', fecha_examen_medico: '2027-06-30',
   fecha_examen_toxicologico: '2027-06-30', fecha_carta_antecedentes: '2027-06-30' }));

const custodios = ids.omega ? [{
  id: 'CUS-OMEGA-01', propietario_id: ids.omega, nombre: 'Escolta Omega 1',
  tipo: 'Armado', porta_arma: true, precio_dia: 4200, disponibilidad: 'disponible',
  certificaciones: ['C3', 'SEDENA'], fecha_vencimiento_cert: '2027-12-31',
  num_licencia_sedena: 'SED-001', fecha_vencimiento_licencia_sedena: '2027-12-31',
  aprobacion: 'aprobada',
}] : [];

// patios.tipo es NOT NULL, y la capacidad se mide en vehículos, no en m².
const patios = ids.omega ? [{
  id: 'PAT-OMEGA-01', propietario_id: ids.omega, nombre: 'Patio Omega Veracruz',
  tipo: 'Patio Techado', ubicacion: 'Veracruz, Ver.',
  capacidad_vehiculos: 80, precio_dia: 2500,
  estado: 'disponible', aprobacion: 'aprobada',
  fecha_vencimiento_permiso: '2027-12-31',
}] : [];

// lavados cobra por lavado (precio_lavado), no por día, y tipos_vehiculo es
// NOT NULL.
const lavados = ids.omega ? [{
  id: 'LAV-OMEGA-01', propietario_id: ids.omega, nombre: 'Lavado Omega',
  tipos_vehiculo: ['Torton', 'Full', 'Contenedor'],
  tipos_lavado: ['Lavado Exterior', 'Lavado Completo', 'Lavado Contenedor'],
  precio_lavado: 900, ubicacion: 'Veracruz, Ver.',
  estado: 'disponible', aprobacion: 'aprobada',
}] : [];

for (const [tabla, filas] of [['camiones', camiones], ['operadores', operadores],
                              ['custodios', custodios], ['patios', patios], ['lavados', lavados]]) {
  if (!filas.length) { R.info(`${tabla}: nada que sembrar`); continue; }
  const r = await srv._pedir('POST', `/rest/v1/${tabla}`, {
    body: filas,
    headers: { Prefer: 'resolution=merge-duplicates,return=representation' },
  });
  if (r.ok) R.ok(`${tabla}: ${filas.length} registros aprobados y disponibles`);
  else R.falla(`${tabla}: no pude sembrar`, `${r.error}\nFilas: ${filas.map(f => f.id).join(', ')}`);
}

// ── Resumen ───────────────────────────────────────────────────────────────
R.seccion('4. Credenciales del ambiente de pruebas');

R.info(`Contraseña de todas las cuentas: ${CLAVE}`,
  USUARIOS.filter(u => ids[u.llave]).map(u => `${u.rol.padEnd(11)} ${u.email.padEnd(34)} ${u.nombre}`).join('\n'));

R.info('Para entrar desde el navegador',
  'npx serve .   →   http://localhost:3000/app.html\n' +
  'localhost ya apunta al proyecto de pruebas (js/config.js), con el distintivo PRUEBAS abajo a la izquierda.');

R.resumen();
R.guardar('02-sembrado');
