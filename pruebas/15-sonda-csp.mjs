// Sonda de la CSP de vercel.json (F-04, regla 44c de docs/AUDITORIA.md).
//
//   node pruebas/15-sonda-csp.mjs
//
// Sirve el repositorio en localhost con las MISMAS cabeceras que vercel.json,
// abre index, privacidad, terminos y app.html en Chrome sin interfaz y recoge
// toda violacion de CSP. Desde app.html pide, como haria la app con sesion,
// cada tipo de recurso que usa (REST, websocket de Realtime, Storage, teselas,
// Nominatim, icono de Leaflet, ventana de la Carta Porte) y dos controles que
// DEBEN bloquearse. Sale con 1 si algo legitimo se bloquea o si un control pasa:
// un control que pasa significa que la CSP no se esta aplicando.
//
// No toca ninguna base: la unica peticion a Supabase es una lectura anonima que
// devuelve 401. Por eso no exige sello de paridad (Regla #3).
// Lo que NO cubre: las pantallas con sesion iniciada. Esas, en dev con la consola.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import os from 'node:os';
import { fileURLToPath } from 'node:url';

const RAIZ = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const vercel = JSON.parse(fs.readFileSync(path.join(RAIZ, 'vercel.json'), 'utf8'));
const PUERTO = 5180, CDP = 9333;
const TIPOS = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.webmanifest': 'application/manifest+json' };

// path-to-regexp mínimo para las reglas de este vercel.json
const reglas = vercel.headers.map(r => ({ re: new RegExp('^' + r.source.replace(/\.(?=[a-z])/g, '\\.') + '$'), headers: r.headers }));

http.createServer((req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (p === '/') p = '/index.html';
  const f = path.join(RAIZ, p);
  for (const r of reglas) if (r.re.test(p)) for (const h of r.headers) res.setHeader(h.key, h.value);
  fs.readFile(f, (e, data) => {
    if (e) { res.statusCode = 404; return res.end('404'); }
    res.setHeader('Content-Type', TIPOS[path.extname(f)] || 'application/octet-stream');
    res.end(data);
  });
}).listen(PUERTO);

const CHROME = [process.env.CHROME, 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].find(p => p && fs.existsSync(p));
if (!CHROME) { console.error('No encontre Chrome ni Edge. Pasa la ruta en CHROME=...'); process.exit(2); }
const PERFIL = fs.mkdtempSync(path.join(os.tmpdir(), 'portgo-csp-'));
const chrome = spawn(CHROME, [
  '--headless=new', `--remote-debugging-port=${CDP}`, '--no-first-run', '--no-default-browser-check',
  `--user-data-dir=${PERFIL}`, 'about:blank'], { stdio: 'ignore' });

const espera = ms => new Promise(r => setTimeout(r, ms));
let ws;
for (let i = 0; i < 40 && !ws; i++) {
  try {
    const t = await (await fetch(`http://127.0.0.1:${CDP}/json/list`)).json();
    const pag = t.find(x => x.type === 'page');
    if (pag) ws = new WebSocket(pag.webSocketDebuggerUrl);
  } catch { await espera(250); }
}
await new Promise(r => ws.onopen = r);
let id = 0; const pend = new Map(); const violaciones = []; const consola = []; let fallos = 0;
ws.onmessage = ev => {
  const m = JSON.parse(ev.data);
  if (m.id && pend.has(m.id)) { pend.get(m.id)(m.result ?? m); pend.delete(m.id); }
  if (m.method === 'Runtime.consoleAPICalled') {
    const txt = m.params.args.map(a => a.value ?? a.description ?? '').join(' ');
    if (txt.startsWith('CSPV ')) violaciones.push(txt); else if (m.params.type === 'error') consola.push(txt);
  }
  if (m.method === 'Runtime.exceptionThrown') consola.push('EXC ' + (m.params.exceptionDetails.exception?.description || m.params.exceptionDetails.text).split('\n')[0]);
  if (m.method === 'Log.entryAdded' && /Content Security Policy/i.test(m.params.entry.text)) violaciones.push('LOG ' + m.params.entry.text.slice(0, 220));
};
const cmd = (method, params = {}) => new Promise(r => { const i = ++id; pend.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
await cmd('Runtime.enable'); await cmd('Log.enable'); await cmd('Page.enable');
await cmd('Page.addScriptToEvaluateOnNewDocument', { source:
  "document.addEventListener('securitypolicyviolation', e => console.log('CSPV ' + e.violatedDirective + ' <- ' + e.blockedURI + ' @' + (e.sourceFile||'').split('/').pop() + ':' + e.lineNumber))" });

const evalua = async expr => (await cmd('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true, userGesture: true })).result?.value;

for (const pag of ['index.html', 'privacidad.html', 'terminos.html', 'app.html']) {
  violaciones.length = 0; consola.length = 0;
  await cmd('Page.navigate', { url: `http://localhost:${PUERTO}/${pag}` });
  await espera(6000);
  console.log(`\n== ${pag}`);
  if (pag === 'index.html') console.log('  lucide cargado:', await evalua("typeof lucide"));
  if (pag === 'app.html') {
    console.log('  supabase SDK:', await evalua("typeof supabase"), '| Leaflet:', await evalua("typeof L"), '| sb:', await evalua("typeof sb"));
    console.log('  SW:', await evalua("navigator.serviceWorker.getRegistration().then(r => r ? 'registrado' : 'no')"));
    // Lo que la app hace con sesión, pedido desde la propia página:
    const host = await evalua("new URL(sb.supabaseUrl).host");
    const pruebas = {
      'REST supabase':  `fetch('https://${host}/rest/v1/catalogos?select=clave&limit=1',{headers:{apikey:sb.supabaseKey}}).then(r=>'llega '+r.status).catch(e=>'BLOQ '+e.message)`,
      'Realtime wss':   `new Promise(ok=>{try{const w=new WebSocket('wss://${host}/realtime/v1/websocket?apikey='+sb.supabaseKey+'&vsn=1.0.0');w.onopen=()=>{w.close();ok('abre')};w.onerror=()=>ok('error de red (ver violaciones)')}catch(e){ok('BLOQ '+e.message)}})`,
      'Edge Function':  `fetch('https://${host}/functions/v1/enviar-notificacion',{method:'OPTIONS'}).then(r=>'llega '+r.status).catch(e=>'error '+e.message)`,
      'img Storage':    `new Promise(ok=>{const i=new Image();i.onload=()=>ok('carga');i.onerror=()=>ok('error (404 esperado si no esta bloqueada)');i.src='https://${host}/storage/v1/object/sign/x/y.png?token=z'})`,
      'tesela OSM':     `new Promise(ok=>{const i=new Image();i.onload=()=>ok('carga');i.onerror=()=>ok('error');i.src='https://a.tile.openstreetmap.org/1/0/0.png'})`,
      'Nominatim':      `fetch('https://nominatim.openstreetmap.org/search?format=json&q=veracruz&limit=1').then(r=>'llega '+r.status).catch(e=>'BLOQ '+e.message)`,
      'icono Leaflet':  `new Promise(ok=>{const i=new Image();i.onload=()=>ok('carga');i.onerror=()=>ok('error');i.src='https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png'})`,
      'Carta Porte':    `new Promise(ok=>{const w=window.open('','_blank');if(!w)return ok('popup bloqueado');w.document.write('<style>b{color:rgb(255,0,0)}</style><b id=b>x</b><button id=k onclick="window.pulsado=1">x</button><script>window.ok=1<\/script>');w.document.close();w.document.getElementById('k').click();setTimeout(()=>{ok('estilo='+(w.getComputedStyle(w.document.getElementById('b')).color==='rgb(255, 0, 0)')+' script='+(w.ok===1)+' onclick='+(w.pulsado===1));w.close()},300)})`,
      'CONTROL ajeno':  `fetch('https://example.com/').then(r=>'LLEGA '+r.status).catch(e=>'bloqueado: '+e.message)`,
      'CONTROL script': `new Promise(ok=>{const s=document.createElement('script');s.onload=()=>ok('CARGA');s.onerror=()=>ok('bloqueado');s.src='https://unpkg.com/lodash@4.17.21/lodash.min.js';document.head.appendChild(s)})`,
    };
    for (const [n, e] of Object.entries(pruebas)) {
      const r = String(await evalua(e));
      const mal = n.startsWith('CONTROL') ? !r.startsWith('bloqueado')
                : n === 'Carta Porte' ? r !== 'estilo=true script=true onclick=true' : r.startsWith('BLOQ');
      if (mal) fallos++;
      console.log(`  ${mal ? 'FALLO' : 'ok   '} ${n.padEnd(15)} ${r}`);
    }
    await espera(1500);
  }
  // Solo cuentan como fallo las violaciones que NO son de los dos controles.
  const legitimas = [...new Set(violaciones)].filter(v => !/example\.com|lodash/.test(v));
  fallos += legitimas.length;
  console.log('  violaciones CSP:', violaciones.length ? '\n    ' + [...new Set(violaciones)].join('\n    ') : 'ninguna');
  if (consola.length) console.log('  errores de consola:\n    ' + [...new Set(consola)].slice(0, 8).join('\n    '));
}
ws.close(); chrome.kill();
console.log(fallos
  ? `\n${fallos} FALLO(S): la CSP bloquea algo que la app usa, o no se esta aplicando.`
  : '\nCSP correcta: nada legitimo bloqueado, los dos controles bloqueados.');
process.exit(fallos ? 1 : 0);
