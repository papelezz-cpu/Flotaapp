package mx.portgo.app.ui.screens.notificaciones

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.NotificationsNone
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
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
import mx.portgo.app.ui.components.EsqueletoLista
import mx.portgo.app.ui.components.EstadoVacio
import mx.portgo.app.ui.navigation.Rutas
import mx.portgo.app.ui.theme.Espacio
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

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Notificaciones") },
                navigationIcon = {
                    IconButton(onClick = onAtras) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Atrás")
                    }
                },
                actions = {
                    TextButton(onClick = { vm.cargar() }) { Text("Actualizar") }
                },
            )
        },
    ) { relleno ->
        Box(Modifier.fillMaxSize().padding(relleno)) {
            when (val e = estado) {
                is EstadoCarga.Cargando -> EsqueletoLista(5)

                is EstadoCarga.Fallo -> BannerError(e.mensaje, onReintentar = { vm.cargar() })

                is EstadoCarga.Listo -> {
                    if (e.datos.isEmpty()) {
                        EstadoVacio(
                            titulo = "Sin notificaciones",
                            detalle = "Aquí llegan los avisos de ofertas, servicios y mensajes.",
                            icono = Icons.Default.NotificationsNone,
                        )
                    } else {
                        LazyColumn(
                            contentPadding = PaddingValues(Espacio.m),
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

/**
 * A dónde lleva tocar una notificación.
 *
 * Para un mensaje nuevo se abre el hilo exacto usando `meta`; para el resto,
 * la sección que corresponde. Si falta el contexto se cae a la sección, que es
 * mejor que no hacer nada.
 */
private fun rutaDe(n: Notificacion): String? = when (n.destino) {
    DestinoNotificacion.Chat -> {
        val ctxId = n.ctxId
        val de = n.deUserId
        if (ctxId != null && de != null) {
            Rutas.chat(
                contexto = if (n.ctxTipo == "reserva") "reserva" else "pedido",
                ctxId = ctxId,
                otroId = de,
                titulo = n.deNombre ?: "Conversación",
            )
        } else {
            Rutas.RESERVACIONES
        }
    }
    DestinoNotificacion.Solicitudes -> Rutas.SOLICITUDES
    DestinoNotificacion.Reservaciones -> Rutas.RESERVACIONES
    DestinoNotificacion.Flota -> Rutas.FLOTA
    DestinoNotificacion.Ninguno -> null
}

@Composable
private fun TarjetaNotificacion(n: Notificacion, onClick: () -> Unit) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = if (n.leido) {
                MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.25f)
            } else {
                MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.4f)
            },
        ),
    ) {
        Row(Modifier.padding(Espacio.m), verticalAlignment = Alignment.Top) {
            // El punto es redundante con el color de fondo a propósito: el
            // color solo no basta para quien no lo distingue.
            Box(
                Modifier
                    .padding(top = 6.dp)
                    .size(8.dp)
                    .clip(CircleShape)
                    .background(
                        if (n.leido) MaterialTheme.colorScheme.surfaceVariant
                        else MaterialTheme.colorScheme.primary,
                    ),
            )
            Spacer(Modifier.size(Espacio.s))
            Column(Modifier.weight(1f)) {
                Text(
                    n.titulo ?: "Aviso",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = if (n.leido) FontWeight.Normal else FontWeight.SemiBold,
                )
                if (!n.mensaje.isNullOrBlank()) {
                    Text(n.mensaje, style = MaterialTheme.typography.bodyMedium)
                }
                Text(
                    Fmt.hace(n.creadoEn),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
