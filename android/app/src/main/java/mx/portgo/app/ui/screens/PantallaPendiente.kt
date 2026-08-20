package mx.portgo.app.ui.screens

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
import androidx.compose.material.icons.filled.Language
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import mx.portgo.app.BuildConfig
import mx.portgo.app.ui.theme.Espacio
import mx.portgo.app.ui.theme.PortGoColor

/**
 * Módulo que todavía no está en la app.
 *
 * Existe porque el diseño pone en el inicio los doce módulos, y varios aún no
 * se han construido. Hay dos formas malas de resolverlo: ocultar las tarjetas
 * —y entonces el inicio no se parece al diseño ni deja ver a dónde va la app—
 * o dejarlas mudas, que hace pensar que la app está rota.
 *
 * Esta es la tercera: la tarjeta está, se toca, y dice la verdad — esa sección
 * sigue solo en la web, con un botón para ir. Cada fase que se construya
 * reemplaza una de estas pantallas.
 */
@Composable
fun PantallaPendiente(
    modulo: String,
    descripcion: String,
    modifier: Modifier = Modifier,
) {
    val contexto = LocalContext.current

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(Espacio.xl),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            Icons.Default.Language,
            contentDescription = null,
            modifier = Modifier.size(48.dp),
            tint = PortGoColor.TextoTerciario,
        )
        Spacer(Modifier.height(Espacio.m))
        Text(
            modulo,
            style = MaterialTheme.typography.titleLarge,
            color = PortGoColor.Tinta,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(Espacio.s))
        Text(
            "$descripcion Por ahora esta sección está disponible en el sitio web; " +
                "la estamos trayendo a la app.",
            style = MaterialTheme.typography.bodyMedium,
            color = PortGoColor.TextoSecundario,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(Espacio.l))
        OutlinedButton(
            onClick = {
                runCatching {
                    contexto.startActivity(
                        Intent(Intent.ACTION_VIEW, Uri.parse("${BuildConfig.WEB_URL}/app.html")),
                    )
                }
            },
        ) { Text("Abrir en el navegador") }
    }
}
