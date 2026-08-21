package mx.portgo.app.ui.screens.solicitudes

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import mx.portgo.app.core.Fmt
import mx.portgo.app.data.model.PedidoConOfertas
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.di.AppContainer
import mx.portgo.app.ui.components.BannerError
import mx.portgo.app.ui.components.BotonHeader
import mx.portgo.app.ui.components.ChipEstado
import mx.portgo.app.ui.components.EncabezadoModulo
import mx.portgo.app.ui.components.EsqueletoLista
import mx.portgo.app.ui.components.EstadoVacio
import mx.portgo.app.ui.components.FilaFiltros
import mx.portgo.app.ui.components.TarjetaLista
import mx.portgo.app.ui.theme.ColoresEstado
import mx.portgo.app.ui.theme.Espacio
import mx.portgo.app.ui.theme.PortGoColor
import mx.portgo.app.ui.theme.SpaceGrotesk
import mx.portgo.app.ui.viewmodel.EstadoCarga
import mx.portgo.app.ui.viewmodel.SolicitudesViewModel
import mx.portgo.app.ui.viewmodel.vmFactory

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PantallaSolicitudes(
    usuario: UsuarioActual,
    container: AppContainer,
    onAbrir: (String) -> Unit,
    onAtras: (() -> Unit)?,
    noLeidas: Int,
    onCampana: () -> Unit,
) {
    val vm: SolicitudesViewModel = viewModel(
        key = usuario.id,
        factory = vmFactory { SolicitudesViewModel(container.pedidos, usuario) },
    )
    val estado by vm.estado.collectAsStateWithLifecycle()
    val filtro by vm.filtroTexto.collectAsStateWithLifecycle()
    val refrescando by vm.refrescando.collectAsStateWithLifecycle()

    val listaEstado = rememberLazyListState()

    // Paginación infinita: se pide la siguiente página tres elementos antes del
    // final, para que no se vea el salto.
    val cercaDelFinal by remember {
        derivedStateOf {
            val ultimo = listaEstado.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
            val total = listaEstado.layoutInfo.totalItemsCount
            total > 0 && ultimo >= total - 3
        }
    }
    LaunchedEffect(cercaDelFinal) { if (cercaDelFinal) vm.cargarMas() }

    Column(
        Modifier
            .fillMaxSize()
            .background(PortGoColor.Arena),
    ) {
        EncabezadoModulo(
            titulo = "Solicitudes",
            onAtras = onAtras,
            noLeidas = noLeidas,
            onCampana = onCampana,
            accion = {
                BotonHeader(
                    icono = Icons.Default.Tune,
                    descripcion = "Filtrar solicitudes",
                    onClick = { /* la fila de filtros ya está visible */ },
                )
            },
        )

        FilaFiltros(
            opciones = vm.filtrosDisponibles,
            seleccionado = filtro,
            onSeleccionar = vm::cambiarFiltro,
        )

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
                            titulo = if (usuario.esCliente) "Todavía no tienes solicitudes"
                            else "No hay solicitudes disponibles",
                            detalle = if (usuario.esCliente) {
                                "Publica una con el botón + y las empresas te enviarán sus ofertas."
                            } else {
                                "Cuando se publique una solicitud que puedas atender, aparecerá aquí."
                            },
                            icono = Icons.Default.Inbox,
                        )
                    } else {
                        LazyColumn(
                            state = listaEstado,
                            contentPadding = PaddingValues(
                                start = Espacio.m, end = Espacio.m,
                                top = 2.dp, bottom = Espacio.l,
                            ),
                            verticalArrangement = Arrangement.spacedBy(Espacio.gapRejilla),
                        ) {
                            items(visibles, key = { it.pedido.id }) { item ->
                                TarjetaSolicitud(item, usuario.esCliente) { onAbrir(item.pedido.id) }
                            }
                        }
                    }
                }
            }
        }
    }
}

/**
 * Tarjeta de solicitud.
 *
 * El pie cambia según lo que importa en cada momento del ciclo: mientras
 * recibe ofertas, la mejor oferta; ya acordada, con quién; en revisión, que
 * está esperando. Es la información por la que uno abriría la tarjeta, puesta
 * antes de abrirla.
 */
@Composable
private fun TarjetaSolicitud(
    item: PedidoConOfertas,
    esCliente: Boolean,
    onClick: () -> Unit,
) {
    val p = item.pedido
    val vivas = item.ofertasVivas.size
    val aceptada = item.ofertaAceptada

    // El chip prioriza las ofertas vivas sobre el estado: para el cliente,
    // "3 ofertas" es más accionable que "en negociación".
    val chip: @Composable () -> Unit = when {
        esCliente && vivas > 0 && p.estadoEnum.admiteOfertas -> {
            {
                ChipEstado(
                    "$vivas oferta${if (vivas == 1) "" else "s"}",
                    PortGoColor.TealOscuro, PortGoColor.TealTenue,
                )
            }
        }
        else -> {
            { ChipEstadoPedidoDiseno(p.estadoEnum) }
        }
    }

    val (etiquetaPie, contenidoPie) = when {
        esCliente && item.mejorPrecio != null && p.estadoEnum.admiteOfertas ->
            "Mejor oferta" to @Composable {
                Text(
                    Fmt.precioMxn(item.mejorPrecio),
                    fontFamily = SpaceGrotesk,
                    fontWeight = FontWeight.Bold,
                    style = MaterialTheme.typography.titleMedium,
                    color = PortGoColor.TealOscuro,
                )
            }

        aceptada != null ->
            "Acordado con" to @Composable {
                Text(
                    aceptada.adminNombre ?: "—",
                    style = MaterialTheme.typography.titleMedium,
                    color = PortGoColor.Tinta,
                )
            }

        p.estadoEnum == mx.portgo.app.data.model.EstadoPedido.PENDIENTE_REVISION ->
            "Publicado" to @Composable {
                Text(
                    "Esperando aprobación",
                    style = MaterialTheme.typography.titleMedium,
                    color = PortGoColor.Tinta,
                )
            }

        !esCliente && p.precioCliente != null ->
            "Presupuesto" to @Composable {
                Text(
                    Fmt.precioMxn(p.precioCliente),
                    fontFamily = SpaceGrotesk,
                    fontWeight = FontWeight.Bold,
                    style = MaterialTheme.typography.titleMedium,
                    color = PortGoColor.TealOscuro,
                )
            }

        else -> null to null
    }

    TarjetaLista(
        titulo = p.tipoCamion ?: "Servicio",
        subtitulo = p.ruta.takeIf { it != "—" },
        meta = listOfNotNull(
            p.tipoCamionSugerido ?: p.tipoCamion,
            p.fechaIni?.let { "Sale el ${Fmt.fecha(it)}" },
            p.tipoCarga ?: p.categoriaCarga,
        ).joinToString(" · ").takeIf { it.isNotBlank() },
        onClick = onClick,
        chip = chip,
        etiquetaPie = etiquetaPie,
        pie = contenidoPie,
    )
}

/** Chip de estado con la paleta del diseño. */
@Composable
private fun ChipEstadoPedidoDiseno(estado: mx.portgo.app.data.model.EstadoPedido) {
    val (color, fondo) = when (estado) {
        mx.portgo.app.data.model.EstadoPedido.ABIERTO,
        mx.portgo.app.data.model.EstadoPedido.EN_NEGOCIACION,
        -> PortGoColor.TealOscuro to PortGoColor.TealTenue

        mx.portgo.app.data.model.EstadoPedido.PENDIENTE_REVISION,
        mx.portgo.app.data.model.EstadoPedido.PENDIENTE_ACUERDO,
        -> ColoresEstado.alerta to ColoresEstado.alertaSuave

        mx.portgo.app.data.model.EstadoPedido.ACORDADO,
        -> ColoresEstado.peligro to ColoresEstado.peligroSuave

        mx.portgo.app.data.model.EstadoPedido.FINALIZADO,
        -> ColoresEstado.exito to ColoresEstado.exitoSuave

        else -> ColoresEstado.neutro to ColoresEstado.neutroSuave
    }
    ChipEstado(estado.etiqueta, color, fondo)
}
