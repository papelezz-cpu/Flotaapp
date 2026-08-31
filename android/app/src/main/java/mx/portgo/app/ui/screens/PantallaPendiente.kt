package mx.portgo.app.ui.screens

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.Language
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import mx.portgo.app.BuildConfig
import mx.portgo.app.ui.components.EncabezadoModulo
import mx.portgo.app.ui.theme.Espacio
import mx.portgo.app.ui.theme.PortGoColor
import mx.portgo.app.ui.theme.SpaceGrotesk

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
    onAtras: (() -> Unit)? = null,
) {
    val contexto = LocalContext.current

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(PortGoColor.Arena),
    ) {
        // Con encabezado y no suelta en medio de la pantalla: se llega aquí
        // tocando una tarjeta del inicio, y sin flecha la única salida es la
        // barra inferior, que no lleva a todos los módulos.
        EncabezadoModulo(titulo = modulo, onAtras = onAtras)

        Column(
            Modifier
                .fillMaxSize()
                .padding(Espacio.xl),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Box(
                Modifier
                    .size(76.dp)
                    .clip(CircleShape)
                    .background(PortGoColor.TealTenue),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Default.Language,
                    contentDescription = null,
                    modifier = Modifier.size(36.dp),
                    tint = PortGoColor.TealOscuro,
                )
            }
            Spacer(Modifier.height(Espacio.m))
            Text(
                modulo,
                fontFamily = SpaceGrotesk,
                fontWeight = FontWeight.Bold,
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
                shape = RoundedCornerShape(12.dp),
            ) {
                Icon(
                    Icons.AutoMirrored.Filled.OpenInNew,
                    contentDescription = null,
                    modifier = Modifier.size(17.dp),
                )
                Spacer(Modifier.width(Espacio.s))
                Text("Abrir en el navegador")
            }
        }
    }
}
