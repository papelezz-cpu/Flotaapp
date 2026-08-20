package mx.portgo.app.ui.screens.solicitudes

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
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import mx.portgo.app.core.Fmt
import mx.portgo.app.data.model.EstadoOferta
import mx.portgo.app.data.model.Oferta
import mx.portgo.app.data.model.Pedido
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.di.AppContainer
import mx.portgo.app.ui.LocalCatalogos
import mx.portgo.app.ui.components.BannerError
import mx.portgo.app.ui.components.ChipEstadoOferta
import mx.portgo.app.ui.components.EncabezadoModulo
import mx.portgo.app.ui.components.SeccionFicha
import mx.portgo.app.ui.components.TarjetaFicha
import mx.portgo.app.ui.components.ChipEstadoPedido
import mx.portgo.app.ui.components.EsqueletoLista
import mx.portgo.app.ui.components.FilaDato
import mx.portgo.app.ui.theme.ColoresEstado
import mx.portgo.app.ui.theme.Espacio
import mx.portgo.app.ui.theme.PortGoColor
import mx.portgo.app.ui.theme.Radio
import mx.portgo.app.ui.theme.SpaceGrotesk
import mx.portgo.app.ui.viewmodel.EstadoCarga
import mx.portgo.app.ui.viewmodel.SolicitudDetalleViewModel
import mx.portgo.app.ui.viewmodel.vmFactory

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PantallaSolicitudDetalle(
    pedidoId: String,
    usuario: UsuarioActual,
    container: AppContainer,
    onAtras: () -> Unit,
    onAbrirChat: (otroId: String, titulo: String, pedidoId: String) -> Unit,
) {
    val vm: SolicitudDetalleViewModel = viewModel(
        key = pedidoId,
        factory = vmFactory {
            SolicitudDetalleViewModel(container.pedidos, container.flota, usuario, pedidoId)
        },
    )
    val estado by vm.estado.collectAsStateWithLifecycle()
    val ocupado by vm.ocupado.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }

    LaunchedEffect(Unit) {
        vm.avisos.collect { snackbar.showSnackbar(it) }
    }

    var mostrarOferta by rememberSaveable { mutableStateOf(false) }
    var contraofertarA by rememberSaveable { mutableStateOf<String?>(null) }
    var rechazarA by rememberSaveable { mutableStateOf<String?>(null) }
    var confirmarCancelar by rememberSaveable { mutableStateOf(false) }

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
            EncabezadoModulo(titulo = "Solicitud", onAtras = onAtras)
            if (ocupado) LinearProgressIndicator(Modifier.fillMaxWidth())

            when (val e = estado) {
                is EstadoCarga.Cargando -> EsqueletoLista(3)

                is EstadoCarga.Fallo -> BannerError(e.mensaje, onReintentar = vm::cargar)

                is EstadoCarga.Listo -> {
                    val datos = e.datos
                    Column(
                        Modifier
                            .fillMaxSize()
                            .verticalScroll(rememberScrollState())
                            .padding(Espacio.m),
                    ) {
                        FichaSolicitud(datos.pedido)

                        Spacer(Modifier.height(Espacio.m))

                        // ── Empresa: ofertar ──
                        if (usuario.esEmpresa) {
                            val yaOferte = datos.ofertas.any {
                                it.adminId == usuario.id && it.estadoEnum.esViva
                            }
                            val miOfertaConContra = datos.ofertas.firstOrNull {
                                it.adminId == usuario.id && it.estadoEnum == EstadoOferta.CONTRA_OFERTA
                            }

                            when {
                                miOfertaConContra != null -> TarjetaContraofertaRecibida(
                                    oferta = miOfertaConContra,
                                    habilitado = !ocupado,
                                    onAceptar = { vm.responderContraoferta(miOfertaConContra.id, true) },
                                    onRechazar = { vm.responderContraoferta(miOfertaConContra.id, false) },
                                )

                                yaOferte -> Text(
                                    "Ya enviaste tu oferta. Te avisamos cuando el cliente responda.",
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )

                                datos.pedido.estadoEnum.admiteOfertas -> Button(
                                    onClick = { mostrarOferta = true },
                                    enabled = !ocupado,
                                    modifier = Modifier.fillMaxWidth(),
                                ) { Text("Hacer una oferta") }

                                else -> Text(
                                    "Esta solicitud ya no admite ofertas.",
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }

                        // ── Ofertas recibidas ──
                        if (datos.ofertas.isNotEmpty()) {
                            Spacer(Modifier.height(Espacio.l))
                            Text(
                                if (usuario.esCliente) "Ofertas recibidas" else "Ofertas en esta solicitud",
                                style = MaterialTheme.typography.titleMedium,
                            )
                            Spacer(Modifier.height(Espacio.s))

                            // A la empresa se le muestran las ajenas sin
                            // identificar: necesita saber contra cuánto compite,
                            // no con quién.
                            datos.ofertas.forEach { oferta ->
                                val esMia = oferta.adminId == usuario.id
                                TarjetaOferta(
                                    oferta = oferta,
                                    verNombre = usuario.esCliente || esMia,
                                    esMia = esMia,
                                    habilitado = !ocupado,
                                    puedeResponder = usuario.esCliente &&
                                        oferta.estadoEnum == EstadoOferta.ENVIADA,
                                    onAceptar = { vm.aceptarOferta(oferta.id) },
                                    onContraofertar = { contraofertarA = oferta.id },
                                    onRechazar = { rechazarA = oferta.id },
                                    onChat = {
                                        oferta.adminId?.let {
                                            onAbrirChat(it, oferta.adminNombre ?: "Empresa", pedidoId)
                                        }
                                    },
                                )
                                Spacer(Modifier.height(Espacio.s))
                            }
                        }

                        // ── Cliente: cancelar ──
                        if (usuario.esCliente && !datos.pedido.estadoEnum.esTerminal &&
                            datos.pedido.estadoEnum.admiteOfertas
                        ) {
                            Spacer(Modifier.height(Espacio.l))
                            OutlinedButton(
                                onClick = { confirmarCancelar = true },
                                enabled = !ocupado,
                                modifier = Modifier.fillMaxWidth(),
                            ) { Text("Cancelar solicitud") }
                        }

                        Spacer(Modifier.height(Espacio.xl))
                    }
                }
            }
        }
    }

    // ── Diálogos ──
    if (mostrarOferta) {
        val camiones by vm.camiones.collectAsStateWithLifecycle()
        val operadores by vm.operadores.collectAsStateWithLifecycle()
        DialogoHacerOferta(
            camiones = camiones,
            operadores = operadores,
            onCerrar = { mostrarOferta = false },
            onEnviar = { camion, precio, operador, mensaje ->
                mostrarOferta = false
                vm.enviarOferta(camion, precio, operador, mensaje)
            },
        )
    }

    contraofertarA?.let { id ->
        DialogoPrecio(
            titulo = "Contraoferta",
            descripcion = "Propón el precio al que sí cerrarías el trato.",
            etiquetaBoton = "Enviar contraoferta",
            onCerrar = { contraofertarA = null },
            onConfirmar = { precio ->
                contraofertarA = null
                vm.contraofertar(id, precio)
            },
        )
    }

    rechazarA?.let { id ->
        DialogoNota(
            titulo = "Rechazar oferta",
            descripcion = "Puedes decirle a la empresa por qué. Es opcional.",
            etiquetaBoton = "Rechazar",
            peligro = true,
            onCerrar = { rechazarA = null },
            onConfirmar = { nota ->
                rechazarA = null
                vm.rechazarOferta(id, nota)
            },
        )
    }

    if (confirmarCancelar) {
        AlertDialog(
            onDismissRequest = { confirmarCancelar = false },
            title = { Text("¿Cancelar esta solicitud?") },
            text = { Text("Las ofertas activas quedarán descartadas.") },
            confirmButton = {
                TextButton(onClick = {
                    confirmarCancelar = false
                    vm.cancelarSolicitud()
                }) { Text("Sí, cancelar") }
            },
            dismissButton = {
                TextButton(onClick = { confirmarCancelar = false }) { Text("No") }
            },
        )
    }
}

@Composable
private fun FichaSolicitud(p: Pedido) {
    TarjetaFicha {
        run {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top,
            ) {
                Text(
                    p.tipoCamion ?: "Servicio",
                    style = MaterialTheme.typography.titleLarge,
                    modifier = Modifier.weight(1f),
                )
                ChipEstadoPedido(p.estadoEnum)
            }

            if (p.unidadCorregida) {
                Text(
                    "El cliente ajustó la unidad sugerida (${p.tipoCamionSugerido}).",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            SeccionFicha("Ruta y fechas")

            FilaDato("Ruta", p.ruta)
            FilaDato("Arribo a puerto", p.fechaArriboPuerto?.let { Fmt.fecha(it) })
            FilaDato("Carga / entrega", Fmt.rangoFechas(p.fechaIni, p.fechaFin))
            FilaDato(
                "Tipo de carga",
                LocalCatalogos.current.categoria(p.categoriaCarga)?.etiqueta
                    ?: p.categoriaCarga ?: p.tipoCarga,
            )
            FilaDato("Peso", p.pesoCarga?.let { "${Fmt.numero(it)} kg" })
            FilaDato("Tarimas", p.numTarimas?.toString())
            FilaDato("Bultos", p.numBultos?.toString())

            if (p.refrigerado) {
                FilaDato(
                    "Refrigeración",
                    listOfNotNull(p.tempMin?.let { "mín ${Fmt.numero(it)}°" },
                        p.tempMax?.let { "máx ${Fmt.numero(it)}°" })
                        .joinToString(" · ").ifBlank { "Sí" },
                )
            }

            if ((p.numContenedores ?: 0) > 0) {
                FilaDato("Contenedores", buildString {
                    append(p.numContenedores)
                    p.contenedor1Tipo?.let { append(" · $it") }
                    p.contenedor2Tipo?.let { append(" + $it") }
                })
            }

            // Se muestra si el pedido trae medidas, sin preguntar por el nombre
            // de la categoría: esa lista ahora es editable desde el catálogo.
            if (p.tieneDimensiones) {
                FilaDato(
                    "Medidas",
                    listOfNotNull(p.largoM, p.anchoM, p.altoM)
                        .joinToString(" × ") { Fmt.numero(it) } + " m",
                )
            }

            if (p.cargaPeligrosa) {
                FilaDato(
                    "Material peligroso",
                    listOfNotNull(p.hazmatClase?.let { "Clase $it" }, p.hazmatUn?.let { "UN $it" })
                        .joinToString(" · ").ifBlank { "Sí" },
                )
            }

            if (p.entraAPuerto) {
                Spacer(Modifier.height(Espacio.s))
                Text(
                    "⚓ Requiere ingreso al recinto portuario",
                    style = MaterialTheme.typography.bodySmall,
                    color = ColoresEstado.alerta,
                    fontWeight = FontWeight.Medium,
                )
            }

            FilaDato("Presupuesto", p.precioCliente?.let { Fmt.precioMxn(it) })
            FilaDato("Plazo de pago", p.plazoPago)

            if (!p.descripcion.isNullOrBlank()) {
                SeccionFicha("Notas")
                Text(p.descripcion, style = MaterialTheme.typography.bodyMedium)
            }

            if (!p.rechazoNota.isNullOrBlank()) {
                Spacer(Modifier.height(Espacio.s))
                Text(
                    "Motivo de la devolución: ${p.rechazoNota}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.error,
                )
            }
        }
    }
}

@Composable
private fun TarjetaOferta(
    oferta: Oferta,
    verNombre: Boolean,
    esMia: Boolean,
    habilitado: Boolean,
    puedeResponder: Boolean,
    onAceptar: () -> Unit,
    onContraofertar: () -> Unit,
    onRechazar: () -> Unit,
    onChat: () -> Unit,
) {
    Card(
        Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Radio.tarjeta),
        colors = CardDefaults.cardColors(
            // La propia oferta se distingue con un teñido teal muy suave, no
            // con un borde grueso: en una lista de cinco ofertas lo que hay que
            // comparar son los precios, no encontrar la propia.
            containerColor = if (esMia) PortGoColor.TealTenue else PortGoColor.Superficie,
        ),
        border = BorderStroke(1.dp, if (esMia) PortGoColor.Teal else PortGoColor.BordeTarjeta),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Column(Modifier.padding(15.dp)) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text(
                        when {
                            esMia -> "Tu oferta"
                            verNombre -> oferta.adminNombre ?: "Empresa"
                            else -> "Otra empresa"
                        },
                        style = MaterialTheme.typography.titleMedium,
                    )
                    oferta.creadoEn?.let {
                        Text(
                            Fmt.hace(it),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                ChipEstadoOferta(oferta.estadoEnum)
            }

            Spacer(Modifier.height(Espacio.s))

            Text(
                Fmt.precioMxn(oferta.precioOferta),
                fontFamily = SpaceGrotesk,
                fontWeight = FontWeight.Bold,
                style = MaterialTheme.typography.headlineSmall,
                color = PortGoColor.TealOscuro,
            )

            if (oferta.contraPrecio != null) {
                Text(
                    "Contraoferta del cliente: ${Fmt.precioMxn(oferta.contraPrecio)}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = ColoresEstado.alerta,
                )
            }

            if (verNombre) {
                FilaDato("Unidad", oferta.camionId)
                FilaDato("Chofer", oferta.operadorNombre)
            }

            if (!oferta.mensaje.isNullOrBlank() && verNombre) {
                Spacer(Modifier.height(Espacio.xs))
                Text(oferta.mensaje, style = MaterialTheme.typography.bodyMedium)
            }

            if (puedeResponder) {
                Spacer(Modifier.height(Espacio.m))
                Row(horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
                    Button(
                        onClick = onAceptar,
                        enabled = habilitado,
                        modifier = Modifier.weight(1f),
                    ) { Text("Aceptar") }

                    OutlinedButton(
                        onClick = onContraofertar,
                        enabled = habilitado,
                        modifier = Modifier.weight(1f),
                    ) { Text("Contraofertar") }
                }
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    TextButton(onClick = onRechazar, enabled = habilitado) { Text("Rechazar") }
                    TextButton(onClick = onChat) {
                        Icon(
                            Icons.AutoMirrored.Filled.Chat,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp),
                        )
                        Spacer(Modifier.size(Espacio.xs))
                        Text("Mensaje")
                    }
                }
            }
        }
    }
}

@Composable
private fun TarjetaContraofertaRecibida(
    oferta: Oferta,
    habilitado: Boolean,
    onAceptar: () -> Unit,
    onRechazar: () -> Unit,
) {
    Card(
        Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Radio.tarjeta),
        colors = CardDefaults.cardColors(containerColor = ColoresEstado.alertaSuave),
        border = BorderStroke(1.dp, ColoresEstado.alerta),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Column(Modifier.padding(15.dp)) {
            Text("El cliente te contraofertó", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(Espacio.s))
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(Espacio.l),
            ) {
                Column {
                    Text(
                        "Tu oferta",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(Fmt.precioMxn(oferta.precioOferta), style = MaterialTheme.typography.titleMedium)
                }
                Column {
                    Text(
                        "Su propuesta",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        Fmt.precioMxn(oferta.contraPrecio),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
            Spacer(Modifier.height(Espacio.m))
            Row(horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
                Button(onClick = onAceptar, enabled = habilitado, modifier = Modifier.weight(1f)) {
                    Text("Aceptar")
                }
                OutlinedButton(
                    onClick = onRechazar,
                    enabled = habilitado,
                    modifier = Modifier.weight(1f),
                ) { Text("Rechazar") }
            }
        }
    }
}
