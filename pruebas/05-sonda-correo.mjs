// ══════════════════════════════════════════════════════════════════════════
//  SONDA DE CORREO — comprueba la única diferencia permitida
//
//  Pruebas debe ser una copia exacta de producción salvo en una cosa: de
//  pruebas no puede salir ni un correo. Eso importa más ahora que antes: la
//  base de pruebas lleva copiadas las direcciones REALES de los clientes y
//  las empresas, así que un envío accidental le llega a gente de verdad.
//
//  La sonda no provoca un envío para averiguarlo (sería exactamente el
//  accidente que se quiere evitar): le pregunta a la Edge Function en qué
//  modo está y comprueba que responda "bloqueado".
//
//  Si falla:
//    npx supabase secrets set CORREO_SALIDA=bloqueada --project-ref <ref-pruebas>
//    npx supabase functions deploy enviar-notificacion --project-ref <ref-pruebas>
//
//  Correr:  node pruebas/05-sonda-correo.mjs
// ══════════════════════════════════════════════════════════════════════════
import { Sesion, leerAmbientePruebas, leerCredenciales, exigirCuentas, CONFIG } from './lib/api.mjs';

let AMB, cred;
try {
  AMB = leerAmbientePruebas();
  cred = exigirCuentas(leerCredenciales(), ['superadmin']);
} catch (e) { console.error(`\n${e.message}\n`); process.exit(1); }

const FN = `${AMB.url}/functions/v1/enviar-notificacion`;
console.log(`\nSonda de correo contra: ${AMB.url}\n`);

const s = new Sesion('superadmin', AMB);
const entrada = await s.login(cred.superadmin.email, cred.superadmin.password);
if (!entrada.ok) {
  console.error(`❌ No se pudo entrar como ${cred.superadmin.email} en pruebas.`);
  console.error(`   ${entrada.error}`);
  console.error('\n   Si la cuenta no existe, la réplica de auth.users no se aplicó:');
  console.error('   bash supabase/replicar-produccion-a-pruebas.sh\n');
  process.exit(1);
}

const r = await s.edge(FN, { tipo: 'sonda_correo' });

if (!r.ok) {
  console.error(`❌ La Edge Function no respondió (HTTP ${r.status}): ${r.error}`);
  console.error('\n   Si dice 404, enviar-notificacion no está desplegada en pruebas.');
  console.error('   Mientras no lo esté, el ambiente NO es una copia de producción:');
  console.error('   npx supabase functions deploy enviar-notificacion --project-ref <ref-pruebas>\n');
  process.exit(1);
}

if (r.data?.sonda !== true) {
  console.error('❌ La función respondió, pero no conoce la sonda.');
  console.error('   Está desplegada una versión vieja del código. Vuelve a desplegar:');
  console.error('   npx supabase functions deploy enviar-notificacion --project-ref <ref-pruebas>\n');
  process.exit(1);
}

let fallos = 0;

if (r.data.correo === 'bloqueado') {
  console.log('✅ La salida de correo de enviar-notificacion está BLOQUEADA en pruebas.');
} else {
  console.error('❌ PELIGRO: la salida de correo está ACTIVA en pruebas.');
  console.error('   Con los datos de producción copiados, cualquier prueba que dispare');
  console.error('   una notificación le va a escribir a un cliente real.');
  console.error('   npx supabase secrets set CORREO_SALIDA=bloqueada --project-ref <ref-pruebas>');
  fallos++;
}

// ── Los correos que NO pasan por la Edge Function ─────────────────────────
// Supabase Auth manda los suyos por su cuenta (confirmación, recuperación,
// cambio de correo) y el secreto CORREO_SALIDA no los toca. Esa configuración
// no se ve desde SQL, así que verificar-paridad.sh no la mide: se comprueba
// aquí, contra el mismo endpoint público que usa la app para arrancar.
console.log('\nConfiguración de Auth (la que decide los correos de Supabase):');

async function ajustes(amb) {
  const res = await fetch(`${amb.url}/auth/v1/settings`, { headers: { apikey: amb.anon } });
  if (!res.ok) throw new Error(`HTTP ${res.status} leyendo los ajustes de ${amb.nombre}`);
  return res.json();
}

try {
  const [aProd, aPrue] = await Promise.all([ajustes(CONFIG), ajustes(AMB)]);

  // mailer_autoconfirm = true significa "no pedir confirmación por correo", o
  // sea: no se manda ese correo. Producción lo tiene así; si pruebas no, manda
  // un correo real a cada alta Y además se comporta distinto, porque allí el
  // usuario nuevo no podría entrar hasta confirmar.
  const campos = ['mailer_autoconfirm', 'disable_signup'];
  for (const c of campos) {
    const igual = aProd[c] === aPrue[c];
    console.log(`  ${igual ? '✅' : '❌'} ${c}: producción=${aProd[c]}  pruebas=${aPrue[c]}`);
    if (!igual) fallos++;
  }

  if (aPrue.mailer_autoconfirm === false) {
    console.error('\n  En pruebas la confirmación por correo está ENCENDIDA: cada alta de');
    console.error('  usuario dispara un correo de Supabase a una dirección real, y ese');
    console.error('  correo no pasa por enviar-notificacion, así que el bloqueo no lo tapa.');
    console.error('  Panel de pruebas → Authentication → Sign In / Providers → Email');
    console.error('  → apaga "Confirm email".');
  }
} catch (e) {
  console.error(`  ⚠ No se pudieron comparar los ajustes de Auth: ${e.message}`);
  fallos++;
}

if (fallos === 0) {
  console.log('\n✅ De pruebas no sale ningún correo, y Auth se comporta igual que en producción.\n');
  process.exit(0);
}
console.error(`\n❌ ${fallos} cosa(s) por corregir antes de sembrar o probar.\n`);
process.exit(1);
