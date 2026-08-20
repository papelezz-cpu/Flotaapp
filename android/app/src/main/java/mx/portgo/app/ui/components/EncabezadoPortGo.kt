package mx.portgo.app.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.NotificationsNone
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import mx.portgo.app.ui.theme.ColoresEstado
import mx.portgo.app.ui.theme.Espacio
import mx.portgo.app.ui.theme.PortGoColor
import mx.portgo.app.ui.theme.Radio

/**
 * Encabezado de las pantallas raíz.
 *
 * Dos variantes, como define el handoff: en el inicio va el logo con el
 * wordmark; en el resto, el título del módulo. La campana está en ambas.
 *
 * No usa `TopAppBar` de Material porque su altura y sus paddings están fijados
 * por la especificación de Material, no por este diseño — y el handoff pide un
 * encabezado bajo (`6px 16px 12px`) sobre fondo arena, sin la superficie
 * elevada que TopAppBar impone.
 */
@Composable
fun EncabezadoPortGo(
    esInicio: Boolean,
    titulo: String,
    noLeidas: Int,
    onCampana: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier
            .fillMaxWidth()
            .background(PortGoColor.Arena)
            .statusBarsPadding()
            .padding(start = Espacio.m, end = Espacio.m, top = 6.dp, bottom = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (esInicio) {
            LogoPortGo()
            Spacer(Modifier.width(10.dp))
            Text(
                "PortGo",
                style = MaterialTheme.typography.titleLarge,
                color = PortGoColor.Tinta,
            )
        } else {
            Text(
                titulo,
                style = MaterialTheme.typography.titleLarge,
                color = PortGoColor.Tinta,
            )
        }

        Spacer(Modifier.weight(1f))

        BotonCampana(noLeidas = noLeidas, onClick = onCampana)
    }
}

/**
 * Logo: nodo central con tres satélites.
 *
 * Se dibuja en lugar de importar un SVG porque son cuatro círculos y tres
 * líneas — un vector nuevo para eso solo agregaría un archivo que mantener.
 */
@Composable
private fun LogoPortGo(modifier: Modifier = Modifier) {
    Box(
        modifier
            .size(28.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(PortGoColor.Teal)
            .drawBehind {
                val centro = Offset(size.width / 2f, size.height / 2f)
                val radio = size.minDimension * 0.26f
                val puntos = listOf(-90f, 30f, 150f).map { grados ->
                    val rad = Math.toRadians(grados.toDouble())
                    Offset(
                        centro.x + (radio * kotlin.math.cos(rad)).toFloat(),
                        centro.y + (radio * kotlin.math.sin(rad)).toFloat(),
                    )
                }
                puntos.forEach { p ->
                    drawLine(
                        color = PortGoColor.Superficie,
                        start = centro,
                        end = p,
                        strokeWidth = size.minDimension * 0.055f,
                    )
                }
                drawCircle(PortGoColor.Superficie, radius = size.minDimension * 0.11f, center = centro)
                puntos.forEach { p ->
                    drawCircle(PortGoColor.Superficie, radius = size.minDimension * 0.085f, center = p)
                }
            },
    )
}

/**
 * Campana con punto de aviso.
 *
 * El punto indica "hay algo sin leer" sin decir cuántos: el conteo exacto vive
 * en la pantalla de notificaciones y en los badges de cada módulo, donde
 * además dice de qué. Un número aquí competiría con esos sin aportar.
 */
@Composable
private fun BotonCampana(
    noLeidas: Int,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier
            .size(38.dp)
            .clip(RoundedCornerShape(Radio.botonHeader))
            .background(PortGoColor.Superficie)
            .border(
                BorderStroke(1.dp, PortGoColor.BordeTarjeta),
                RoundedCornerShape(Radio.botonHeader),
            )
            .clickable(onClick = onClick)
            .semantics {
                contentDescription = if (noLeidas > 0) {
                    "Notificaciones, $noLeidas sin leer"
                } else {
                    "Notificaciones"
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            Icons.Default.NotificationsNone,
            contentDescription = null,
            tint = PortGoColor.Tinta,
            modifier = Modifier.size(19.dp),
        )
        if (noLeidas > 0) {
            Box(
                Modifier
                    .align(Alignment.TopEnd)
                    .offset(x = (-7).dp, y = 7.dp)
                    .size(8.dp)
                    .clip(CircleShape)
                    .background(ColoresEstado.peligro)
                    .drawBehind {
                        drawCircle(
                            color = PortGoColor.Superficie,
                            radius = size.minDimension / 2f,
                            style = Stroke(width = 1.5.dp.toPx()),
                        )
                    },
            )
        }
    }
}
