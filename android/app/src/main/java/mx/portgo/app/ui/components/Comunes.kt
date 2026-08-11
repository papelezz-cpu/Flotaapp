package mx.portgo.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import mx.portgo.app.data.model.EstadoOferta
import mx.portgo.app.data.model.EstadoPedido
import mx.portgo.app.data.model.EstadoReserva
import mx.portgo.app.ui.theme.ColoresEstado
import mx.portgo.app.ui.theme.Espacio

/**
 * Etiqueta de estado.
 *
 * El color no es decorativo: distingue de un vistazo una solicitud que espera
 * acción de una que ya está cerrada. Aun así el texto siempre está presente —
 * nunca el color solo — porque una de cada doce personas no distingue rojo de
 * verde, y aquí eso sería la diferencia entre "cancelada" y "activa".
 */
@Composable
fun ChipEstado(
    texto: String,
    color: Color,
    fondo: Color,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(50))
            .background(fondo)
            .padding(horizontal = 10.dp, vertical = 4.dp),
    ) {
        Text(
            text = texto,
            style = MaterialTheme.typography.labelSmall,
            color = color,
        )
    }
}

@Composable
fun ChipEstadoPedido(estado: EstadoPedido, modifier: Modifier = Modifier) {
    val (color, fondo) = when (estado) {
        EstadoPedido.ABIERTO -> ColoresEstado.exito to ColoresEstado.exitoSuave
        EstadoPedido.EN_NEGOCIACION -> ColoresEstado.info to ColoresEstado.infoSuave
        EstadoPedido.PENDIENTE_REVISION,
        EstadoPedido.PENDIENTE_ACUERDO,
        -> ColoresEstado.alerta to ColoresEstado.alertaSuave
        EstadoPedido.ACORDADO -> ColoresEstado.info to ColoresEstado.infoSuave
        EstadoPedido.FINALIZADO -> ColoresEstado.exito to ColoresEstado.exitoSuave
        EstadoPedido.CANCELADO,
        EstadoPedido.RECHAZADO,
        EstadoPedido.EXPIRADO,
        -> ColoresEstado.peligro to ColoresEstado.peligroSuave
        EstadoPedido.DESCONOCIDO -> ColoresEstado.neutro to ColoresEstado.neutroSuave
    }
    ChipEstado(estado.etiqueta, color, fondo, modifier)
}

@Composable
fun ChipEstadoReserva(estado: EstadoReserva, modifier: Modifier = Modifier) {
    val (color, fondo) = when (estado) {
        EstadoReserva.ACTIVA -> ColoresEstado.exito to ColoresEstado.exitoSuave
        EstadoReserva.PENDIENTE,
        EstadoReserva.POR_APROBAR,
        EstadoReserva.CANCELACION_SOLICITADA,
        -> ColoresEstado.alerta to ColoresEstado.alertaSuave
        EstadoReserva.COMPLETADA -> ColoresEstado.info to ColoresEstado.infoSuave
        EstadoReserva.CANCELADA,
        EstadoReserva.RECHAZADA,
        -> ColoresEstado.peligro to ColoresEstado.peligroSuave
        EstadoReserva.DESCONOCIDO -> ColoresEstado.neutro to ColoresEstado.neutroSuave
    }
    ChipEstado(estado.etiqueta, color, fondo, modifier)
}

@Composable
fun ChipEstadoOferta(estado: EstadoOferta, modifier: Modifier = Modifier) {
    val (color, fondo) = when (estado) {
        EstadoOferta.ENVIADA -> ColoresEstado.info to ColoresEstado.infoSuave
        EstadoOferta.CONTRA_OFERTA -> ColoresEstado.alerta to ColoresEstado.alertaSuave
        EstadoOferta.ACEPTADA -> ColoresEstado.exito to ColoresEstado.exitoSuave
        EstadoOferta.RECHAZADA -> ColoresEstado.peligro to ColoresEstado.peligroSuave
        EstadoOferta.DESCONOCIDO -> ColoresEstado.neutro to ColoresEstado.neutroSuave
    }
    ChipEstado(estado.etiqueta, color, fondo, modifier)
}

/**
 * Esqueleto de carga.
 *
 * Se prefiere sobre una rueda centrada porque conserva la forma de la lista:
 * la pantalla no salta cuando llegan los datos, y la espera se percibe más
 * corta. Es lo mismo que hace la web con `skeletonList()`.
 */
@Composable
fun EsqueletoLista(
    filas: Int = 4,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(Espacio.m)
            .clearAndSetSemantics { }, // decorativo: no lo lee el lector de pantalla
        verticalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        repeat(filas) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(96.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f)),
            )
        }
    }
}

@Composable
fun CargandoCentrado(modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        CircularProgressIndicator()
    }
}

@Composable
fun EstadoVacio(
    titulo: String,
    detalle: String? = null,
    icono: androidx.compose.ui.graphics.vector.ImageVector = Icons.Default.Inbox,
    accion: (@Composable () -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(Espacio.xl),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            icono,
            contentDescription = null,
            modifier = Modifier.size(48.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
        )
        Spacer(Modifier.height(Espacio.m))
        Text(
            titulo,
            style = MaterialTheme.typography.titleMedium,
            textAlign = TextAlign.Center,
        )
        if (detalle != null) {
            Spacer(Modifier.height(Espacio.xs))
            Text(
                detalle,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
        if (accion != null) {
            Spacer(Modifier.height(Espacio.m))
            accion()
        }
    }
}

/**
 * Error visible con opción de reintentar.
 *
 * Nunca se traga un error: en este backend, un fallo de RLS devuelve lista
 * vacía sin avisar, y confundir "no tienes permiso" con "no hay nada" cuesta
 * horas de depuración. Si algo falló, se dice.
 */
@Composable
fun BannerError(
    mensaje: String,
    onReintentar: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = Espacio.m, vertical = Espacio.s)
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.errorContainer)
            .padding(Espacio.m),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            Icons.Default.ErrorOutline,
            contentDescription = "Error",
            tint = MaterialTheme.colorScheme.onErrorContainer,
        )
        Spacer(Modifier.size(Espacio.s))
        Text(
            mensaje,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onErrorContainer,
            modifier = Modifier.weight(1f),
        )
        if (onReintentar != null) {
            TextButton(onClick = onReintentar) { Text("Reintentar") }
        }
    }
}

/** Par etiqueta/valor de una ficha de detalle. */
@Composable
fun FilaDato(
    etiqueta: String,
    valor: String?,
    modifier: Modifier = Modifier,
) {
    if (valor.isNullOrBlank() || valor == "—") return
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 3.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Text(
            etiqueta,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(0.42f),
        )
        Text(
            valor,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.weight(0.58f),
        )
    }
}
