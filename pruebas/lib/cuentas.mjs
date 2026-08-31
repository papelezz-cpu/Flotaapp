// Las cuentas del ambiente de pruebas, en un solo lugar: las siembra
// 02-sembrar.mjs y las usa 03-flujo-completo.mjs. Si cambian aquí, cambian
// en los dos lados a la vez.
//
// El dominio pruebas.portgo.mx no existe a propósito: aunque se dispare una
// notificación por correo, no le llega a ninguna persona real.

import { leerCredenciales } from './api.mjs';

// La contraseña de las cuentas sembradas NO vive en el repositorio: sale del
// bloque "pruebas" de pruebas/credenciales.local.json, que está en .gitignore.
//
// Antes estaba aquí en claro y no importaba, porque pruebas solo tenía datos
// inventados. Desde que pruebas es una copia fiel de producción (Regla #3),
// esa misma contraseña abre una cuenta SUPERADMIN sobre datos reales de
// clientes — y este repositorio es público.
function claveDeSiembra() {
  const c = leerCredenciales().pruebas?.clave_siembra;
  if (!c || /PON-AQUI|PENDIENTE/.test(c) || String(c).length < 12) {
    throw new Error(
      `Falta "clave_siembra" en el bloque "pruebas" de pruebas/credenciales.local.json.

  Es la contraseña de las cuentas que crea 02-sembrar.mjs, incluida una de
  superadmin. No puede estar en el repositorio: es público, y pruebas tiene
  los datos reales de los clientes de producción.

  Pon una cadena larga (12+ caracteres) que no uses en ningún otro sitio.`);
  }
  return c;
}

export const CLAVE = claveDeSiembra();

export const CUENTAS = [
  { llave: 'superadmin',  email: 'sa@pruebas.portgo.mx',          nombre: 'Control PortGo (pruebas)', rol: 'superadmin' },
  { llave: 'delta',       email: 'delta@pruebas.portgo.mx',       nombre: 'Transportes Delta',        rol: 'admin' },
  { llave: 'omega',       email: 'omega@pruebas.portgo.mx',       nombre: 'Fletes Omega',             rol: 'admin' },
  { llave: 'importadora', email: 'importadora@pruebas.portgo.mx', nombre: 'Importadora del Sur',      rol: 'cliente' },
  { llave: 'naviera',     email: 'naviera@pruebas.portgo.mx',     nombre: 'Naviera del Norte',        rol: 'cliente' },
];

export const cuenta = (llave) => CUENTAS.find(c => c.llave === llave);
