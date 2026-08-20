package mx.portgo.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import mx.portgo.app.ui.theme.PortGoColor

/** Una pestaña de la barra inferior. */
data class PestanaBarra(
    val ruta: String,
    val etiqueta: String,
    val icono: ImageVector,
)

/**
 * Barra inferior con botón de acción central.
 *
 * Se construye a mano y no con `NavigationBar` + `BottomAppBar` de Material
 * por dos razones del diseño que los componentes de fábrica no cubren:
 *
 *  1. El FAB va **encajado en la barra**, sobresaliendo hacia arriba y con un
 *     borde del color del fondo que lo recorta contra ella. `BottomAppBar` lo
 *     coloca dentro o flotando aparte, nunca así.
 *  2. El FAB lleva **etiqueta debajo** ("Publicar" / "Agregar"), alineada con
 *     las de las pestañas. Ningún FAB de Material admite label inferior.
 *
 * La estructura es de cinco huecos: dos pestañas, el FAB, dos pestañas. Eso
 * mantiene el botón principal centrado y al alcance del pulgar en cualquier
 * pantalla, que es la idea de toda la dirección 1b.
 */
@Composable
fun BarraInferiorPortGo(
    pestanas: List<PestanaBarra>,
    rutaActual: String?,
    onPestana: (String) -> Unit,
    etiquetaAccion: String,
    onAccion: () -> Unit,
    modifier: Modifier = Modifier,
    /**
     * El handoff pinta la etiqueta del FAB en teal cuando la pantalla actual es
     * el destino natural de la acción, y en gris en el resto.
     */
    accionDestacada: Boolean = false,
) {
    require(pestanas.size == 4) {
        "La barra 1b tiene exactamente cuatro pestañas: dos a cada lado del FAB."
    }

    Column(modifier.fillMaxWidth()) {
        HorizontalDivider(thickness = 1.dp, color = PortGoColor.BordeBarra)

        Box(
            Modifier
                .fillMaxWidth()
                .background(PortGoColor.Superficie),
        ) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .navigationBarsPadding()
                    .padding(start = 6.dp, end = 6.dp, top = 9.dp, bottom = 4.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Bottom,
            ) {
                pestanas.take(2).forEach { p ->
                    Pestana(p, rutaActual == p.ruta) { onPestana(p.ruta) }
                }

                HuecoAccion(
                    etiqueta = etiquetaAccion,
                    destacada = accionDestacada,
                    onClick = onAccion,
                )

                pestanas.drop(2).forEach { p ->
                    Pestana(p, rutaActual == p.ruta) { onPestana(p.ruta) }
                }
            }
        }
    }
}

@Composable
private fun Pestana(
    pestana: PestanaBarra,
    activa: Boolean,
    onClick: () -> Unit,
) {
    val color = if (activa) PortGoColor.Teal else PortGoColor.TextoTerciario

    Column(
        modifier = Modifier
            .width(60.dp)
            .clip(MaterialTheme.shapes.small)
            .clickable(
                // Sin ondas: el diseño no las contempla y sobre la barra blanca
                // se ven como una mancha gris.
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                role = Role.Tab,
                onClick = onClick,
            )
            .semantics {
                contentDescription =
                    if (activa) "${pestana.etiqueta}, pestaña actual" else pestana.etiqueta
            }
            .padding(vertical = 2.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            pestana.icono,
            contentDescription = null,
            tint = color,
            modifier = Modifier.size(22.dp),
        )
        Spacer(Modifier.height(3.dp))
        Text(
            pestana.etiqueta,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = if (activa) FontWeight.SemiBold else FontWeight.Medium,
            color = color,
        )
    }
}

/**
 * El hueco central: el círculo sobresale por encima de la barra y la etiqueta
 * queda alineada con las de las pestañas.
 *
 * El botón se dibuja con `offset` negativo dentro de un contenedor angosto, en
 * vez de con posicionamiento absoluto, para que siga participando del reparto
 * horizontal de la fila y quede centrado solo.
 */
@Composable
private fun HuecoAccion(
    etiqueta: String,
    destacada: Boolean,
    onClick: () -> Unit,
) {
    Column(
        modifier = Modifier.width(58.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier
                .offset(y = (-26).dp)
                .size(56.dp)
                // El borde del color del fondo es lo que recorta el círculo
                // contra la barra y le da el efecto de estar encajado.
                .shadow(elevation = 10.dp, shape = CircleShape, clip = false)
                .background(PortGoColor.Arena, CircleShape)
                .padding(4.dp)
                .clip(CircleShape)
                .background(PortGoColor.Teal)
                .clickable(role = Role.Button, onClick = onClick)
                .semantics { contentDescription = etiqueta },
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Default.Add,
                contentDescription = null,
                tint = PortGoColor.Superficie,
                modifier = Modifier.size(26.dp),
            )
        }

        // Compensa el desplazamiento del círculo para que la etiqueta caiga a
        // la misma altura que las de las pestañas.
        Spacer(Modifier.height(0.dp))
        Text(
            etiqueta,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Medium,
            color = if (destacada) PortGoColor.Teal else PortGoColor.TextoTerciario,
            modifier = Modifier.offset(y = (-23).dp),
        )
    }
}
