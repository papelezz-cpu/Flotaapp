package mx.portgo.app.ui.screens.flota

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.di.AppContainer
import mx.portgo.app.ui.LocalCatalogos
import mx.portgo.app.ui.components.CampoArchivo
import mx.portgo.app.ui.components.CampoFecha
import mx.portgo.app.ui.theme.Espacio
import mx.portgo.app.ui.viewmodel.AltaCamionViewModel
import mx.portgo.app.ui.viewmodel.AltaCamionViewModel.Archivo
import mx.portgo.app.ui.viewmodel.vmFactory

/**
 * Alta de una unidad, en tres pasos.
 *
 * Son ~30 campos y ocho archivos. En una sola pantalla eso es un
 * desplazamiento interminable donde la gente abandona a la mitad; en tres pasos
 * con un objetivo claro cada uno se llena de pie, junto al camión.
 *
 * El orden no es casual: primero lo que identifica la unidad (que es lo que el
 * usuario sabe de memoria), después los papeles con sus vigencias, y al final
 * las fotos, que es cuando ya está caminando alrededor del camión.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun PantallaAltaCamion(
    usuario: UsuarioActual,
    container: AppContainer,
    onAtras: () -> Unit,
    onGuardada: () -> Unit,
) {
    val vm: AltaCamionViewModel = viewModel(
        factory = vmFactory {
            AltaCamionViewModel(container.flota, container.storage, usuario)
        },
    )
    val form by vm.form.collectAsStateWithLifecycle()
    val archivos by vm.archivos.collectAsStateWithLifecycle()
    val guardando by vm.guardando.collectAsStateWithLifecycle()
    val progreso by vm.progreso.collectAsStateWithLifecycle()
    val catalogos = LocalCatalogos.current
    val snackbar = remember { SnackbarHostState() }

    var paso by rememberSaveable { mutableIntStateOf(0) }
    val pasos = listOf("Identificación", "Documentos", "Fotos")

    LaunchedEffect(Unit) { vm.avisos.collect { snackbar.showSnackbar(it) } }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbar) },
        topBar = {
            TopAppBar(
                title = { Text("Nueva unidad · ${pasos[paso]}") },
                navigationIcon = {
                    IconButton(onClick = { if (paso > 0) paso-- else onAtras() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Atrás")
                    }
                },
            )
        },
    ) { relleno ->
        Column(Modifier.fillMaxSize().padding(relleno)) {

            LinearProgressIndicator(
                progress = { (paso + 1f) / pasos.size },
                modifier = Modifier.fillMaxWidth(),
            )
            if (guardando) {
                Text(
                    progreso ?: "Guardando…",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = Espacio.m, vertical = Espacio.xs),
                )
            }

            Column(
                Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .imePadding()
                    .padding(Espacio.m),
            ) {
                when (paso) {
                    0 -> PasoIdentificacion(vm, form, catalogos.tiposUnidad.map { it.valor })
                    1 -> PasoDocumentos(vm, form, archivos)
                    else -> PasoFotos(vm, archivos)
                }
                Spacer(Modifier.height(Espacio.xl))
            }

            HorizontalDivider()
            Row(
                Modifier.fillMaxWidth().padding(Espacio.m),
                horizontalArrangement = Arrangement.spacedBy(Espacio.s),
            ) {
                if (paso > 0) {
                    OutlinedButton(
                        onClick = { paso-- },
                        enabled = !guardando,
                        modifier = Modifier.weight(1f),
                    ) { Text("Atrás") }
                }
                Button(
                    onClick = {
                        if (paso < pasos.lastIndex) paso++ else vm.guardar(onGuardada)
                    },
                    enabled = !guardando && (paso > 0 || form.identificacionCompleta),
                    modifier = Modifier.weight(2f),
                ) {
                    if (guardando) {
                        CircularProgressIndicator(
                            Modifier.size(20.dp),
                            strokeWidth = 2.dp,
                            color = MaterialTheme.colorScheme.onPrimary,
                        )
                    } else {
                        Text(if (paso < pasos.lastIndex) "Continuar" else "Registrar unidad")
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun PasoIdentificacion(
    vm: AltaCamionViewModel,
    form: AltaCamionViewModel.Formulario,
    tiposUnidad: List<String>,
) {
    var tipoAbierto by remember { mutableStateOf(false) }
    var placaAbierta by remember { mutableStateOf(false) }
    var combAbierto by remember { mutableStateOf(false) }

    OutlinedTextField(
        value = form.numEconomico,
        onValueChange = { v -> vm.actualizar { it.copy(numEconomico = v.uppercase()) } },
        label = { Text("Número económico *") },
        supportingText = { Text("Es el identificador de la unidad. No se puede repetir.") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )

    Spacer(Modifier.height(Espacio.s))

    // Los tipos salen del catálogo remoto, no compilados: son los mismos que
    // decide qué solicitudes puede atender esta unidad.
    ExposedDropdownMenuBox(expanded = tipoAbierto, onExpandedChange = { tipoAbierto = it }) {
        OutlinedTextField(
            value = form.tipo,
            onValueChange = {},
            readOnly = true,
            label = { Text("Tipo de unidad *") },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(tipoAbierto) },
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor(MenuAnchorType.PrimaryNotEditable),
        )
        ExposedDropdownMenu(tipoAbierto, { tipoAbierto = false }) {
            tiposUnidad.forEach { t ->
                DropdownMenuItem(
                    text = { Text(t) },
                    onClick = { vm.actualizar { it.copy(tipo = t) }; tipoAbierto = false },
                )
            }
        }
    }

    Spacer(Modifier.height(Espacio.s))
    Row(horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
        OutlinedTextField(
            value = form.placas,
            onValueChange = { v -> vm.actualizar { it.copy(placas = v.uppercase()) } },
            label = { Text("Placas") },
            singleLine = true,
            modifier = Modifier.weight(1f),
        )
        ExposedDropdownMenuBox(
            expanded = placaAbierta,
            onExpandedChange = { placaAbierta = it },
            modifier = Modifier.weight(1f),
        ) {
            OutlinedTextField(
                value = form.tipoPlaca,
                onValueChange = {},
                readOnly = true,
                label = { Text("Tipo") },
                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(placaAbierta) },
                modifier = Modifier.fillMaxWidth().menuAnchor(MenuAnchorType.PrimaryNotEditable),
            )
            ExposedDropdownMenu(placaAbierta, { placaAbierta = false }) {
                AltaCamionViewModel.TIPOS_PLACA.forEach { t ->
                    DropdownMenuItem(
                        text = { Text(t) },
                        onClick = { vm.actualizar { it.copy(tipoPlaca = t) }; placaAbierta = false },
                    )
                }
            }
        }
    }

    Spacer(Modifier.height(Espacio.s))
    Row(horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
        OutlinedTextField(
            value = form.marca,
            onValueChange = { v -> vm.actualizar { it.copy(marca = v) } },
            label = { Text("Marca") },
            singleLine = true,
            modifier = Modifier.weight(1f),
        )
        OutlinedTextField(
            value = form.modeloAnio,
            onValueChange = { v -> vm.actualizar { it.copy(modeloAnio = v.filter(Char::isDigit)) } },
            label = { Text("Año") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            modifier = Modifier.weight(1f),
        )
    }

    Spacer(Modifier.height(Espacio.s))
    Row(horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
        OutlinedTextField(
            value = form.version,
            onValueChange = { v -> vm.actualizar { it.copy(version = v) } },
            label = { Text("Versión") },
            singleLine = true,
            modifier = Modifier.weight(1f),
        )
        OutlinedTextField(
            value = form.color,
            onValueChange = { v -> vm.actualizar { it.copy(color = v) } },
            label = { Text("Color") },
            singleLine = true,
            modifier = Modifier.weight(1f),
        )
    }

    Spacer(Modifier.height(Espacio.s))
    Row(horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
        OutlinedTextField(
            value = form.capacidad,
            onValueChange = { v -> vm.actualizar { it.copy(capacidad = v) } },
            label = { Text("Capacidad") },
            suffix = { Text("ton") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            modifier = Modifier.weight(1f),
        )
        OutlinedTextField(
            value = form.precioDia,
            onValueChange = { v ->
                vm.actualizar { it.copy(precioDia = v.filter { c -> c.isDigit() || c == '.' }) }
            },
            label = { Text("Precio por día") },
            prefix = { Text("$") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            modifier = Modifier.weight(1f),
        )
    }

    Spacer(Modifier.height(Espacio.s))
    OutlinedTextField(
        value = form.dimensiones,
        onValueChange = { v -> vm.actualizar { it.copy(dimensiones = v) } },
        label = { Text("Dimensiones de la caja") },
        placeholder = { Text("12.5 × 2.6 × 2.9 m") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )

    Spacer(Modifier.height(Espacio.m))
    Text("Qué carga puede llevar", style = MaterialTheme.typography.titleMedium)
    Spacer(Modifier.height(Espacio.xs))
    FlowRow(horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
        AltaCamionViewModel.TIPOS_CARGA.forEach { t ->
            FilterChip(
                selected = t in form.tiposCarga,
                onClick = { vm.alternarTipoCarga(t) },
                label = { Text(t) },
            )
        }
    }

    Spacer(Modifier.height(Espacio.m))
    Text("Datos del vehículo", style = MaterialTheme.typography.titleMedium)
    Spacer(Modifier.height(Espacio.xs))
    OutlinedTextField(
        value = form.numSerie,
        onValueChange = { v -> vm.actualizar { it.copy(numSerie = v.uppercase()) } },
        label = { Text("Número de serie (VIN)") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )
    Spacer(Modifier.height(Espacio.s))
    Row(horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
        OutlinedTextField(
            value = form.numMotor,
            onValueChange = { v -> vm.actualizar { it.copy(numMotor = v.uppercase()) } },
            label = { Text("Número de motor") },
            singleLine = true,
            modifier = Modifier.weight(1f),
        )
        ExposedDropdownMenuBox(
            expanded = combAbierto,
            onExpandedChange = { combAbierto = it },
            modifier = Modifier.weight(1f),
        ) {
            OutlinedTextField(
                value = form.combustible,
                onValueChange = {},
                readOnly = true,
                label = { Text("Combustible") },
                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(combAbierto) },
                modifier = Modifier.fillMaxWidth().menuAnchor(MenuAnchorType.PrimaryNotEditable),
            )
            ExposedDropdownMenu(combAbierto, { combAbierto = false }) {
                AltaCamionViewModel.COMBUSTIBLES.forEach { c ->
                    DropdownMenuItem(
                        text = { Text(c) },
                        onClick = { vm.actualizar { it.copy(combustible = c) }; combAbierto = false },
                    )
                }
            }
        }
    }
}

@Composable
private fun PasoDocumentos(
    vm: AltaCamionViewModel,
    form: AltaCamionViewModel.Formulario,
    archivos: Map<Archivo, android.net.Uri>,
) {
    Text(
        "Fotografía cada documento y captura su vigencia. Las vigencias son lo " +
            "que decide si la unidad puede salir a carretera.",
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Spacer(Modifier.height(Espacio.m))

    Text("Tarjeta de circulación", style = MaterialTheme.typography.titleMedium)
    Spacer(Modifier.height(Espacio.xs))
    OutlinedTextField(
        value = form.tarjetaCirculacion,
        onValueChange = { v -> vm.actualizar { it.copy(tarjetaCirculacion = v) } },
        label = { Text("Número de tarjeta") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )
    Spacer(Modifier.height(Espacio.s))
    Row(horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
        CampoFecha(
            etiqueta = "Expedición",
            valor = form.fechaExpedicionTc,
            onCambio = { v -> vm.actualizar { it.copy(fechaExpedicionTc = v) } },
            modifier = Modifier.weight(1f),
        )
        CampoFecha(
            etiqueta = "Vence",
            valor = form.venceTc,
            onCambio = { v -> vm.actualizar { it.copy(venceTc = v) } },
            esVigencia = true,
            modifier = Modifier.weight(1f),
        )
    }
    Spacer(Modifier.height(Espacio.s))
    ArchivoDe(vm, archivos, Archivo.TARJETA)

    Spacer(Modifier.height(Espacio.l))
    Text("Seguro", style = MaterialTheme.typography.titleMedium)
    Spacer(Modifier.height(Espacio.xs))
    CampoFecha(
        etiqueta = "Vence el seguro",
        valor = form.venceSeguro,
        onCambio = { v -> vm.actualizar { it.copy(venceSeguro = v) } },
        esVigencia = true,
    )
    Spacer(Modifier.height(Espacio.s))
    ArchivoDe(vm, archivos, Archivo.SEGURO)

    Spacer(Modifier.height(Espacio.l))
    Text("Permiso SCT", style = MaterialTheme.typography.titleMedium)
    Spacer(Modifier.height(Espacio.xs))
    CampoFecha(
        etiqueta = "Vence el permiso",
        valor = form.vencePermisoSct,
        onCambio = { v -> vm.actualizar { it.copy(vencePermisoSct = v) } },
        esVigencia = true,
    )
    Spacer(Modifier.height(Espacio.s))
    ArchivoDe(vm, archivos, Archivo.PERMISO_SCT)

    Spacer(Modifier.height(Espacio.l))
    Text("CAAT y verificación", style = MaterialTheme.typography.titleMedium)
    Spacer(Modifier.height(Espacio.xs))
    OutlinedTextField(
        value = form.caat,
        onValueChange = { v -> vm.actualizar { it.copy(caat = v.uppercase()) } },
        label = { Text("CAAT") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )
    Spacer(Modifier.height(Espacio.s))
    Row(horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
        CampoFecha(
            etiqueta = "Vigencia CAAT",
            valor = form.vigenciaCaat,
            onCambio = { v -> vm.actualizar { it.copy(vigenciaCaat = v) } },
            esVigencia = true,
            modifier = Modifier.weight(1f),
        )
        CampoFecha(
            etiqueta = "Verificación",
            valor = form.venceVerificacion,
            onCambio = { v -> vm.actualizar { it.copy(venceVerificacion = v) } },
            esVigencia = true,
            modifier = Modifier.weight(1f),
        )
    }

    Spacer(Modifier.height(Espacio.l))
    Text("Materiales peligrosos", style = MaterialTheme.typography.titleMedium)
    Text(
        "Solo si la unidad los transporta.",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Spacer(Modifier.height(Espacio.xs))
    CampoFecha(
        etiqueta = "Vence el permiso",
        valor = form.vencePeligrosa,
        onCambio = { v -> vm.actualizar { it.copy(vencePeligrosa = v) } },
        esVigencia = true,
    )
    Spacer(Modifier.height(Espacio.s))
    ArchivoDe(vm, archivos, Archivo.PELIGROSA)
}

@Composable
private fun PasoFotos(
    vm: AltaCamionViewModel,
    archivos: Map<Archivo, android.net.Uri>,
) {
    Text(
        "Camina alrededor de la unidad y tómale cuatro fotos. Son las que ve el " +
            "cliente al recibir tu oferta.",
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Spacer(Modifier.height(Espacio.m))

    listOf(Archivo.FOTO_FRENTE, Archivo.FOTO_LATERAL, Archivo.FOTO_TRASERA, Archivo.FOTO_PLACA)
        .forEach { a ->
            ArchivoDe(vm, archivos, a)
            Spacer(Modifier.height(Espacio.s))
        }

    Spacer(Modifier.height(Espacio.m))
    Text(
        "Al registrarla queda pendiente de aprobación. Podrás ofertar con ella " +
            "cuando el administrador la revise.",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@Composable
private fun ArchivoDe(
    vm: AltaCamionViewModel,
    archivos: Map<Archivo, android.net.Uri>,
    archivo: Archivo,
) {
    CampoArchivo(
        etiqueta = archivo.etiqueta,
        ayuda = archivo.ayuda,
        adjunto = archivos[archivo],
        onAdjuntar = { vm.adjuntar(archivo, it) },
        onQuitar = { vm.quitar(archivo) },
    )
}
