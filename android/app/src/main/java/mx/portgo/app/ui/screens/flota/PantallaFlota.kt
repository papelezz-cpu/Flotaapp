package mx.portgo.app.ui.screens.flota

import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Badge
import androidx.compose.material.icons.filled.LocalShipping
import androidx.compose.material.icons.filled.WarningAmber
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
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
import mx.portgo.app.ui.components.BotonHeader
import mx.portgo.app.ui.components.ChipEstado
import mx.portgo.app.ui.components.EncabezadoModulo
import mx.portgo.app.ui.components.EsqueletoLista
import mx.portgo.app.ui.components.EstadoVacio
import mx.portgo.app.ui.components.FilaFiltros
import mx.portgo.app.ui.components.RecargarAlVolver
import mx.portgo.app.ui.components.TarjetaFicha
import mx.portgo.app.ui.theme.ColoresEstado
import mx.portgo.app.ui.theme.Espacio
import mx.portgo.app.ui.theme.PortGoColor
import mx.portgo.app.ui.theme.SpaceGrotesk
import mx.portgo.app.ui.viewmodel.EstadoCarga
import mx.portgo.app.ui.viewmodel.FlotaViewModel
import mx.portgo.app.ui.viewmodel.vmFactory

private const val UNIDADES = "Unidades"
private const val CHOFERES = "Choferes"

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
    onAtras: (() -> Unit)? = null,
) {
    val vm: FlotaViewModel = viewModel(
        key = usuario.id,
        factory = vmFactory { FlotaViewModel(container.flota, usuario) },
    )
    val camiones by vm.camiones.collectAsStateWithLifecycle()
    val operadores by vm.operadores.collectAsStateWithLifecycle()
    val vigencias by vm.vigencias.collectAsStateWithLifecycle()
    val refrescando by vm.refrescando.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }

    var pestana by rememberSaveable { mutableStateOf(UNIDADES) }

    // Sacar una unidad de servicio puede fallar por RLS o por el guard de
    // flota. Un switch que se mueve y no guarda nada es peor que un error.
    LaunchedEffect(Unit) { vm.avisos.collect { snackbar.showSnackbar(it) } }

    // Las unidades también se dan de alta en la web y se aprueban desde el
    // panel, así que la flota cambia estando la app abierta. Sin esto, una
    // unidad recién aprobada no aparecía hasta deslizar para actualizar.
    RecargarAlVolver(vm::cargar)

    Scaffold(
        snackbarHost = { SnackbarHost(snackbar) },
        containerColor = PortGoColor.Arena,
    ) { relleno ->
        Column(
            Modifier
                .fillMaxSize()
                .background(PortGoColor.Arena)
                .padding(relleno),
        ) {
            // El alta va como acción del encabezado y no como FAB flotante: el
            // diseño ya tiene un FAB, el central de la barra inferior, y es su
            // elemento distintivo. Un segundo botón flotante en la esquina
            // competiría con él y además quedaría justo encima de la barra.
            EncabezadoModulo(
                titulo = "Flota",
                onAtras = onAtras,
                accion = {
                    if (pestana == UNIDADES) {
                        BotonHeader(Icons.Default.Add, "Registrar unidad", onNuevaUnidad)
                    }
                },
            )

            FilaFiltros(
                opciones = listOf(UNIDADES, CHOFERES),
                seleccionado = pestana,
                onSeleccionar = { pestana = it },
            )

            PullToRefreshBox(
                isRefreshing = refrescando,
                onRefresh = vm::refrescar,
                modifier = Modifier.fillMaxSize(),
            ) {
                if (pestana == UNIDADES) {
                    ListaRecursos(
                        estado = camiones,
                        vacioTitulo = "No tienes unidades registradas",
                        vacioDetalle = "Registra tu primera unidad desde aquí. Puedes " +
                            "fotografiar los documentos con la cámara.",
                        vacioIcono = Icons.Default.LocalShipping,
                        onReintentar = vm::cargar,
                        vacioAccion = {
                            Button(
                                onClick = onNuevaUnidad,
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = PortGoColor.Teal,
                                ),
                                shape = RoundedCornerShape(12.dp),
                            ) {
                                Icon(Icons.Default.Add, contentDescription = null)
                                Spacer(Modifier.width(Espacio.s))
                                Text("Registrar unidad")
                            }
                        },
                        encabezado = {
                            if (vigencias.isNotEmpty()) AvisoVigencias(vigencias)
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
                        vacioDetalle = "Los choferes se dan de alta desde el sitio web.",
                        vacioIcono = Icons.Default.Badge,
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
    vacioIcono: ImageVector,
    onReintentar: () -> Unit,
    vacioAccion: (@Composable () -> Unit)? = null,
    encabezado: @Composable (() -> Unit)? = null,
    fila: @Composable (T) -> Unit,
) {
    when (estado) {
        is EstadoCarga.Cargando -> EsqueletoLista(4)

        is EstadoCarga.Fallo -> BannerError(estado.mensaje, onReintentar = onReintentar)

        is EstadoCarga.Listo -> {
            if (estado.datos.isEmpty()) {
                EstadoVacio(vacioTitulo, vacioDetalle, vacioIcono, accion = vacioAccion)
            } else {
                LazyColumn(
                    contentPadding = PaddingValues(
                        start = Espacio.m, end = Espacio.m,
                        top = 2.dp, bottom = Espacio.l,
                    ),
                    verticalArrangement = Arrangement.spacedBy(Espacio.gapRejilla),
                ) {
                    if (encabezado != null) item { encabezado() }
                    items(estado.datos, key = { it.identificador }) { fila(it) }
                }
            }
        }
    }
}

/**
 * Aviso de documentos por vencer.
 *
 * Va arriba de la lista y no dentro de cada tarjeta porque es lo único de esta
 * pantalla con fecha límite: un permiso vencido saca la unidad de servicio, y
 * enterarse el día que pasa es enterarse tarde.
 */
@Composable
private fun AvisoVigencias(vigencias: List<Pair<Camion, Pair<String, Long>>>) {
    TarjetaFicha {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                Icons.Default.WarningAmber,
                contentDescription = null,
                tint = ColoresEstado.alerta,
                modifier = Modifier.size(18.dp),
            )
            Spacer(Modifier.width(Espacio.s))
            Text(
                "Documentos por vencer",
                style = MaterialTheme.typography.titleMedium,
                color = PortGoColor.Tinta,
            )
        }
        Spacer(Modifier.height(10.dp))
        HorizontalDivider(thickness = 1.dp, color = PortGoColor.Divisor)
        Spacer(Modifier.height(10.dp))

        vigencias.take(5).forEachIndexed { indice, (camion, venc) ->
            val (documento, dias) = venc
            if (indice > 0) Spacer(Modifier.height(6.dp))
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "${camion.id} · $documento",
                    style = MaterialTheme.typography.bodyMedium,
                    color = PortGoColor.Tinta,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    when {
                        dias < 0 -> "hace ${-dias} d"
                        dias == 0L -> "hoy"
                        else -> "en $dias d"
                    },
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    color = if (dias <= 0) ColoresEstado.peligro else ColoresEstado.alerta,
                )
            }
        }

        Spacer(Modifier.height(10.dp))
        Text(
            "Actualízalos desde el sitio web para no perder la unidad de servicio.",
            style = MaterialTheme.typography.bodySmall,
            color = PortGoColor.TextoSecundario,
        )
    }
}

@Composable
private fun TarjetaCamion(camion: Camion, onDisponibilidad: (Boolean) -> Unit) {
    TarjetaFicha {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.Top,
        ) {
            Column(Modifier.weight(1f)) {
                Text(
                    camion.etiqueta,
                    style = MaterialTheme.typography.titleMedium,
                    color = PortGoColor.Tinta,
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    listOfNotNull(camion.tipo, camion.placas).joinToString(" · "),
                    style = MaterialTheme.typography.bodyMedium,
                    color = PortGoColor.TextoSecundario,
                )
            }
            Spacer(Modifier.width(Espacio.s))
            ChipAprobacion(camion)
        }

        if (camion.rechazado && !camion.rechazoNota.isNullOrBlank()) {
            Spacer(Modifier.height(Espacio.s))
            Text(
                "Motivo: ${camion.rechazoNota}",
                style = MaterialTheme.typography.bodySmall,
                color = ColoresEstado.peligro,
                fontWeight = FontWeight.Medium,
            )
        }

        Spacer(Modifier.height(11.dp))
        HorizontalDivider(thickness = 1.dp, color = PortGoColor.Divisor)
        Spacer(Modifier.height(6.dp))

        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(
                    when {
                        camion.ocupado -> "En servicio"
                        camion.disponibilidad == "disponible" -> "Disponible"
                        else -> "Fuera de servicio"
                    },
                    style = MaterialTheme.typography.bodyMedium,
                    color = PortGoColor.TextoSecundario,
                )
                camion.precioDia?.let { precio ->
                    Fmt.precioDia(precio)?.let {
                        Text(
                            it,
                            fontFamily = SpaceGrotesk,
                            fontWeight = FontWeight.Bold,
                            style = MaterialTheme.typography.titleMedium,
                            color = PortGoColor.TealOscuro,
                        )
                    }
                }
            }
            // Una unidad ocupada no se puede sacar de servicio a mano: está
            // atada a una reservación en curso, y desconectarla dejaría el
            // servicio sin unidad asignada.
            Switch(
                checked = camion.disponibilidad == "disponible" || camion.ocupado,
                onCheckedChange = onDisponibilidad,
                enabled = camion.aprobado && !camion.ocupado,
                colors = SwitchDefaults.colors(
                    checkedThumbColor = PortGoColor.Superficie,
                    checkedTrackColor = PortGoColor.Teal,
                    checkedBorderColor = PortGoColor.Teal,
                ),
            )
        }
    }
}

@Composable
private fun TarjetaOperador(operador: Operador) {
    TarjetaFicha {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.Top,
        ) {
            Column(Modifier.weight(1f)) {
                Text(
                    operador.etiqueta,
                    style = MaterialTheme.typography.titleMedium,
                    color = PortGoColor.Tinta,
                )
                operador.subtitulo?.let {
                    Spacer(Modifier.height(4.dp))
                    Text(
                        it,
                        style = MaterialTheme.typography.bodyMedium,
                        color = PortGoColor.TextoSecundario,
                    )
                }
            }
            Spacer(Modifier.width(Espacio.s))
            ChipAprobacion(operador)
        }

        operador.venceLicencia?.let { fecha ->
            val dias = Fmt.diasHasta(fecha)
            Spacer(Modifier.height(11.dp))
            HorizontalDivider(thickness = 1.dp, color = PortGoColor.Divisor)
            Spacer(Modifier.height(10.dp))
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    "Licencia vence",
                    style = MaterialTheme.typography.bodyMedium,
                    color = PortGoColor.TextoSecundario,
                )
                Text(
                    Fmt.fecha(fecha),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    color = if (dias != null && dias <= 30) ColoresEstado.alerta
                    else PortGoColor.Tinta,
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
