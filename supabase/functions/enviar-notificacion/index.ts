import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { SMTPClient } from 'https://deno.land/x/denomailer/mod.ts';

const GMAIL_USER = Deno.env.get('GMAIL_USER')!;
const GMAIL_PASS = Deno.env.get('GMAIL_PASS')!;
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

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

const TEMPLATES: Record<string, (p: Record<string, unknown>) => { subject: string; html: string }> = {
  nueva_solicitud: (p) => tpl(
    `Nueva solicitud de ${p.cliente_nombre} — PortGo`,
    `<h2 style="margin:0 0 12px;color:#1a4fd6">Nueva solicitud de servicio</h2>
    <p><strong>${p.cliente_nombre || 'Un cliente'}</strong> publicó una solicitud en PortGo.</p>
    <table style="width:100%;border-collapse:collapse;margin:16px 0">
      <tr><td style="padding:6px 0;color:#64748b;width:140px">Servicio:</td><td><strong>${p.tipo_camion || '—'}</strong></td></tr>
    </table>
    <p>Ingresa a la plataforma para revisar y hacer tu oferta.</p>`
  ),

  acuerdo: (p) => tpl(
    `Acuerdo pendiente de aprobación — PortGo`,
    `<h2 style="margin:0 0 12px;color:#1a4fd6">Acuerdo listo para aprobar</h2>
    <p>El cliente <strong>${p.cliente_nombre}</strong> aceptó la oferta de <strong>${p.admin_nombre}</strong>.</p>
    <table style="width:100%;border-collapse:collapse;margin:16px 0">
      <tr><td style="padding:6px 0;color:#64748b;width:140px">Servicio:</td><td><strong>${p.tipo_camion || '—'}</strong></td></tr>
      <tr><td style="padding:6px 0;color:#64748b">Precio acordado:</td><td><strong>$${Number(p.precio||0).toLocaleString('es-MX')} MXN</strong></td></tr>
    </table>
    <p>Ingresa al módulo de <strong>Aprobaciones</strong> para revisar y activar el acuerdo.</p>`
  ),

  nueva_reserva: (p) => tpl(
    `Nueva solicitud de reserva — PortGo`,
    `<h2 style="margin:0 0 12px;color:#1a4fd6">Solicitud de reserva recibida</h2>
    <p>Tienes una nueva solicitud de reserva en PortGo.</p>
    ${p.camion ? `<table style="width:100%;border-collapse:collapse;margin:16px 0">
      <tr><td style="padding:6px 0;color:#64748b;width:140px">Unidad:</td><td><strong>${(p.camion as Record<string,string>).id} — ${(p.camion as Record<string,string>).tipo}</strong></td></tr>
      ${p.reserva ? `
      <tr><td style="padding:6px 0;color:#64748b">Cliente:</td><td>${(p.reserva as Record<string,string>).cliente}</td></tr>
      <tr><td style="padding:6px 0;color:#64748b">Período:</td><td>${(p.reserva as Record<string,string>).fecha_ini} – ${(p.reserva as Record<string,string>).fecha_fin}</td></tr>
      ${(p.reserva as Record<string,string>).descripcion ? `<tr><td style="padding:6px 0;color:#64748b">Detalle:</td><td>${(p.reserva as Record<string,string>).descripcion}</td></tr>` : ''}` : ''}
    </table>` : ''}
    <p>Ingresa a <strong>Reservaciones</strong> para confirmar o rechazar.</p>`
  ),

  solicitud_recibida: (p) => tpl(
    `Tu solicitud fue recibida — PortGo`,
    `<h2 style="margin:0 0 12px;color:#1a4fd6">¡Solicitud recibida!</h2>
    <p>Hola <strong>${p.clienteNombre}</strong>, tu solicitud de reserva fue enviada correctamente.</p>
    ${p.camion ? `<table style="width:100%;border-collapse:collapse;margin:16px 0">
      <tr><td style="padding:6px 0;color:#64748b;width:140px">Unidad:</td><td><strong>${(p.camion as Record<string,string>).id}</strong> — ${(p.camion as Record<string,string>).tipo}</td></tr>
      <tr><td style="padding:6px 0;color:#64748b">Empresa:</td><td>${(p.camion as Record<string,string>).empresa || '—'}</td></tr>
      <tr><td style="padding:6px 0;color:#64748b">Período:</td><td>${p.fecha_ini} – ${p.fecha_fin}</td></tr>
    </table>` : ''}
    <p>La empresa revisará tu solicitud y recibirás una notificación cuando sea confirmada o rechazada.</p>`
  ),

  reserva_aceptada: (p) => tpl(
    `¡Tu reserva fue aceptada! — PortGo`,
    `<h2 style="margin:0 0 12px;color:#16a34a">✓ Reserva confirmada</h2>
    <p>Hola <strong>${p.clienteNombre}</strong>, tu reserva fue <strong style="color:#16a34a">aceptada</strong>.</p>
    ${p.camion ? `<table style="width:100%;border-collapse:collapse;margin:16px 0">
      <tr><td style="padding:6px 0;color:#64748b;width:140px">Unidad:</td><td><strong>${(p.camion as Record<string,string>).id}</strong></td></tr>
      <tr><td style="padding:6px 0;color:#64748b">Período:</td><td>${p.fecha_ini} – ${p.fecha_fin}</td></tr>
    </table>` : ''}
    <p>Ingresa a la plataforma para ver los detalles completos de tu reservación.</p>`
  ),

  reserva_rechazada: (p) => tpl(
    `Tu reserva no pudo confirmarse — PortGo`,
    `<h2 style="margin:0 0 12px;color:#dc2626">Reserva no confirmada</h2>
    <p>Hola <strong>${p.clienteNombre}</strong>, lamentablemente tu reserva no pudo ser confirmada en esta ocasión.</p>
    ${p.nota ? `<div style="background:#fef2f2;border-left:3px solid #dc2626;padding:10px 14px;border-radius:4px;margin:14px 0"><strong>Motivo:</strong> ${p.nota}</div>` : ''}
    <p>Puedes publicar una nueva solicitud en la plataforma para encontrar otro proveedor disponible.</p>`
  ),

  nueva_oferta: (p) => tpl(
    `Tienes una nueva oferta — PortGo`,
    `<h2 style="margin:0 0 12px;color:#1a4fd6">📨 Nueva oferta recibida</h2>
    <p>Hola <strong>${p.clienteNombre}</strong>, <strong>${p.adminNombre}</strong> hizo una oferta para tu solicitud.</p>
    <table style="width:100%;border-collapse:collapse;margin:16px 0">
      <tr><td style="padding:6px 0;color:#64748b;width:140px">Servicio:</td><td><strong>${p.tipo_camion || '—'}</strong></td></tr>
      <tr><td style="padding:6px 0;color:#64748b">Precio ofrecido:</td><td><strong style="color:#1a4fd6">$${Number(p.precio||0).toLocaleString('es-MX')} MXN</strong></td></tr>
    </table>
    <p>Ingresa a <strong>Mis solicitudes</strong> para revisar y responder la oferta.</p>`
  ),

  acuerdo_aprobado: (p) => tpl(
    `¡Acuerdo aprobado! — PortGo`,
    `<h2 style="margin:0 0 12px;color:#16a34a">✓ Acuerdo aprobado</h2>
    <p>El acuerdo de <strong>${p.tipo_camion || 'transporte'}</strong> fue aprobado. Ya hay una reservación activa.</p>
    <p>Ingresa a la plataforma para ver los detalles.</p>`
  ),
};

// ── Email sender ───────────────────────────────────────
async function sendEmail(to: string, subject: string, html: string) {
  const client = new SMTPClient({
    connection: { hostname: 'smtp.gmail.com', port: 465, tls: true,
      auth: { username: GMAIL_USER, password: GMAIL_PASS } },
  });
  await client.send({ from: `PortGo <${GMAIL_USER}>`, to, subject, html });
  await client.close();
}

// ── Main handler ───────────────────────────────────────
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors });

  try {
    const payload = await req.json();
    const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const { data: { users } } = await sb.auth.admin.listUsers();
    const userById: Record<string, string> = {};
    users.forEach((u: { id: string; email?: string }) => { if (u.email) userById[u.id] = u.email; });

    // Determine event type — support both legacy shape and new `tipo` field
    const tipo: string = payload.tipo || (payload.tipo_evento === 'acuerdo' ? 'acuerdo' : 'nueva_solicitud');
    const tplFn = TEMPLATES[tipo];
    if (!tplFn) return json({ ok: true, skipped: true });

    const { subject, html } = tplFn(payload);
    const sent: string[] = [];

    if (['nueva_solicitud', 'acuerdo'].includes(tipo)) {
      // Send to all admins + superadmins
      const targetRol = tipo === 'acuerdo' ? 'superadmin' : 'admin';
      const { data: perfiles } = await sb.from('perfiles').select('user_id').eq('rol', targetRol);
      if (!perfiles?.length) return json({ ok: true, sent: 0 });
      // For 'nueva_solicitud' also include superadmins
      const ids = new Set(perfiles.map((p: { user_id: string }) => p.user_id));
      if (tipo === 'nueva_solicitud') {
        const { data: sas } = await sb.from('perfiles').select('user_id').eq('rol', 'superadmin');
        sas?.forEach((p: { user_id: string }) => ids.add(p.user_id));
      }
      for (const id of ids) {
        const email = userById[id];
        if (email) { await sendEmail(email, subject, html); sent.push(email); }
      }

    } else if (tipo === 'nueva_reserva' && payload.propietario_id) {
      // Send to the resource owner
      const email = userById[payload.propietario_id as string];
      if (email) { await sendEmail(email, subject, html); sent.push(email); }

    } else if (payload.clienteEmail) {
      // Send to the client directly
      await sendEmail(payload.clienteEmail as string, subject, html);
      sent.push(payload.clienteEmail as string);

    } else if (tipo === 'nueva_oferta' && payload.clienteId) {
      // Send to the client by user id
      const email = userById[payload.clienteId as string];
      if (email) { await sendEmail(email, subject, html); sent.push(email); }

    } else if (tipo === 'acuerdo_aprobado') {
      // Send to both cliente and admin
      for (const uid of [payload.clienteId, payload.adminId].filter(Boolean) as string[]) {
        const email = userById[uid];
        if (email) { await sendEmail(email, subject, html); sent.push(email); }
      }
    }

    return json({ ok: true, sent: sent.length, emails: sent });
  } catch (err) {
    console.error(err);
    return json({ ok: false, error: String(err) }, 500);
  }
});
