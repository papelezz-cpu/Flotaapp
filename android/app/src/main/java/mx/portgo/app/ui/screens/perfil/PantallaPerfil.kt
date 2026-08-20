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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
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
import mx.portgo.app.ui.components.EncabezadoModulo
import mx.portgo.app.ui.components.FilaDato
import mx.portgo.app.ui.components.TarjetaFicha
import mx.portgo.app.ui.theme.ColoresEstado
import mx.portgo.app.ui.theme.Espacio
import mx.portgo.app.ui.theme.PortGoColor
import mx.portgo.app.ui.theme.SpaceGrotesk

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
            EncabezadoModulo(titulo = "Perfil", onAtras = null)

            Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = Espacio.m),
            ) {
                Identidad(usuario, perfil)

                Spacer(Modifier.height(Espacio.m))

                perfil?.let { p ->
                    TarjetaFicha {
                        TituloTarjeta("Datos de la cuenta")
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
                    Spacer(Modifier.height(Espacio.gapRejilla))
                }

                TarjetaFicha {
                    TituloTarjeta("Preferencias")

                    FilaInterruptor(
                        titulo = "Desbloqueo biométrico",
                        detalle = "Pide huella, rostro o PIN al abrir la app. La sesión se " +
                            "guarda cifrada en el dispositivo.",
                        marcado = biometria,
                        onCambio = {
                            biometria = it
                            sesionVm.biometriaActiva = it
                        },
                    )

                    Spacer(Modifier.height(Espacio.s))
                    HorizontalDivider(thickness = 1.dp, color = PortGoColor.Divisor)
                    Spacer(Modifier.height(Espacio.s))

                    FilaInterruptor(
                        titulo = "Correos de avisos",
                        detalle = if (usuario.esCliente) {
                            "Avisos de ofertas nuevas en tus solicitudes."
                        } else {
                            "Avisos de solicitudes nuevas que puedes atender."
                        } + " Los correos del servicio contratado siempre llegan.",
                        marcado = notifEmail,
                        onCambio = { quiere ->
                            notifEmail = quiere
                            alcance.launch {
                                val r = container.auth
                                    .actualizarPreferenciaCorreo(usuario.id, quiere)
                                if (r is Resultado.Error) {
                                    notifEmail = !quiere // revertir: no se guardó
                                    snackbar.showSnackbar(r.error.mensaje)
                                }
                            }
                        },
                    )
                }

                Spacer(Modifier.height(Espacio.gapRejilla))

                TarjetaFicha {
                    TituloTarjeta("Cuenta y documentos")
                    Text(
                        // Las unidades ya se registran desde la app; lo que sigue
                        // siendo exclusivo de la web son los choferes y los
                        // documentos fiscales de la empresa.
                        if (usuario.esCliente) {
                            "Tus documentos fiscales y los datos de facturación se " +
                                "gestionan en el sitio web."
                        } else {
                            "El alta de choferes y los documentos fiscales de la empresa " +
                                "se hacen en el sitio web, donde se adjuntan los archivos " +
                                "y sus vigencias."
                        },
                        style = MaterialTheme.typography.bodyMedium,
                        color = PortGoColor.TextoSecundario,
                    )
                    Spacer(Modifier.height(Espacio.s))
                    OutlinedButton(
                        onClick = {
                            contexto.startActivity(
                                Intent(
                                    Intent.ACTION_VIEW,
                                    Uri.parse("${BuildConfig.WEB_URL}/app.html"),
                                ),
                            )
                        },
                        shape = RoundedCornerShape(12.dp),
                    ) {
                        Icon(
                            Icons.AutoMirrored.Filled.OpenInNew,
                            contentDescription = null,
                            modifier = Modifier.size(17.dp),
                        )
                        Spacer(Modifier.width(Espacio.s))
                        Text("Abrir PortGo en el navegador")
                    }
                }

                Spacer(Modifier.height(Espacio.l))

                OutlinedButton(
                    onClick = { confirmarSalir = true },
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
                ) {
                    Icon(
                        Icons.AutoMirrored.Filled.Logout,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(Modifier.width(Espacio.s))
                    Text("Cerrar sesión")
                }

                Spacer(Modifier.height(Espacio.m))
                Text(
                    "PortGo ${BuildConfig.VERSION_NAME}",
                    style = MaterialTheme.typography.bodySmall,
                    color = PortGoColor.TextoTerciario,
                    modifier = Modifier.align(Alignment.CenterHorizontally),
                )
                Spacer(Modifier.height(Espacio.xl))
            }
        }
    }

    if (confirmarSalir) {
        AlertDialog(
            onDismissRequest = { confirmarSalir = false },
            containerColor = PortGoColor.Superficie,
            shape = RoundedCornerShape(18.dp),
            title = { Text("¿Cerrar sesión?", color = PortGoColor.Tinta) },
            text = {
                Text(
                    "Tendrás que escribir tu correo y contraseña la próxima vez.",
                    color = PortGoColor.TextoSecundario,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    confirmarSalir = false
                    onCerrarSesion()
                }) { Text("Cerrar sesión", color = ColoresEstado.peligro) }
            },
            dismissButton = {
                TextButton(onClick = { confirmarSalir = false }) {
                    Text("Cancelar", color = PortGoColor.TextoSecundario)
                }
            },
        )
    }
}

/**
 * Bloque de identidad.
 *
 * La inicial en un círculo teal sustituye a la foto: en esta app nadie sube
 * avatar, así que un marcador de imagen vacío solo ocuparía espacio.
 */
@Composable
private fun Identidad(usuario: UsuarioActual, perfil: Perfil?) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier
                .size(56.dp)
                .clip(CircleShape)
                .background(PortGoColor.TealTenue),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                usuario.nombre.take(1).uppercase(),
                fontFamily = SpaceGrotesk,
                fontWeight = FontWeight.Bold,
                style = MaterialTheme.typography.headlineSmall,
                color = PortGoColor.TealOscuro,
            )
        }
        Spacer(Modifier.width(Espacio.m))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    usuario.nombre,
                    fontFamily = SpaceGrotesk,
                    fontWeight = FontWeight.Bold,
                    style = MaterialTheme.typography.titleLarge,
                    color = PortGoColor.Tinta,
                )
                if (perfil?.verificado == true) {
                    Spacer(Modifier.width(Espacio.xs))
                    Icon(
                        Icons.Default.Verified,
                        contentDescription = "Cuenta verificada",
                        tint = PortGoColor.Teal,
                        modifier = Modifier.size(19.dp),
                    )
                }
            }
            Text(
                usuario.email,
                style = MaterialTheme.typography.bodyMedium,
                color = PortGoColor.TextoSecundario,
            )
            Text(
                if (usuario.esCliente) "Cliente" else "Empresa transportista",
                style = MaterialTheme.typography.bodySmall,
                color = PortGoColor.TextoTerciario,
            )
        }
    }
}

@Composable
private fun TituloTarjeta(texto: String) {
    Text(
        texto,
        style = MaterialTheme.typography.titleMedium,
        color = PortGoColor.Tinta,
    )
    Spacer(Modifier.height(Espacio.s))
}

@Composable
private fun FilaInterruptor(
    titulo: String,
    detalle: String,
    marcado: Boolean,
    onCambio: (Boolean) -> Unit,
) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(
                titulo,
                style = MaterialTheme.typography.bodyLarge,
                color = PortGoColor.Tinta,
            )
            Text(
                detalle,
                style = MaterialTheme.typography.bodySmall,
                color = PortGoColor.TextoSecundario,
            )
        }
        Spacer(Modifier.width(Espacio.s))
        Switch(
            checked = marcado,
            onCheckedChange = onCambio,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color.White,
                checkedTrackColor = PortGoColor.Teal,
                checkedBorderColor = PortGoColor.Teal,
            ),
        )
    }
}
