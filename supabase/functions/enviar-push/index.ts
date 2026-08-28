// ============================================================================
// enviar-push — entrega por FCM las notificaciones que lo merecen
// ============================================================================
//
// Quién la llama: el trigger trg_enviar_push de la base, vía pg_net, cada vez
// que se insertan filas en `notificaciones`. NO la llama ningún cliente.
//
// Por qué desde la base y no desde el navegador: el correo (enviar-notificacion)
// se dispara con fire-and-forget desde el cliente, así que si quien aprueba
// cierra la pestaña a mitad, el aviso no sale. Y la regla de a quién notificar
// vive en el cliente, con lo que los tres clientes pueden divergir. Aquí la
// fila de `notificaciones` ya es esa decisión, tomada en un solo sitio.
//
// FCM HTTP v1, no la API legacy: la de servidor con clave estática está
// retirada desde 2024. v1 exige un token OAuth firmado con la cuenta de
// servicio, que es lo que hace obtenerTokenOAuth().
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3';

const SUPABASE_URL      = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
// La credencial con la que la base se identifica al llamarnos. Es el mismo
// valor que el secreto `push_service_key` del vault.
const PUSH_SERVICE_KEY  = Deno.env.get('PUSH_SERVICE_KEY')!;
// El JSON completo de la cuenta de servicio de Firebase, en una sola línea.
const FIREBASE_SA       = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')!;

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

// ── OAuth para FCM v1 ───────────────────────────────────────────────────────
// Se firma un JWT con la clave privada de la cuenta de servicio y se cambia por
// un token de acceso. Dura una hora, así que se cachea: sin esto habría una
// ida y vuelta extra a Google en cada notificación.
let cacheToken: { valor: string; expira: number } | null = null;

async function obtenerTokenOAuth(): Promise<string> {
  if (cacheToken && Date.now() < cacheToken.expira - 60_000) return cacheToken.valor;

  const sa = JSON.parse(FIREBASE_SA);
  const ahora = Math.floor(Date.now() / 1000);
  const claims = {
    iss:   sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud:   'https://oauth2.googleapis.com/token',
    iat:   ahora,
    exp:   ahora + 3600,
  };

  const b64url = (s: string) =>
    btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const cabecera = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const cuerpo   = b64url(JSON.stringify(claims));
  const porFirmar = `${cabecera}.${cuerpo}`;

  // La clave privada viene en PEM; WebCrypto la quiere en DER dentro de un
  // ArrayBuffer, así que hay que quitar cabeceras y deshacer el base64.
  const pem = sa.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));

  const clave = await crypto.subtle.importKey(
    'pkcs8', der,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false, ['sign'],
  );
  const firma = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5', clave, new TextEncoder().encode(porFirmar),
  );
  const jwt = `${porFirmar}.${b64url(String.fromCharCode(...new Uint8Array(firma)))}`;

  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion:  jwt,
    }),
  });
  if (!r.ok) throw new Error(`OAuth de FCM falló: ${r.status} ${await r.text()}`);

  const { access_token, expires_in } = await r.json();
  cacheToken = { valor: access_token, expira: Date.now() + expires_in * 1000 };
  return access_token;
}

// ── Entrada ─────────────────────────────────────────────────────────────────
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors });

  // Solo la base puede llamar aquí. No hay sesión de usuario que verificar:
  // la credencial es la misma que el trigger lee del vault.
  const auth = req.headers.get('Authorization') || '';
  if (auth !== `Bearer ${PUSH_SERVICE_KEY}`) {
    return json({ error: 'No autorizado' }, 401);
  }

  let notificaciones: Array<{
    user_id: string; tipo: string; titulo: string;
    mensaje: string | null; meta: Record<string, unknown> | null;
  }>;
  try {
    ({ notificaciones } = await req.json());
  } catch {
    return json({ error: 'Cuerpo inválido' }, 400);
  }
  if (!Array.isArray(notificaciones) || notificaciones.length === 0) {
    return json({ ok: true, enviados: 0 });
  }

  const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
  const sa = JSON.parse(FIREBASE_SA);

  // Un solo viaje a la base para todos los destinatarios del lote.
  const destinatarios = [...new Set(notificaciones.map((n) => n.user_id))];
  const { data: dispositivos, error } = await sb
    .from('dispositivos_push')
    .select('user_id, token')
    .in('user_id', destinatarios);

  if (error)        return json({ error: error.message }, 500);
  if (!dispositivos?.length) return json({ ok: true, enviados: 0, motivo: 'sin dispositivos' });

  const porUsuario = new Map<string, string[]>();
  for (const d of dispositivos) {
    if (!porUsuario.has(d.user_id)) porUsuario.set(d.user_id, []);
    porUsuario.get(d.user_id)!.push(d.token);
  }

  const oauth = await obtenerTokenOAuth();
  const urlFcm = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

  let enviados = 0;
  const muertos: string[] = [];

  // FCM v1 no acepta envíos múltiples en una llamada, así que va uno por token.
  // Se lanzan en paralelo: el lote máximo medido en producción es de 8.
  await Promise.all(
    notificaciones.flatMap((n) =>
      (porUsuario.get(n.user_id) || []).map(async (token) => {
        const r = await fetch(urlFcm, {
          method: 'POST',
          headers: { Authorization: `Bearer ${oauth}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({
            message: {
              token,
              notification: { title: n.titulo, body: n.mensaje ?? '' },
              // `data` viaja aparte para que la app sepa a dónde navegar al
              // tocar el aviso. Todos los valores han de ser texto: FCM
              // rechaza el mensaje si alguno es número u objeto.
              data: {
                tipo: n.tipo,
                ...Object.fromEntries(
                  Object.entries(n.meta ?? {}).map(([k, v]) => [k, String(v)]),
                ),
              },
              android: { priority: 'high', notification: { channel_id: 'portgo_avisos' } },
            },
          }),
        });

        if (r.ok) { enviados++; return; }

        // Token de un dispositivo que ya no existe: se anota para borrarlo.
        // Es la vía principal de limpieza; el cron mensual es solo la red.
        const detalle = await r.text();
        if (r.status === 404 || detalle.includes('UNREGISTERED') || detalle.includes('INVALID_ARGUMENT')) {
          muertos.push(token);
        } else {
          console.error(`FCM ${r.status} para ${n.tipo}: ${detalle.slice(0, 200)}`);
        }
      }),
    ),
  );

  if (muertos.length) {
    await sb.from('dispositivos_push').delete().in('token', muertos);
  }

  return json({ ok: true, enviados, tokens_retirados: muertos.length });
});
