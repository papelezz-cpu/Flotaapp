package mx.portgo.app.ui.screens.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LockReset
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.launch
import mx.portgo.app.data.repository.AuthRepository
import mx.portgo.app.ui.SesionViewModel
import mx.portgo.app.ui.components.BotonPrincipal
import mx.portgo.app.ui.components.RadioCampo
import mx.portgo.app.ui.components.coloresCampo
import mx.portgo.app.ui.theme.ColoresEstado
import mx.portgo.app.ui.theme.Espacio
import mx.portgo.app.ui.theme.PortGoColor
import mx.portgo.app.ui.theme.SpaceGrotesk

/**
 * Elegir una contraseña nueva, tras llegar por el enlace del correo.
 *
 * Se muestra cuando el deep link `portgo://auth` entrega una sesión de
 * recuperación. Como ese esquema **solo** está registrado para el correo de
 * recuperación, cualquier deep link que llegue significa exactamente esto.
 *
 * Al terminar se cierra la sesión a propósito, igual que hace la web: obligar a
 * entrar con la contraseña nueva confirma que el usuario la recuerda, y deja
 * inservible el enlace del correo si alguien más lo tuviera.
 */
@Composable
fun PantallaNuevaContrasena(
    vm: SesionViewModel,
    onListo: () -> Unit,
) {
    val alcance = rememberCoroutineScope()
    val snackbar = remember { SnackbarHostState() }
    val ocupado by vm.ocupado.collectAsStateWithLifecycle()

    var contrasena by rememberSaveable { mutableStateOf("") }
    var confirmacion by rememberSaveable { mutableStateOf("") }
    var visible by rememberSaveable { mutableStateOf(false) }

    val muyCorta = contrasena.isNotEmpty() && contrasena.length < AuthRepository.MIN_CONTRASENA
    val noCoinciden = confirmacion.isNotEmpty() && contrasena != confirmacion
    val puedeGuardar = !muyCorta && !noCoinciden &&
        contrasena.length >= AuthRepository.MIN_CONTRASENA && contrasena == confirmacion

    Scaffold(
        snackbarHost = { SnackbarHost(snackbar) },
        containerColor = PortGoColor.Arena,
    ) { relleno ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(PortGoColor.Arena)
                .padding(relleno)
                .verticalScroll(rememberScrollState())
                .imePadding()
                .padding(Espacio.l),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Box(
                Modifier
                    .size(76.dp)
                    .clip(CircleShape)
                    .background(PortGoColor.TealTenue),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Default.LockReset,
                    contentDescription = null,
                    modifier = Modifier.size(38.dp),
                    tint = PortGoColor.TealOscuro,
                )
            }

            Spacer(Modifier.height(Espacio.m))

            Text(
                "Elige una contraseña nueva",
                fontFamily = SpaceGrotesk,
                fontWeight = FontWeight.Bold,
                style = MaterialTheme.typography.titleLarge,
                color = PortGoColor.Tinta,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(Espacio.s))
            Text(
                "Debe tener al menos ${AuthRepository.MIN_CONTRASENA} caracteres.",
                style = MaterialTheme.typography.bodyMedium,
                color = PortGoColor.TextoSecundario,
                textAlign = TextAlign.Center,
            )

            Spacer(Modifier.height(Espacio.l))

            OutlinedTextField(
                value = contrasena,
                onValueChange = { contrasena = it },
                label = { Text("Contraseña nueva") },
                singleLine = true,
                isError = muyCorta,
                shape = RadioCampo,
                colors = coloresCampo(),
                supportingText = if (muyCorta) {
                    {
                        Text(
                            "Mínimo ${AuthRepository.MIN_CONTRASENA} caracteres",
                            color = ColoresEstado.peligro,
                        )
                    }
                } else null,
                visualTransformation = if (visible) VisualTransformation.None
                else PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                trailingIcon = {
                    IconButton(onClick = { visible = !visible }) {
                        Icon(
                            if (visible) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                            contentDescription = if (visible) "Ocultar" else "Mostrar",
                            tint = PortGoColor.TextoSecundario,
                        )
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            )

            Spacer(Modifier.height(Espacio.gapRejilla))

            OutlinedTextField(
                value = confirmacion,
                onValueChange = { confirmacion = it },
                label = { Text("Repite la contraseña") },
                singleLine = true,
                isError = noCoinciden,
                shape = RadioCampo,
                colors = coloresCampo(),
                supportingText = if (noCoinciden) {
                    { Text("Las contraseñas no coinciden", color = ColoresEstado.peligro) }
                } else null,
                visualTransformation = if (visible) VisualTransformation.None
                else PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                modifier = Modifier.fillMaxWidth(),
            )

            Spacer(Modifier.height(Espacio.l))

            BotonPrincipal(
                texto = "Guardar y entrar",
                onClick = {
                    vm.cambiarContrasena(contrasena) { ok, mensaje ->
                        alcance.launch { snackbar.showSnackbar(mensaje) }
                        if (ok) onListo()
                    }
                },
                ocupado = ocupado,
                habilitado = puedeGuardar,
            )

            TextButton(onClick = onListo, enabled = !ocupado) {
                Text("Cancelar", color = PortGoColor.TextoSecundario)
            }
        }
    }
}
