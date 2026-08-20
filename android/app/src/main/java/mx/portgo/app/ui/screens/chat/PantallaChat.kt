package mx.portgo.app.ui.screens.chat

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import mx.portgo.app.core.Fmt
import mx.portgo.app.data.model.Mensaje
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.di.AppContainer
import mx.portgo.app.ui.components.BannerError
import mx.portgo.app.ui.components.CargandoCentrado
import mx.portgo.app.ui.components.EncabezadoModulo
import mx.portgo.app.ui.components.EstadoVacio
import mx.portgo.app.ui.theme.Espacio
import mx.portgo.app.ui.theme.PortGoColor
import mx.portgo.app.ui.viewmodel.ChatViewModel
import mx.portgo.app.ui.viewmodel.EstadoCarga
import mx.portgo.app.ui.viewmodel.vmFactory

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PantallaChat(
    esReserva: Boolean,
    contextoId: String,
    otroUsuarioId: String,
    titulo: String,
    usuario: UsuarioActual,
    container: AppContainer,
    onAtras: () -> Unit,
) {
    val vm: ChatViewModel = viewModel(
        key = "$contextoId-$otroUsuarioId",
        factory = vmFactory {
            ChatViewModel(container.chat, usuario, esReserva, contextoId, otroUsuarioId)
        },
    )
    val estado by vm.estado.collectAsStateWithLifecycle()
    val enviando by vm.enviando.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }
    val listaEstado = rememberLazyListState()

    var borrador by rememberSaveable { mutableStateOf("") }

    LaunchedEffect(Unit) { vm.avisos.collect { snackbar.showSnackbar(it) } }

    // Al llegar un mensaje se baja al final, que es donde el usuario espera
    // estar en una conversación.
    val total = (estado as? EstadoCarga.Listo)?.datos?.size ?: 0
    LaunchedEffect(total) {
        if (total > 0) listaEstado.animateScrollToItem(total - 1)
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbar) },
        containerColor = PortGoColor.Arena,
    ) { relleno ->
        Column(
            Modifier
                .fillMaxSize()
                .background(PortGoColor.Arena)
                .padding(relleno)
                .imePadding(),
        ) {
            EncabezadoModulo(titulo = titulo, onAtras = onAtras)
            Box(Modifier.weight(1f)) {
                when (val e = estado) {
                    is EstadoCarga.Cargando -> CargandoCentrado()

                    is EstadoCarga.Fallo -> BannerError(e.mensaje, onReintentar = vm::cargar)

                    is EstadoCarga.Listo -> {
                        if (e.datos.isEmpty()) {
                            EstadoVacio(
                                titulo = "Todavía no hay mensajes",
                                detalle = "Escribe el primero. Toda la coordinación del " +
                                    "servicio queda registrada aquí.",
                            )
                        } else {
                            LazyColumn(
                                state = listaEstado,
                                contentPadding = PaddingValues(Espacio.m),
                                verticalArrangement = Arrangement.spacedBy(Espacio.s),
                            ) {
                                items(e.datos, key = { it.id }) { msg ->
                                    Burbuja(msg, msg.esMio(vm.miId))
                                }
                            }
                        }
                    }
                }
            }

            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(Espacio.s),
                verticalAlignment = Alignment.Bottom,
            ) {
                OutlinedTextField(
                    value = borrador,
                    onValueChange = { borrador = it },
                    placeholder = { Text("Escribe un mensaje") },
                    modifier = Modifier.weight(1f),
                    maxLines = 4,
                    supportingText = {
                        Text(
                            "Por seguridad no se permiten números de teléfono.",
                            style = MaterialTheme.typography.bodySmall,
                        )
                    },
                )
                Spacer(Modifier.size(Espacio.s))
                IconButton(
                    onClick = {
                        vm.enviar(borrador)
                        borrador = ""
                    },
                    enabled = borrador.isNotBlank() && !enviando,
                ) {
                    Icon(Icons.AutoMirrored.Filled.Send, contentDescription = "Enviar")
                }
            }
        }
    }
}

@Composable
private fun Burbuja(msg: Mensaje, esMio: Boolean) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = if (esMio) Arrangement.End else Arrangement.Start,
    ) {
        Column(
            Modifier
                .widthIn(max = 300.dp)
                .clip(
                    RoundedCornerShape(
                        topStart = 16.dp,
                        topEnd = 16.dp,
                        bottomStart = if (esMio) 16.dp else 4.dp,
                        bottomEnd = if (esMio) 4.dp else 16.dp,
                    ),
                )
                .background(if (esMio) PortGoColor.TealTenue else PortGoColor.Superficie)
                .border(
                    BorderStroke(
                        1.dp,
                        if (esMio) PortGoColor.Teal.copy(alpha = 0.25f) else PortGoColor.BordeTarjeta,
                    ),
                    RoundedCornerShape(
                        topStart = 16.dp, topEnd = 16.dp,
                        bottomStart = if (esMio) 16.dp else 4.dp,
                        bottomEnd = if (esMio) 4.dp else 16.dp,
                    ),
                )
                .padding(horizontal = Espacio.m, vertical = Espacio.s),
        ) {
            if (!esMio && !msg.deNombre.isNullOrBlank()) {
                Text(
                    msg.deNombre,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
            Text(msg.texto, style = MaterialTheme.typography.bodyMedium)
            Text(
                Fmt.hace(msg.creadoEn),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.align(Alignment.End),
            )
        }
    }
}
