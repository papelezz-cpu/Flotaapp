package mx.portgo.app.ui.screens.auth

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.SystemUpdate
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import mx.portgo.app.BuildConfig
import mx.portgo.app.ui.theme.Espacio

/**
 * Bloqueo por versión mínima.
 *
 * Es el interruptor de emergencia del que habla `app_config`: cuando una
 * versión vieja escribiría datos mal —porque cambió el contrato de una RPC o
 * el significado de un campo—, se sube `version_minima_android` y esas
 * instalaciones se detienen aquí, antes de tocar nada.
 *
 * No tiene salida a propósito: no hay botón de "continuar de todos modos" ni
 * se puede volver atrás. Si estuviera permitido saltárselo, no serviría para
 * lo único que tiene que servir.
 *
 * Se evalúa **antes del login**, por eso `app_config` es legible sin sesión.
 */
@Composable
fun PantallaActualizar(
    versionMinima: String?,
    urlDescarga: String?,
) {
    val contexto = LocalContext.current

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(Espacio.xl),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            Icons.Default.SystemUpdate,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.primary,
        )

        Spacer(Modifier.height(Espacio.l))

        Text(
            "Necesitas actualizar PortGo",
            style = MaterialTheme.typography.titleLarge,
            textAlign = TextAlign.Center,
        )

        Spacer(Modifier.height(Espacio.s))

        Text(
            "Esta versión ya no es compatible con el sistema. Actualiza para " +
                "seguir operando tus servicios.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )

        Spacer(Modifier.height(Espacio.l))

        if (!urlDescarga.isNullOrBlank()) {
            Button(
                onClick = {
                    runCatching {
                        contexto.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(urlDescarga)))
                    }
                },
            ) { Text("Actualizar ahora") }
        }

        Spacer(Modifier.height(Espacio.l))

        Text(
            "Tienes la ${BuildConfig.VERSION_NAME}" +
                (versionMinima?.let { " · se requiere la $it o posterior" } ?: ""),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}
