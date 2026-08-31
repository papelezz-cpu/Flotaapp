package mx.portgo.app.core

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
import androidx.core.content.FileProvider
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Archivos temporales para capturar con la cámara.
 *
 * `TakePicture` necesita que la app le entregue de antemano el `Uri` donde
 * escribir. No se puede pasar un `File` directo: desde Android 7 compartir un
 * `file://` con otra app lanza `FileUriExposedException`, así que va por
 * FileProvider (declarado en el manifiesto).
 *
 * Se usa `cacheDir` a propósito y no el almacenamiento permanente: la foto solo
 * tiene que sobrevivir hasta que se suba a Storage. Si el usuario abandona el
 * formulario a la mitad, el sistema limpia la caché solo.
 *
 * Por qué importa la cámara aquí: en la web, subir la tarjeta de circulación
 * significa tener un escaneo hecho de antes. En el patio, junto a la unidad, se
 * fotografía en el momento. Es el trámite más pesado del alta y en el teléfono
 * se vuelve el más natural.
 */
object CapturaArchivo {

    /**
     * Si el dispositivo tiene una app de camara que la nuestra pueda ver.
     *
     * Lo segundo importa tanto como lo primero: desde Android 11 la
     * visibilidad de paquetes esta restringida y sin el bloque <queries> del
     * manifiesto esto devuelve false aunque haya camara. Tambien devuelve
     * false, con razon, en un emulador configurado sin camara.
     */
    fun hayCamara(contexto: Context): Boolean = runCatching {
        contexto.packageManager
            .resolveActivity(Intent(MediaStore.ACTION_IMAGE_CAPTURE), 0) != null
    }.getOrDefault(false)

    fun nuevoDestino(contexto: Context, prefijo: String): Pair<File, Uri> {
        val carpeta = File(contexto.cacheDir, "capturas").apply { mkdirs() }
        val marca = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        val archivo = File(carpeta, "${prefijo}_$marca.jpg")

        val uri = FileProvider.getUriForFile(
            contexto,
            "${contexto.packageName}.fileprovider",
            archivo,
        )
        return archivo to uri
    }

    /** Borra las capturas ya subidas. Se llama al salir del formulario. */
    fun limpiar(contexto: Context) {
        runCatching {
            File(contexto.cacheDir, "capturas").listFiles()?.forEach { it.delete() }
        }
    }
}
