package mx.portgo.app.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import mx.portgo.app.ui.theme.Espacio
import mx.portgo.app.ui.theme.PortGoColor
import mx.portgo.app.ui.theme.Radio

/**
 * Fila de filtros en píldoras, con desplazamiento horizontal.
 *
 * Uno solo activo a la vez, como define el handoff. El activo va en teal
 * sólido y los demás en blanco con borde: el contraste es fuerte a propósito,
 * porque en una lista larga el filtro aplicado explica por qué faltan cosas y
 * tiene que verse sin buscarlo.
 */
@Composable
fun FilaFiltros(
    opciones: List<String>,
    seleccionado: String,
    onSeleccionar: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = Espacio.m, vertical = Espacio.s),
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        opciones.forEach { opcion ->
            ChipFiltro(
                texto = opcion,
                activo = opcion == seleccionado,
                onClick = { onSeleccionar(opcion) },
            )
        }
    }
}

@Composable
private fun ChipFiltro(
    texto: String,
    activo: Boolean,
    onClick: () -> Unit,
) {
    Box(
        Modifier
            .clip(RoundedCornerShape(Radio.pill))
            .background(if (activo) PortGoColor.Teal else PortGoColor.Superficie)
            .then(
                if (activo) Modifier
                else Modifier.border(
                    BorderStroke(1.dp, PortGoColor.BordeTarjeta),
                    RoundedCornerShape(Radio.pill),
                ),
            )
            .clickable(onClick = onClick)
            .semantics {
                selected = activo
                role = Role.Tab
            }
            .padding(horizontal = 16.dp, vertical = 9.dp),
    ) {
        Text(
            texto,
            style = MaterialTheme.typography.bodyMedium,
            color = if (activo) PortGoColor.Superficie else PortGoColor.TextoSecundario,
        )
    }
}

/**
 * Tarjeta de lista del diseño.
 *
 * Estructura fija: título a dos líneas + chip de estado, línea de meta, y —si
 * hay— una fila inferior separada por un divisor con etiqueta a la izquierda y
 * valor a la derecha.
 *
 * Esa fila inferior es la que hace la tarjeta útil de un vistazo: es donde va
 * el dato por el que uno abre la pantalla — la mejor oferta, con quién se
 * acordó, cuánto falta. El resto es contexto.
 */
@Composable
fun TarjetaLista(
    titulo: String,
    subtitulo: String?,
    meta: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    chip: (@Composable () -> Unit)? = null,
    etiquetaPie: String? = null,
    pie: (@Composable () -> Unit)? = null,
    extra: (@Composable ColumnScope.() -> Unit)? = null,
) {
    Card(
        onClick = onClick,
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Radio.tarjeta),
        colors = CardDefaults.cardColors(containerColor = PortGoColor.Superficie),
        border = BorderStroke(1.dp, PortGoColor.BordeTarjeta),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Column(Modifier.padding(15.dp)) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top,
            ) {
                Column(Modifier.weight(1f, fill = false)) {
                    Text(
                        titulo,
                        style = MaterialTheme.typography.titleMedium,
                        color = PortGoColor.Tinta,
                    )
                    subtitulo?.let {
                        Text(
                            it,
                            style = MaterialTheme.typography.titleMedium,
                            color = PortGoColor.Tinta,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
                chip?.let {
                    Spacer(Modifier.padding(start = Espacio.s))
                    it()
                }
            }

            meta?.let {
                Spacer(Modifier.height(6.dp))
                Text(
                    it,
                    style = MaterialTheme.typography.bodyMedium,
                    color = PortGoColor.TextoSecundario,
                )
            }

            extra?.let {
                Spacer(Modifier.height(10.dp))
                it()
            }

            if (pie != null) {
                Spacer(Modifier.height(11.dp))
                HorizontalDivider(thickness = 1.dp, color = PortGoColor.Divisor)
                Spacer(Modifier.height(10.dp))
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        etiquetaPie.orEmpty(),
                        style = MaterialTheme.typography.bodyMedium,
                        color = PortGoColor.TextoSecundario,
                    )
                    pie()
                }
            }
        }
    }
}

/**
 * Barra de avance del viaje.
 *
 * Va con el número de paso al lado ("4/5") y no solo con la barra: el relleno
 * dice cuánto falta de forma aproximada, el número dice exactamente en qué
 * punto está. En una operación donde cada paso tiene consecuencias — cargó,
 * salió, entregó — la precisión importa más que la sensación.
 */
@Composable
fun BarraProgreso(
    paso: Int,
    total: Int,
    modifier: Modifier = Modifier,
    color: Color = PortGoColor.Teal,
) {
    Row(
        modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Box(
            Modifier
                .weight(1f)
                .height(5.dp)
                .clip(RoundedCornerShape(3.dp))
                .background(Color(0xFFECEADF))
                .semantics { contentDescription = "Paso $paso de $total" },
        ) {
            Box(
                Modifier
                    .fillMaxWidth(fraction = (paso.toFloat() / total).coerceIn(0f, 1f))
                    .height(5.dp)
                    .clip(RoundedCornerShape(3.dp))
                    .background(color),
            )
        }
        Text(
            "$paso/$total",
            style = MaterialTheme.typography.bodySmall,
            color = PortGoColor.TextoSecundario,
        )
    }
}

/**
 * Tarjeta blanca estándar, para las fichas de detalle.
 *
 * El handoff no especifica las pantallas de detalle, así que se extrapola con
 * el mismo sistema de las listas: blanco sobre arena, borde suave, radio 16 y
 * la misma sombra mínima. Mantener una sola forma de tarjeta en toda la app es
 * lo que hace que las pantallas nuevas se sientan del mismo producto sin tener
 * que diseñarlas una por una.
 */
@Composable
fun TarjetaFicha(
    modifier: Modifier = Modifier,
    contenido: @Composable ColumnScope.() -> Unit,
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Radio.tarjeta),
        colors = CardDefaults.cardColors(containerColor = PortGoColor.Superficie),
        border = BorderStroke(1.dp, PortGoColor.BordeTarjeta),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Column(Modifier.padding(15.dp), content = contenido)
    }
}

/**
 * Separador interno de una ficha, con su título de sección.
 *
 * Agrupa los datos en bloques con sentido en vez de dejar treinta filas
 * seguidas: en una ficha larga —un pedido trae hasta veinte campos— lo que
 * cansa no es la cantidad sino no poder saltar al bloque que se busca.
 */
@Composable
fun SeccionFicha(titulo: String, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth()) {
        Spacer(Modifier.height(12.dp))
        HorizontalDivider(thickness = 1.dp, color = PortGoColor.Divisor)
        Spacer(Modifier.height(10.dp))
        Text(
            titulo.uppercase(),
            style = MaterialTheme.typography.labelLarge,
            color = PortGoColor.TextoSecundario,
        )
        Spacer(Modifier.height(6.dp))
    }
}
