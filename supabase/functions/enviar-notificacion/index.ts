import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { SMTPClient } from 'https://deno.land/x/denomailer/mod.ts';

const GMAIL_USER = Deno.env.get('GMAIL_USER')!;
const GMAIL_PASS = Deno.env.get('GMAIL_PASS')!;
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { tipo_camion, cliente_nombre } = await req.json();

    // Obtener emails de admins/superadmins vía service role
    const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    const { data: perfiles } = await sb
      .from('perfiles')
      .select('user_id')
      .eq('rol', 'superadmin');

    if (!perfiles?.length) {
      return new Response(JSON.stringify({ ok: true, sent: 0 }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const userIds = perfiles.map((p: { user_id: string }) => p.user_id);
    const { data: { users } } = await sb.auth.admin.listUsers();

    const adminEmails = users
      .filter((u: { id: string; email?: string }) => userIds.includes(u.id) && u.email)
      .map((u: { email: string }) => u.email);

    if (!adminEmails.length) {
      return new Response(JSON.stringify({ ok: true, sent: 0 }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const html = `
      <div style="font-family:sans-serif;max-width:480px;margin:auto">
        <h2 style="color:#1a73e8">Nueva solicitud en PortGo</h2>
        <p><strong>${cliente_nombre || 'Un cliente'}</strong> publicó una solicitud de servicio.</p>
        <ul>
          <li><strong>Tipo:</strong> ${tipo_camion || 'No especificado'}</li>
        </ul>
        <p>Ingresa al módulo de <strong>Aprobaciones</strong> para revisarla.</p>
      </div>
    `;

    const client = new SMTPClient({
      connection: {
        hostname: 'smtp.gmail.com',
        port: 465,
        tls: true,
        auth: { username: GMAIL_USER, password: GMAIL_PASS },
      },
    });

    for (const to of adminEmails) {
      await client.send({
        from: `PortGo <${GMAIL_USER}>`,
        to,
        subject: 'Nueva solicitud pendiente de revisión — PortGo',
        html,
      });
    }

    await client.close();

    return new Response(JSON.stringify({ ok: true, sent: adminEmails.length }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    console.error(err);
    return new Response(JSON.stringify({ ok: false, error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
