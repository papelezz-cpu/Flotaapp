package mx.portgo.app.ui.screens.solicitudes

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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
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
import mx.portgo.app.ui.components.ChipEstadoPedido
import mx.portgo.app.ui.components.EsqueletoLista
import mx.portgo.app.ui.components.EstadoVacio
import mx.portgo.app.ui.components.RecargarAlVolver
import mx.portgo.app.ui.theme.Espacio
import mx.portgo.app.ui.viewmodel.EstadoCarga
import mx.portgo.app.ui.viewmodel.SolicitudesViewModel
import mx.portgo.app.ui.viewmodel.vmFactory

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PantallaSolicitudes(
    usuario: UsuarioActual,
    container: AppContainer,
    onAbrir: (String) -> Unit,
    onNueva: () -> Unit,
) {
    val vm: SolicitudesViewModel = viewModel(
        factory = vmFactory { SolicitudesViewModel(container.pedidos, usuario) },
    )
    val estado by vm.estado.collectAsStateWithLifecycle()
    val pestana by vm.pestana.collectAsStateWithLifecycle()
    val filtro by vm.filtro.collectAsStateWithLifecycle()
    val refrescando by vm.refrescando.collectAsStateWithLifecycle()

    val listaEstado = rememberLazyListState()

    // Paginación infinita: se pide la siguiente página cuando faltan tres
    // elementos para el final, no al llegar, para que no se vea el salto.
    val cercaDelFinal by remember {
        derivedStateOf {
            val ultimo = listaEstado.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
            val total = listaEstado.layoutInfo.totalItemsCount
            total > 0 && ultimo >= total - 3
        }
    }
    androidx.compose.runtime.LaunchedEffect(cercaDelFinal) {
        if (cercaDelFinal) vm.cargarMas()
    }

    // Las solicitudes se publican y se aprueban desde la web, así que el
    // mercado cambia mientras la app está abierta.
    RecargarAlVolver(vm::cargar)

    Scaffold(
        floatingActionButton = {
            if (usuario.esCliente) {
                ExtendedFloatingActionButton(
                    onClick = onNueva,
                    icon = { Icon(Icons.Default.Add, contentDescription = null) },
                    text = { Text("Nueva solicitud") },
                )
            }
        },
    ) { relleno ->
        Column(Modifier.fillMaxSize().padding(relleno)) {

            if (usuario.esEmpresa) {
                TabRow(selectedTabIndex = pestana.ordinal) {
                    Tab(
                        selected = pestana == SolicitudesViewModel.Pestana.PRINCIPAL,
                        onClick = { vm.cambiarPestana(SolicitudesViewModel.Pestana.PRINCIPAL) },
                        text = { Text(vm.etiquetaPrincipal) },
                    )
                    Tab(
                        selected = pestana == SolicitudesViewModel.Pestana.MIS_OFERTAS,
                        onClick = { vm.cambiarPestana(SolicitudesViewModel.Pestana.MIS_OFERTAS) },
                        text = { Text("Mis ofertas") },
                    )
                }
            }

            if (vm.filtrosDisponibles.size > 1) {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState())
                        .padding(horizontal = Espacio.m, vertical = Espacio.s),
                    horizontalArrangement = Arrangement.spacedBy(Espacio.s),
                ) {
                    vm.filtrosDisponibles.forEach { est ->
                        FilterChip(
                            selected = filtro == est,
                            onClick = { vm.cambiarFiltro(est) },
                            label = { Text(est.etiqueta) },
                        )
                    }
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
                                titulo = if (usuario.esCliente) "Todavía no tienes solicitudes"
                                else "No hay solicitudes disponibles",
                                detalle = if (usuario.esCliente) {
                                    "Publica una y las empresas transportistas te enviarán sus ofertas."
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
                                    top = Espacio.s, bottom = 88.dp,
                                ),
                                verticalArrangement = Arrangement.spacedBy(Espacio.s),
                            ) {
                                items(visibles, key = { it.pedido.id }) { item ->
                                    TarjetaSolicitud(
                                        item = item,
                                        esCliente = usuario.esCliente,
                                        onClick = { onAbrir(item.pedido.id) },
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TarjetaSolicitud(
    item: PedidoConOfertas,
    esCliente: Boolean,
    onClick: () -> Unit,
) {
    val p = item.pedido

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
                Text(
                    p.tipoCamion ?: "Servicio",
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f),
                )
                ChipEstadoPedido(p.estadoEnum)
            }

            Spacer(Modifier.height(Espacio.xs))

            Text(
                p.ruta,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Spacer(Modifier.height(Espacio.s))

            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column {
                    Text(
                        "Carga · ${Fmt.rangoFechas(p.fechaIni, p.fechaFin)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    if (p.fechaArriboPuerto != null) {
                        Text(
                            "Arribo a puerto · ${Fmt.fecha(p.fechaArriboPuerto)}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }

                // Al cliente le importa cuántas ofertas tiene; a la empresa,
                // contra qué precio compite.
                if (esCliente) {
                    val vivas = item.ofertasVivas.size
                    if (vivas > 0) {
                        Text(
                            "$vivas oferta${if (vivas == 1) "" else "s"}",
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.primary,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                } else {
                    p.precioCliente?.let {
                        Text(
                            "Presupuesto ${Fmt.pesos(it)}",
                            style = MaterialTheme.typography.labelLarge,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                }
            }
        }
    }
}
