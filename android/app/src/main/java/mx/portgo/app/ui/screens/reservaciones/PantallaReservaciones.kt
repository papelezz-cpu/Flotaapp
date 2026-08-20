package mx.portgo.app.ui.screens.reservaciones

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.EventAvailable
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
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
import mx.portgo.app.data.model.EstadoCobro
import mx.portgo.app.data.model.EstadoReserva
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.di.AppContainer
import mx.portgo.app.ui.LocalCatalogos
import mx.portgo.app.ui.components.BadgeConteo
import mx.portgo.app.ui.components.BannerError
import mx.portgo.app.ui.components.BarraProgreso
import mx.portgo.app.ui.components.ChipEstado
import mx.portgo.app.ui.components.EncabezadoModulo
import mx.portgo.app.ui.components.EsqueletoLista
import mx.portgo.app.ui.components.EstadoVacio
import mx.portgo.app.ui.components.FilaFiltros
import mx.portgo.app.ui.components.RecargarAlVolver
import mx.portgo.app.ui.components.TarjetaLista
import mx.portgo.app.ui.theme.ColoresEstado
import mx.portgo.app.ui.theme.Espacio
import mx.portgo.app.ui.theme.PortGoColor
import mx.portgo.app.ui.theme.SpaceGrotesk
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
    onAtras: (() -> Unit)?,
    noLeidas: Int,
    onCampana: () -> Unit,
) {
    val vm: ReservacionesViewModel = viewModel(
        factory = vmFactory {
            ReservacionesViewModel(
                container.reservaciones, container.chat, container.auth, usuario,
            )
        },
    )
    val estado by vm.estado.collectAsStateWithLifecycle()
    val filtro by vm.filtroTexto.collectAsStateWithLifecycle()
    val refrescando by vm.refrescando.collectAsStateWithLifecycle()

    // El superadmin aprueba acuerdos y cierres desde la web: un servicio puede
    // aparecer o cambiar de estado con la app abierta.
    RecargarAlVolver(vm::cargar)

    Column(
        Modifier
            .fillMaxSize()
            .background(PortGoColor.Arena),
    ) {
        EncabezadoModulo(titulo = "Reservas", onAtras = onAtras)

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
                            titulo = "No hay servicios aquí",
                            detalle = if (usuario.esCliente) {
                                "Cuando se apruebe un acuerdo, el servicio aparecerá en esta lista."
                            } else {
                                "Cuando se apruebe un acuerdo de una de tus ofertas, aparecerá aquí."
                            },
                            icono = Icons.Default.EventAvailable,
                        )
                    } else {
                        LazyColumn(
                            contentPadding = PaddingValues(
                                start = Espacio.m, end = Espacio.m,
                                top = 2.dp, bottom = Espacio.l,
                            ),
                            verticalArrangement = Arrangement.spacedBy(Espacio.gapRejilla),
                        ) {
                            items(visibles, key = { it.reservacion.id }) { fila ->
                                TarjetaReservacion(fila, usuario.esCliente) {
                                    onAbrir(fila.reservacion.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/**
 * Tarjeta de servicio.
 *
 * El bloque de progreso solo aparece mientras el viaje corre. En una reserva
 * completada la barra al 100% no informa de nada —ya se sabe que terminó— y en
 * su lugar va lo que sí queda pendiente de saber: si ya se calificó.
 */
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
    val enCurso = r.estadoEnum == EstadoReserva.ACTIVA || r.estadoEnum == EstadoReserva.PENDIENTE

    TarjetaLista(
        titulo = listOfNotNull(r.recurso.etiqueta, r.unidad).joinToString(" · "),
        subtitulo = null,
        meta = listOfNotNull(fila.contraparte, r.descripcion?.takeIf { it.isNotBlank() })
            .joinToString(" · ").takeIf { it.isNotBlank() },
        onClick = onClick,
        chip = { ChipEstadoReservaDiseno(r.estadoEnum) },
        extra = if (enCurso) {
            {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    ChipEstado(
                        pasos.getOrNull(idx)?.etiqueta ?: "—",
                        if (r.estadoEnum == EstadoReserva.ACTIVA) PortGoColor.TealOscuro
                        else ColoresEstado.alerta,
                        if (r.estadoEnum == EstadoReserva.ACTIVA) PortGoColor.TealTenue
                        else ColoresEstado.alertaSuave,
                    )
                    Spacer(Modifier.width(Espacio.s))
                    BarraProgreso(
                        paso = idx + 1,
                        total = pasos.size,
                        color = if (r.estadoEnum == EstadoReserva.ACTIVA) PortGoColor.Teal
                        else ColoresEstado.alerta,
                    )
                }
            }
        } else if (r.estadoEnum == EstadoReserva.COMPLETADA) {
            {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Default.Star,
                        contentDescription = null,
                        tint = if (r.calificado) ColoresEstado.alerta else PortGoColor.TextoTerciario,
                        modifier = Modifier.size(15.dp),
                    )
                    Spacer(Modifier.width(5.dp))
                    Text(
                        if (r.calificado) "Calificado" else "Sin calificar",
                        style = MaterialTheme.typography.bodyMedium,
                        color = PortGoColor.TextoSecundario,
                    )
                    Spacer(Modifier.weight(1f))
                    IndicadoresFila(fila)
                }
            }
        } else null,
        etiquetaPie = Fmt.rangoFechas(r.fechaIni, r.fechaFin),
        pie = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (enCurso) {
                    IndicadoresFila(fila)
                    Spacer(Modifier.width(Espacio.s))
                }
                Text(
                    Fmt.precioMxn(r.precioAcordado),
                    fontFamily = SpaceGrotesk,
                    fontWeight = FontWeight.Bold,
                    style = MaterialTheme.typography.titleMedium,
                    color = if (r.estadoCobro == EstadoCobro.VENCIDO) ColoresEstado.peligro
                    else PortGoColor.TealOscuro,
                )
            }
        },
    )
}

/**
 * Avisos de la fila: mensajes sin leer y expedientes pendientes.
 *
 * Van juntos y pequeños porque son secundarios al estado del viaje, pero el de
 * expediente importa: es lo que traba el ingreso a puerto o dispara las
 * demoras del contenedor.
 */
@Composable
private fun IndicadoresFila(fila: FilaReservacion) {
    val pendientes = fila.expedientes.count { !it.completo }

    Row(verticalAlignment = Alignment.CenterVertically) {
        if (pendientes > 0) {
            Icon(
                Icons.Default.Description,
                contentDescription = "$pendientes expediente(s) pendiente(s)",
                tint = ColoresEstado.alerta,
                modifier = Modifier.size(17.dp),
            )
            Spacer(Modifier.width(6.dp))
        }
        if (fila.mensajesSinLeer > 0) {
            Icon(
                Icons.AutoMirrored.Filled.Chat,
                contentDescription = null,
                tint = PortGoColor.TextoSecundario,
                modifier = Modifier.size(17.dp),
            )
            Spacer(Modifier.width(3.dp))
            BadgeConteo(fila.mensajesSinLeer)
        }
    }
}

/** Chip de estado con la paleta del diseño. */
@Composable
private fun ChipEstadoReservaDiseno(estado: EstadoReserva) {
    val (color, fondo) = when (estado) {
        EstadoReserva.ACTIVA -> ColoresEstado.exito to ColoresEstado.exitoSuave
        EstadoReserva.PENDIENTE,
        EstadoReserva.POR_APROBAR,
        EstadoReserva.CANCELACION_SOLICITADA,
        -> ColoresEstado.alerta to ColoresEstado.alertaSuave
        EstadoReserva.COMPLETADA -> PortGoColor.TealOscuro to PortGoColor.TealTenue
        EstadoReserva.CANCELADA,
        EstadoReserva.RECHAZADA,
        -> ColoresEstado.peligro to ColoresEstado.peligroSuave
        EstadoReserva.DESCONOCIDO -> ColoresEstado.neutro to ColoresEstado.neutroSuave
    }
    ChipEstado(estado.etiqueta, color, fondo)
}
