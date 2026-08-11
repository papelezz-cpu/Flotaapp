package mx.portgo.app.ui.screens.reservaciones

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import mx.portgo.app.core.Fmt
import mx.portgo.app.data.model.EstadoCobro
import mx.portgo.app.data.model.EstadoReserva
import mx.portgo.app.data.model.EtapaExpediente
import mx.portgo.app.data.model.Reservacion
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.di.AppContainer
import mx.portgo.app.ui.LocalCatalogos
import mx.portgo.app.ui.components.BannerError
import mx.portgo.app.ui.components.ChipEstadoReserva
import mx.portgo.app.ui.components.EsqueletoLista
import mx.portgo.app.ui.components.FilaDato
import mx.portgo.app.ui.screens.solicitudes.DialogoNota
import mx.portgo.app.ui.theme.ColoresEstado
import mx.portgo.app.ui.theme.Espacio
import mx.portgo.app.ui.viewmodel.EstadoCarga
import mx.portgo.app.ui.viewmodel.ReservacionDetalleViewModel
import mx.portgo.app.ui.viewmodel.vmFactory

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PantallaReservacionDetalle(
    reservaId: String,
    usuario: UsuarioActual,
    container: AppContainer,
    onAtras: () -> Unit,
    onAbrirChat: (otroId: String, titulo: String, reservaId: String) -> Unit,
    onAbrirExpediente: (reservaId: String, etapa: String) -> Unit,
) {
    val vm: ReservacionDetalleViewModel = viewModel(
        key = reservaId,
        factory = vmFactory {
            ReservacionDetalleViewModel(
                container.reservaciones, container.storage, container.auth, usuario, reservaId,
            )
        },
    )
    val estado by vm.estado.collectAsStateWithLifecycle()
    val ocupado by vm.ocupado.collectAsStateWithLifecycle()
    val subiendo by vm.subiendo.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }
    val contexto = LocalContext.current

    LaunchedEffect(Unit) { vm.avisos.collect { snackbar.showSnackbar(it) } }

    var confirmarCancelar by rememberSaveable { mutableStateOf(false) }
    var pedirCancelacion by rememberSaveable { mutableStateOf(false) }
    var calificando by rememberSaveable { mutableStateOf(false) }

    // Se aceptan varios archivos de una vez: nadie sube una sola foto de una
    // maniobra, y hacerlo de uno en uno con la red del puerto es desesperante.
    val selectorArchivos = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenMultipleDocuments(),
    ) { uris: List<Uri> -> vm.subirEvidencias(uris) }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbar) },
        topBar = {
            TopAppBar(
                title = { Text("Servicio") },
                navigationIcon = {
                    IconButton(onClick = onAtras) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Atrás")
                    }
                },
                actions = {
                    vm.contraparteId?.let { otro ->
                        val d = (estado as? EstadoCarga.Listo)?.datos
                        IconButton(onClick = {
                            onAbrirChat(otro, d?.nombreContraparte ?: "Conversación", reservaId)
                        }) {
                            Icon(Icons.AutoMirrored.Filled.Chat, contentDescription = "Mensajes")
                        }
                    }
                },
            )
        },
    ) { relleno ->
        Column(Modifier.fillMaxSize().padding(relleno)) {
            if (ocupado || subiendo) LinearProgressIndicator(Modifier.fillMaxWidth())

            when (val e = estado) {
                is EstadoCarga.Cargando -> EsqueletoLista(3)
                is EstadoCarga.Fallo -> BannerError(e.mensaje, onReintentar = vm::cargar)

                is EstadoCarga.Listo -> {
                    val d = e.datos
                    val r = d.reservacion
                    val catalogos = LocalCatalogos.current

                    Column(
                        Modifier
                            .fillMaxSize()
                            .verticalScroll(rememberScrollState())
                            .padding(Espacio.m),
                    ) {
                        FichaServicio(r, d.nombreContraparte, vm.soyCliente)

                        // ── Seguimiento ──
                        if (r.estadoEnum == EstadoReserva.ACTIVA ||
                            r.estadoEnum == EstadoReserva.POR_APROBAR
                        ) {
                            Spacer(Modifier.height(Espacio.l))
                            LineaTiempo(r)

                            if (usuario.esEmpresa && r.estadoEnum == EstadoReserva.ACTIVA &&
                                !r.enUltimoPaso(catalogos)
                            ) {
                                Spacer(Modifier.height(Espacio.s))
                                val siguiente = catalogos.siguientePaso(r.recurso, r.trackingEstado)
                                Button(
                                    onClick = { vm.avanzarTracking() },
                                    enabled = !ocupado,
                                    modifier = Modifier.fillMaxWidth(),
                                ) { Text("Marcar: ${siguiente?.etiqueta ?: ""}") }
                            }
                        }

                        // ── Expedientes documentales ──
                        Spacer(Modifier.height(Espacio.l))
                        SeccionExpedientes(
                            expedientes = d.expedientes,
                            esCliente = vm.soyCliente,
                            habilitado = !ocupado,
                            onAbrir = { etapa -> onAbrirExpediente(reservaId, etapa) },
                            onSolicitar = { etapa -> vm.abrirExpediente(etapa) },
                        )

                        // ── Evidencias / cierre ──
                        Spacer(Modifier.height(Espacio.l))
                        Text("Evidencias del servicio", style = MaterialTheme.typography.titleMedium)
                        Text(
                            if (r.estadoEnum == EstadoReserva.ACTIVA) {
                                "Sube al menos una foto para marcar el servicio como completado. " +
                                    "La otra parte también deberá subir la suya antes de que un " +
                                    "administrador apruebe el cierre."
                            } else {
                                "Máximo 5 archivos, dentro de los 5 días posteriores al cierre."
                            },
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )

                        Spacer(Modifier.height(Espacio.s))
                        ListaEvidencias("Tus evidencias", d.misEvidenciasUrl) { url ->
                            contexto.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                        }
                        ListaEvidencias(
                            if (vm.soyCliente) "Evidencias de la empresa" else "Evidencias del cliente",
                            d.evidenciasOtroUrl,
                        ) { url ->
                            contexto.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                        }

                        if (r.estadoEnum == EstadoReserva.ACTIVA ||
                            r.estadoEnum == EstadoReserva.POR_APROBAR
                        ) {
                            Spacer(Modifier.height(Espacio.s))
                            FilledTonalButton(
                                onClick = { selectorArchivos.launch(arrayOf("image/*", "application/pdf")) },
                                enabled = !subiendo,
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Icon(Icons.Default.AttachFile, contentDescription = null)
                                Spacer(Modifier.size(Espacio.s))
                                Text(
                                    if (r.estadoEnum == EstadoReserva.ACTIVA) {
                                        "Subir evidencia y marcar completado"
                                    } else {
                                        "Agregar evidencia"
                                    },
                                )
                            }
                        }

                        // ── Acciones finales ──
                        Spacer(Modifier.height(Espacio.l))

                        if (r.estadoEnum == EstadoReserva.COMPLETADA && vm.soyCliente && !r.calificado) {
                            Button(
                                onClick = { calificando = true },
                                enabled = !ocupado,
                                modifier = Modifier.fillMaxWidth(),
                            ) { Text("Calificar el servicio") }
                            Spacer(Modifier.height(Espacio.s))
                        }

                        if (r.estadoEnum == EstadoReserva.ACTIVA) {
                            OutlinedButton(
                                onClick = {
                                    if (vm.soyCliente) pedirCancelacion = true else confirmarCancelar = true
                                },
                                enabled = !ocupado,
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Text(
                                    if (vm.soyCliente) "Solicitar cancelación" else "Cancelar servicio",
                                )
                            }
                            if (vm.soyCliente) {
                                Text(
                                    "Cancelar implica liberar la unidad y cerrar la solicitud, " +
                                        "así que lo revisa un administrador.",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.padding(top = Espacio.xs),
                                )
                            }
                        }

                        Spacer(Modifier.height(Espacio.xl))
                    }
                }
            }
        }
    }

    if (confirmarCancelar) {
        AlertDialog(
            onDismissRequest = { confirmarCancelar = false },
            title = { Text("¿Cancelar este servicio?") },
            text = {
                Text(
                    "La unidad quedará disponible y la solicitud se reabrirá para nuevas " +
                        "ofertas. No podrás volver a ofertar en ella.",
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    confirmarCancelar = false
                    vm.cancelar(null)
                }) { Text("Sí, cancelar") }
            },
            dismissButton = {
                TextButton(onClick = { confirmarCancelar = false }) { Text("No") }
            },
        )
    }

    if (pedirCancelacion) {
        DialogoNota(
            titulo = "Solicitar cancelación",
            descripcion = "Cuéntanos por qué necesitas cancelar. Un administrador lo revisará.",
            etiquetaBoton = "Enviar solicitud",
            obligatoria = true,
            onCerrar = { pedirCancelacion = false },
            onConfirmar = { motivo ->
                pedirCancelacion = false
                vm.solicitarCancelacion(motivo.orEmpty(), null)
            },
        )
    }

    if (calificando) {
        DialogoCalificar(
            onCerrar = { calificando = false },
            onEnviar = { estrellas, comentario ->
                calificando = false
                vm.calificar(estrellas, comentario)
            },
        )
    }
}

@Composable
private fun FichaServicio(r: Reservacion, contraparte: String?, soyCliente: Boolean) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(Espacio.m)) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top,
            ) {
                Text(
                    r.unidad ?: "Servicio",
                    style = MaterialTheme.typography.titleLarge,
                    modifier = Modifier.weight(1f),
                )
                ChipEstadoReserva(r.estadoEnum)
            }

            Spacer(Modifier.height(Espacio.s))
            HorizontalDivider()
            Spacer(Modifier.height(Espacio.s))

            FilaDato(if (soyCliente) "Empresa" else "Cliente", contraparte)
            FilaDato("Tipo de recurso", r.recurso.etiqueta)
            FilaDato("Periodo", Fmt.rangoFechas(r.fechaIni, r.fechaFin))
            FilaDato("Precio acordado", Fmt.precioMxn(r.precioAcordado))
            FilaDato("Plazo de pago", r.plazoPago)

            if (r.estadoCobro != EstadoCobro.NO_APLICA) {
                FilaDato(
                    "Cobro",
                    buildString {
                        append(r.estadoCobro.etiqueta)
                        r.fechaVencimientoPago?.let { append(" · vence ${Fmt.fecha(it)}") }
                    },
                )
            }

            if (!r.descripcion.isNullOrBlank()) {
                Spacer(Modifier.height(Espacio.s))
                Text(r.descripcion, style = MaterialTheme.typography.bodyMedium)
            }

            if (r.estadoEnum == EstadoReserva.CANCELACION_SOLICITADA) {
                Spacer(Modifier.height(Espacio.s))
                Text(
                    "Cancelación en revisión. Motivo: ${r.cancelacionMotivo ?: "—"}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = ColoresEstado.alerta,
                )
            }

            if (r.estadoEnum == EstadoReserva.POR_APROBAR) {
                Spacer(Modifier.height(Espacio.s))
                Text(
                    "Cierre solicitado por ${r.finalizacionSolicitadaPor ?: "una de las partes"}. " +
                        "Un administrador revisará las evidencias.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = ColoresEstado.alerta,
                )
            }
        }
    }
}

@Composable
private fun LineaTiempo(r: Reservacion) {
    val catalogos = LocalCatalogos.current
    val pasos = catalogos.pasos(r.recurso)
    val actual = r.pasoActual(catalogos)

    Column {
        Text("Seguimiento", style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(Espacio.s))

        pasos.forEachIndexed { i, paso ->
            val hecho = i < actual
            val esActual = i == actual

            Row(
                Modifier.fillMaxWidth().padding(vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    Modifier
                        .size(24.dp)
                        .background(
                            color = when {
                                hecho -> ColoresEstado.exito
                                esActual -> MaterialTheme.colorScheme.primary
                                else -> MaterialTheme.colorScheme.surfaceVariant
                            },
                            shape = CircleShape,
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    if (hecho) {
                        Icon(
                            Icons.Default.Check,
                            contentDescription = null,
                            tint = Color.White,
                            modifier = Modifier.size(16.dp),
                        )
                    }
                }
                Spacer(Modifier.size(Espacio.m))
                Text(
                    paso.etiqueta,
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = if (esActual) FontWeight.Bold else FontWeight.Normal,
                    color = if (hecho || esActual) MaterialTheme.colorScheme.onSurface
                    else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun SeccionExpedientes(
    expedientes: List<mx.portgo.app.data.model.Expediente>,
    esCliente: Boolean,
    habilitado: Boolean,
    onAbrir: (String) -> Unit,
    onSolicitar: (EtapaExpediente) -> Unit,
) {
    Column {
        Text("Documentación del viaje", style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(Espacio.s))

        EtapaExpediente.entries.forEach { etapa ->
            val exp = expedientes.firstOrNull { it.etapa == etapa.db }

            when {
                exp != null -> {
                    val dias = exp.diasParaVacios
                    AssistChip(
                        onClick = { onAbrir(etapa.db) },
                        label = {
                            Text(
                                buildString {
                                    append(etapa.etiqueta)
                                    if (exp.completo) append(" ✓")
                                    if (dias != null) append(" · ${dias} d")
                                },
                            )
                        },
                        leadingIcon = {
                            Icon(
                                Icons.Default.Description,
                                contentDescription = null,
                                tint = if (exp.completo) ColoresEstado.exito else ColoresEstado.alerta,
                            )
                        },
                    )
                }
                // Solo el transportista solicita documentación; el cliente la sube.
                !esCliente -> {
                    OutlinedButton(
                        onClick = { onSolicitar(etapa) },
                        enabled = habilitado,
                    ) { Text("Solicitar ${etapa.etiqueta.lowercase()}") }
                }
                else -> Unit
            }
            Spacer(Modifier.height(Espacio.xs))
        }

        if (expedientes.isEmpty() && esCliente) {
            Text(
                "El transportista aún no te ha pedido documentación.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun ListaEvidencias(
    titulo: String,
    urls: List<String?>,
    onAbrir: (String) -> Unit,
) {
    if (urls.isEmpty()) return
    Column(Modifier.padding(top = Espacio.s)) {
        Text(
            titulo,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        urls.forEachIndexed { i, url ->
            if (url == null) {
                Text(
                    "Evidencia ${i + 1} (no disponible)",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                TextButton(onClick = { onAbrir(url) }) { Text("Ver evidencia ${i + 1}") }
            }
        }
    }
}

@Composable
private fun DialogoCalificar(
    onCerrar: () -> Unit,
    onEnviar: (Int, String?) -> Unit,
) {
    var estrellas by remember { mutableIntStateOf(5) }
    var comentario by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onCerrar,
        title = { Text("Calificar el servicio") },
        text = {
            Column {
                Row(horizontalArrangement = Arrangement.Center, modifier = Modifier.fillMaxWidth()) {
                    (1..5).forEach { n ->
                        IconButton(onClick = { estrellas = n }) {
                            Icon(
                                if (n <= estrellas) Icons.Default.Star else Icons.Default.StarBorder,
                                contentDescription = "$n estrella${if (n == 1) "" else "s"}",
                                tint = ColoresEstado.alerta,
                                modifier = Modifier.size(32.dp),
                            )
                        }
                    }
                }
                Spacer(Modifier.height(Espacio.s))
                OutlinedTextField(
                    value = comentario,
                    onValueChange = { comentario = it },
                    label = { Text("Comentario (opcional)") },
                    minLines = 3,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(onClick = { onEnviar(estrellas, comentario.trim().ifBlank { null }) }) {
                Text("Enviar")
            }
        },
        dismissButton = { TextButton(onClick = onCerrar) { Text("Cancelar") } },
    )
}
