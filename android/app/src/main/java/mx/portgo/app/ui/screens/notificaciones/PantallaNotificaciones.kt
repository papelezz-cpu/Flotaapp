package mx.portgo.app.ui.screens.notificaciones

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.NotificationsNone
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import mx.portgo.app.core.Fmt
import mx.portgo.app.data.model.DestinoNotificacion
import mx.portgo.app.data.model.Notificacion
import mx.portgo.app.ui.components.BannerError
import mx.portgo.app.ui.components.BotonHeader
import mx.portgo.app.ui.components.EncabezadoModulo
import mx.portgo.app.ui.components.EsqueletoLista
import mx.portgo.app.ui.components.EstadoVacio
import mx.portgo.app.ui.navigation.Rutas
import mx.portgo.app.ui.theme.Espacio
import mx.portgo.app.ui.theme.PortGoColor
import mx.portgo.app.ui.theme.Radio
import mx.portgo.app.ui.viewmodel.EstadoCarga
import mx.portgo.app.ui.viewmodel.NotificacionesViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PantallaNotificaciones(
    vm: NotificacionesViewModel,
    onAtras: () -> Unit,
    onNavegar: (String) -> Unit,
) {
    val estado by vm.lista.collectAsStateWithLifecycle()

    // Al abrir se dan por vistas: se apaga el contador, pero la lista NO se
    // redibuja, así el usuario todavía distingue cuáles eran nuevas.
    LaunchedEffect(Unit) { vm.marcarTodasVistas() }

    Scaffold(containerColor = PortGoColor.Arena) { relleno ->
        Column(
            Modifier
                .fillMaxSize()
                .background(PortGoColor.Arena)
                .padding(relleno),
        ) {
            EncabezadoModulo(
                titulo = "Notificaciones",
                onAtras = onAtras,
                accion = {
                    BotonHeader(Icons.Default.Refresh, "Actualizar", onClick = { vm.cargar() })
                },
            )

            Box(Modifier.fillMaxSize()) {
                when (val e = estado) {
                    is EstadoCarga.Cargando -> EsqueletoLista(5)

                    is EstadoCarga.Fallo -> BannerError(e.mensaje, onReintentar = { vm.cargar() })

                    is EstadoCarga.Listo -> {
                        if (e.datos.isEmpty()) {
                            EstadoVacio(
                                titulo = "Sin notificaciones",
                                detalle = "Aquí llegan los avisos de ofertas y servicios.",
                                icono = Icons.Default.NotificationsNone,
                            )
                        } else {
                            LazyColumn(
                                contentPadding = PaddingValues(
                                    start = Espacio.m, end = Espacio.m,
                                    top = 2.dp, bottom = Espacio.l,
                                ),
                                verticalArrangement = Arrangement.spacedBy(Espacio.s),
                            ) {
                                items(e.datos, key = { it.id }) { n ->
                                    TarjetaNotificacion(n) {
                                        vm.marcarLeida(n.id)
                                        rutaDe(n)?.let(onNavegar)
                                    }
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
 * A dónde lleva tocar una notificación: la sección que le corresponde.
 */
private fun rutaDe(n: Notificacion): String? = when (n.destino) {
    DestinoNotificacion.Solicitudes -> Rutas.SOLICITUDES
    DestinoNotificacion.Reservaciones -> Rutas.RESERVACIONES
    DestinoNotificacion.Flota -> Rutas.FLOTA
    DestinoNotificacion.Ninguno -> null
}

/**
 * Fila de aviso.
 *
 * Lo no leído se tiñe de teal tenue y lo leído queda en blanco, el mismo par
 * que usa el resto de la app. El punto de color es redundante con el fondo a
 * propósito: el color solo no basta para quien no lo distingue.
 */
@Composable
private fun TarjetaNotificacion(n: Notificacion, onClick: () -> Unit) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Radio.tarjeta),
        colors = CardDefaults.cardColors(
            containerColor = if (n.leido) PortGoColor.Superficie else PortGoColor.TealTenue,
        ),
        border = BorderStroke(
            1.dp,
            if (n.leido) PortGoColor.BordeTarjeta else PortGoColor.Teal.copy(alpha = 0.25f),
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Row(Modifier.padding(15.dp), verticalAlignment = Alignment.Top) {
            Box(
                Modifier
                    .padding(top = 6.dp)
                    .size(8.dp)
                    .clip(CircleShape)
                    .background(
                        if (n.leido) PortGoColor.TextoTerciario else PortGoColor.Teal,
                    ),
            )
            Spacer(Modifier.width(Espacio.s))
            Column(Modifier.weight(1f)) {
                Text(
                    n.titulo ?: "Aviso",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = if (n.leido) FontWeight.Normal else FontWeight.SemiBold,
                    color = PortGoColor.Tinta,
                )
                if (!n.mensaje.isNullOrBlank()) {
                    Spacer(Modifier.height(3.dp))
                    Text(
                        n.mensaje,
                        style = MaterialTheme.typography.bodyMedium,
                        color = PortGoColor.TextoSecundario,
                    )
                }
                Spacer(Modifier.height(5.dp))
                Text(
                    Fmt.hace(n.creadoEn),
                    style = MaterialTheme.typography.labelSmall,
                    color = PortGoColor.TextoTerciario,
                )
            }
        }
    }
}
