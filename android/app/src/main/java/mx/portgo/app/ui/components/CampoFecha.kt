package mx.portgo.app.ui.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import java.time.Instant
import java.time.ZoneOffset
import mx.portgo.app.core.Fmt
import mx.portgo.app.ui.theme.ColoresEstado
import mx.portgo.app.ui.theme.Espacio

/**
 * Selector de fecha.
 *
 * Es una tarjeta y no un campo de texto deshabilitado: un `enabled = false` no
 * recibe toques ni lo anuncia el lector de pantalla, así que el usuario ve algo
 * que parece editable y no responde.
 *
 * Cuando la fecha es una vigencia, avisa si ya venció o está por vencer. Ese
 * dato es el que decide si una unidad puede salir a carretera, y descubrirlo al
 * llenar el formulario es mucho mejor que descubrirlo en la báscula.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CampoFecha(
    etiqueta: String,
    valor: String?,
    onCambio: (String?) -> Unit,
    modifier: Modifier = Modifier,
    esVigencia: Boolean = false,
) {
    var abierto by rememberSaveable { mutableStateOf(false) }
    val dias = if (esVigencia) Fmt.diasHasta(valor) else null

    OutlinedCard(onClick = { abierto = true }, modifier = modifier.fillMaxWidth()) {
        Column(Modifier.padding(horizontal = Espacio.m, vertical = 12.dp)) {
            Text(
                etiqueta,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                valor?.let { Fmt.fecha(it) } ?: "Elegir fecha",
                style = MaterialTheme.typography.bodyLarge,
            )
            if (dias != null) {
                Text(
                    when {
                        dias < 0 -> "Venció hace ${-dias} día(s)"
                        dias == 0L -> "Vence hoy"
                        dias <= 30 -> "Vence en $dias día(s)"
                        else -> "Vigente"
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = when {
                        dias < 0 -> ColoresEstado.peligro
                        dias <= 30 -> ColoresEstado.alerta
                        else -> ColoresEstado.exito
                    },
                )
            }
        }
    }

    if (abierto) {
        val estado = rememberDatePickerState()
        DatePickerDialog(
            onDismissRequest = { abierto = false },
            confirmButton = {
                TextButton(onClick = {
                    estado.selectedDateMillis?.let { millis ->
                        // El selector devuelve medianoche UTC; se convierte a
                        // fecha civil sin desplazar el día.
                        onCambio(
                            Instant.ofEpochMilli(millis)
                                .atZone(ZoneOffset.UTC).toLocalDate().toString(),
                        )
                    }
                    abierto = false
                }) { Text("Elegir") }
            },
            dismissButton = {
                TextButton(onClick = { abierto = false }) { Text("Cancelar") }
            },
        ) { DatePicker(state = estado) }
    }
}
