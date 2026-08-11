package mx.portgo.app.core

import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * Desbloqueo biométrico al reabrir la app.
 *
 * La sesión persiste cifrada en [SecureSessionStorage]; esta es la otra mitad
 * del trato: el refresh token sobrevive al cierre de la app, pero para volver
 * a usarlo hace falta la huella o el rostro del dueño. Sin esto, un teléfono
 * perdido desbloqueado da acceso completo a las reservaciones, los precios
 * acordados y el chat con los clientes.
 *
 * `DEVICE_CREDENTIAL` va incluido a propósito: en muchos equipos de flota el
 * sensor de huella está desgastado o el operador trae guantes. Sin la
 * alternativa del PIN, la app quedaría inservible justo en el contexto en el
 * que se usa.
 */
object BiometricGate {

    private const val AUTENTICADORES =
        BiometricManager.Authenticators.BIOMETRIC_WEAK or
            BiometricManager.Authenticators.DEVICE_CREDENTIAL

    enum class Disponibilidad {
        /** Hay huella/rostro o al menos PIN configurado. */
        DISPONIBLE,

        /** El equipo lo soporta pero no hay nada dado de alta. */
        SIN_CONFIGURAR,

        /** El equipo no tiene hardware, o está inutilizable. */
        NO_DISPONIBLE,
    }

    fun disponibilidad(activity: FragmentActivity): Disponibilidad =
        when (BiometricManager.from(activity).canAuthenticate(AUTENTICADORES)) {
            BiometricManager.BIOMETRIC_SUCCESS -> Disponibilidad.DISPONIBLE
            BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> Disponibilidad.SIN_CONFIGURAR
            else -> Disponibilidad.NO_DISPONIBLE
        }

    /**
     * Devuelve `true` si el usuario se autenticó. `false` cubre tanto la
     * cancelación como el fallo: en ambos casos la app se queda en la pantalla
     * de bloqueo, nunca entra.
     */
    suspend fun solicitar(
        activity: FragmentActivity,
        titulo: String = "Desbloquea PortGo",
        subtitulo: String = "Usa tu huella, rostro o PIN para continuar",
    ): Boolean = suspendCancellableCoroutine { cont ->
        val ejecutor = ContextCompat.getMainExecutor(activity)

        val prompt = BiometricPrompt(
            activity,
            ejecutor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    if (cont.isActive) cont.resume(true)
                }

                override fun onAuthenticationError(code: Int, mensaje: CharSequence) {
                    if (cont.isActive) cont.resume(false)
                }

                // onAuthenticationFailed (huella no reconocida) NO resuelve:
                // el prompt sigue abierto para reintentar, que es lo que espera
                // el usuario. Solo un error terminal o el éxito cierran esto.
            },
        )

        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(titulo)
            .setSubtitle(subtitulo)
            .setAllowedAuthenticators(AUTENTICADORES)
            .build()

        cont.invokeOnCancellation { prompt.cancelAuthentication() }
        prompt.authenticate(info)
    }
}
