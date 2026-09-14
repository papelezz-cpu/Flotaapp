// Versiones fijas a proposito. Sin fijarlas, el import resuelve a "la ultima"
// por redireccion, asi que dos despliegues del MISMO commit pueden compilar
// modulos distintos — y una funcion que se rompe sin que nadie toque nada, sin
// commit al que culpar, es de las cosas mas caras de diagnosticar. Estas son
// las versiones que corrian el 2026-08-21, verificadas en produccion.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.112.3'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Las tres respuestas llevaban 'Content-Type' solo en el camino bueno, asi que
// los errores llegaban como texto suelto y el cliente los leia a medias.
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })

// perfiles.rol tiene CHECK, asi que un valor invalido lo rechaza la base — pero
// lo rechaza DESPUES de crear el usuario de auth, dejando una cuenta sin perfil.
// Validar aqui evita llegar a ese punto.
const ROLES = ['cliente', 'admin', 'superadmin'] as const

// Sin superadmin no se aprueban cuentas, ni recursos, ni solicitudes: la
// plataforma se para y no hay camino de vuelta desde la aplicacion. Ni borrar al
// ultimo ni degradarlo puede quedar a un clic de distancia.
async function quedanOtrosSuperadmins(
  sbAdmin: { from: (t: string) => any },
  excepto: string,
): Promise<boolean> {
  const { data, error } = await sbAdmin.from('perfiles')
    .select('user_id').eq('rol', 'superadmin').neq('user_id', excepto).limit(1)
  // Si no se puede comprobar, se asume que no quedan: ante la duda, no se toca
  // al ultimo superadmin.
  if (error) return false
  return (data?.length ?? 0) > 0
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const authHeader = req.headers.get('Authorization') || ''
    if (!authHeader.startsWith('Bearer ')) {
      return json({ error: 'No autenticado' }, 401)
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
      return json({ error: 'Token inválido' }, 401)
    }

    // Verificar que el caller es superadmin
    const { data: perfil } = await sbAdmin.from('perfiles').select('rol').eq('user_id', caller.id).single()
    if (perfil?.rol !== 'superadmin') {
      return json({ error: 'Acceso denegado' }, 403)
    }

    const body = await req.json()
    const { accion, nombre, email, password, rol, user_id } = body

    if (accion === 'crear') {
      if (!nombre || !email || !password || !rol) {
        return json({ error: 'Faltan campos requeridos' }, 400)
      }
      if (!ROLES.includes(rol)) {
        return json({ error: `Rol no valido: ${rol}. Debe ser ${ROLES.join(', ')}.` }, 400)
      }
      const { data: newUser, error: createErr } = await sbAdmin.auth.admin.createUser({
        email, password, email_confirm: true,
        user_metadata: { nombre }
      })
      if (createErr) return json({ error: createErr.message }, 400)

      // El alta son DOS escrituras y la segunda puede fallar sola. Sin
      // comprobarla, la funcion devolvia ok:true con el usuario de auth creado y
      // sin fila en perfiles — y la app decide el rol leyendo perfiles, asi que
      // esa cuenta no puede entrar aunque exista. Es la "alta a medias" contra la
      // que avisa docs/FLUJO-OPERATIVO.md, y el superadmin no se enteraba.
      //
      // No se borra el usuario de auth para deshacer: borrar es decision del
      // superadmin, no de esta funcion (regla #1 de CLAUDE.md). Se le dice que
      // quedo a medias, cual es, y que hacer.
      const { error: perfilErr } = await sbAdmin.from('perfiles')
        .insert({ user_id: newUser.user.id, nombre, rol })
      if (perfilErr) {
        return json({
          error: `La cuenta se creo pero su perfil no: ${perfilErr.message}. ` +
                 `Quedo a medias y no podra entrar. Usuario ${newUser.user.id} (${email}): ` +
                 `crea su fila en perfiles, o borralo desde Usuarios y vuelve a darlo de alta.`,
          user_id: newUser.user.id,
          parcial: true,
        }, 500)
      }
      return json({ ok: true, user_id: newUser.user.id })
    }

    if (accion === 'editar') {
      if (!user_id) return json({ error: 'Falta user_id' }, 400)
      if (rol && !ROLES.includes(rol)) {
        return json({ error: `Rol no valido: ${rol}. Debe ser ${ROLES.join(', ')}.` }, 400)
      }

      // Degradar al ultimo superadmin deja la plataforma sin quien apruebe nada.
      if (rol && rol !== 'superadmin') {
        const { data: actual } = await sbAdmin.from('perfiles')
          .select('rol').eq('user_id', user_id).maybeSingle()
        if (actual?.rol === 'superadmin' && !await quedanOtrosSuperadmins(sbAdmin, user_id)) {
          return json({
            error: 'Es el unico superadmin. Cambiarle el rol dejaria la plataforma ' +
                   'sin quien apruebe cuentas, recursos ni solicitudes. Nombra otro antes.',
          }, 409)
        }
      }

      // ── El perfil PRIMERO, las credenciales despues ──────────────────────
      //
      // Son dos sistemas distintos (postgres y auth) y no hay transaccion que
      // los abarque, asi que uno puede fallar con el otro ya escrito. El orden
      // decide que queda a medias cuando eso pasa.
      //
      // El perfil va delante porque es el que puede ser RECHAZADO: el rol lo
      // vigila un guard y lo acota un CHECK. Si falla, no se ha tocado nada
      // mas. Al reves —como estaba— un rol rechazado dejaba el correo ya
      // cambiado, que es justo lo que se vio el 2026-09-14 en pruebas:
      // "los datos de acceso se actualizaron, pero el perfil no".
      //
      // El cambio de rol NO va por el UPDATE normal: lo bloquea
      // trg_guard_perfil_self_update, que se dispara en toda actualizacion de
      // perfiles y cuya unica salida es is_superadmin() — falsa con la clave de
      // servicio, porque auth.uid() es NULL. Va por cambiar_rol(), concedida
      // solo a service_role. Ver 20260914120000.
      if (rol) {
        const { error: rolErr } = await sbAdmin.rpc('cambiar_rol', {
          p_user_id: user_id, p_rol: rol,
        })
        if (rolErr) return json({ error: `No se pudo cambiar el rol: ${rolErr.message}` }, 400)
      }

      if (nombre) {
        const { error: perfilErr } = await sbAdmin.from('perfiles')
          .update({ nombre }).eq('user_id', user_id)
        if (perfilErr) {
          return json({
            error: `No se pudo actualizar el nombre: ${perfilErr.message}`,
            parcial: Boolean(rol),
          }, 500)
        }
      }

      const authUpdate: Record<string, string> = {}
      if (email)    authUpdate.email    = email
      if (password) authUpdate.password = password

      if (Object.keys(authUpdate).length) {
        const { error: updateErr } = await sbAdmin.auth.admin.updateUserById(user_id, authUpdate)
        if (updateErr) {
          return json({
            error: `El perfil se actualizo, pero los datos de acceso no: ${updateErr.message}`,
            parcial: Boolean(rol || nombre),
          }, 400)
        }
      }

      return json({ ok: true })
    }

    if (accion === 'eliminar') {
      if (!user_id) return json({ error: 'Falta user_id' }, 400)

      if (user_id === caller.id) {
        return json({ error: 'No puedes borrar tu propia cuenta desde aqui.' }, 409)
      }

      const { data: objetivo } = await sbAdmin.from('perfiles')
        .select('rol').eq('user_id', user_id).maybeSingle()
      if (objetivo?.rol === 'superadmin' && !await quedanOtrosSuperadmins(sbAdmin, user_id)) {
        return json({
          error: 'Es el unico superadmin. Borrarlo dejaria la plataforma sin quien ' +
                 'apruebe cuentas, recursos ni solicitudes, y no hay forma de ' +
                 'recuperarlo desde la aplicacion. Nombra otro antes.',
        }, 409)
      }

      // Hay cuentas cuyo borrado falla por las restricciones CHECK que exigen
      // partes presentes en pedidos y reservaciones. Sin comprobarlo, el
      // superadmin veia "ok" y el usuario seguia ahi — y si la peticion venia de
      // un derecho ARCO de cancelacion, se daba por atendida sin atenderse.
      const { error: delErr } = await sbAdmin.auth.admin.deleteUser(user_id)
      if (delErr) return json({ error: `No se pudo borrar: ${delErr.message}` }, 400)

      return json({ ok: true })
    }

    if (accion === 'listar') {
      const { data: perfiles } = await sbAdmin.from('perfiles').select('user_id, nombre, rol, aprobacion_cuenta, created_at').order('created_at')
      const { data: { users } } = await sbAdmin.auth.admin.listUsers()
      const ROL_ORDER: Record<string, number> = { superadmin: 0, admin: 1, cliente: 2 }
      const lista = (perfiles || [])
        .map(p => {
          const u = users.find((x: any) => x.id === p.user_id)
          return { ...p, email: u?.email || '—' }
        })
        .sort((a: any, b: any) => (ROL_ORDER[a.rol] ?? 9) - (ROL_ORDER[b.rol] ?? 9))
      return json({ lista })
    }

    return json({ error: 'Acción no reconocida' }, 400)

  } catch (e) {
    return json({ error: 'Error interno al gestionar el usuario.' }, 500)
  }
})
