// Versiones fijas a proposito. Sin fijarlas, el import resuelve a "la ultima"
// por redireccion, asi que dos despliegues del MISMO commit pueden compilar
// modulos distintos — y una funcion que se rompe sin que nadie toque nada, sin
// commit al que culpar, es de las cosas mas caras de diagnosticar. Estas son
// las versiones que corrian el 2026-08-21, verificadas en produccion.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.112.3';
import { SMTPClient } from 'https://deno.land/x/denomailer@1.6.0/mod.ts';

const GMAIL_USER = Deno.env.get('GMAIL_USER')!;
const GMAIL_PASS = Deno.env.get('GMAIL_PASS')!;
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

// ── La UNICA diferencia permitida entre produccion y pruebas ──────────────
//
// portgo-pruebas es una copia fiel de produccion: mismos usuarios, mismos
// correos REALES de clientes y empresas. Con esos datos dentro, cualquier
// prueba que dispare una notificacion le escribiria a gente de verdad.
//
// El bloqueo vive aqui, en el codigo, y no en "esperemos que falten los
// secretos": si faltara GMAIL_PASS la funcion reventaria al conectar y la
// prueba veria un error donde deberia ver un envio correcto — una diferencia
// de comportamiento, no solo de salida. Asi el codigo es identico en los dos
// proyectos y lo unico que cambia es un secreto.
//
// Ausente o 'activa' = comportamiento de produccion. En pruebas:
//   npx supabase secrets set CORREO_SALIDA=bloqueada --project-ref <ref-pruebas>
const CORREO_BLOQUEADO = (Deno.env.get('CORREO_SALIDA') ?? 'activa').toLowerCase() === 'bloqueada';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

// Escapa HTML: todo el contenido de los templates viene de datos que el usuario controla
// (nombre, descripción, nota de rechazo…), y se inyecta directo en el cuerpo del correo.
function esc(v: unknown): string {
  return String(v ?? '').replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[c] as string));
}

// dd/mm/aaaa — mismo formato que fmtFecha() en js/utils.js
function fmtF(v: unknown): string {
  const p = String(v ?? '').slice(0, 10).split('-');
  return p.length === 3 ? `${p[2]}/${p[1]}/${p[0]}` : esc(v);
}

// ── Quién puede ofertar por un tipo de servicio ─────────
// Réplica de _categoriaTipo() y del gate esCamionPed de js/pedidos.js. Tiene
// que dar el mismo resultado que el cliente: si aquí avisamos a una empresa
// que la app luego no deja ofertar, el correo es basura; y si callamos a una
// que sí podía, le quitamos la oportunidad.
function categoriaTipo(tipo: unknown): string | null {
  const t = String(tipo ?? '');
  if (!t || t === 'Cualquiera') return null;
  if (t.startsWith('Full')) return 'full';
  if (t.startsWith('Torton')) return 'torton';
  if (t.startsWith('Sencillo')) return 'sencillo';
  if (t.startsWith('Camioneta 1.5')) return 'cam15';
  if (t.startsWith('Camioneta 3.5')) return 'cam35';
  if (t === 'Rabón') return 'rabon';
  if (t.startsWith('Plataforma')) return 'plataforma';
  if (t === 'Lowboy' || t === 'Cama baja') return 'lowboy';
  if (t === 'HAZMAT') return 'hazmat';
  return t;
}

function esServicioCamion(tipo: unknown): boolean {
  const t = String(tipo ?? '');
  if (!t) return false;
  return !t.startsWith('Custodio') && t !== 'Supervisión remota' &&
         !t.startsWith('Patio') && t !== 'Bodega' &&
         !t.startsWith('Lavado') && t !== 'Desinfección';
}

// ── HTML email templates ───────────────────────────────
const BRAND = `<div style="font-family:Inter,sans-serif;max-width:520px;margin:auto;color:#1e293b">
  <div style="background:#1a4fd6;padding:18px 24px;border-radius:12px 12px 0 0">
    <span style="color:#fff;font-size:1.2rem;font-weight:700">⚓ PortGo</span>
  </div>
  <div style="background:#f8fafc;padding:28px 24px;border-radius:0 0 12px 12px">`;
const END_BRAND = `  </div>
</div>`;

function tpl(subject: string, body: string) {
  return { subject, html: `${BRAND}${body}${END_BRAND}` };
}

// Tabla de detalles de una solicitud, compartida por los correos de revisión
// (al superadmin) y de publicación (a las empresas). Una empresa decide si
// vale la pena ofertar por la ruta y las fechas, no por el tipo de unidad.
function filasSolicitud(p: Record<string, unknown>): string {
  const fila = (k: string, v: string) =>
    `<tr><td style="padding:6px 0;color:#64748b;width:140px">${k}</td><td>${v}</td></tr>`;
  const ruta = p.origen
    ? `${esc(p.origen)}${p.destino ? ` <strong>→</strong> ${esc(p.destino)}` : ''}`
    : null;
  const fechas = p.fecha_ini
    ? `${fmtF(p.fecha_ini)}${p.fecha_fin ? ` – ${fmtF(p.fecha_fin)}` : ''}`
    : null;
  return `<table style="width:100%;border-collapse:collapse;margin:16px 0">
    ${fila('Servicio:', `<strong>${esc(p.tipo_camion) || '—'}</strong>`)}
    ${ruta ? fila('Ruta:', `<strong>${ruta}</strong>`) : ''}
    ${p.fecha_arribo_puerto ? fila('Arribo a puerto:', fmtF(p.fecha_arribo_puerto)) : ''}
    ${fechas ? fila('Carga / entrega:', fechas) : ''}
    ${p.tipo_carga ? fila('Carga:', esc(p.tipo_carga)) : ''}
    ${p.precio_cliente ? fila('Presupuesto:', `<strong>$${Number(p.precio_cliente).toLocaleString('es-MX')} MXN</strong>`) : ''}
    ${p.plazo_pago ? fila('Plazo de pago:', esc(p.plazo_pago)) : ''}
  </table>`;
}

// El asunto va en texto plano — no lleva esc(), o un cliente llamado
// "Ruiz & Co" aparece como "Ruiz &amp; Co" en la bandeja.
//
// Y tiene que ser CORTO: denomailer codifica el Subject como un único
// encoded-word RFC 2047, además con los espacios sin escapar. Mientras cabe
// en una línea los clientes lo toleran (los asuntos de siempre, ~40
// caracteres, llegan bien), pero en cuanto pasa de ~75 la cabecera se pliega
// a media palabra codificada, queda inválida, y el cliente ya no puede
// parsear el mensaje: lo muestra en crudo, con headers y fronteras MIME.
//
// Por eso la RUTA NO va en el asunto. Dos razones:
//   1. origen/destino traen la dirección completa del autocompletado, que por
//      sí sola revienta el límite.
//   2. No hay campo de ciudad en la base, y sacarla del texto libre no tiene
//      regla fiable: en "Manzanillo, Colima, 28200" la ciudad es el primer
//      segmento, y en "Circuito del Nogal, Privadas del Bosque, Hermosillo"
//      es el último. Cualquier heurística acierta en una y falla en la otra.
//
// La ruta completa y correcta va en el CUERPO, que no tiene límite de
// longitud ni codificación de cabecera.
const TIPO_MAX = 30;

function asuntoSolicitud(p: Record<string, unknown>): string {
  const t = String(p.tipo_camion ?? '').trim() || 'servicio';
  return t.length <= TIPO_MAX ? t : t.slice(0, TIPO_MAX - 3).trimEnd() + '...';
}

const TEMPLATES: Record<string, (p: Record<string, unknown>) => { subject: string; html: string }> = {
  // A las empresas, cuando el superadmin YA publicó la solicitud y por lo
  // tanto ya se puede ofertar.
  nueva_solicitud: (p) => tpl(
    `Nueva solicitud - ${asuntoSolicitud(p)} - PortGo`,
    `<h2 style="margin:0 0 12px;color:#1a4fd6">Nueva solicitud disponible para ofertar</h2>
    <p>Se publicó una solicitud que coincide con tu flota.</p>
    ${filasSolicitud(p)}
    <p>Ingresa a <strong>Solicitudes</strong> en PortGo para revisarla y hacer tu oferta.</p>
    <p style="color:#64748b;font-size:0.85rem">Las ofertas tienen vigencia limitada: entre más pronto ofertes, más posibilidades tienes.</p>`
  ),

  // Al superadmin, cuando el cliente acaba de crear la solicitud y está en
  // pendiente_revision. Las empresas todavía NO deben recibir nada: la
  // solicitud aún no es visible ni ofertable para ellas.
  revision_solicitud: (p) => tpl(
    `Solicitud por revisar - ${asuntoSolicitud(p)} - PortGo`,
    `<h2 style="margin:0 0 12px;color:#b45309">⏳ Solicitud pendiente de tu revisión</h2>
    <p><strong>${esc(p.cliente_nombre) || 'Un cliente'}</strong> creó una solicitud que requiere tu aprobación antes de publicarse.</p>
    ${filasSolicitud(p)}
    <p>Ingresa a <strong>Pendientes de aprobación → Solicitudes</strong> para publicarla o devolverla con comentarios.</p>`
  ),

  // Aprobación en lote: un solo correo con el resumen, en lugar de N blasts.
  solicitudes_lote: (p) => tpl(
    `${Number(p.total) || 0} solicitudes nuevas para ofertar - PortGo`,
    `<h2 style="margin:0 0 12px;color:#1a4fd6">Se publicaron ${Number(p.total) || 0} solicitudes</h2>
    <p>Ya están disponibles para ofertar en PortGo:</p>
    <ul style="padding-left:18px;margin:16px 0">
      ${(Array.isArray(p.rutas) ? p.rutas as string[] : []).slice(0, 15)
        .map((r) => `<li style="margin:4px 0">${esc(r)}</li>`).join('')}
    </ul>
    ${(Array.isArray(p.rutas) ? (p.rutas as string[]).length : 0) > 15
      ? `<p style="color:#64748b;font-size:0.85rem">…y ${(p.rutas as string[]).length - 15} más.</p>` : ''}
    <p>Ingresa a <strong>Solicitudes</strong> para revisarlas y ofertar.</p>`
  ),

  // Resolución del superadmin sobre algo que el usuario está esperando:
  // su cuenta, su solicitud, su camión, la finalización de un servicio.
  // Antes todas estas resoluciones llegaban SOLO a la campana, o sea que el
  // usuario se enteraba si abría la app — justo lo que no hace mientras
  // espera que le aprueben la cuenta para poder entrar.
  resolucion: (p) => tpl(
    `${String(p.titulo ?? 'Actualización').slice(0, 45)} - PortGo`,
    `<h2 style="margin:0 0 12px;color:${p.aprobado === false ? '#dc2626' : '#16a34a'}">${p.aprobado === false ? '⚠' : '✓'} ${esc(p.titulo)}</h2>
    <p>${esc(p.mensaje)}</p>
    ${p.nota ? `<div style="background:${p.aprobado === false ? '#fef2f2' : '#f0fdf4'};border-left:3px solid ${p.aprobado === false ? '#dc2626' : '#16a34a'};padding:10px 14px;border-radius:4px;margin:14px 0"><strong>${p.aprobado === false ? 'Motivo' : 'Nota'}:</strong> ${esc(p.nota)}</div>` : ''}
    <p>Ingresa a PortGo para ver los detalles.</p>`
  ),

  // El acuerdo se cierra solo desde que existe cerrar_acuerdo — el
  // superadmin ya no tiene que aprobarlo. Solo sigue necesitando actuar en
  // el caso raro de que la empresa tenga documentos vencidos (p.cerrado
  // llega false en ese caso); para el resto, este correo es puramente
  // informativo.
  acuerdo: (p) => p.cerrado === false ? tpl(
    `Acuerdo pendiente de aprobación — PortGo`,
    `<h2 style="margin:0 0 12px;color:#dc2626">⚠ Acuerdo bloqueado por documentos vencidos</h2>
    <p>El cliente <strong>${esc(p.cliente_nombre)}</strong> aceptó la oferta de <strong>${esc(p.admin_nombre)}</strong>, pero la empresa tiene documentos vencidos y el acuerdo no se pudo cerrar solo.</p>
    <table style="width:100%;border-collapse:collapse;margin:16px 0">
      <tr><td style="padding:6px 0;color:#64748b;width:140px">Servicio:</td><td><strong>${esc(p.tipo_camion) || '—'}</strong></td></tr>
      <tr><td style="padding:6px 0;color:#64748b">Precio acordado:</td><td><strong>$${Number(p.precio||0).toLocaleString('es-MX')} MXN</strong></td></tr>
    </table>
    <p>Ingresa al módulo de <strong>Aprobaciones</strong> para revisarlo y activarlo.</p>`
  ) : tpl(
    `Nuevo acuerdo cerrado — PortGo`,
    `<h2 style="margin:0 0 12px;color:#16a34a">✓ Se cerró un nuevo acuerdo</h2>
    <p>El cliente <strong>${esc(p.cliente_nombre)}</strong> y <strong>${esc(p.admin_nombre)}</strong> cerraron un acuerdo — ya quedó como reservación activa, sin necesitar aprobación.</p>
    <table style="width:100%;border-collapse:collapse;margin:16px 0">
      <tr><td style="padding:6px 0;color:#64748b;width:140px">Servicio:</td><td><strong>${esc(p.tipo_camion) || '—'}</strong></td></tr>
      <tr><td style="padding:6px 0;color:#64748b">Precio acordado:</td><td><strong>$${Number(p.precio||0).toLocaleString('es-MX')} MXN</strong></td></tr>
    </table>
    <p>Ingresa a <strong>Reservaciones</strong> si quieres verlo.</p>`
  ),

  nueva_reserva: (p) => tpl(
    `Nueva solicitud de reserva — PortGo`,
    `<h2 style="margin:0 0 12px;color:#1a4fd6">Solicitud de reserva recibida</h2>
    <p>Tienes una nueva solicitud de reserva en PortGo.</p>
    ${p.camion ? `<table style="width:100%;border-collapse:collapse;margin:16px 0">
      <tr><td style="padding:6px 0;color:#64748b;width:140px">Unidad:</td><td><strong>${esc((p.camion as Record<string,string>).id)} — ${esc((p.camion as Record<string,string>).tipo)}</strong></td></tr>
      ${p.reserva ? `
      <tr><td style="padding:6px 0;color:#64748b">Cliente:</td><td>${esc((p.reserva as Record<string,string>).cliente)}</td></tr>
      <tr><td style="padding:6px 0;color:#64748b">Período:</td><td>${esc((p.reserva as Record<string,string>).fecha_ini)} – ${esc((p.reserva as Record<string,string>).fecha_fin)}</td></tr>
      ${(p.reserva as Record<string,string>).descripcion ? `<tr><td style="padding:6px 0;color:#64748b">Detalle:</td><td>${esc((p.reserva as Record<string,string>).descripcion)}</td></tr>` : ''}` : ''}
    </table>` : ''}
    <p>Ingresa a <strong>Reservaciones</strong> para confirmar o rechazar.</p>`
  ),

  solicitud_recibida: (p) => tpl(
    `Tu solicitud fue recibida — PortGo`,
    `<h2 style="margin:0 0 12px;color:#1a4fd6">¡Solicitud recibida!</h2>
    <p>Hola <strong>${esc(p.clienteNombre)}</strong>, tu solicitud de reserva fue enviada correctamente.</p>
    ${p.camion ? `<table style="width:100%;border-collapse:collapse;margin:16px 0">
      <tr><td style="padding:6px 0;color:#64748b;width:140px">Unidad:</td><td><strong>${esc((p.camion as Record<string,string>).id)}</strong> — ${esc((p.camion as Record<string,string>).tipo)}</td></tr>
      <tr><td style="padding:6px 0;color:#64748b">Empresa:</td><td>${esc((p.camion as Record<string,string>).empresa) || '—'}</td></tr>
      <tr><td style="padding:6px 0;color:#64748b">Período:</td><td>${esc(p.fecha_ini)} – ${esc(p.fecha_fin)}</td></tr>
    </table>` : ''}
    <p>La empresa revisará tu solicitud y recibirás una notificación cuando sea confirmada o rechazada.</p>`
  ),

  reserva_aceptada: (p) => tpl(
    `¡Tu reserva fue aceptada! — PortGo`,
    `<h2 style="margin:0 0 12px;color:#16a34a">✓ Reserva confirmada</h2>
    <p>Hola <strong>${esc(p.clienteNombre)}</strong>, tu reserva fue <strong style="color:#16a34a">aceptada</strong>.</p>
    ${p.camion ? `<table style="width:100%;border-collapse:collapse;margin:16px 0">
      <tr><td style="padding:6px 0;color:#64748b;width:140px">Unidad:</td><td><strong>${esc((p.camion as Record<string,string>).id)}</strong></td></tr>
      <tr><td style="padding:6px 0;color:#64748b">Período:</td><td>${esc(p.fecha_ini)} – ${esc(p.fecha_fin)}</td></tr>
    </table>` : ''}
    <p>Ingresa a la plataforma para ver los detalles completos de tu reservación.</p>`
  ),

  reserva_rechazada: (p) => tpl(
    `Tu reserva no pudo confirmarse — PortGo`,
    `<h2 style="margin:0 0 12px;color:#dc2626">Reserva no confirmada</h2>
    <p>Hola <strong>${esc(p.clienteNombre)}</strong>, lamentablemente tu reserva no pudo ser confirmada en esta ocasión.</p>
    ${p.nota ? `<div style="background:#fef2f2;border-left:3px solid #dc2626;padding:10px 14px;border-radius:4px;margin:14px 0"><strong>Motivo:</strong> ${esc(p.nota)}</div>` : ''}
    <p>Puedes publicar una nueva solicitud en la plataforma para encontrar otro proveedor disponible.</p>`
  ),

  nueva_oferta: (p) => tpl(
    `Tienes una nueva oferta — PortGo`,
    `<h2 style="margin:0 0 12px;color:#1a4fd6">📨 Nueva oferta recibida</h2>
    <p>Hola <strong>${esc(p.clienteNombre)}</strong>, <strong>${esc(p.adminNombre)}</strong> hizo una oferta para tu solicitud.</p>
    <table style="width:100%;border-collapse:collapse;margin:16px 0">
      <tr><td style="padding:6px 0;color:#64748b;width:140px">Servicio:</td><td><strong>${esc(p.tipo_camion) || '—'}</strong></td></tr>
      <tr><td style="padding:6px 0;color:#64748b">Precio ofrecido:</td><td><strong style="color:#1a4fd6">$${Number(p.precio||0).toLocaleString('es-MX')} MXN</strong></td></tr>
    </table>
    <p>Ingresa a <strong>Mis solicitudes</strong> para revisar y responder la oferta.</p>`
  ),

  acuerdo_aprobado: (p) => tpl(
    `¡Acuerdo aprobado! — PortGo`,
    `<h2 style="margin:0 0 12px;color:#16a34a">✓ Acuerdo aprobado</h2>
    <p>El acuerdo de <strong>${esc(p.tipo_camion) || 'transporte'}</strong> fue aprobado. Ya hay una reservación activa.</p>
    <p>Ingresa a la plataforma para ver los detalles.</p>`
  ),
};

// ── Email sender ───────────────────────────────────────
// Una sola conexión SMTP por invocación. Antes se abría (y cerraba) una
// conexión a Gmail por destinatario, en serie: con 30 empresas eran 30
// conexiones dentro de la misma llamada, lo bastante lento para topar con el
// límite de tiempo de la Edge Function y con el rate limit de Gmail.
// Para varios destinatarios se usa BCC: nadie ve el correo de los demás.
async function sendEmailBulk(to: string[], subject: string, html: string) {
  if (!to.length) return;
  if (CORREO_BLOQUEADO) {
    // Se hace TODO lo demas igual que en produccion (plantilla, destinatarios,
    // fila en notificaciones) y solo se omite la conexion SMTP. En la bitacora
    // queda cuantos habrian recibido y con que asunto, que es lo que una
    // prueba necesita comprobar. Las direcciones no se registran: son datos
    // personales reales copiados de produccion.
    console.log(JSON.stringify({ correo: 'bloqueado', destinatarios: to.length, asunto: subject }));
    return;
  }
  const client = new SMTPClient({
    connection: { hostname: 'smtp.gmail.com', port: 465, tls: true,
      auth: { username: GMAIL_USER, password: GMAIL_PASS } },
  });
  try {
    const from = `PortGo <${GMAIL_USER}>`;
    if (to.length === 1) {
      await client.send({ from, to: to[0], subject, html });
    } else {
      await client.send({ from, to: from, bcc: to, subject, html });
    }
  } finally {
    await client.close();
  }
}

// listUsers() pagina de 50 en 50 por default: sin esto, en cuanto PortGo pase
// de 50 usuarios los destinatarios que caen fuera de la primera página se
// quedan sin correo y sin error visible.
async function emailsDeIds(sb: ReturnType<typeof createClient>, ids: string[]): Promise<string[]> {
  if (!ids.length) return [];

  // Pocos destinatarios (oferta, reserva, acuerdo): una consulta puntual por
  // usuario sale mucho más barato que listar el directorio completo.
  if (ids.length <= 5) {
    const res = await Promise.all(ids.map((id) => sb.auth.admin.getUserById(id)));
    return res.map((r) => r.data?.user?.email).filter(Boolean) as string[];
  }

  // Muchos destinatarios (aviso a empresas): conviene una sola pasada.
  const map: Record<string, string> = {};
  for (let page = 1; page <= 20; page++) {
    const { data, error } = await sb.auth.admin.listUsers({ page, perPage: 200 });
    const users = data?.users ?? [];
    if (error || !users.length) break;
    users.forEach((u: { id: string; email?: string }) => { if (u.email) map[u.id] = u.email; });
    if (users.length < 200) break;
  }
  return ids.map((id) => map[id]).filter(Boolean);
}

async function idsPorRol(sb: ReturnType<typeof createClient>, rol: string): Promise<string[]> {
  const { data } = await sb.from('perfiles').select('user_id').eq('rol', rol);
  return (data ?? []).map((p: { user_id: string }) => p.user_id);
}

// Correos que el usuario puede apagar desde su perfil (perfiles.notif_email).
// Son los frecuentes: oportunidades, ofertas recibidas y cola de revisión.
// Los transaccionales (reserva confirmada, aceptada, rechazada, acuerdo
// aprobado) NO están aquí a propósito: son parte del servicio contratado, no
// avisos, y apagarlos dejaría a alguien enterándose tarde de algo que ya se
// comprometió a cumplir. La campana dentro de la app tampoco se ve afectada.
const TIPOS_SILENCIABLES = new Set([
  'nueva_solicitud', 'solicitudes_lote', 'revision_solicitud', 'acuerdo', 'nueva_oferta',
]);

async function quierenCorreo(
  sb: ReturnType<typeof createClient>,
  ids: string[],
): Promise<string[]> {
  if (!ids.length) return [];
  const { data, error } = await sb.from('perfiles')
    .select('user_id').in('user_id', ids).eq('notif_email', true);

  // Falla abierto a propósito. Si la consulta truena — típicamente porque la
  // migración de notif_email todavía no se corrió — filtrar dejaría la lista
  // vacía y NADIE recibiría correo, en silencio y sin que nadie se entere.
  // Mandar un correo que alguien no quería es molesto; no mandar ninguno rompe
  // el negocio.
  if (error) {
    console.error('No se pudo leer notif_email, se envía sin filtrar:', error);
    return ids;
  }

  const sí = new Set((data ?? []).map((p: { user_id: string }) => p.user_id));
  return ids.filter((id) => sí.has(id));
}

// Empresas activas que podrían ofertar por este tipo de servicio. Con
// tipoCamion = null (aprobación en lote) van todas.
// Se excluyen las cuentas no activas: aprobacion_cuenta null = activa;
// pendiente / rechazada / suspendida no deben recibir avisos de negocio.
async function destinatariosEmpresas(
  sb: ReturnType<typeof createClient>,
  tipoCamion: unknown,
): Promise<string[]> {
  const { data } = await sb.from('perfiles')
    .select('user_id').eq('rol', 'admin').is('aprobacion_cuenta', null);
  const todos = (data ?? []).map((p: { user_id: string }) => p.user_id);
  if (!todos.length) return [];

  const cat = categoriaTipo(tipoCamion);
  // Custodios, patios, lavados y "Cualquiera" no dependen de la flota de
  // camiones: cualquier empresa puede ofertar, igual que en la app.
  if (!cat || !esServicioCamion(tipoCamion)) return todos;

  const { data: cams } = await sb.from('camiones')
    .select('propietario_id, tipo').in('aprobacion', ['aprobada', 'pendiente']);
  const conAlgo = new Set(
    (cams ?? []).map((c: { propietario_id: string }) => c.propietario_id),
  );
  const conCategoria = new Set(
    (cams ?? [])
      .filter((c: { tipo: string }) => categoriaTipo(c.tipo) === cat)
      .map((c: { propietario_id: string }) => c.propietario_id),
  );
  // Si ninguna empresa tiene esa categoría, es mejor avisar a todas que dejar
  // la solicitud sin una sola oferta. Ojo: esto se decide sobre la categoría,
  // no sobre la lista ya filtrada — si no, basta una empresa sin flota para
  // que la lista no quede vacía y el aviso general nunca se dispare.
  if (!todos.some((id) => conCategoria.has(id))) return todos;

  // Una empresa SIN unidades cargadas sí puede ofertar en la app (el gate de
  // js/pedidos.js solo aplica cuando _adminCamionTipos.size > 0), así que
  // también tiene que enterarse: es justo la empresa recién aprobada que
  // todavía no sube su flota, y dejarla en silencio es el peor momento.
  return todos.filter((id) => conCategoria.has(id) || !conAlgo.has(id));
}

// ── Main handler ───────────────────────────────────────
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors });

  try {
    const authHeader = req.headers.get('Authorization') || '';
    if (!authHeader.startsWith('Bearer ')) {
      return json({ error: 'No autenticado' }, 401);
    }
    const jwt = authHeader.replace('Bearer ', '');

    const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    // Cualquier usuario logueado puede disparar notificaciones (se envían tras acciones
    // normales de la app), pero el caller debe ser una sesión válida — cierra el hueco
    // de que cualquiera en internet, sin cuenta, use esta función como relay de correo.
    const { data: { user: caller }, error: authErr } = await sb.auth.getUser(jwt);
    if (authErr || !caller) {
      return json({ error: 'Token inválido' }, 401);
    }

    const payload = await req.json();

    // Sonda: responde en qué modo está la salida de correo y no manda nada ni
    // toca ninguna tabla. Existe para poder COMPROBAR que en pruebas el correo
    // está bloqueado sin tener que provocar un envío real para averiguarlo —
    // que, con los datos de producción copiados, le escribiría a un cliente de
    // verdad. Va después de validar la sesión: no es un endpoint abierto.
    if (payload.tipo === 'sonda_correo') {
      return json({ ok: true, sonda: true, correo: CORREO_BLOQUEADO ? 'bloqueado' : 'enviado' });
    }

    // Determine event type — support both legacy shape and new `tipo` field
    const tipo: string = payload.tipo || (payload.tipo_evento === 'acuerdo' ? 'acuerdo' : 'nueva_solicitud');
    const tplFn = TEMPLATES[tipo];
    if (!tplFn) return json({ ok: true, skipped: true });

    // Los correos masivos a empresas solo los puede disparar un superadmin
    // (es él quien publica las solicitudes). Sin esto, cualquier usuario con
    // sesión podía usar la función como relay para mandarle a TODAS las
    // empresas un correo con texto que él controla, desde el dominio de PortGo.
    if (tipo === 'nueva_solicitud' || tipo === 'solicitudes_lote') {
      const { data: perfilCaller } = await sb.from('perfiles')
        .select('rol').eq('user_id', caller.id).maybeSingle();
      if (perfilCaller?.rol !== 'superadmin') {
        return json({ error: 'No autorizado' }, 403);
      }
    }

    const { subject, html } = tplFn(payload);

    // ── A quién le toca este correo ───────────────────────
    // Se resuelven primero los user_id y hasta el final se traducen a correos,
    // para no traer el directorio de usuarios cuando el destinatario es uno.
    let ids: string[] = [];
    let directos: string[] = [];

    if (tipo === 'nueva_solicitud' || tipo === 'solicitudes_lote') {
      ids = await destinatariosEmpresas(
        sb, tipo === 'nueva_solicitud' ? payload.tipo_camion : null);

    } else if (tipo === 'revision_solicitud' || tipo === 'acuerdo') {
      // Solo superadmins: son los que tienen que actuar.
      ids = await idsPorRol(sb, 'superadmin');

    } else if (tipo === 'resolucion') {
      ids = (Array.isArray(payload.destinoIds) ? payload.destinoIds : [])
        .filter(Boolean) as string[];

    } else if (tipo === 'nueva_reserva' && payload.propietario_id) {
      ids = [payload.propietario_id as string];

    } else if (payload.clienteEmail) {
      directos = [payload.clienteEmail as string];

    } else if (tipo === 'nueva_oferta' && payload.clienteId) {
      ids = [payload.clienteId as string];

    } else if (tipo === 'acuerdo_aprobado') {
      ids = [payload.clienteId, payload.adminId].filter(Boolean) as string[];
    }

    // Respetar la preferencia del usuario, solo en los tipos silenciables.
    if (TIPOS_SILENCIABLES.has(tipo)) ids = await quierenCorreo(sb, ids);

    let emails = [...directos, ...(await emailsDeIds(sb, ids))];
    emails = [...new Set(emails.filter(Boolean))];
    if (!emails.length) return json({ ok: true, sent: 0 });

    await sendEmailBulk(emails, subject, html);
    // Solo el conteo: devolver la lista de correos permitía a cualquier
    // usuario con sesión enumerar las direcciones de todas las empresas.
    // `correo` es lo que deja comprobar desde fuera que pruebas no manda nada
    // (node pruebas/05-sonda-correo.mjs); en producción siempre dice 'enviado'.
    return json({
      ok: true,
      sent: CORREO_BLOQUEADO ? 0 : emails.length,
      correo: CORREO_BLOQUEADO ? 'bloqueado' : 'enviado',
      destinatarios: emails.length,
    });
  } catch (err) {
    console.error(err);
    return json({ ok: false, error: String(err) }, 500);
  }
});
