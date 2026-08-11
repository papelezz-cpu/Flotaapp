package mx.portgo.app.ui.screens.solicitudes

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import mx.portgo.app.data.model.Camion
import mx.portgo.app.data.model.Operador
import mx.portgo.app.ui.theme.Espacio

/**
 * Formulario de oferta de la empresa.
 *
 * Solo aparecen unidades aprobadas, libres y del tipo que pide la solicitud —
 * el filtro lo aplica el repositorio. Si la lista sale vacía no se muestra un
 * desplegable inútil: se dice exactamente por qué no puede ofertar, que es la
 * pregunta que se haría enseguida.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DialogoHacerOferta(
    camiones: List<Camion>,
    operadores: List<Operador>,
    onCerrar: () -> Unit,
    onEnviar: (camionId: String, precio: Double, operadorId: String?, mensaje: String?) -> Unit,
) {
    var camionSel by remember { mutableStateOf<Camion?>(camiones.singleOrNull()) }
    var operadorSel by remember { mutableStateOf<Operador?>(operadores.singleOrNull()) }
    var precio by remember { mutableStateOf("") }
    var mensaje by remember { mutableStateOf("") }
    var camionAbierto by remember { mutableStateOf(false) }
    var operadorAbierto by remember { mutableStateOf(false) }

    val precioValido = precio.toDoubleOrNull()?.takeIf { it > 0 }
    val puedeEnviar = camionSel != null && precioValido != null &&
        (operadores.isEmpty() || operadorSel != null)

    AlertDialog(
        onDismissRequest = onCerrar,
        title = { Text("Hacer una oferta") },
        text = {
            if (camiones.isEmpty()) {
                Text(
                    "No tienes unidades aprobadas y disponibles del tipo que pide esta " +
                        "solicitud. Revisa tu flota o espera a que se apruebe una unidad.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            } else {
                Column(
                    Modifier
                        .heightIn(max = 420.dp)
                        .verticalScroll(rememberScrollState()),
                ) {
                    ExposedDropdownMenuBox(
                        expanded = camionAbierto,
                        onExpandedChange = { camionAbierto = it },
                    ) {
                        OutlinedTextField(
                            value = camionSel?.let { "${it.id} · ${it.tipo}" } ?: "",
                            onValueChange = {},
                            readOnly = true,
                            label = { Text("Unidad que asignas") },
                            trailingIcon = {
                                ExposedDropdownMenuDefaults.TrailingIcon(expanded = camionAbierto)
                            },
                            modifier = Modifier
                                .fillMaxWidth()
                                .menuAnchor(
                                    androidx.compose.material3.MenuAnchorType.PrimaryNotEditable,
                                ),
                        )
                        ExposedDropdownMenu(
                            expanded = camionAbierto,
                            onDismissRequest = { camionAbierto = false },
                        ) {
                            camiones.forEach { c ->
                                DropdownMenuItem(
                                    text = { Text("${c.id} · ${c.tipo ?: ""}") },
                                    onClick = { camionSel = c; camionAbierto = false },
                                )
                            }
                        }
                    }

                    if (operadores.isNotEmpty()) {
                        Spacer(Modifier.height(Espacio.s))
                        ExposedDropdownMenuBox(
                            expanded = operadorAbierto,
                            onExpandedChange = { operadorAbierto = it },
                        ) {
                            OutlinedTextField(
                                value = operadorSel?.nombre ?: "",
                                onValueChange = {},
                                readOnly = true,
                                label = { Text("Chofer") },
                                trailingIcon = {
                                    ExposedDropdownMenuDefaults.TrailingIcon(expanded = operadorAbierto)
                                },
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .menuAnchor(
                                        androidx.compose.material3.MenuAnchorType.PrimaryNotEditable,
                                    ),
                            )
                            ExposedDropdownMenu(
                                expanded = operadorAbierto,
                                onDismissRequest = { operadorAbierto = false },
                            ) {
                                operadores.forEach { o ->
                                    DropdownMenuItem(
                                        text = { Text(o.nombre ?: o.id) },
                                        onClick = { operadorSel = o; operadorAbierto = false },
                                    )
                                }
                            }
                        }
                    }

                    Spacer(Modifier.height(Espacio.s))
                    OutlinedTextField(
                        value = precio,
                        onValueChange = { precio = it.filter { c -> c.isDigit() || c == '.' } },
                        label = { Text("Precio en MXN") },
                        prefix = { Text("$") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        modifier = Modifier.fillMaxWidth(),
                    )

                    Spacer(Modifier.height(Espacio.s))
                    OutlinedTextField(
                        value = mensaje,
                        onValueChange = { mensaje = it },
                        label = { Text("Mensaje al cliente (opcional)") },
                        minLines = 2,
                        modifier = Modifier.fillMaxWidth(),
                    )

                    Spacer(Modifier.height(Espacio.s))
                    Text(
                        "Tu oferta tiene vigencia limitada. Entre más pronto la envíes, " +
                            "más posibilidades tienes.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        },
        confirmButton = {
            if (camiones.isNotEmpty()) {
                TextButton(
                    onClick = {
                        onEnviar(
                            camionSel!!.id,
                            precioValido!!,
                            operadorSel?.id,
                            mensaje.trim().ifBlank { null },
                        )
                    },
                    enabled = puedeEnviar,
                ) { Text("Enviar oferta") }
            }
        },
        dismissButton = {
            TextButton(onClick = onCerrar) { Text(if (camiones.isEmpty()) "Entendido" else "Cancelar") }
        },
    )
}

/** Captura de un precio. Se usa para la contraoferta del cliente. */
@Composable
fun DialogoPrecio(
    titulo: String,
    descripcion: String,
    etiquetaBoton: String,
    onCerrar: () -> Unit,
    onConfirmar: (Double) -> Unit,
) {
    var texto by remember { mutableStateOf("") }
    val valor = texto.toDoubleOrNull()?.takeIf { it > 0 }

    AlertDialog(
        onDismissRequest = onCerrar,
        title = { Text(titulo) },
        text = {
            Column {
                Text(descripcion, style = MaterialTheme.typography.bodyMedium)
                Spacer(Modifier.height(Espacio.m))
                OutlinedTextField(
                    value = texto,
                    onValueChange = { texto = it.filter { c -> c.isDigit() || c == '.' } },
                    label = { Text("Precio en MXN") },
                    prefix = { Text("$") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(onClick = { onConfirmar(valor!!) }, enabled = valor != null) {
                Text(etiquetaBoton)
            }
        },
        dismissButton = { TextButton(onClick = onCerrar) { Text("Cancelar") } },
    )
}

/** Captura de una nota libre. Se usa al rechazar y al pedir cancelación. */
@Composable
fun DialogoNota(
    titulo: String,
    descripcion: String,
    etiquetaBoton: String,
    obligatoria: Boolean = false,
    peligro: Boolean = false,
    onCerrar: () -> Unit,
    onConfirmar: (String?) -> Unit,
) {
    var texto by remember { mutableStateOf("") }
    val valida = !obligatoria || texto.isNotBlank()

    AlertDialog(
        onDismissRequest = onCerrar,
        title = { Text(titulo) },
        text = {
            Column {
                Text(descripcion, style = MaterialTheme.typography.bodyMedium)
                Spacer(Modifier.height(Espacio.m))
                OutlinedTextField(
                    value = texto,
                    onValueChange = { texto = it },
                    label = { Text(if (obligatoria) "Motivo" else "Nota (opcional)") },
                    minLines = 3,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onConfirmar(texto.trim().ifBlank { null }) },
                enabled = valida,
                colors = if (peligro) {
                    androidx.compose.material3.ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.error,
                    )
                } else {
                    androidx.compose.material3.ButtonDefaults.textButtonColors()
                },
            ) { Text(etiquetaBoton) }
        },
        dismissButton = { TextButton(onClick = onCerrar) { Text("Cancelar") } },
    )
}
