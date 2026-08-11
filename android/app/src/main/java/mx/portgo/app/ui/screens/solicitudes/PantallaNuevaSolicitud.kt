package mx.portgo.app.ui.screens.solicitudes

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import mx.portgo.app.core.Fmt
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.di.AppContainer
import mx.portgo.app.ui.LocalCatalogos
import mx.portgo.app.ui.theme.Espacio
import mx.portgo.app.ui.viewmodel.NuevaSolicitudViewModel
import mx.portgo.app.ui.viewmodel.vmFactory

/**
 * Publicar una solicitud.
 *
 * El formulario se adapta a la categoría de carga: solo pide lo que esa carga
 * necesita. Preguntar la clase HAZMAT a quien manda tarimas de refresco, o el
 * número de contenedores a quien manda granel, es cómo se llegó a un formulario
 * de ~20 campos que nadie quería llenar dos veces.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun PantallaNuevaSolicitud(
    usuario: UsuarioActual,
    container: AppContainer,
    onAtras: () -> Unit,
    onPublicada: () -> Unit,
) {
    val vm: NuevaSolicitudViewModel = viewModel(
        factory = vmFactory {
            NuevaSolicitudViewModel(container.pedidos, container.supabase, usuario)
        },
    )
    val form by vm.form.collectAsStateWithLifecycle()
    val (unidadSugerida, razon) = vm.unidadSugerida.collectAsStateWithLifecycle().value
    val publicando by vm.publicando.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }
    val catalogos = LocalCatalogos.current

    LaunchedEffect(Unit) { vm.avisos.collect { snackbar.showSnackbar(it) } }
    // Si el catálogo remoto llegó después de abrir la pantalla, el formulario
    // se realinea con lo que ahora pide la categoría elegida.
    LaunchedEffect(catalogos) { vm.sincronizarConCatalogos(catalogos) }

    var eligiendoFecha by rememberSaveable { mutableStateOf<String?>(null) }
    var plazoAbierto by remember { mutableStateOf(false) }
    var contAbierto by remember { mutableStateOf(false) }
    var unidadAbierta by remember { mutableStateOf(false) }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbar) },
        topBar = {
            TopAppBar(
                title = { Text("Nueva solicitud") },
                navigationIcon = {
                    IconButton(onClick = onAtras) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Atrás")
                    }
                },
            )
        },
    ) { relleno ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(relleno)
                .verticalScroll(rememberScrollState())
                .imePadding()
                .padding(Espacio.m),
        ) {
            // ── 1. Qué se mueve ──
            Titulo("¿Qué vas a mover?")
            FlowRow(horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
                catalogos.categoriasCarga.forEach { cat ->
                    FilterChip(
                        selected = form.categoria == cat.valor,
                        onClick = { vm.elegirCategoria(cat) },
                        label = { Text(cat.etiqueta) },
                    )
                }
            }
            catalogos.categoria(form.categoria)?.ayuda?.let { ayuda ->
                Text(
                    ayuda,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = Espacio.xs),
                )
            }

            Spacer(Modifier.height(Espacio.l))

            // ── 2. Detalles de la carga ──
            Titulo("Detalles de la carga")

            if (form.pidePeso) {
                CampoNumero(
                    valor = form.pesoTon,
                    onCambio = { v -> vm.actualizar { it.copy(pesoTon = v) } },
                    etiqueta = "Peso aproximado",
                    sufijo = "toneladas",
                )
            }

            if (form.pideTarimas) {
                Spacer(Modifier.height(Espacio.s))
                CampoNumero(
                    valor = form.numTarimas,
                    onCambio = { v -> vm.actualizar { it.copy(numTarimas = v) } },
                    etiqueta = "Tarimas o pallets",
                    sufijo = "tarimas",
                    soloEnteros = true,
                )
                Text(
                    "Un camión se llena por peso o por espacio, lo que ocurra primero.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            if (form.pideBultos) {
                Spacer(Modifier.height(Espacio.s))
                CampoNumero(
                    valor = form.numBultos,
                    onCambio = { v -> vm.actualizar { it.copy(numBultos = v) } },
                    etiqueta = "Número de bultos",
                    soloEnteros = true,
                )
            }

            if (form.pideContenedores) {
                Spacer(Modifier.height(Espacio.s))
                CampoNumero(
                    valor = form.numContenedores,
                    onCambio = { v -> vm.actualizar { it.copy(numContenedores = v) } },
                    etiqueta = "Cuántos contenedores",
                    soloEnteros = true,
                )
                Spacer(Modifier.height(Espacio.s))
                ExposedDropdownMenuBox(
                    expanded = contAbierto,
                    onExpandedChange = { contAbierto = it },
                ) {
                    OutlinedTextField(
                        value = form.contenedor1Tipo,
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("Tipo de contenedor") },
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(contAbierto) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .menuAnchor(androidx.compose.material3.MenuAnchorType.PrimaryNotEditable),
                    )
                    ExposedDropdownMenu(contAbierto, { contAbierto = false }) {
                        catalogos.tiposContenedor.forEach { t ->
                            DropdownMenuItem(
                                text = { Text(t.etiqueta) },
                                onClick = {
                                    vm.actualizar { it.copy(contenedor1Tipo = t.valor) }
                                    contAbierto = false
                                },
                            )
                        }
                    }
                }
            }

            if (form.pideDimensiones) {
                Spacer(Modifier.height(Espacio.s))
                Row(horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
                    CampoNumero(
                        valor = form.largoM,
                        onCambio = { v -> vm.actualizar { it.copy(largoM = v) } },
                        etiqueta = "Largo (m)",
                        modifier = Modifier.weight(1f),
                    )
                    CampoNumero(
                        valor = form.anchoM,
                        onCambio = { v -> vm.actualizar { it.copy(anchoM = v) } },
                        etiqueta = "Ancho (m)",
                        modifier = Modifier.weight(1f),
                    )
                    CampoNumero(
                        valor = form.altoM,
                        onCambio = { v -> vm.actualizar { it.copy(altoM = v) } },
                        etiqueta = "Alto (m)",
                        modifier = Modifier.weight(1f),
                    )
                }
            }

            if (form.pideHazmat) {
                Spacer(Modifier.height(Espacio.s))
                Row(horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
                    OutlinedTextField(
                        value = form.hazmatClase,
                        onValueChange = { v -> vm.actualizar { it.copy(hazmatClase = v) } },
                        label = { Text("Clase") },
                        singleLine = true,
                        modifier = Modifier.weight(1f),
                    )
                    OutlinedTextField(
                        value = form.hazmatUn,
                        onValueChange = { v -> vm.actualizar { it.copy(hazmatUn = v) } },
                        label = { Text("Número UN") },
                        singleLine = true,
                        modifier = Modifier.weight(1f),
                    )
                }
            }

            if (form.pideRefri) {
                Spacer(Modifier.height(Espacio.s))
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("Requiere refrigeración", style = MaterialTheme.typography.bodyLarge)
                    Switch(
                        checked = form.refrigerado,
                        onCheckedChange = { v -> vm.actualizar { it.copy(refrigerado = v) } },
                    )
                }
                if (form.refrigerado) {
                    Row(horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
                        CampoNumero(
                            valor = form.tempMin,
                            onCambio = { v -> vm.actualizar { it.copy(tempMin = v) } },
                            etiqueta = "Temp. mín (°C)",
                            permiteNegativo = true,
                            modifier = Modifier.weight(1f),
                        )
                        CampoNumero(
                            valor = form.tempMax,
                            onCambio = { v -> vm.actualizar { it.copy(tempMax = v) } },
                            etiqueta = "Temp. máx (°C)",
                            permiteNegativo = true,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }

            // ── 3. Unidad recomendada ──
            Spacer(Modifier.height(Espacio.l))
            Card(
                Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.4f),
                ),
            ) {
                Column(Modifier.padding(Espacio.m)) {
                    Text("Unidad recomendada", style = MaterialTheme.typography.labelLarge)
                    Spacer(Modifier.height(Espacio.xs))
                    Text(
                        vm.tipoFinal ?: "Captura los datos de la carga",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                    if (!razon.isNullOrBlank() && form.unidadManual == null) {
                        Spacer(Modifier.height(Espacio.xs))
                        Text(razon, style = MaterialTheme.typography.bodySmall)
                    }
                    if (form.unidadManual != null) {
                        Spacer(Modifier.height(Espacio.xs))
                        Text(
                            "La elegiste tú. Sugerida: ${unidadSugerida ?: "—"}",
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }

                    Spacer(Modifier.height(Espacio.s))
                    ExposedDropdownMenuBox(
                        expanded = unidadAbierta,
                        onExpandedChange = { unidadAbierta = it },
                    ) {
                        AssistChip(
                            onClick = { unidadAbierta = true },
                            label = { Text("Cambiar unidad") },
                            modifier = Modifier.menuAnchor(
                                androidx.compose.material3.MenuAnchorType.PrimaryNotEditable,
                            ),
                        )
                        ExposedDropdownMenu(unidadAbierta, { unidadAbierta = false }) {
                            DropdownMenuItem(
                                text = { Text("Usar la recomendada") },
                                onClick = { vm.elegirUnidadManual(null); unidadAbierta = false },
                            )
                            catalogos.tiposUnidad.forEach { u ->
                                DropdownMenuItem(
                                    text = { Text(u.etiqueta) },
                                    onClick = { vm.elegirUnidadManual(u.valor); unidadAbierta = false },
                                )
                            }
                        }
                    }
                }
            }

            // ── 4. Ruta y fechas ──
            Spacer(Modifier.height(Espacio.l))
            Titulo("Ruta")
            OutlinedTextField(
                value = form.origen,
                onValueChange = { v -> vm.actualizar { it.copy(origen = v) } },
                label = { Text("Origen *") },
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(Espacio.s))
            OutlinedTextField(
                value = form.destino,
                onValueChange = { v -> vm.actualizar { it.copy(destino = v) } },
                label = { Text("Destino *") },
                modifier = Modifier.fillMaxWidth(),
            )

            Spacer(Modifier.height(Espacio.m))
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text("Entra al recinto portuario", style = MaterialTheme.typography.bodyLarge)
                    Text(
                        "Implica maniobras, esperas y expediente documental.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Switch(
                    checked = form.entraAPuerto,
                    onCheckedChange = { v -> vm.actualizar { it.copy(entraAPuerto = v) } },
                )
            }

            Spacer(Modifier.height(Espacio.m))
            Titulo("Fechas")
            if (form.entraAPuerto) {
                BotonFecha(
                    etiqueta = "Arribo del buque a puerto",
                    valor = form.fechaArriboPuerto,
                    onClick = { eligiendoFecha = "arribo" },
                )
                Spacer(Modifier.height(Espacio.s))
            }
            BotonFecha(
                etiqueta = "Recolección de la carga *",
                valor = form.fechaIni,
                onClick = { eligiendoFecha = "ini" },
            )
            Spacer(Modifier.height(Espacio.s))
            BotonFecha(
                etiqueta = "Entrega estimada",
                valor = form.fechaFin,
                onClick = { eligiendoFecha = "fin" },
            )

            // ── 5. Comercial ──
            Spacer(Modifier.height(Espacio.l))
            Titulo("Presupuesto y pago")
            CampoNumero(
                valor = form.presupuesto,
                onCambio = { v -> vm.actualizar { it.copy(presupuesto = v) } },
                etiqueta = "Presupuesto estimado (MXN)",
                prefijo = "$",
            )
            Spacer(Modifier.height(Espacio.s))
            ExposedDropdownMenuBox(expanded = plazoAbierto, onExpandedChange = { plazoAbierto = it }) {
                OutlinedTextField(
                    value = form.plazoPago,
                    onValueChange = {},
                    readOnly = true,
                    label = { Text("Plazo de pago") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(plazoAbierto) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .menuAnchor(androidx.compose.material3.MenuAnchorType.PrimaryNotEditable),
                )
                ExposedDropdownMenu(plazoAbierto, { plazoAbierto = false }) {
                    catalogos.plazosPago.forEach { p ->
                        DropdownMenuItem(
                            text = { Text(p.etiqueta) },
                            onClick = {
                                vm.actualizar { it.copy(plazoPago = p.valor) }
                                plazoAbierto = false
                            },
                        )
                    }
                }
            }

            Spacer(Modifier.height(Espacio.m))
            OutlinedTextField(
                value = form.descripcion,
                onValueChange = { v -> vm.actualizar { it.copy(descripcion = v) } },
                label = { Text("Notas para el transportista") },
                minLines = 3,
                modifier = Modifier.fillMaxWidth(),
            )

            Spacer(Modifier.height(Espacio.l))
            HorizontalDivider()
            Spacer(Modifier.height(Espacio.m))

            Button(
                onClick = { vm.publicar(onPublicada) },
                enabled = vm.puedePublicar(),
                modifier = Modifier.fillMaxWidth().height(52.dp),
            ) {
                if (publicando) {
                    CircularProgressIndicator(
                        Modifier.height(20.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary,
                    )
                } else {
                    Text("Publicar solicitud")
                }
            }
            Text(
                "Un administrador la revisa antes de publicarla a las empresas.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = Espacio.xs),
            )

            Spacer(Modifier.height(Espacio.xl))
        }
    }

    eligiendoFecha?.let { cual ->
        val estadoFecha = rememberDatePickerState()
        DatePickerDialog(
            onDismissRequest = { eligiendoFecha = null },
            confirmButton = {
                TextButton(onClick = {
                    val millis = estadoFecha.selectedDateMillis
                    if (millis != null) {
                        // El selector devuelve medianoche UTC; se convierte a
                        // fecha civil sin desplazar el día.
                        val fecha = Instant.ofEpochMilli(millis)
                            .atZone(ZoneOffset.UTC).toLocalDate().toString()
                        vm.actualizar {
                            when (cual) {
                                "arribo" -> it.copy(fechaArriboPuerto = fecha)
                                "fin" -> it.copy(fechaFin = fecha)
                                else -> it.copy(fechaIni = fecha)
                            }
                        }
                    }
                    eligiendoFecha = null
                }) { Text("Elegir") }
            },
            dismissButton = {
                TextButton(onClick = { eligiendoFecha = null }) { Text("Cancelar") }
            },
        ) {
            DatePicker(state = estadoFecha)
        }
    }
}

@Composable
private fun Titulo(texto: String) {
    Text(
        texto,
        style = MaterialTheme.typography.titleMedium,
        modifier = Modifier.padding(bottom = Espacio.s),
    )
}

/**
 * Selector de fecha.
 *
 * Es una tarjeta y no un OutlinedTextField deshabilitado: un campo `enabled =
 * false` no recibe toques ni lo anuncia el lector de pantalla, así que el
 * usuario ve algo que parece editable y no responde.
 */
@Composable
private fun BotonFecha(etiqueta: String, valor: String?, onClick: () -> Unit) {
    OutlinedCard(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
    ) {
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
        }
    }
}

@Composable
private fun CampoNumero(
    valor: String,
    onCambio: (String) -> Unit,
    etiqueta: String,
    modifier: Modifier = Modifier,
    sufijo: String? = null,
    prefijo: String? = null,
    soloEnteros: Boolean = false,
    permiteNegativo: Boolean = false,
) {
    OutlinedTextField(
        value = valor,
        onValueChange = { entrada ->
            val limpio = entrada.filter { c ->
                c.isDigit() || (!soloEnteros && c == '.') || (permiteNegativo && c == '-')
            }
            onCambio(limpio)
        },
        label = { Text(etiqueta) },
        prefix = prefijo?.let { { Text(it) } },
        suffix = sufijo?.let { { Text(it) } },
        singleLine = true,
        keyboardOptions = KeyboardOptions(
            keyboardType = if (soloEnteros) KeyboardType.Number else KeyboardType.Decimal,
        ),
        modifier = modifier.fillMaxWidth(),
    )
}
