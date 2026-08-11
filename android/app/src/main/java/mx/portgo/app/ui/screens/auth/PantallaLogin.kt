package mx.portgo.app.ui.screens.auth

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Anchor
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.launch
import mx.portgo.app.BuildConfig
import mx.portgo.app.ui.SesionViewModel
import mx.portgo.app.ui.theme.Espacio

/**
 * Acceso a la app.
 *
 * Deliberadamente **no** incluye el alta de cuenta. Registrarse en PortGo son
 * ~25 campos fiscales y hasta ocho documentos (INE, constancia de situación
 * fiscal, acta constitutiva, opinión de cumplimiento del SAT, fotos de las
 * instalaciones), y termina en una revisión manual que tarda hasta dos días
 * hábiles. Es un trámite de escritorio que se hace una sola vez, con los
 * papeles a la mano. El botón abre ese formulario en el navegador del sistema
 * en vez de reimplementarlo en el teléfono.
 */
@Composable
fun PantallaLogin(
    vm: SesionViewModel,
    mensajeInicial: String? = null,
    onMensajeVisto: () -> Unit = {},
) {
    val contexto = LocalContext.current
    val teclado = LocalSoftwareKeyboardController.current
    val alcance = rememberCoroutineScope()
    val snackbar = remember { SnackbarHostState() }
    val ocupado by vm.ocupado.collectAsStateWithLifecycle()

    var correo by rememberSaveable { mutableStateOf(vm.correoRecordado.orEmpty()) }
    var contrasena by rememberSaveable { mutableStateOf("") }
    var verContrasena by rememberSaveable { mutableStateOf(false) }
    var mostrarRecuperar by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(mensajeInicial) {
        mensajeInicial?.let {
            // Indefinite: los motivos por los que no pudiste entrar (cuenta
            // suspendida, enlace vencido) hay que poder leerlos con calma, no
            // que se vayan solos en tres segundos.
            snackbar.showSnackbar(it, actionLabel = "Entendido", duration = SnackbarDuration.Indefinite)
            onMensajeVisto()
        }
    }

    fun entrar() {
        teclado?.hide()
        if (correo.isBlank() || contrasena.isBlank()) {
            alcance.launch { snackbar.showSnackbar("Escribe tu correo y contraseña.") }
            return
        }
        vm.iniciarSesion(correo, contrasena) { error ->
            alcance.launch { snackbar.showSnackbar(error) }
        }
    }

    Scaffold(snackbarHost = { SnackbarHost(snackbar) }) { relleno ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(relleno)
                .verticalScroll(rememberScrollState())
                .imePadding()
                .padding(horizontal = Espacio.l),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Spacer(Modifier.height(Espacio.xl))

            Icon(
                Icons.Default.Anchor,
                contentDescription = null,
                modifier = Modifier.size(56.dp),
                tint = MaterialTheme.colorScheme.primary,
            )
            Spacer(Modifier.height(Espacio.s))
            Text(
                "PortGo",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
            )
            Text(
                "Transporte portuario",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Spacer(Modifier.height(Espacio.xl))

            OutlinedTextField(
                value = correo,
                onValueChange = { correo = it },
                label = { Text("Correo") },
                singleLine = true,
                enabled = !ocupado,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Email,
                    imeAction = ImeAction.Next,
                ),
                modifier = Modifier.fillMaxWidth(),
            )

            Spacer(Modifier.height(Espacio.s))

            OutlinedTextField(
                value = contrasena,
                onValueChange = { contrasena = it },
                label = { Text("Contraseña") },
                singleLine = true,
                enabled = !ocupado,
                visualTransformation = if (verContrasena) VisualTransformation.None
                else PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Password,
                    imeAction = ImeAction.Done,
                ),
                keyboardActions = KeyboardActions(onDone = { entrar() }),
                trailingIcon = {
                    IconButton(onClick = { verContrasena = !verContrasena }) {
                        Icon(
                            if (verContrasena) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                            contentDescription = if (verContrasena) "Ocultar contraseña"
                            else "Mostrar contraseña",
                        )
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            )

            Spacer(Modifier.height(Espacio.l))

            Button(
                onClick = { entrar() },
                enabled = !ocupado,
                modifier = Modifier.fillMaxWidth().height(52.dp),
            ) {
                if (ocupado) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary,
                    )
                } else {
                    Text("Entrar")
                }
            }

            TextButton(onClick = { mostrarRecuperar = true }, enabled = !ocupado) {
                Text("Olvidé mi contraseña")
            }

            Spacer(Modifier.height(Espacio.l))

            Text(
                "¿Todavía no tienes cuenta?",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            TextButton(
                onClick = {
                    contexto.startActivity(
                        Intent(Intent.ACTION_VIEW, Uri.parse("${BuildConfig.WEB_URL}/app.html")),
                    )
                },
            ) {
                Text("Registrarme en portgo.mx")
            }
            Text(
                "El alta pide documentos fiscales y la revisa nuestro equipo. " +
                    "Se hace desde el sitio web.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )

            Spacer(Modifier.height(Espacio.xl))
        }
    }

    if (mostrarRecuperar) {
        DialogoRecuperar(
            correoInicial = correo,
            onCerrar = { mostrarRecuperar = false },
            onEnviar = { destino ->
                mostrarRecuperar = false
                vm.recuperarContrasena(destino) { msg ->
                    alcance.launch { snackbar.showSnackbar(msg) }
                }
            },
        )
    }
}

@Composable
private fun DialogoRecuperar(
    correoInicial: String,
    onCerrar: () -> Unit,
    onEnviar: (String) -> Unit,
) {
    var destino by remember { mutableStateOf(correoInicial) }

    AlertDialog(
        onDismissRequest = onCerrar,
        title = { Text("Recuperar contraseña") },
        text = {
            Column {
                Text(
                    "Te mandamos un enlace para elegir una nueva.",
                    style = MaterialTheme.typography.bodyMedium,
                )
                Spacer(Modifier.height(Espacio.m))
                OutlinedTextField(
                    value = destino,
                    onValueChange = { destino = it },
                    label = { Text("Correo") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onEnviar(destino) },
                enabled = destino.isNotBlank(),
            ) { Text("Enviar") }
        },
        dismissButton = { TextButton(onClick = onCerrar) { Text("Cancelar") } },
    )
}
