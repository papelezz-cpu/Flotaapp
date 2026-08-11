package mx.portgo.app.ui.screens.perfil

import android.content.Intent
import android.net.Uri
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
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import mx.portgo.app.BuildConfig
import mx.portgo.app.core.Resultado
import mx.portgo.app.data.model.Perfil
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.di.AppContainer
import mx.portgo.app.ui.SesionViewModel
import mx.portgo.app.ui.components.FilaDato
import mx.portgo.app.ui.theme.ColoresEstado
import mx.portgo.app.ui.theme.Espacio

@Composable
fun PantallaPerfil(
    usuario: UsuarioActual,
    container: AppContainer,
    sesionVm: SesionViewModel,
    onCerrarSesion: () -> Unit,
) {
    val contexto = LocalContext.current
    val alcance = rememberCoroutineScope()
    val snackbar = remember { SnackbarHostState() }

    var perfil by remember { mutableStateOf<Perfil?>(null) }
    var notifEmail by remember { mutableStateOf(true) }
    var biometria by rememberSaveable { mutableStateOf(sesionVm.biometriaActiva) }
    var confirmarSalir by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(usuario.id) {
        when (val r = container.auth.perfil(usuario.id)) {
            is Resultado.Ok -> {
                perfil = r.dato
                notifEmail = r.dato?.notifEmail ?: true
            }
            is Resultado.Error -> snackbar.showSnackbar(r.error.mensaje)
        }
    }

    Scaffold(snackbarHost = { SnackbarHost(snackbar) }) { relleno ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(relleno)
                .verticalScroll(rememberScrollState())
                .padding(Espacio.m),
        ) {
            // ── Identidad ──
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier
                        .size(56.dp)
                        .clip(CircleShape)
                        .background(MaterialTheme.colorScheme.primaryContainer),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        usuario.nombre.take(1).uppercase(),
                        style = MaterialTheme.typography.headlineSmall,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                }
                Spacer(Modifier.size(Espacio.m))
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            usuario.nombre,
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.Bold,
                        )
                        if (perfil?.verificado == true) {
                            Spacer(Modifier.size(Espacio.xs))
                            Icon(
                                Icons.Default.Verified,
                                contentDescription = "Cuenta verificada",
                                tint = ColoresEstado.info,
                                modifier = Modifier.size(20.dp),
                            )
                        }
                    }
                    Text(
                        usuario.email,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        if (usuario.esCliente) "Cliente" else "Empresa transportista",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            Spacer(Modifier.height(Espacio.l))

            // ── Datos fiscales ──
            perfil?.let { p ->
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(Espacio.m)) {
                        Text("Datos de la cuenta", style = MaterialTheme.typography.titleMedium)
                        Spacer(Modifier.height(Espacio.s))
                        FilaDato("Razón social", p.razonSocial)
                        FilaDato("RFC", p.rfc)
                        FilaDato("Teléfono", p.telefono)
                        FilaDato(
                            "Verificación",
                            when (p.metodoVerificacion) {
                                "fisica" -> "Verificación física"
                                "documental" -> "Verificación documental"
                                else -> null
                            },
                        )
                    }
                }
                Spacer(Modifier.height(Espacio.m))
            }

            // ── Preferencias ──
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(Espacio.m)) {
                    Text("Preferencias", style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.height(Espacio.s))

                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text("Desbloqueo biométrico", style = MaterialTheme.typography.bodyLarge)
                            Text(
                                "Pide huella, rostro o PIN al abrir la app. La sesión se guarda " +
                                    "cifrada en el dispositivo.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Switch(
                            checked = biometria,
                            onCheckedChange = {
                                biometria = it
                                sesionVm.biometriaActiva = it
                            },
                        )
                    }

                    Spacer(Modifier.height(Espacio.m))
                    HorizontalDivider()
                    Spacer(Modifier.height(Espacio.m))

                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text("Correos de avisos", style = MaterialTheme.typography.bodyLarge)
                            Text(
                                if (usuario.esCliente) {
                                    "Avisos de ofertas nuevas en tus solicitudes."
                                } else {
                                    "Avisos de solicitudes nuevas que puedes atender."
                                } + " Los correos del servicio contratado siempre llegan.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Switch(
                            checked = notifEmail,
                            onCheckedChange = { quiere ->
                                notifEmail = quiere
                                alcance.launch {
                                    val r = container.auth
                                        .actualizarPreferenciaCorreo(usuario.id, quiere)
                                    if (r is Resultado.Error) {
                                        notifEmail = !quiere  // revertir: no se guardó
                                        snackbar.showSnackbar(r.error.mensaje)
                                    }
                                }
                            },
                        )
                    }
                }
            }

            Spacer(Modifier.height(Espacio.m))

            // ── Enlaces ──
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(Espacio.m)) {
                    Text("Cuenta y documentos", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "El alta de unidades, choferes y documentos fiscales se hace en el " +
                            "sitio web, donde se adjuntan los archivos y sus vigencias.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(Espacio.s))
                    OutlinedButton(
                        onClick = {
                            contexto.startActivity(
                                Intent(Intent.ACTION_VIEW, Uri.parse("${BuildConfig.WEB_URL}/app.html")),
                            )
                        },
                    ) { Text("Abrir PortGo en el navegador") }
                }
            }

            Spacer(Modifier.height(Espacio.l))

            OutlinedButton(
                onClick = { confirmarSalir = true },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.AutoMirrored.Filled.Logout, contentDescription = null)
                Spacer(Modifier.size(Espacio.s))
                Text("Cerrar sesión")
            }

            Spacer(Modifier.height(Espacio.m))
            Text(
                "PortGo ${BuildConfig.VERSION_NAME}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.align(Alignment.CenterHorizontally),
            )
            Spacer(Modifier.height(Espacio.xl))
        }
    }

    if (confirmarSalir) {
        AlertDialog(
            onDismissRequest = { confirmarSalir = false },
            title = { Text("¿Cerrar sesión?") },
            text = { Text("Tendrás que escribir tu correo y contraseña la próxima vez.") },
            confirmButton = {
                TextButton(onClick = {
                    confirmarSalir = false
                    onCerrarSesion()
                }) { Text("Cerrar sesión") }
            },
            dismissButton = {
                TextButton(onClick = { confirmarSalir = false }) { Text("Cancelar") }
            },
        )
    }
}
