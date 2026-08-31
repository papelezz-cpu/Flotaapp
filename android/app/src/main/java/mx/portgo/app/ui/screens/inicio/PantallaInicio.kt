package mx.portgo.app.ui.screens.inicio

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Assignment
import androidx.compose.material.icons.filled.AccountBalanceWallet
import androidx.compose.material.icons.filled.Apartment
import androidx.compose.material.icons.filled.Badge
import androidx.compose.material.icons.filled.EventAvailable
import androidx.compose.material.icons.filled.EventBusy
import androidx.compose.material.icons.filled.LocalShipping
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.di.AppContainer
import mx.portgo.app.ui.components.BannerError
import mx.portgo.app.ui.components.EsqueletoLista
import mx.portgo.app.ui.components.EtiquetaSeccion
import mx.portgo.app.ui.components.RecargarAlVolver
import mx.portgo.app.ui.components.TarjetaAcceso
import mx.portgo.app.ui.components.TarjetaStat
import mx.portgo.app.ui.navigation.Rutas
import mx.portgo.app.ui.theme.ColoresEstado
import mx.portgo.app.ui.theme.Espacio
import mx.portgo.app.ui.theme.PortGoColor
import mx.portgo.app.ui.viewmodel.EstadoCarga
import mx.portgo.app.ui.viewmodel.InicioViewModel
import mx.portgo.app.ui.viewmodel.vmFactory

/** Un acceso de la rejilla. */
private data class Acceso(
    val titulo: String,
    val descripcion: String,
    val icono: ImageVector,
    val ruta: String,
    val badge: Int? = null,
    val alerta: Boolean = false,
)

/**
 * Inicio: rejilla de accesos a los módulos.
 *
 * Sustituye a la versión anterior, que listaba "qué te toca hacer". El cambio
 * viene del diseño y resuelve un problema real: con la app creciendo hacia
 * paridad con la web, hacía falta un lugar donde vivan todos los módulos. Una
 * lista de pendientes no escala a doce secciones.
 *
 * Los badges conservan lo bueno de la versión anterior — se sigue viendo de un
 * vistazo qué espera por ti — pero ahora colgados de cada módulo.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PantallaInicio(
    usuario: UsuarioActual,
    container: AppContainer,
    onIrA: (String) -> Unit,
) {
    val vm: InicioViewModel = viewModel(
        key = usuario.id,
        factory = vmFactory {
            InicioViewModel(
                container.pedidos, container.reservaciones,
                container.flota, container.auth, usuario,
            )
        },
    )
    val estado by vm.estado.collectAsStateWithLifecycle()
    val refrescando by vm.refrescando.collectAsStateWithLifecycle()

    RecargarAlVolver(vm::cargar)

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
                val accesos = if (usuario.esCliente) accesosCliente(r) else accesosEmpresa(r)

                LazyVerticalGrid(
                    columns = GridCells.Fixed(2),
                    contentPadding = PaddingValues(
                        start = Espacio.m, end = Espacio.m, top = 2.dp, bottom = Espacio.m,
                    ),
                    horizontalArrangement = Arrangement.spacedBy(Espacio.gapRejilla),
                    verticalArrangement = Arrangement.spacedBy(Espacio.gapRejilla),
                ) {
                    // ── Saludo ──
                    item(span = { GridItemSpan(2) }) {
                        Column {
                            Text(
                                if (usuario.esCliente) "${vm.saludo}, ${vm.titulo} 👋" else vm.titulo,
                                style = if (usuario.esCliente) {
                                    MaterialTheme.typography.headlineMedium
                                } else {
                                    MaterialTheme.typography.headlineSmall
                                },
                                color = PortGoColor.Tinta,
                            )
                            Spacer(Modifier.height(3.dp))
                            Text(
                                if (usuario.esCliente) "¿Qué quieres mover hoy?"
                                else "Tu operación de hoy",
                                style = MaterialTheme.typography.bodyMedium,
                                color = PortGoColor.TextoSecundario,
                            )
                        }
                    }

                    // ── Indicadores (solo empresa) ──
                    if (usuario.esEmpresa) {
                        item(span = { GridItemSpan(2) }) {
                            Row(
                                Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(Espacio.s),
                            ) {
                                TarjetaStat(
                                    cifra = r.unidades.toString(),
                                    etiqueta = "Unidades",
                                    modifier = Modifier.weight(1f),
                                )
                                TarjetaStat(
                                    cifra = r.ofertasActivas.toString(),
                                    etiqueta = "Ofertas activas",
                                    colorCifra = ColoresEstado.alerta,
                                    modifier = Modifier.weight(1f),
                                )
                                TarjetaStat(
                                    // Sin calificaciones todavía se muestra un
                                    // guion, no "0.0": una empresa nueva no es
                                    // una empresa mal calificada.
                                    cifra = r.calificacion?.let { "★%.1f".format(it) } ?: "★ —",
                                    etiqueta = "Calificación",
                                    colorCifra = PortGoColor.Tinta,
                                    modifier = Modifier.weight(1f),
                                )
                            }
                        }
                    }

                    item(span = { GridItemSpan(2) }) {
                        EtiquetaSeccion(
                            if (usuario.esCliente) "Accesos rápidos" else "Gestión",
                        )
                    }

                    items(accesos) { a ->
                        TarjetaAcceso(
                            titulo = a.titulo,
                            descripcion = a.descripcion,
                            icono = a.icono,
                            badge = a.badge,
                            alerta = a.alerta,
                            onClick = { onIrA(a.ruta) },
                        )
                    }
                }
            }
        }
    }
}

private fun accesosCliente(r: InicioViewModel.Resumen) = listOf(
    Acceso(
        "Solicitar servicio", "Transporte, custodia y más",
        Icons.Default.LocalShipping, Rutas.NUEVA_SOLICITUD,
    ),
    Acceso(
        "Mis solicitudes", "Estado de tus pedidos",
        Icons.AutoMirrored.Filled.Assignment, Rutas.SOLICITUDES,
        badge = r.solicitudesPendientes,
    ),
    Acceso(
        "Catálogo", "Empresas verificadas",
        Icons.Default.Apartment, Rutas.CATALOGO,
    ),
    Acceso(
        "Reservaciones", "Tus reservas activas",
        Icons.Default.EventAvailable, Rutas.RESERVACIONES,
        badge = r.reservasActivas,
    ),
    Acceso(
        "Mis pagos", "Por pagar y pagados",
        Icons.Default.AccountBalanceWallet, Rutas.PAGOS,
    ),
    Acceso(
        "Privacidad", "Datos y derechos ARCO",
        Icons.Default.Shield, Rutas.PRIVACIDAD,
    ),
)

private fun accesosEmpresa(r: InicioViewModel.Resumen) = listOf(
    Acceso(
        "Solicitudes", "Pedidos para ofertar",
        Icons.AutoMirrored.Filled.Assignment, Rutas.SOLICITUDES,
        badge = r.solicitudesPendientes,
    ),
    Acceso(
        "Reservaciones", "Viajes activos",
        Icons.Default.EventAvailable, Rutas.RESERVACIONES,
        badge = r.reservasActivas,
    ),
    Acceso(
        "Mis unidades", "Flota de camiones",
        Icons.Default.LocalShipping, Rutas.FLOTA,
    ),
    Acceso(
        // Variante de alerta: un documento vencido deja la unidad parada, no
        // es un pendiente más.
        "Vigencias", "Documentos por vencer",
        Icons.Default.EventBusy, Rutas.VIGENCIAS,
        badge = r.vigenciasPorVencer, alerta = true,
    ),
    Acceso(
        "Operadores", "Personal de conducción",
        Icons.Default.Badge, Rutas.OPERADORES,
    ),
    Acceso(
        "Cobros", "Pagos y vencimientos",
        Icons.Default.Payments, Rutas.COBROS,
    ),
)
