import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const authHeader = req.headers.get('Authorization') || ''
    if (!authHeader.startsWith('Bearer ')) {
      return new Response(JSON.stringify({ error: 'No autenticado' }), { status: 401, headers: corsHeaders })
    }
    const jwt = authHeader.replace('Bearer ', '')

    // Cliente admin para todas las operaciones privilegiadas
    const sbAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // Verificar el token del caller usando el servidor (soporta ES256)
    const { data: { user: caller }, error: authErr } = await sbAdmin.auth.getUser(jwt)
    if (authErr || !caller) {
      return new Response(JSON.stringify({ error: 'Token inválido' }), { status: 401, headers: corsHeaders })
    }

    // Verificar que el caller es superadmin
    const { data: perfil } = await sbAdmin.from('perfiles').select('rol').eq('user_id', caller.id).single()
    if (perfil?.rol !== 'superadmin') {
      return new Response(JSON.stringify({ error: 'Acceso denegado' }), { status: 403, headers: corsHeaders })
    }

    const body = await req.json()
    const { accion, nombre, email, password, rol, user_id } = body

    if (accion === 'crear') {
      if (!nombre || !email || !password || !rol) {
        return new Response(JSON.stringify({ error: 'Faltan campos requeridos' }), { status: 400, headers: corsHeaders })
      }
      const { data: newUser, error: createErr } = await sbAdmin.auth.admin.createUser({
        email, password, email_confirm: true,
        user_metadata: { nombre }
      })
      if (createErr) return new Response(JSON.stringify({ error: createErr.message }), { status: 400, headers: corsHeaders })
      await sbAdmin.from('perfiles').insert({ user_id: newUser.user.id, nombre, rol })
      return new Response(JSON.stringify({ ok: true }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (accion === 'editar') {
      if (!user_id) return new Response(JSON.stringify({ error: 'Falta user_id' }), { status: 400, headers: corsHeaders })
      const authUpdate: Record<string, string> = {}
      if (email)    authUpdate.email    = email
      if (password) authUpdate.password = password

      if (Object.keys(authUpdate).length) {
        const { error: updateErr } = await sbAdmin.auth.admin.updateUserById(user_id, authUpdate)
        if (updateErr) return new Response(JSON.stringify({ error: updateErr.message }), { status: 400, headers: corsHeaders })
      }

      const perfilUpdate: Record<string, string> = {}
      if (nombre) perfilUpdate.nombre = nombre
      if (rol)    perfilUpdate.rol    = rol

      if (Object.keys(perfilUpdate).length) {
        await sbAdmin.from('perfiles').update(perfilUpdate).eq('user_id', user_id)
      }

      return new Response(JSON.stringify({ ok: true }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (accion === 'eliminar') {
      if (!user_id) return new Response(JSON.stringify({ error: 'Falta user_id' }), { status: 400, headers: corsHeaders })
      await sbAdmin.auth.admin.deleteUser(user_id)
      return new Response(JSON.stringify({ ok: true }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (accion === 'listar') {
      const { data: perfiles } = await sbAdmin.from('perfiles').select('user_id, nombre, rol, created_at').order('created_at')
      const { data: { users } } = await sbAdmin.auth.admin.listUsers()
      const ROL_ORDER: Record<string, number> = { superadmin: 0, admin: 1, cliente: 2 }
      const lista = (perfiles || [])
        .map(p => {
          const u = users.find((x: any) => x.id === p.user_id)
          return { ...p, email: u?.email || '—' }
        })
        .sort((a: any, b: any) => (ROL_ORDER[a.rol] ?? 9) - (ROL_ORDER[b.rol] ?? 9))
      return new Response(JSON.stringify({ lista }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    return new Response(JSON.stringify({ error: 'Acción no reconocida' }), { status: 400, headers: corsHeaders })

  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders })
  }
})
