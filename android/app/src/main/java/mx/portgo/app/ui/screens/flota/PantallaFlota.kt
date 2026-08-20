package mx.portgo.app.ui.screens.flota

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.LocalShipping
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import mx.portgo.app.core.Fmt
import mx.portgo.app.data.model.Camion
import mx.portgo.app.data.model.Operador
import mx.portgo.app.data.model.RecursoFlota
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.di.AppContainer
import mx.portgo.app.ui.components.BannerError
import mx.portgo.app.ui.components.ChipEstado
import mx.portgo.app.ui.components.EsqueletoLista
import mx.portgo.app.ui.components.EstadoVacio
import mx.portgo.app.ui.components.RecargarAlVolver
import mx.portgo.app.ui.theme.ColoresEstado
import mx.portgo.app.ui.theme.Espacio
import mx.portgo.app.ui.viewmodel.EstadoCarga
import mx.portgo.app.ui.viewmodel.FlotaViewModel
import mx.portgo.app.ui.viewmodel.vmFactory

/**
 * Flota de la empresa: consulta, disponibilidad y alta.
 *
 * El alta se hacía solo desde la web con el argumento de que es un trámite de
 * escritorio. Era un mal argumento: quien recibe una unidad nueva está en el
 * patio, junto al camión, sin computadora. Ahora se registra desde aquí, y con
 * la cámara del teléfono resulta más cómodo que en la web — la tarjeta de
 * circulación se fotografía en el momento en vez de buscar un escaneo.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PantallaFlota(
    usuario: UsuarioActual,
    container: AppContainer,
    onNuevaUnidad: () -> Unit = {},
) {
    val vm: FlotaViewModel = viewModel(
        factory = vmFactory { FlotaViewModel(container.flota, usuario) },
    )
    val camiones by vm.camiones.collectAsStateWithLifecycle()
    val operadores by vm.operadores.collectAsStateWithLifecycle()
    val vigencias by vm.vigencias.collectAsStateWithLifecycle()
    val refrescando by vm.refrescando.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }

    var pestana by rememberSaveable { mutableIntStateOf(0) }

    // Sacar una unidad de servicio puede fallar por RLS o por el guard de
    // flota. Un switch que se mueve y no guarda nada es peor que un error.
    LaunchedEffect(Unit) { vm.avisos.collect { snackbar.showSnackbar(it) } }

    // Las unidades se dan de alta en la web y se aprueban desde el panel, así
    // que la flota cambia estando la app abierta. Sin esto, una unidad recién
    // aprobada no aparecía hasta deslizar para actualizar.
    RecargarAlVolver(vm::cargar)

    Scaffold(
        snackbarHost = { SnackbarHost(snackbar) },
        floatingActionButton = {
            // Solo en la pestana de unidades: el alta de choferes es otro
            // formulario y mezclar los dos botones confunde.
            if (pestana == 0) {
                ExtendedFloatingActionButton(
                    onClick = onNuevaUnidad,
                    icon = { Icon(Icons.Default.Add, contentDescription = null) },
                    text = { Text("Nueva unidad") },
                )
            }
        },
    ) { relleno ->
        Column(Modifier.fillMaxSize().padding(relleno)) {
            TabRow(selectedTabIndex = pestana) {
                Tab(pestana == 0, { pestana = 0 }, text = { Text("Unidades") })
                Tab(pestana == 1, { pestana = 1 }, text = { Text("Choferes") })
            }

            PullToRefreshBox(
                isRefreshing = refrescando,
                onRefresh = vm::refrescar,
                modifier = Modifier.fillMaxSize(),
            ) {
                if (pestana == 0) {
                    ListaRecursos(
                        estado = camiones,
                        vacioTitulo = "No tienes unidades registradas",
                        vacioDetalle = "Registra tu primera unidad desde aquí. Puedes " +
                            "fotografiar los documentos con la cámara.",
                        onReintentar = vm::cargar,
                        encabezado = {
                            if (vigencias.isNotEmpty()) {
                                AvisoVigencias(vigencias)
                            }
                        },
                    ) { camion ->
                        TarjetaCamion(
                            camion = camion,
                            onDisponibilidad = { disponible ->
                                vm.cambiarDisponibilidad(camion.id, disponible)
                            },
                        )
                    }
                } else {
                    ListaRecursos(
                        estado = operadores,
                        vacioTitulo = "No tienes choferes registrados",
                        vacioDetalle = "Los choferes se dan de alta desde el sitio web.",  // TODO: alta de operador
                        onReintentar = vm::cargar,
                    ) { operador ->
                        TarjetaOperador(operador)
                    }
                }
            }
        }
    }
}

@Composable
private fun <T : RecursoFlota> ListaRecursos(
    estado: EstadoCarga<List<T>>,
    vacioTitulo: String,
    vacioDetalle: String,
    onReintentar: () -> Unit,
    encabezado: @Composable (() -> Unit)? = null,
    fila: @Composable (T) -> Unit,
) {
    when (estado) {
        is EstadoCarga.Cargando -> EsqueletoLista(4)

        is EstadoCarga.Fallo -> BannerError(estado.mensaje, onReintentar = onReintentar)

        is EstadoCarga.Listo -> {
            if (estado.datos.isEmpty()) {
                EstadoVacio(vacioTitulo, vacioDetalle, Icons.Default.LocalShipping)
            } else {
                LazyColumn(
                    contentPadding = PaddingValues(Espacio.m),
                    verticalArrangement = Arrangement.spacedBy(Espacio.s),
                ) {
                    if (encabezado != null) {
                        item { encabezado(); Spacer(Modifier.height(Espacio.s)) }
                    }
                    items(estado.datos, key = { it.identificador }) { fila(it) }
                }
            }
        }
    }
}

@Composable
private fun AvisoVigencias(vigencias: List<Pair<Camion, Pair<String, Long>>>) {
    Card(
        Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.5f),
        ),
    ) {
        Column(Modifier.padding(Espacio.m)) {
            Text("Documentos por vencer", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(Espacio.xs))
            vigencias.take(5).forEach { (camion, venc) ->
                val (documento, dias) = venc
                Text(
                    when {
                        dias < 0 -> "${camion.id} · $documento venció hace ${-dias} día(s)"
                        dias == 0L -> "${camion.id} · $documento vence hoy"
                        else -> "${camion.id} · $documento vence en $dias día(s)"
                    },
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
            Text(
                "Actualízalos desde el sitio web para no perder la unidad de servicio.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = Espacio.xs),
            )
        }
    }
}

@Composable
private fun TarjetaCamion(camion: Camion, onDisponibilidad: (Boolean) -> Unit) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(Espacio.m)) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top,
            ) {
                Column(Modifier.weight(1f)) {
                    Text(camion.etiqueta, style = MaterialTheme.typography.titleMedium)
                    Text(
                        listOfNotNull(camion.tipo, camion.placas).joinToString(" · "),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                ChipAprobacion(camion)
            }

            camion.precioDia?.let {
                Text(
                    Fmt.precioDia(it) ?: "",
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(top = Espacio.xs),
                )
            }

            if (camion.rechazado && !camion.rechazoNota.isNullOrBlank()) {
                Text(
                    "Motivo: ${camion.rechazoNota}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }

            Spacer(Modifier.height(Espacio.s))

            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    when {
                        camion.ocupado -> "En servicio"
                        camion.disponibilidad == "disponible" -> "Disponible"
                        else -> "Fuera de servicio"
                    },
                    style = MaterialTheme.typography.bodyMedium,
                )
                // Una unidad ocupada no se puede sacar de servicio a mano: está
                // atada a una reservación en curso, y desconectarla dejaría el
                // servicio sin unidad asignada.
                Switch(
                    checked = camion.disponibilidad == "disponible" || camion.ocupado,
                    onCheckedChange = onDisponibilidad,
                    enabled = camion.aprobado && !camion.ocupado,
                )
            }
        }
    }
}

@Composable
private fun TarjetaOperador(operador: Operador) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(Espacio.m)) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top,
            ) {
                Column(Modifier.weight(1f)) {
                    Text(operador.etiqueta, style = MaterialTheme.typography.titleMedium)
                    operador.subtitulo?.let {
                        Text(
                            it,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                ChipAprobacion(operador)
            }

            operador.venceLicencia?.let { fecha ->
                val dias = Fmt.diasHasta(fecha)
                Text(
                    "Licencia vence ${Fmt.fecha(fecha)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = if (dias != null && dias <= 30) ColoresEstado.alerta
                    else MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = Espacio.xs),
                )
            }
        }
    }
}

@Composable
private fun ChipAprobacion(recurso: RecursoFlota) {
    val (texto, color, fondo) = when {
        recurso.aprobado -> Triple("Aprobado", ColoresEstado.exito, ColoresEstado.exitoSuave)
        recurso.enRevision -> Triple("En revisión", ColoresEstado.alerta, ColoresEstado.alertaSuave)
        recurso.rechazado -> Triple("Rechazado", ColoresEstado.peligro, ColoresEstado.peligroSuave)
        else -> Triple("—", ColoresEstado.neutro, ColoresEstado.neutroSuave)
    }
    ChipEstado(texto, color, fondo)
}
