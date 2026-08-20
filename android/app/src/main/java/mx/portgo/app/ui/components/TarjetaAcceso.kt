package mx.portgo.app.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import mx.portgo.app.ui.theme.ColoresEstado
import mx.portgo.app.ui.theme.Espacio
import mx.portgo.app.ui.theme.PortGoColor
import mx.portgo.app.ui.theme.Radio

/**
 * Tarjeta de acceso a un módulo, para la rejilla del inicio.
 *
 * El badge de conteo no es adorno: es lo que convierte el inicio en una lista
 * de pendientes. "Mis solicitudes · 2" dice que hay dos esperando respuesta sin
 * necesidad de entrar a mirar.
 *
 * La variante `alerta` (fondo y icono en naranja) se reserva para lo que ya es
 * un problema, no para lo que es meramente urgente — hoy solo Vigencias, donde
 * un documento vencido deja la unidad parada.
 */
@Composable
fun TarjetaAcceso(
    titulo: String,
    descripcion: String,
    icono: ImageVector,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    badge: Int? = null,
    alerta: Boolean = false,
) {
    val fondoIcono = if (alerta) ColoresEstado.peligroSuave else PortGoColor.TealTenue
    val tinteIcono = if (alerta) ColoresEstado.peligro else PortGoColor.Teal

    Card(
        onClick = onClick,
        modifier = modifier
            // El lector de pantalla anuncia la tarjeta completa de una vez, con
            // el conteo incluido; si no, lee tres fragmentos sueltos.
            .semantics(mergeDescendants = true) {
                contentDescription = buildString {
                    append(titulo)
                    badge?.takeIf { it > 0 }?.let { append(", $it pendientes") }
                    append(". ")
                    append(descripcion)
                }
            },
        shape = RoundedCornerShape(Radio.tarjeta),
        colors = CardDefaults.cardColors(containerColor = PortGoColor.Superficie),
        border = BorderStroke(1.dp, PortGoColor.BordeTarjeta),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Column(Modifier.padding(14.dp)) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top,
            ) {
                Box(
                    Modifier
                        .size(42.dp)
                        .clip(RoundedCornerShape(Radio.iconoTarjeta))
                        .background(fondoIcono),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        icono,
                        contentDescription = null,
                        tint = tinteIcono,
                        modifier = Modifier.size(21.dp),
                    )
                }

                badge?.takeIf { it > 0 }?.let { BadgeConteo(it) }
            }

            Spacer(Modifier.height(10.dp))
            Text(titulo, style = MaterialTheme.typography.titleSmall, color = PortGoColor.Tinta)
            Spacer(Modifier.height(2.dp))
            Text(
                descripcion,
                style = MaterialTheme.typography.bodySmall,
                color = PortGoColor.TextoSecundario,
            )
        }
    }
}

/** Píldora naranja de conteo. */
@Composable
fun BadgeConteo(
    valor: Int,
    modifier: Modifier = Modifier,
    color: Color = ColoresEstado.peligro,
) {
    Box(
        modifier
            .defaultMinSize(minWidth = 20.dp, minHeight = 20.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(color)
            .padding(horizontal = 7.dp, vertical = 2.dp)
            // El conteo ya se anuncia en la descripción de la tarjeta; leerlo
            // otra vez suelto solo repite.
            .clearAndSetSemantics { },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            if (valor > 99) "99+" else valor.toString(),
            style = MaterialTheme.typography.labelMedium,
            color = PortGoColor.Superficie,
        )
    }
}

/** Tarjeta de indicador para la fila de KPIs de la empresa. */
@Composable
fun TarjetaStat(
    cifra: String,
    etiqueta: String,
    modifier: Modifier = Modifier,
    colorCifra: Color = PortGoColor.Teal,
) {
    Card(
        modifier = modifier.semantics(mergeDescendants = true) {
            contentDescription = "$cifra $etiqueta"
        },
        shape = RoundedCornerShape(Radio.stat),
        colors = CardDefaults.cardColors(containerColor = PortGoColor.Superficie),
        border = BorderStroke(1.dp, PortGoColor.BordeTarjeta),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Column(Modifier.padding(horizontal = 13.dp, vertical = 12.dp)) {
            Text(
                cifra,
                style = MaterialTheme.typography.headlineSmall,
                color = colorCifra,
            )
            Spacer(Modifier.height(2.dp))
            Text(
                etiqueta,
                style = MaterialTheme.typography.bodySmall,
                color = PortGoColor.TextoSecundario,
            )
        }
    }
}

/** Encabezado de sección en mayúsculas ("ACCESOS RÁPIDOS", "GESTIÓN"). */
@Composable
fun EtiquetaSeccion(texto: String, modifier: Modifier = Modifier) {
    Text(
        texto.uppercase(),
        style = MaterialTheme.typography.labelLarge,
        color = PortGoColor.TextoSecundario,
        modifier = modifier.padding(bottom = Espacio.s),
    )
}
