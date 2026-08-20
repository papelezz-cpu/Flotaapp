package mx.portgo.app.ui.components

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldColors
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.material3.Button
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import mx.portgo.app.ui.theme.PortGoColor

/**
 * Paleta de los campos de formulario.
 *
 * Va en un solo sitio y no repetida en cada pantalla porque el diseño no
 * especifica los formularios: si el criterio queda copiado en seis archivos, el
 * primer ajuste que pida el usuario al ver la app en un teléfono real habría
 * que aplicarlo seis veces, y bastaría olvidar uno para que un formulario se
 * viera de otro producto.
 *
 * El borde sin foco es el mismo de las tarjetas, así los campos pertenecen al
 * mismo sistema; el foco es teal, que es como esta app dice "aquí estás".
 */
@Composable
fun coloresCampo(): TextFieldColors = OutlinedTextFieldDefaults.colors(
    focusedBorderColor = PortGoColor.Teal,
    unfocusedBorderColor = PortGoColor.BordeTarjeta,
    disabledBorderColor = PortGoColor.BordeTarjeta,
    focusedLabelColor = PortGoColor.TealOscuro,
    unfocusedLabelColor = PortGoColor.TextoSecundario,
    cursorColor = PortGoColor.Teal,
    focusedTextColor = PortGoColor.Tinta,
    unfocusedTextColor = PortGoColor.Tinta,
    disabledTextColor = PortGoColor.TextoSecundario,
    focusedContainerColor = PortGoColor.Superficie,
    unfocusedContainerColor = PortGoColor.Superficie,
    disabledContainerColor = PortGoColor.Superficie,
)

/** Radio de los campos y botones de formulario, para no repetir el número. */
val RadioCampo = RoundedCornerShape(12.dp)

/**
 * Botón principal de una pantalla.
 *
 * Incluye el estado ocupado dentro y no fuera: el patrón de deshabilitar el
 * botón y poner el spinner en otro lado deja al usuario sin saber si su toque
 * se registró. Aquí el spinner ocupa el sitio del texto, en el mismo botón que
 * acaba de tocar.
 */
@Composable
fun BotonPrincipal(
    texto: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    ocupado: Boolean = false,
    habilitado: Boolean = true,
) {
    Button(
        onClick = onClick,
        enabled = habilitado && !ocupado,
        shape = RadioCampo,
        colors = ButtonDefaults.buttonColors(
            containerColor = PortGoColor.Teal,
            contentColor = Color.White,
            disabledContainerColor = PortGoColor.Teal.copy(alpha = 0.4f),
            disabledContentColor = Color.White.copy(alpha = 0.8f),
        ),
        modifier = modifier
            .fillMaxWidth()
            .height(50.dp),
    ) {
        if (ocupado) {
            CircularProgressIndicator(
                modifier = Modifier.size(20.dp),
                strokeWidth = 2.dp,
                color = Color.White,
            )
        } else {
            Text(texto, style = MaterialTheme.typography.titleMedium)
        }
    }
}
