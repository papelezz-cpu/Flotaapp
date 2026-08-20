package mx.portgo.app.ui.screens.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.fragment.app.FragmentActivity
import kotlinx.coroutines.launch
import mx.portgo.app.core.BiometricGate
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.ui.components.BotonPrincipal
import mx.portgo.app.ui.theme.Espacio
import mx.portgo.app.ui.theme.PortGoColor
import mx.portgo.app.ui.theme.SpaceGrotesk

/**
 * Pantalla de bloqueo.
 *
 * Aparece cuando hay una sesión válida guardada pero el usuario activó el
 * desbloqueo biométrico. Es la contraparte de persistir el refresh token: la
 * web cierra sesión al cerrar el navegador; aquí la sesión sobrevive, pero
 * hace falta la huella, el rostro o el PIN del dueño para usarla.
 *
 * Nunca muestra datos detrás: no hay una vista previa borrosa del contenido,
 * porque eso ya filtraría nombres de clientes y rutas a quien tenga el
 * teléfono en la mano.
 */
@Composable
fun PantallaBloqueo(
    usuario: UsuarioActual,
    activity: FragmentActivity,
    onDesbloqueado: () -> Unit,
    onSalir: () -> Unit,
) {
    val alcance = rememberCoroutineScope()
    var intentando by rememberSaveable { mutableStateOf(false) }
    var falloPrevio by rememberSaveable { mutableStateOf(false) }

    fun pedir() {
        if (intentando) return
        intentando = true
        alcance.launch {
            val ok = BiometricGate.solicitar(
                activity = activity,
                subtitulo = "Sesión de ${usuario.nombre}",
            )
            intentando = false
            if (ok) onDesbloqueado() else falloPrevio = true
        }
    }

    // Se pide en cuanto aparece: obligar a tocar un botón antes del diálogo del
    // sistema es un paso de más en algo que se hace decenas de veces al día.
    LaunchedEffect(Unit) {
        if (BiometricGate.disponibilidad(activity) == BiometricGate.Disponibilidad.DISPONIBLE) {
            pedir()
        } else {
            // El usuario tenía biometría activada y luego quitó su huella y su
            // PIN del sistema. No hay forma de verificar quién es: se cierra
            // sesión en vez de dejar entrar sin comprobación.
            onSalir()
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(PortGoColor.Arena)
            .padding(Espacio.xl),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Box(
            Modifier
                .size(88.dp)
                .clip(CircleShape)
                .background(PortGoColor.TealTenue),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Default.Fingerprint,
                contentDescription = null,
                modifier = Modifier.size(44.dp),
                tint = PortGoColor.TealOscuro,
            )
        }

        Spacer(Modifier.height(Espacio.l))
        Text(
            "PortGo está bloqueado",
            fontFamily = SpaceGrotesk,
            fontWeight = FontWeight.Bold,
            style = MaterialTheme.typography.titleLarge,
            color = PortGoColor.Tinta,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(Espacio.s))
        Text(
            "Identifícate para volver a la sesión de ${usuario.nombre}.",
            style = MaterialTheme.typography.bodyMedium,
            color = PortGoColor.TextoSecundario,
            textAlign = TextAlign.Center,
        )

        Spacer(Modifier.height(Espacio.xl))

        BotonPrincipal(
            texto = if (falloPrevio) "Intentar de nuevo" else "Desbloquear",
            onClick = { pedir() },
            ocupado = intentando,
        )

        TextButton(onClick = onSalir) {
            Text("Usar otra cuenta", color = PortGoColor.TextoSecundario)
        }
    }
}
