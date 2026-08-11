package mx.portgo.app

import android.content.Intent
import android.os.Bundle
import android.util.Log
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.jan.supabase.auth.handleDeeplinks
import mx.portgo.app.ui.SesionViewModel
import mx.portgo.app.ui.navigation.RaizPortGo
import mx.portgo.app.ui.theme.PortGoTheme

/**
 * Única Activity de la app; todo lo demás es Compose.
 *
 * Hereda de FragmentActivity (no de ComponentActivity) porque BiometricPrompt
 * lo exige: se apoya en el FragmentManager para sobrevivir a los cambios de
 * configuración mientras el diálogo del sistema está arriba.
 */
class MainActivity : FragmentActivity() {

    /** Motivo por el que un enlace de recuperación no sirvió, para mostrarlo en el login. */
    private var errorEnlace by mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)

        val container = (application as PortGoApplication).container

        procesarDeepLink(intent)

        setContent {
            PortGoTheme {
                val sesionVm: SesionViewModel = viewModel(
                    factory = remember { SesionViewModel.factory(container) },
                )
                val estado by sesionVm.estado.collectAsStateWithLifecycle()

                val recuperacion by sesionVm.recuperacion.collectAsStateWithLifecycle()

                RaizPortGo(
                    estado = estado,
                    sesionVm = sesionVm,
                    container = container,
                    activity = this,
                    recuperacionEnCurso = recuperacion,
                    onRecuperacionResuelta = sesionVm::cerrarRecuperacion,
                    errorEnlace = errorEnlace,
                    onErrorEnlaceVisto = { errorEnlace = null },
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        procesarDeepLink(intent)
    }

    /**
     * Canjea el enlace del correo por una sesión.
     *
     * El SDK reconoce los dos formatos que puede mandar Supabase — PKCE
     * (`?code=…`) y el antiguo (`#access_token=…`) — y guarda la sesión.
     *
     * Quien reacciona NO es el callback de aquí, sino `SesionViewModel`
     * observando `sessionStatus`: el intercambio del código es una llamada de
     * red que suele terminar antes de que la interfaz esté lista, y un callback
     * se perdería. El StateFlow de la sesión conserva su valor y no.
     *
     * El error se registra en vez de tragarse: una versión anterior de este
     * método envolvía la llamada en `runCatching {}` sin más, y el resultado fue
     * que el enlace abría la app en la pantalla de login sin decir por qué.
     */
    private fun procesarDeepLink(intent: Intent?) {
        val uri = intent?.data ?: return
        if (uri.scheme != "portgo") return

        // Supabase avisa de los enlaces inválidos con `error` / `error_code`,
        // en la consulta o en el fragmento. El caso más común con diferencia:
        // el enlace ya se usó una vez.
        //
        // Los tokens de recuperación son de UN SOLO USO. Abrir el correo en la
        // computadora "para ver si funciona" quema el token en el endpoint de
        // verificación, y el intento posterior en el teléfono ya llega muerto.
        // Sin este aviso, la app abría en el login sin explicar nada y parecía
        // que el enlace no estaba configurado.
        val error = uri.getQueryParameter("error_code")
            ?: uri.getQueryParameter("error")
            ?: uri.fragment?.let { Regex("error_code=([^&]+)").find(it)?.groupValues?.get(1) }

        if (error != null) {
            errorEnlace = when {
                error.contains("expired") || error.contains("otp") ->
                    "Ese enlace ya se usó o venció. Los enlaces de recuperación " +
                        "sirven una sola vez: pide uno nuevo y ábrelo directamente " +
                        "en este dispositivo."
                else ->
                    "No se pudo validar el enlace de recuperación. Pide uno nuevo."
            }
            return
        }

        val container = (application as PortGoApplication).container
        try {
            container.supabase.handleDeeplinks(intent)
        } catch (t: Throwable) {
            errorEnlace = "No se pudo procesar el enlace. Pide uno nuevo desde la app."
            // Se anota la FORMA del enlace, nunca el token: el fragmento y el
            // parámetro `code` son credenciales de un solo uso.
            Log.e(
                "PortGo",
                "No se pudo procesar el enlace de recuperación. " +
                    "tiene_code=${uri.getQueryParameter("code") != null} " +
                    "tiene_fragmento=${!uri.fragment.isNullOrBlank()}",
                t,
            )
        }
    }
}
