package mx.portgo.app.ui.screens.expedientes

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.UploadFile
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import mx.portgo.app.data.model.EtapaExpediente
import mx.portgo.app.data.model.ExpedienteDocumento
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.di.AppContainer
import mx.portgo.app.ui.components.BannerError
import mx.portgo.app.ui.components.EncabezadoModulo
import mx.portgo.app.ui.components.EsqueletoLista
import mx.portgo.app.ui.screens.solicitudes.DialogoNota
import mx.portgo.app.ui.theme.ColoresEstado
import mx.portgo.app.ui.theme.Espacio
import mx.portgo.app.ui.theme.PortGoColor
import mx.portgo.app.ui.theme.Radio
import mx.portgo.app.ui.viewmodel.EstadoCarga
import mx.portgo.app.ui.viewmodel.ExpedienteViewModel
import mx.portgo.app.ui.viewmodel.abrirEnNavegador
import mx.portgo.app.ui.viewmodel.vmFactory

/**
 * Checklist documental de una etapa del viaje.
 *
 * Es checklist y no subida libre a propósito: con subida libre nadie sabe qué
 * falta, y lo que traba un contenedor en la aduana es exactamente el documento
 * que nadie notó que faltaba. Aquí las dos partes ven el mismo semáforo.
 *
 * Los papeles los sube el cliente (o su agente aduanal); quien los da por
 * buenos es el transportista, que es quien se queda varado si algo falta. El
 * guard `guard_expediente_documento` impone esa división en la base, así que la
 * app solo decide qué botones enseñar.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PantallaExpediente(
    reservaId: String,
    etapaClave: String,
    usuario: UsuarioActual,
    container: AppContainer,
    onAtras: () -> Unit,
) {
    val etapa = EtapaExpediente.de(etapaClave)

    val vm: ExpedienteViewModel = viewModel(
        key = "${usuario.id}-$reservaId-$etapaClave",
        factory = vmFactory {
            ExpedienteViewModel(
                container.reservaciones, container.storage, usuario, reservaId, etapaClave,
            )
        },
    )
    val estado by vm.estado.collectAsStateWithLifecycle()
    val ocupado by vm.ocupado.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }

    val contexto = LocalContext.current
    LaunchedEffect(Unit) { vm.avisos.collect { snackbar.showSnackbar(it) } }
    LaunchedEffect(Unit) { vm.abrirUrl.collect { abrirEnNavegador(contexto, it) } }

    var subiendoA by rememberSaveable { mutableStateOf<String?>(null) }
    var rechazandoA by rememberSaveable { mutableStateOf<String?>(null) }

    val selector = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument(),
    ) { uri: Uri? ->
        val docId = subiendoA
        subiendoA = null
        if (uri != null && docId != null) vm.adjuntar(docId, uri)
    }

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
            EncabezadoModulo(titulo = "Documentación", onAtras = onAtras)
            if (ocupado) LinearProgressIndicator(Modifier.fillMaxWidth())

            when (val e = estado) {
                is EstadoCarga.Cargando -> EsqueletoLista(4)
                is EstadoCarga.Fallo -> BannerError(e.mensaje, onReintentar = vm::cargar)

                is EstadoCarga.Listo -> {
                    val docs = e.datos
                    val faltantes = docs.count { it.obligatorio && !it.aceptado }

                    Column(
                        Modifier
                            .fillMaxSize()
                            .verticalScroll(rememberScrollState())
                            .padding(Espacio.m),
                    ) {
                        Text(
                            if (faltantes == 0) "Expediente completo"
                            else "Faltan $faltantes documento${if (faltantes == 1) "" else "s"} obligatorio${if (faltantes == 1) "" else "s"}",
                            style = MaterialTheme.typography.titleMedium,
                            color = if (faltantes == 0) ColoresEstado.exito else ColoresEstado.alerta,
                        )

                        if (etapa == EtapaExpediente.ENTREGA_VACIOS) {
                            Text(
                                "Las demoras corren por día desde que el contenedor sale de la " +
                                    "terminal hasta que entra al patio de vacíos.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }

                        Spacer(Modifier.height(Espacio.m))

                        docs.forEach { doc ->
                            TarjetaDocumento(
                                doc = doc,
                                esCliente = usuario.esCliente,
                                habilitado = !ocupado,
                                onSubir = {
                                    subiendoA = doc.id
                                    selector.launch(arrayOf("image/*", "application/pdf"))
                                },
                                onAceptar = { vm.dictaminar(doc.id, true, null) },
                                onRechazar = { rechazandoA = doc.id },
                                onVer = { vm.abrirArchivo(doc) },
                            )
                            Spacer(Modifier.height(Espacio.s))
                        }

                        Spacer(Modifier.height(Espacio.l))
                    }
                }
            }
        }
    }

    rechazandoA?.let { id ->
        DialogoNota(
            titulo = "Rechazar documento",
            descripcion = "Dile al cliente qué está mal para que lo pueda corregir.",
            etiquetaBoton = "Rechazar",
            obligatoria = true,
            peligro = true,
            onCerrar = { rechazandoA = null },
            onConfirmar = { nota ->
                rechazandoA = null
                vm.dictaminar(id, false, nota)
            },
        )
    }
}

@Composable
private fun TarjetaDocumento(
    doc: ExpedienteDocumento,
    esCliente: Boolean,
    habilitado: Boolean,
    onSubir: () -> Unit,
    onAceptar: () -> Unit,
    onRechazar: () -> Unit,
    onVer: () -> Unit,
) {
    val (icono, color) = when {
        doc.aceptado -> Icons.Default.CheckCircle to ColoresEstado.exito
        doc.rechazado -> Icons.Default.Error to ColoresEstado.peligro
        doc.subido -> Icons.Default.UploadFile to ColoresEstado.info
        else -> Icons.Default.RadioButtonUnchecked to ColoresEstado.neutro
    }

    // Blanca con borde, como el resto de las tarjetas. El relleno anterior era
    // surfaceVariant al 35%, y en este tema surfaceVariant ES el arena del
    // fondo: la tarjeta quedaba sin contorno sobre la pantalla.
    Card(
        Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Radio.tarjeta),
        colors = CardDefaults.cardColors(containerColor = PortGoColor.Superficie),
        border = BorderStroke(1.dp, PortGoColor.BordeTarjeta),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Column(Modifier.padding(15.dp)) {
            Row(verticalAlignment = Alignment.Top) {
                Icon(icono, contentDescription = null, tint = color, modifier = Modifier.size(22.dp))
                Spacer(Modifier.size(Espacio.s))
                Column(Modifier.weight(1f)) {
                    Row {
                        Text(
                            doc.nombre,
                            style = MaterialTheme.typography.titleMedium,
                            modifier = Modifier.weight(1f),
                        )
                        if (!doc.obligatorio) {
                            Text(
                                "Opcional",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    if (!doc.descripcion.isNullOrBlank()) {
                        Text(
                            doc.descripcion,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            if (doc.rechazado && !doc.notaRechazo.isNullOrBlank()) {
                Spacer(Modifier.height(Espacio.xs))
                Text(
                    "Motivo: ${doc.notaRechazo}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                    fontWeight = FontWeight.Medium,
                )
            }

            Spacer(Modifier.height(Espacio.s))

            Row(horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
                if (doc.archivoPath != null) {
                    TextButton(onClick = onVer) { Text("Ver archivo") }
                }

                if (esCliente && !doc.aceptado) {
                    OutlinedButton(onClick = onSubir, enabled = habilitado) {
                        Text(if (doc.archivoPath == null) "Subir" else "Reemplazar")
                    }
                }

                if (!esCliente && doc.subido) {
                    OutlinedButton(onClick = onAceptar, enabled = habilitado) { Text("Aceptar") }
                    TextButton(onClick = onRechazar, enabled = habilitado) { Text("Rechazar") }
                }
            }
        }
    }
}
