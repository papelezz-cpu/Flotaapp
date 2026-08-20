package mx.portgo.app.data.repository

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.auth.status.SessionSource
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.postgrest.from
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.map
import mx.portgo.app.core.Resultado
import mx.portgo.app.core.SecureSessionStorage
import mx.portgo.app.core.intentar
import mx.portgo.app.data.model.Perfil
import mx.portgo.app.data.model.Rol
import mx.portgo.app.data.model.UsuarioActual

/**
 * Sesión y perfil.
 *
 * El login es de dos tiempos, igual que en la web: primero GoTrue valida las
 * credenciales, y luego se lee `perfiles` para saber si la cuenta puede operar.
 * Una cuenta pendiente, rechazada o suspendida entra a GoTrue perfectamente
 * bien — ese filtro no está en RLS (gap G4), vive en el cliente. Por eso aquí
 * se cierra la sesión de inmediato si el perfil lo dice: si esta app no lo
 * replicara, sería la puerta de entrada para cuentas bloqueadas.
 */
class AuthRepository(
    private val supabase: SupabaseClient,
    private val almacen: SecureSessionStorage,
) {

    /** Resultado de un intento de entrar. */
    sealed interface Acceso {
        data class Concedido(val usuario: UsuarioActual) : Acceso

        /** Credenciales buenas, pero la cuenta no puede operar. */
        data class Bloqueado(val motivo: String) : Acceso
    }

    suspend fun iniciarSesion(correo: String, contrasena: String): Resultado<Acceso> = intentar {
        supabase.auth.signInWith(Email) {
            this.email = correo.trim()
            this.password = contrasena
        }

        val userId = supabase.auth.currentUserOrNull()?.id
            ?: error("No se pudo leer la sesión recién creada.")

        val acceso = evaluarPerfil(userId, correo.trim())
        if (acceso is Acceso.Bloqueado) {
            supabase.auth.signOut()
        } else {
            almacen.ultimoCorreo = correo.trim()
        }
        acceso
    }

    /**
     * Restaura la sesión guardada. Devuelve null si no hay ninguna.
     *
     * Vuelve a revisar el perfil a propósito: entre una apertura y otra pueden
     * haber suspendido la cuenta, y el token seguiría siendo válido.
     */
    suspend fun restaurarSesion(): Resultado<Acceso?> = intentar {
        supabase.auth.awaitInitialization()
        val usuario = supabase.auth.currentUserOrNull() ?: return@intentar null

        val acceso = evaluarPerfil(usuario.id, usuario.email.orEmpty())
        if (acceso is Acceso.Bloqueado) supabase.auth.signOut()
        acceso
    }

    private suspend fun evaluarPerfil(userId: String, correo: String): Acceso {
        val perfil = supabase.from("perfiles")
            .select {
                filter { eq("user_id", userId) }
                limit(1)
            }
            .decodeSingleOrNull<Perfil>()

        perfil?.motivoBloqueo?.let { return Acceso.Bloqueado(it) }

        // Sin perfil: puede ser un registro a medias. La web consulta
        // `solicitudes_cuenta` para dar un mensaje mejor; aquí basta con no
        // dejar entrar, porque el alta se hace en la web de todos modos.
        if (perfil == null) {
            return Acceso.Bloqueado(
                "Tu cuenta todavía no está activa. Si acabas de registrarte, " +
                    "espera la aprobación del equipo de PortGo.",
            )
        }

        val rol = perfil.rolEnum
        if (rol == Rol.SUPERADMIN) {
            return Acceso.Bloqueado(
                "El panel de administración solo está disponible en la versión web de PortGo.",
            )
        }
        if (rol == Rol.DESCONOCIDO) {
            return Acceso.Bloqueado("Tu cuenta no tiene un rol asignado. Contacta a soporte.")
        }

        return Acceso.Concedido(
            UsuarioActual(
                id = userId,
                email = correo,
                nombre = perfil.nombre?.takeIf { it.isNotBlank() } ?: correo,
                rol = rol,
                metodoVerificacion = perfil.metodoVerificacion,
            ),
        )
    }

    suspend fun cerrarSesion(): Resultado<Unit> = intentar {
        supabase.auth.signOut()
        // El correo se conserva para prellenar el campo la próxima vez; la
        // preferencia de biometría también, porque es del dispositivo.
    }

    /**
     * Envía el correo de recuperación.
     *
     * El enlace regresa a `portgo://auth`. Ese esquema tiene que estar dado de
     * alta en Supabase → Authentication → URL Configuration → Redirect URLs, o
     * el correo llega pero el enlace no abre la app (gap G6 del análisis).
     */
    suspend fun recuperarContrasena(correo: String): Resultado<Unit> = intentar {
        supabase.auth.resetPasswordForEmail(correo.trim())
    }

    /** Se llama después de que el deep link de recuperación restauró la sesión. */
    suspend fun cambiarContrasena(nueva: String): Resultado<Unit> = intentar {
        require(nueva.length >= MIN_CONTRASENA) {
            "La contraseña debe tener al menos $MIN_CONTRASENA caracteres."
        }
        supabase.auth.updateUser { password = nueva }
    }

    suspend fun perfil(userId: String): Resultado<Perfil?> = intentar {
        supabase.from("perfiles")
            .select { filter { eq("user_id", userId) }; limit(1) }
            .decodeSingleOrNull<Perfil>()
    }

    /** Nombres de varios usuarios de un jalón, para no consultar en bucle. */
    suspend fun nombresDe(ids: Collection<String>): Map<String, String> {
        if (ids.isEmpty()) return emptyMap()
        return runCatching {
            supabase.from("perfiles")
                .select { filter { isIn("user_id", ids.distinct()) } }
                .decodeList<Perfil>()
                .associate { it.userId to (it.nombre ?: "—") }
        }.getOrDefault(emptyMap())
    }

    suspend fun actualizarPreferenciaCorreo(userId: String, quiere: Boolean): Resultado<Unit> = intentar {
        supabase.from("perfiles").update(mapOf("notif_email" to quiere)) {
            filter { eq("user_id", userId) }
        }
    }


    /**
     * Promedio de calificaciones de una empresa, para el indicador del inicio.
     *
     * Devuelve null si todavía no la han calificado: mostrar "0.0" a una
     * empresa nueva la haría ver mal por no haber trabajado aún, que es lo
     * contrario de lo que el dato significa.
     */
    suspend fun calificacionPromedio(adminId: String): Double? = runCatching {
        val notas = supabase.from("calificaciones")
            .select { filter { eq("admin_id", adminId) } }
            .decodeList<mx.portgo.app.data.model.Calificacion>()
        if (notas.isEmpty()) null else notas.sumOf { it.rating }.toDouble() / notas.size
    }.getOrNull()

    var correoRecordado: String?
        get() = almacen.ultimoCorreo
        set(value) { almacen.ultimoCorreo = value }

    var biometriaActiva: Boolean
        get() = almacen.biometriaActiva
        set(value) { almacen.biometriaActiva = value }

    /**
     * Emite cuando llega una sesión desde un enlace externo (el correo de
     * recuperación de contraseña).
     *
     * Se observa `sessionStatus` en lugar de confiar en el callback de
     * `handleDeeplinks` por dos razones:
     *
     *  1. Funciona igual con PKCE (`?code=…`) que con el formato antiguo
     *     (`#access_token=…`): en ambos casos el SDK marca la sesión resultante
     *     como `SessionSource.External`.
     *  2. `sessionStatus` es un StateFlow, así que conserva el último valor. Si
     *     el intercambio del código termina antes de que la interfaz empiece a
     *     observar —que es lo normal, porque el deep link se procesa en
     *     onCreate—, no se pierde el aviso.
     *
     * Las otras fuentes (`Storage` al restaurar, `SignIn` al entrar con
     * contraseña, `Refresh`) no disparan nada.
     */
    val sesionesExternas: Flow<Unit> =
        supabase.auth.sessionStatus
            .filterIsInstance<SessionStatus.Authenticated>()
            .filter { it.source is SessionSource.External }
            .map { }

    companion object {
        /** Mismo mínimo que valida la web en registro, reset y alta de usuarios. */
        const val MIN_CONTRASENA = 8
    }
}
