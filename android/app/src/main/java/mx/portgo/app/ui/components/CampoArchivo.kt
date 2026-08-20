package mx.portgo.app.ui.components

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import mx.portgo.app.core.CapturaArchivo
import mx.portgo.app.ui.theme.ColoresEstado
import mx.portgo.app.ui.theme.Espacio

/**
 * Campo para adjuntar un documento o foto, con cámara y galería.
 *
 * La cámara va primero y como botón principal a propósito: es la razón por la
 * que dar de alta una unidad desde el teléfono resulta mejor que desde la web.
 * Ahí hay que tener un escaneo hecho de antes; aquí se fotografía la tarjeta de
 * circulación parado junto al camión. La galería queda como alternativa para
 * quien ya trae el archivo o un PDF.
 *
 * El estado se muestra con icono Y texto, no solo con color: en pantalla y con
 * sol de mediodía, el color no basta.
 */
@Composable
fun CampoArchivo(
    etiqueta: String,
    ayuda: String? = null,
    adjunto: Uri?,
    onAdjuntar: (Uri) -> Unit,
    onQuitar: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val contexto = LocalContext.current
    var uriPendiente by remember { mutableStateOf<Uri?>(null) }

    val camara = rememberLauncherForActivityResult(
        ActivityResultContracts.TakePicture(),
    ) { exito ->
        // Solo se acepta si la cámara confirmó que escribió: si el usuario
        // cancela, el archivo temporal existe pero está vacío.
        uriPendiente?.let { if (exito) onAdjuntar(it) }
        uriPendiente = null
    }

    val galeria = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument(),
    ) { uri -> uri?.let(onAdjuntar) }

    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f),
        ),
    ) {
        Column(Modifier.padding(Espacio.m)) {
            Row(verticalAlignment = Alignment.Top) {
                Icon(
                    if (adjunto != null) Icons.Default.CheckCircle
                    else Icons.Default.RadioButtonUnchecked,
                    contentDescription = null,
                    tint = if (adjunto != null) ColoresEstado.exito else ColoresEstado.neutro,
                    modifier = Modifier.size(22.dp),
                )
                Spacer(Modifier.size(Espacio.s))
                Column(Modifier.weight(1f)) {
                    Text(etiqueta, style = MaterialTheme.typography.titleMedium)
                    Text(
                        if (adjunto != null) "Adjuntado" else ayuda ?: "Sin adjuntar",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (adjunto != null) {
                    IconButton(onClick = onQuitar) {
                        Icon(Icons.Default.Close, contentDescription = "Quitar $etiqueta")
                    }
                }
            }

            if (adjunto == null) {
                Spacer(Modifier.height(Espacio.s))
                Row(horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
                    OutlinedButton(
                        onClick = {
                            val (_, uri) = CapturaArchivo.nuevoDestino(
                                contexto,
                                etiqueta.replace(Regex("[^A-Za-z0-9]"), "_"),
                            )
                            uriPendiente = uri
                            camara.launch(uri)
                        },
                        modifier = Modifier.weight(1f),
                    ) {
                        Icon(Icons.Default.PhotoCamera, contentDescription = null)
                        Spacer(Modifier.size(Espacio.xs))
                        Text("Cámara")
                    }
                    OutlinedButton(
                        onClick = { galeria.launch(arrayOf("image/*", "application/pdf")) },
                        modifier = Modifier.weight(1f),
                    ) {
                        Icon(Icons.Default.PhotoLibrary, contentDescription = null)
                        Spacer(Modifier.size(Espacio.xs))
                        Text("Archivo")
                    }
                }
            }
        }
    }
}
