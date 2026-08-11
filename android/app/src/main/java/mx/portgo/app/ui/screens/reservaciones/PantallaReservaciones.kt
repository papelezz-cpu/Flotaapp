package mx.portgo.app.ui.screens.reservaciones

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.automirrored.filled.EventNote
import androidx.compose.material.icons.filled.Description
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import mx.portgo.app.core.Fmt
import mx.portgo.app.data.model.EstadoReserva
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.di.AppContainer
import mx.portgo.app.ui.LocalCatalogos
import mx.portgo.app.ui.components.BannerError
import mx.portgo.app.ui.components.ChipEstadoReserva
import mx.portgo.app.ui.components.EsqueletoLista
import mx.portgo.app.ui.components.EstadoVacio
import mx.portgo.app.ui.theme.ColoresEstado
import mx.portgo.app.ui.theme.Espacio
import mx.portgo.app.ui.viewmodel.EstadoCarga
import mx.portgo.app.ui.viewmodel.FilaReservacion
import mx.portgo.app.ui.viewmodel.ReservacionesViewModel
import mx.portgo.app.ui.viewmodel.vmFactory

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PantallaReservaciones(
    usuario: UsuarioActual,
    container: AppContainer,
    onAbrir: (String) -> Unit,
) {
    val vm: ReservacionesViewModel = viewModel(
        factory = vmFactory {
            ReservacionesViewModel(container.reservaciones, container.chat, usuario)
        },
    )
    val estado by vm.estado.collectAsStateWithLifecycle()
    val filtro by vm.filtro.collectAsStateWithLifecycle()
    val refrescando by vm.refrescando.collectAsStateWithLifecycle()

    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = Espacio.m, vertical = Espacio.s),
            horizontalArrangement = Arrangement.spacedBy(Espacio.s),
        ) {
            vm.filtros.forEach { est ->
                FilterChip(
                    selected = filtro == est,
                    onClick = { vm.cambiarFiltro(est) },
                    label = { Text(est.etiqueta) },
                )
            }
        }

        PullToRefreshBox(
            isRefreshing = refrescando,
            onRefresh = vm::refrescar,
            modifier = Modifier.fillMaxSize(),
        ) {
            when (val e = estado) {
                is EstadoCarga.Cargando -> EsqueletoLista(4)

                is EstadoCarga.Fallo -> BannerError(e.mensaje, onReintentar = vm::cargar)

                is EstadoCarga.Listo -> {
                    val visibles = vm.visibles(e.datos)
                    if (visibles.isEmpty()) {
                        EstadoVacio(
                            titulo = "No hay servicios aquí",
                            detalle = if (usuario.esCliente) {
                                "Cuando se apruebe un acuerdo, el servicio aparecerá en esta lista."
                            } else {
                                "Cuando se apruebe un acuerdo de una de tus ofertas, aparecerá aquí."
                            },
                            icono = Icons.AutoMirrored.Filled.EventNote,
                        )
                    } else {
                        LazyColumn(
                            contentPadding = PaddingValues(
                                start = Espacio.m, end = Espacio.m,
                                top = Espacio.s, bottom = Espacio.l,
                            ),
                            verticalArrangement = Arrangement.spacedBy(Espacio.s),
                        ) {
                            items(visibles, key = { it.reservacion.id }) { fila ->
                                TarjetaReservacion(
                                    fila = fila,
                                    esCliente = usuario.esCliente,
                                    onClick = { onAbrir(fila.reservacion.id) },
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TarjetaReservacion(
    fila: FilaReservacion,
    esCliente: Boolean,
    onClick: () -> Unit,
) {
    val r = fila.reservacion
    val catalogos = LocalCatalogos.current
    val pasos = catalogos.pasos(r.recurso)
    val idx = r.pasoActual(catalogos)

    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f),
        ),
    ) {
        Column(Modifier.padding(Espacio.m)) {

            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top,
            ) {
                Column(Modifier.weight(1f)) {
                    Text(r.unidad ?: "Servicio", style = MaterialTheme.typography.titleMedium)
                    Text(
                        if (esCliente) r.recurso.etiqueta else (r.cliente ?: "Cliente"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                ChipEstadoReserva(r.estadoEnum)
            }

            Spacer(Modifier.height(Espacio.s))

            Text(
                Fmt.rangoFechas(r.fechaIni, r.fechaFin),
                style = MaterialTheme.typography.bodyMedium,
            )

            // Barra de avance del viaje. Solo tiene sentido mientras el
            // servicio corre; en una reserva cancelada sobra.
            if (r.estadoEnum == EstadoReserva.ACTIVA) {
                Spacer(Modifier.height(Espacio.s))
                LinearProgressIndicator(
                    progress = { (idx + 1f) / pasos.size },
                    modifier = Modifier.fillMaxWidth(),
                )
                Text(
                    pasos.getOrNull(idx)?.etiqueta ?: "",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = Espacio.xs),
                )
            }

            Spacer(Modifier.height(Espacio.s))

            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    Fmt.precioMxn(r.precioAcordado),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )

                Row(
                    horizontalArrangement = Arrangement.spacedBy(Espacio.m),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    // Expediente pendiente: al cliente le urge saberlo, es lo
                    // que traba el ingreso a puerto o dispara las demoras.
                    val pendientes = fila.expedientes.count { !it.completo }
                    if (pendientes > 0) {
                        Icon(
                            Icons.Default.Description,
                            contentDescription = "$pendientes expediente(s) pendiente(s)",
                            tint = ColoresEstado.alerta,
                            modifier = Modifier.size(20.dp),
                        )
                    }

                    if (fila.mensajesSinLeer > 0) {
                        BadgedBox(badge = { Badge { Text("${fila.mensajesSinLeer}") } }) {
                            Icon(
                                Icons.AutoMirrored.Filled.Chat,
                                contentDescription = "${fila.mensajesSinLeer} mensajes sin leer",
                                modifier = Modifier.size(20.dp),
                            )
                        }
                    }
                }
            }

            // Aviso de vacíos: las demoras se cobran por día, así que la fecha
            // límite se enseña desde la lista, no escondida en el detalle.
            fila.expedientes
                .firstOrNull { it.etapa == "entrega_vacios" && it.fechaLimiteVacios != null }
                ?.let { exp ->
                    val dias = exp.diasParaVacios
                    if (dias != null && dias <= 3) {
                        Spacer(Modifier.height(Espacio.xs))
                        Text(
                            when {
                                dias < 0 -> "⚠ Vacíos vencidos hace ${-dias} día(s): corren demoras"
                                dias == 0L -> "⚠ Hoy vence la devolución del contenedor"
                                else -> "Faltan $dias día(s) para devolver el contenedor"
                            },
                            style = MaterialTheme.typography.bodySmall,
                            color = if (dias <= 0) ColoresEstado.peligro else ColoresEstado.alerta,
                            fontWeight = FontWeight.Medium,
                        )
                    }
                }
        }
    }
}
