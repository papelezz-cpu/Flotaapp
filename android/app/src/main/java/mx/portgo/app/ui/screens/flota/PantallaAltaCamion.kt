package mx.portgo.app.ui.screens.flota

import androidx.compose.foundation.background
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.di.AppContainer
import mx.portgo.app.ui.LocalCatalogos
import mx.portgo.app.ui.components.BotonPrincipal
import mx.portgo.app.ui.components.CampoArchivo
import mx.portgo.app.ui.components.CampoFecha
import mx.portgo.app.ui.components.EncabezadoModulo
import mx.portgo.app.ui.components.RadioCampo
import mx.portgo.app.ui.components.coloresCampo
import mx.portgo.app.ui.theme.Espacio
import mx.portgo.app.ui.theme.PortGoColor
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
        containerColor = PortGoColor.Arena,
    ) { relleno ->
        Column(
            Modifier
                .fillMaxSize()
                .background(PortGoColor.Arena)
                .padding(relleno),
        ) {
            EncabezadoModulo(
                titulo = "Nueva unidad",
                onAtras = { if (paso > 0) paso-- else onAtras() },
            )

            PasosAlta(paso, pasos)

            if (guardando) {
                Text(
                    progreso ?: "Guardando…",
                    style = MaterialTheme.typography.bodySmall,
                    color = PortGoColor.TextoSecundario,
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

            HorizontalDivider(thickness = 1.dp, color = PortGoColor.BordeBarra)
            Row(
                Modifier
                    .background(PortGoColor.Superficie)
                    .fillMaxWidth()
                    .padding(Espacio.m),
                horizontalArrangement = Arrangement.spacedBy(Espacio.s),
            ) {
                if (paso > 0) {
                    OutlinedButton(
                        onClick = { paso-- },
                        enabled = !guardando,
                        shape = RadioCampo,
                        modifier = Modifier
                            .weight(1f)
                            .height(50.dp),
                    ) { Text("Atrás", color = PortGoColor.TextoSecundario) }
                }
                BotonPrincipal(
                    texto = if (paso < pasos.lastIndex) "Continuar" else "Registrar unidad",
                    onClick = {
                        if (paso < pasos.lastIndex) paso++ else vm.guardar(onGuardada)
                    },
                    ocupado = guardando,
                    habilitado = paso > 0 || form.identificacionCompleta,
                    modifier = Modifier.weight(2f),
                )
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
        shape = RadioCampo,
        colors = coloresCampo(),
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
            shape = RadioCampo,
            colors = coloresCampo(),
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
            shape = RadioCampo,
            colors = coloresCampo(),
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
                shape = RadioCampo,
                colors = coloresCampo(),
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
            shape = RadioCampo,
            colors = coloresCampo(),
            value = form.marca,
            onValueChange = { v -> vm.actualizar { it.copy(marca = v) } },
            label = { Text("Marca") },
            singleLine = true,
            modifier = Modifier.weight(1f),
        )
        OutlinedTextField(
            shape = RadioCampo,
            colors = coloresCampo(),
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
            shape = RadioCampo,
            colors = coloresCampo(),
            value = form.version,
            onValueChange = { v -> vm.actualizar { it.copy(version = v) } },
            label = { Text("Versión") },
            singleLine = true,
            modifier = Modifier.weight(1f),
        )
        OutlinedTextField(
            shape = RadioCampo,
            colors = coloresCampo(),
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
            shape = RadioCampo,
            colors = coloresCampo(),
            value = form.capacidad,
            onValueChange = { v -> vm.actualizar { it.copy(capacidad = v) } },
            label = { Text("Capacidad") },
            suffix = { Text("ton") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            modifier = Modifier.weight(1f),
        )
        OutlinedTextField(
            shape = RadioCampo,
            colors = coloresCampo(),
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
        shape = RadioCampo,
        colors = coloresCampo(),
        value = form.dimensiones,
        onValueChange = { v -> vm.actualizar { it.copy(dimensiones = v) } },
        label = { Text("Dimensiones de la caja") },
        placeholder = { Text("12.5 × 2.6 × 2.9 m") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )

    Spacer(Modifier.height(Espacio.m))
    Text("Qué carga puede llevar", style = MaterialTheme.typography.titleMedium, color = PortGoColor.Tinta)
    Spacer(Modifier.height(Espacio.xs))
    FlowRow(horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
        AltaCamionViewModel.TIPOS_CARGA.forEach { t ->
            FilterChip(
                selected = t in form.tiposCarga,
                onClick = { vm.alternarTipoCarga(t) },
                label = { Text(t) },
                shape = RoundedCornerShape(999.dp),
                colors = FilterChipDefaults.filterChipColors(
                    containerColor = PortGoColor.Superficie,
                    labelColor = PortGoColor.TextoSecundario,
                    selectedContainerColor = PortGoColor.Teal,
                    selectedLabelColor = Color.White,
                ),
                border = FilterChipDefaults.filterChipBorder(
                    enabled = true,
                    selected = t in form.tiposCarga,
                    borderColor = PortGoColor.BordeTarjeta,
                    selectedBorderColor = PortGoColor.Teal,
                ),
            )
        }
    }

    Spacer(Modifier.height(Espacio.m))
    Text("Datos del vehículo", style = MaterialTheme.typography.titleMedium, color = PortGoColor.Tinta)
    Spacer(Modifier.height(Espacio.xs))
    OutlinedTextField(
        shape = RadioCampo,
        colors = coloresCampo(),
        value = form.numSerie,
        onValueChange = { v -> vm.actualizar { it.copy(numSerie = v.uppercase()) } },
        label = { Text("Número de serie (VIN)") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )
    Spacer(Modifier.height(Espacio.s))
    Row(horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
        OutlinedTextField(
            shape = RadioCampo,
            colors = coloresCampo(),
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
                shape = RadioCampo,
                colors = coloresCampo(),
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
        color = PortGoColor.TextoSecundario,
    )
    Spacer(Modifier.height(Espacio.m))

    Text("Tarjeta de circulación", style = MaterialTheme.typography.titleMedium, color = PortGoColor.Tinta)
    Spacer(Modifier.height(Espacio.xs))
    OutlinedTextField(
        shape = RadioCampo,
        colors = coloresCampo(),
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
    Text("Seguro", style = MaterialTheme.typography.titleMedium, color = PortGoColor.Tinta)
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
    Text("Permiso SCT", style = MaterialTheme.typography.titleMedium, color = PortGoColor.Tinta)
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
    Text("CAAT y verificación", style = MaterialTheme.typography.titleMedium, color = PortGoColor.Tinta)
    Spacer(Modifier.height(Espacio.xs))
    OutlinedTextField(
        shape = RadioCampo,
        colors = coloresCampo(),
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
    Text("Materiales peligrosos", style = MaterialTheme.typography.titleMedium, color = PortGoColor.Tinta)
    Text(
        "Solo si la unidad los transporta.",
        style = MaterialTheme.typography.bodySmall,
        color = PortGoColor.TextoSecundario,
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
        color = PortGoColor.TextoSecundario,
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
        color = PortGoColor.TextoSecundario,
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

/**
 * Indicador de paso del alta.
 *
 * Nombra el paso en vez de mostrar solo una barra de relleno: en un formulario
 * de treinta campos, saber que lo que falta son "Fotos" y no "Documentos"
 * cambia si lo terminas ahora o lo dejas para cuando tengas los papeles.
 */
@Composable
private fun PasosAlta(paso: Int, pasos: List<String>) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = Espacio.m, vertical = Espacio.xs),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        pasos.forEachIndexed { indice, nombre ->
            val hecho = indice <= paso
            Column(Modifier.weight(1f)) {
                Spacer(
                    Modifier
                        .fillMaxWidth()
                        .height(4.dp)
                        .background(
                            if (hecho) PortGoColor.Teal else PortGoColor.BordeTarjeta,
                            RoundedCornerShape(2.dp),
                        ),
                )
                Spacer(Modifier.height(5.dp))
                Text(
                    nombre,
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = if (indice == paso) FontWeight.SemiBold else FontWeight.Normal,
                    color = if (hecho) PortGoColor.TealOscuro else PortGoColor.TextoTerciario,
                )
            }
        }
    }
    Spacer(Modifier.height(Espacio.s))
}
