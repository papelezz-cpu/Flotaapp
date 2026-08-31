// ── Cliente REST mínimo para las pruebas ──────────────────────────────────
// Sin npm: usa el fetch nativo de Node 18+. Habla el mismo protocolo que el
// SDK del navegador (GoTrue + PostgREST), así que las pruebas pasan por RLS,
// por los guard triggers y por las RPC exactamente igual que la app real.
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { execFileSync } from 'node:child_process';

export const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

// El proyecto de PRODUCCIÓN sale de js/config.js: una sola fuente de verdad.
//
// Hay dos formatos posibles y se aceptan los dos:
//   1. Un config con los dos ambientes juntos (bloques 'produccion:' y 'pruebas:').
//   2. Un config por rama, que es como está hoy: cada rama trae SOLO su proyecto
//      (main -> producción, dev -> pruebas). Ahí el working tree no sirve, porque
//      en dev daría el ref de pruebas y el candado exigirNoProduccion() quedaría
//      al revés: creería que pruebas es producción y bloquearía todo. Por eso el
//      config de producción se lee de la rama main, que es producción por definición.
function extraerAmbiente(src) {
  const url = src.match(/'(https:\/\/[a-z0-9]+\.supabase\.co)'/)?.[1];
  const anon = src.match(/'(eyJ[A-Za-z0-9._-]+\.[A-Za-z0-9._-]+)'/)?.[1];
  return url && anon ? { url, anon } : null;
}

export function leerConfig() {
  const src = readFileSync(join(RAIZ, 'js', 'config.js'), 'utf8');

  let amb = null;
  if (src.includes('produccion:') && src.includes('pruebas:')) {
    amb = extraerAmbiente(src.slice(src.indexOf('produccion:'), src.indexOf('pruebas:')));
  } else {
    try {
      amb = extraerAmbiente(execFileSync('git', ['show', 'main:js/config.js'], { cwd: RAIZ, encoding: 'utf8' }));
    } catch { /* sin git o sin rama main: cae al error de abajo */ }
  }

  if (!amb) throw new Error(
    'No pude leer URL/anon key de PRODUCCIÓN.\n' +
    'Se buscó en js/config.js (formato con bloques produccion:/pruebas:) y en la\n' +
    'rama main (formato de un config por rama). Sin ese dato no se puede fijar el\n' +
    'candado que impide escribir en producción, así que no se sigue.');

  const { url, anon } = amb;
  return { nombre: 'produccion', url, anon, fnUsuario: `${url}/functions/v1/gestionar-usuario`, fnNotif: `${url}/functions/v1/enviar-notificacion` };
}

export function leerCredenciales() {
  const p = join(RAIZ, 'pruebas', 'credenciales.local.json');
  if (!existsSync(p)) throw new Error('Falta pruebas/credenciales.local.json');
  return JSON.parse(readFileSync(p, 'utf8'));
}

export function exigirCuentas(cred, roles) {
  const falta = roles.filter(r => {
    const v = cred[r];
    return !v?.email || !v?.password || /PON-AQUI/.test(v.email) || /PON-AQUI/.test(v.password);
  });
  if (falta.length) {
    throw new Error(
      `Faltan credenciales en pruebas/credenciales.local.json para: ${falta.join(', ')}.\n` +
      'Abre el archivo, reemplaza los PON-AQUI-... y vuelve a correr.');
  }
  return cred;
}

const CFG = leerConfig();

// El ref del proyecto de producción, para no confundirlo nunca con el de
// pruebas cuando un script vaya a escribir.
export const REF_PRODUCCION = CFG.url.match(/https:\/\/([a-z0-9]+)\./)[1];

// Devuelve el ambiente de pruebas configurado en credenciales.local.json.
// Es donde viven url, anon y service_role del proyecto portgo-pruebas: ese
// archivo está en .gitignore, así que la llave de servicio nunca se sube.
export function leerAmbientePruebas() {
  const cred = leerCredenciales();
  const a = cred.pruebas;
  if (!a?.url || !a?.anon || /PENDIENTE|PON-AQUI/.test(a.url + a.anon)) {
    throw new Error(
      'El ambiente de pruebas todavía no está configurado.\n' +
      'En pruebas/credenciales.local.json llena el bloque "pruebas" con url, anon\n' +
      'y service_role del proyecto portgo-pruebas (Supabase → Settings → API).');
  }
  exigirNoProduccion(a.url);
  return { nombre: 'pruebas', ...a };
}

// Candado: ningún script que escriba puede apuntar a producción por error.
export function exigirNoProduccion(url) {
  if (String(url).includes(REF_PRODUCCION)) {
    throw new Error(
      `ALTO: esa URL es la de PRODUCCIÓN (${REF_PRODUCCION}).\n` +
      'Este script solo corre contra el proyecto de pruebas.');
  }
  return url;
}

// Cada sesión = un usuario autenticado. `bitacora` guarda todas las llamadas
// para poder reconstruir qué se tocó (importante: esto pega en producción).
export class Sesion {
  // `ambiente` decide contra qué proyecto habla: producción por omisión,
  // o el de pruebas si se le pasa leerAmbientePruebas().
  constructor(etiqueta, ambiente = CFG) {
    this.etiqueta = etiqueta;
    this.ambiente = ambiente;
    this.token = null;
    this.userId = null;
    this.email = null;
    this.perfil = null;
    this.bitacora = [];
  }

  get autenticada() { return !!this.token; }

  // Con la llave de servicio la sesión salta RLS: solo para sembrar datos en
  // pruebas, nunca contra producción (leerAmbientePruebas ya lo impide).
  usarLlaveDeServicio() {
    if (!this.ambiente.service_role) throw new Error('Falta service_role en el bloque "pruebas"');
    exigirNoProduccion(this.ambiente.url);
    this.token = this.ambiente.service_role;
    this.esServicio = true;
    return this;
  }

  _headers(extra = {}) {
    const clave = this.esServicio ? this.ambiente.service_role : this.ambiente.anon;
    return {
      apikey: clave,
      Authorization: `Bearer ${this.token || this.ambiente.anon}`,
      'Content-Type': 'application/json',
      ...extra,
    };
  }

  async _pedir(metodo, ruta, { body, headers, base } = {}) {
    const url = (base || this.ambiente.url) + ruta;
    const t0 = Date.now();
    let res, texto;
    try {
      res = await fetch(url, {
        method: metodo,
        headers: this._headers(headers),
        body: body === undefined ? undefined : JSON.stringify(body),
      });
      texto = await res.text();
    } catch (e) {
      const salida = { ok: false, status: 0, data: null, error: `Red: ${e.message}` };
      this.bitacora.push({ metodo, ruta, ms: Date.now() - t0, ...salida });
      return salida;
    }
    let data = null;
    if (texto) { try { data = JSON.parse(texto); } catch { data = texto; } }
    const ok = res.ok;
    const error = ok ? null : (data?.message || data?.error || data?.msg || texto || `HTTP ${res.status}`);
    const salida = { ok, status: res.status, data, error };
    this.bitacora.push({ metodo, ruta: ruta.slice(0, 160), ms: Date.now() - t0, status: res.status, error });
    return salida;
  }

  // ── Auth ────────────────────────────────────────────────────────────
  async login(email, password) {
    const r = await this._pedir('POST', '/auth/v1/token?grant_type=password', {
      body: { email, password },
    });
    if (!r.ok) return r;
    this.token = r.data.access_token;
    this.userId = r.data.user?.id;
    this.email = r.data.user?.email;
    const p = await this.select('perfiles', `user_id=eq.${this.userId}&select=*`);
    this.perfil = p.data?.[0] || null;
    return r;
  }

  logout() { this.token = null; this.userId = null; this.perfil = null; }

  // ── PostgREST ───────────────────────────────────────────────────────
  select(tabla, query = 'select=*') {
    return this._pedir('GET', `/rest/v1/${tabla}?${query}`);
  }

  async contar(tabla, query = '') {
    const r = await this._pedir('GET', `/rest/v1/${tabla}?select=id${query ? '&' + query : ''}`, {
      headers: { Prefer: 'count=exact', Range: '0-0' },
    });
    return r;
  }

  insert(tabla, filas) {
    return this._pedir('POST', `/rest/v1/${tabla}`, {
      body: filas,
      headers: { Prefer: 'return=representation' },
    });
  }

  update(tabla, filtro, patch) {
    return this._pedir('PATCH', `/rest/v1/${tabla}?${filtro}`, {
      body: patch,
      headers: { Prefer: 'return=representation' },
    });
  }

  rpc(fn, args = {}) {
    return this._pedir('POST', `/rest/v1/rpc/${fn}`, { body: args });
  }

  // ── Edge Functions ──────────────────────────────────────────────────
  edge(url, body) {
    const u = new URL(url);
    return this._pedir('POST', u.pathname, { body, base: u.origin });
  }
}

// Sesión anónima: sirve para comprobar qué expone la app a quien no ha entrado.
export function sesionAnonima(ambiente = CFG) { return new Sesion('anon', ambiente); }

// Sesión con la llave de servicio del proyecto de pruebas: crea usuarios y
// siembra datos saltándose RLS. Falla sola si la URL fuera la de producción.
export function sesionServicio(ambiente) {
  return new Sesion('servicio', ambiente).usarLlaveDeServicio();
}

export const CONFIG = CFG;
