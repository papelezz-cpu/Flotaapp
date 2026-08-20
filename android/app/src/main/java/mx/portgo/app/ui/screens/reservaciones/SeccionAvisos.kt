package mx.portgo.app.ui.screens.reservaciones

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.EditCalendar
import androidx.compose.material.icons.filled.PinDrop
import androidx.compose.material.icons.filled.ReportProblem
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import mx.portgo.app.data.repository.AvisosRepository.MotivoReporte
import mx.portgo.app.ui.components.RadioCampo
import mx.portgo.app.ui.components.TarjetaFicha
import mx.portgo.app.ui.components.coloresCampo
import mx.portgo.app.ui.theme.ColoresEstado
import mx.portgo.app.ui.theme.Espacio
import mx.portgo.app.ui.theme.PortGoColor
import mx.portgo.app.ui.theme.SpaceGrotesk

/**
 * Los avisos fijos entre las dos partes.
 *
 * Sustituyen al chat. La diferencia no es de forma: un mensaje libre se queda
 * en el hilo y no cambia nada, mientras que estos botones escriben un aviso con
 * tipo, mandan correo y —en el caso de lugar y hora— modifican el pedido de
 * verdad. Lo que antes era "te lo dejo en la puerta 4" dicho por chat, y que
 * nadie podía reconstruir después, ahora queda como dato.
 *
 * Cada rol ve solo lo suyo: la empresa pide y avisa, el cliente corrige y
 * reporta. No hay un botón que sirva a los dos, así que no hay ninguno que
 * enseñar deshabilitado.
 */
@Composable
fun SeccionAvisos(
    soyCliente: Boolean,
    habilitado: Boolean,
    onSolicitarDocumentos: () -> Unit,
    onConfirmarLugarHora: () -> Unit,
    onAvisarRetraso: () -> Unit,
    onActualizarViaje: () -> Unit,
    onReportarProblema: () -> Unit,
) {
    TarjetaFicha {
        Text(
            if (soyCliente) "Avisar a la empresa" else "Avisar al cliente",
            fontFamily = SpaceGrotesk,
            fontWeight = FontWeight.Bold,
            style = MaterialTheme.typography.titleMedium,
            color = PortGoColor.Tinta,
        )
        Spacer(Modifier.height(2.dp))
        Text(
            if (soyCliente) {
                "La empresa y el administrador reciben el aviso por campana y correo."
            } else {
                "El cliente recibe el aviso por campana y correo."
            },
            style = MaterialTheme.typography.bodySmall,
            color = PortGoColor.TextoSecundario,
        )

        Spacer(Modifier.height(11.dp))
        HorizontalDivider(thickness = 1.dp, color = PortGoColor.Divisor)
        Spacer(Modifier.height(10.dp))

        if (soyCliente) {
            BotonAviso(
                icono = Icons.Default.EditCalendar,
                texto = "Actualizar lugar y hora",
                ayuda = "Cambia el dato en la solicitud, no solo avisa.",
                habilitado = habilitado,
                onClick = onActualizarViaje,
            )
            Spacer(Modifier.height(Espacio.s))
            BotonAviso(
                icono = Icons.Default.ReportProblem,
                texto = "Reportar un problema",
                ayuda = "Llega también al administrador.",
                habilitado = habilitado,
                peligro = true,
                onClick = onReportarProblema,
            )
        } else {
            BotonAviso(
                icono = Icons.Default.Description,
                texto = "Solicitar documentos de carga",
                ayuda = "Carta Porte y documentos del embarque.",
                habilitado = habilitado,
                onClick = onSolicitarDocumentos,
            )
            Spacer(Modifier.height(Espacio.s))
            BotonAviso(
                icono = Icons.Default.PinDrop,
                texto = "Confirmar lugar y hora",
                ayuda = "Usa los datos que ya tiene la solicitud.",
                habilitado = habilitado,
                onClick = onConfirmarLugarHora,
            )
            Spacer(Modifier.height(Espacio.s))
            BotonAviso(
                icono = Icons.Default.Schedule,
                texto = "Avisar retraso",
                ayuda = "Puedes añadir cuánto tiempo o por qué.",
                habilitado = habilitado,
                onClick = onAvisarRetraso,
            )
        }
    }
}

/**
 * Botón de aviso con su línea de ayuda.
 *
 * La ayuda va debajo y no en un tooltip: son acciones que le llegan a otra
 * persona por correo, y conviene saber a quién y con qué antes de tocarlas, no
 * después.
 */
@Composable
private fun BotonAviso(
    icono: ImageVector,
    texto: String,
    ayuda: String,
    habilitado: Boolean,
    onClick: () -> Unit,
    peligro: Boolean = false,
) {
    val color = if (peligro) ColoresEstado.peligro else PortGoColor.TealOscuro
    OutlinedButton(
        onClick = onClick,
        enabled = habilitado,
        shape = RadioCampo,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Icon(icono, contentDescription = null, tint = color, modifier = Modifier.size(19.dp))
        Spacer(Modifier.width(Espacio.s))
        Column(Modifier.weight(1f)) {
            Text(
                texto,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
                color = color,
            )
            Text(
                ayuda,
                style = MaterialTheme.typography.bodySmall,
                color = PortGoColor.TextoSecundario,
            )
        }
    }
}

/**
 * Actualizar lugar y hora de la recogida.
 *
 * Campos de texto libre y no un selector: "bodega 3, andén B, preguntar por
 * Toño" no cabe en ningún control estructurado, y es exactamente lo que se
 * escribe en una operación real.
 */
@Composable
fun DialogoActualizarViaje(
    lugarInicial: String?,
    horaInicial: String?,
    onCerrar: () -> Unit,
    onConfirmar: (lugar: String?, hora: String?) -> Unit,
) {
    var lugar by remember { mutableStateOf(lugarInicial.orEmpty()) }
    var hora by remember { mutableStateOf(horaInicial.orEmpty()) }
    val puede = lugar.isNotBlank() || hora.isNotBlank()

    AlertDialog(
        onDismissRequest = onCerrar,
        containerColor = PortGoColor.Superficie,
        shape = RoundedCornerShape(18.dp),
        title = { Text("Actualizar lugar y hora", color = PortGoColor.Tinta) },
        text = {
            Column {
                Text(
                    "Se guarda en la solicitud y la empresa recibe el aviso.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = PortGoColor.TextoSecundario,
                )
                Spacer(Modifier.height(Espacio.m))
                OutlinedTextField(
                    value = lugar,
                    onValueChange = { lugar = it },
                    label = { Text("Lugar de recogida") },
                    shape = RadioCampo,
                    colors = coloresCampo(),
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(Espacio.s))
                OutlinedTextField(
                    value = hora,
                    onValueChange = { hora = it },
                    label = { Text("Hora") },
                    placeholder = { Text("8:00 a 10:00 am") },
                    singleLine = true,
                    shape = RadioCampo,
                    colors = coloresCampo(),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    onConfirmar(lugar.ifBlank { null }, hora.ifBlank { null })
                },
                enabled = puede,
            ) { Text("Guardar y avisar", color = PortGoColor.TealOscuro) }
        },
        dismissButton = {
            TextButton(onClick = onCerrar) {
                Text("Cancelar", color = PortGoColor.TextoSecundario)
            }
        },
    )
}

/**
 * Elegir el motivo del reporte.
 *
 * Motivos fijos y no texto libre: son los dos casos que la empresa y el
 * administrador pueden actuar. Un campo abierto produce reportes que nadie sabe
 * a quién asignar, que es como se llegó a quitar el chat.
 */
@Composable
fun DialogoMotivoReporte(
    onCerrar: () -> Unit,
    onElegir: (MotivoReporte) -> Unit,
) {
    AlertDialog(
        onDismissRequest = onCerrar,
        containerColor = PortGoColor.Superficie,
        shape = RoundedCornerShape(18.dp),
        title = { Text("¿Qué está pasando?", color = PortGoColor.Tinta) },
        text = {
            Column {
                MotivoReporte.entries.forEach { motivo ->
                    OutlinedButton(
                        onClick = { onElegir(motivo) },
                        shape = RadioCampo,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Row(
                            Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                motivo.etiqueta,
                                style = MaterialTheme.typography.bodyLarge,
                                color = PortGoColor.Tinta,
                            )
                        }
                    }
                    Spacer(Modifier.height(Espacio.s))
                }
            }
        },
        confirmButton = {},
        dismissButton = {
            TextButton(onClick = onCerrar) {
                Text("Cancelar", color = PortGoColor.TextoSecundario)
            }
        },
    )
}
