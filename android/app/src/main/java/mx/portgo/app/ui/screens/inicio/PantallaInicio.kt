package mx.portgo.app.ui.screens.inicio

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import mx.portgo.app.core.Fmt
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.di.AppContainer
import mx.portgo.app.ui.LocalCatalogos
import mx.portgo.app.ui.components.BannerError
import mx.portgo.app.ui.components.EsqueletoLista
import mx.portgo.app.ui.navigation.Rutas
import mx.portgo.app.ui.theme.ColoresEstado
import mx.portgo.app.ui.theme.Espacio
import mx.portgo.app.ui.viewmodel.EstadoCarga
import mx.portgo.app.ui.viewmodel.InicioViewModel
import mx.portgo.app.ui.viewmodel.vmFactory

/**
 * Pantalla de arranque.
 *
 * No es un tablero de indicadores: es la respuesta a "qué me toca hacer".
 * Primero lo que espera por ti, después lo que está en curso. Un despachador
 * abre esto entre dos maniobras, no para analizar su operación.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PantallaInicio(
    usuario: UsuarioActual,
    container: AppContainer,
    onIrA: (String) -> Unit,
    onAbrirSolicitud: (String) -> Unit,
    onAbrirReservacion: (String) -> Unit,
) {
    val vm: InicioViewModel = viewModel(
        factory = vmFactory {
            InicioViewModel(
                container.pedidos, container.reservaciones, container.configuracion, usuario,
            )
        },
    )
    val estado by vm.estado.collectAsStateWithLifecycle()
    val refrescando by vm.refrescando.collectAsStateWithLifecycle()

    PullToRefreshBox(
        isRefreshing = refrescando,
        onRefresh = vm::refrescar,
        modifier = Modifier.fillMaxSize(),
    ) {
        when (val e = estado) {
            is EstadoCarga.Cargando -> EsqueletoLista(3)

            is EstadoCarga.Fallo -> BannerError(e.mensaje, onReintentar = vm::cargar)

            is EstadoCarga.Listo -> {
                val r = e.datos

                LazyColumn(
                    contentPadding = PaddingValues(Espacio.m),
                    verticalArrangement = Arrangement.spacedBy(Espacio.s),
                ) {
                    item {
                        Text(
                            "Hola, ${usuario.nombre.substringBefore(' ')}",
                            style = MaterialTheme.typography.headlineSmall,
                        )
                        Spacer(Modifier.height(Espacio.s))
                    }

                    // ── Lo que espera por ti ──
                    if (r.pendientes.isNotEmpty()) {
                        item {
                            Text("Requiere tu atención", style = MaterialTheme.typography.titleMedium)
                            Spacer(Modifier.height(Espacio.xs))
                        }
                        items(r.pendientes) { p ->
                            Card(
                                onClick = {
                                    when (val d = p.destino) {
                                        is InicioViewModel.Destino.Solicitud -> onAbrirSolicitud(d.id)
                                        is InicioViewModel.Destino.Servicio -> onAbrirReservacion(d.id)
                                        is InicioViewModel.Destino.Seccion -> onIrA(d.ruta)
                                    }
                                },
                                modifier = Modifier.fillMaxWidth(),
                                colors = CardDefaults.cardColors(
                                    containerColor = MaterialTheme.colorScheme.tertiaryContainer
                                        .copy(alpha = 0.45f),
                                ),
                            ) {
                                Row(
                                    Modifier.padding(Espacio.m),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Column(Modifier.weight(1f)) {
                                        Text(
                                            p.titulo,
                                            style = MaterialTheme.typography.titleMedium,
                                            fontWeight = FontWeight.SemiBold,
                                        )
                                        Text(
                                            p.detalle,
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                    Icon(
                                        Icons.AutoMirrored.Filled.KeyboardArrowRight,
                                        contentDescription = null,
                                    )
                                }
                            }
                        }
                        item { Spacer(Modifier.height(Espacio.m)) }
                    } else {
                        item {
                            Card(
                                Modifier.fillMaxWidth(),
                                colors = CardDefaults.cardColors(
                                    containerColor = MaterialTheme.colorScheme.surfaceVariant
                                        .copy(alpha = 0.35f),
                                ),
                            ) {
                                Row(
                                    Modifier.padding(Espacio.m),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Icon(
                                        Icons.Default.CheckCircle,
                                        contentDescription = null,
                                        tint = ColoresEstado.exito,
                                    )
                                    Spacer(Modifier.height(Espacio.s))
                                    Text(
                                        "  Nada pendiente por ahora.",
                                        style = MaterialTheme.typography.bodyLarge,
                                    )
                                }
                            }
                            Spacer(Modifier.height(Espacio.m))
                        }
                    }

                    // ── Viajes en curso ──
                    if (r.serviciosActivos.isNotEmpty()) {
                        item {
                            Text("Servicios en curso", style = MaterialTheme.typography.titleMedium)
                            Spacer(Modifier.height(Espacio.xs))
                        }
                        items(r.serviciosActivos, key = { it.id }) { res ->
                            val catalogos = LocalCatalogos.current
                            val pasos = catalogos.pasos(res.recurso)
                            val idx = res.pasoActual(catalogos)
                            Card(
                                onClick = { onAbrirReservacion(res.id) },
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Column(Modifier.padding(Espacio.m)) {
                                    Text(
                                        res.unidad ?: "Servicio",
                                        style = MaterialTheme.typography.titleMedium,
                                    )
                                    Text(
                                        if (usuario.esCliente) Fmt.rangoFechas(res.fechaIni, res.fechaFin)
                                        else (res.cliente ?: ""),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                    Spacer(Modifier.height(Espacio.s))
                                    LinearProgressIndicator(
                                        progress = { (idx + 1f) / pasos.size },
                                        modifier = Modifier.fillMaxWidth(),
                                    )
                                    Text(
                                        pasos.getOrNull(idx)?.etiqueta ?: "",
                                        style = MaterialTheme.typography.bodySmall,
                                        modifier = Modifier.padding(top = Espacio.xs),
                                    )
                                }
                            }
                        }
                        item { Spacer(Modifier.height(Espacio.m)) }
                    }

                    // ── Atajo al mercado ──
                    item {
                        Card(
                            onClick = { onIrA(Rutas.SOLICITUDES) },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Row(
                                Modifier.padding(Espacio.m),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Column(Modifier.weight(1f)) {
                                    Text(
                                        if (usuario.esCliente) "Mis solicitudes"
                                        else "Solicitudes disponibles",
                                        style = MaterialTheme.typography.titleMedium,
                                    )
                                    Text(
                                        if (usuario.esCliente) {
                                            "${r.solicitudesAbiertas} recibiendo ofertas"
                                        } else {
                                            "${r.solicitudesAbiertas} esperando oferta"
                                        },
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                Icon(
                                    Icons.AutoMirrored.Filled.KeyboardArrowRight,
                                    contentDescription = null,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
