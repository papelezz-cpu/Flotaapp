package mx.portgo.app.data.repository

import android.content.ContentResolver
import android.net.Uri
import android.provider.OpenableColumns
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.storage.storage
import kotlin.time.Duration.Companion.hours
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import mx.portgo.app.core.Resultado
import mx.portgo.app.core.intentar

/**
 * Subida y lectura de archivos.
 *
 * Los buckets `unidades`, `registros` y `documentos-viaje` son **privados**. La
 * base guarda **rutas**, nunca URLs, y las URLs se firman al momento de
 * mostrar. Usar `getPublicUrl` en esos buckets devolvería un enlace que no
 * funciona — y si algún día el bucket se hiciera público, expondría pedimentos
 * y facturas comerciales.
 *
 * La ruta de una evidencia empieza con el `auth.uid()` de quien sube, porque
 * la política de Storage exige que el primer segmento sea el del usuario.
 */
class StorageRepository(
    private val supabase: SupabaseClient,
    private val resolver: ContentResolver,
) {

    /** Máximo por archivo. Mismo límite que valida la web en el registro. */
    private val maxBytes = 10L * 1024 * 1024

    private val tiposPermitidos = setOf(
        "image/jpeg", "image/png", "image/webp", "application/pdf",
    )

    /**
     * Sube una evidencia de servicio al bucket privado `unidades`.
     * Devuelve la **ruta**, que es lo que se guarda en la base.
     */
    suspend fun subirEvidencia(
        miId: String,
        reservaId: String,
        uri: Uri,
    ): Resultado<String> = intentar {
        val bytes = leer(uri)
        val ext = extensionDe(uri)
        val ruta = "$miId/evidencias/$reservaId/${System.currentTimeMillis()}_${aleatorio()}.$ext"

        supabase.storage.from(BUCKET_UNIDADES).upload(ruta, bytes)
        ruta
    }

    /** Sube un documento del expediente al bucket privado `documentos-viaje`. */
    suspend fun subirDocumentoViaje(
        expedienteId: String,
        uri: Uri,
    ): Resultado<Pair<String, String>> = intentar {
        val bytes = leer(uri)
        val nombre = nombreDe(uri) ?: "documento.${extensionDe(uri)}"
        // La política de Storage resuelve el permiso a partir del primer
        // segmento de la ruta, así que tiene que ser el id del expediente.
        val ruta = "$expedienteId/${System.currentTimeMillis()}_$nombre"

        supabase.storage.from(BUCKET_VIAJE).upload(ruta, bytes)
        ruta to nombre
    }

    /**
     * Firma una ruta para poder abrirla. Una hora de vigencia, igual que la web.
     *
     * Tolera entradas heredadas que ya son URL completa: hay evidencias viejas
     * guardadas así, de cuando el bucket era público.
     */
    suspend fun urlFirmada(
        ruta: String,
        bucket: String = BUCKET_UNIDADES,
    ): String? {
        if (ruta.startsWith("http")) return ruta
        return runCatching {
            supabase.storage.from(bucket).createSignedUrl(ruta, 1.hours)
        }.getOrNull()
    }

    suspend fun urlsFirmadas(
        rutas: List<String>,
        bucket: String = BUCKET_UNIDADES,
    ): List<String?> = rutas.map { urlFirmada(it, bucket) }

    /** Los buckets públicos sí admiten URL directa. */
    fun urlPublica(ruta: String, bucket: String): String =
        if (ruta.startsWith("http")) ruta
        else supabase.storage.from(bucket).publicUrl(ruta)

    // ── Utilidades ────────────────────────────────────────────────────────

    private suspend fun leer(uri: Uri): ByteArray = withContext(Dispatchers.IO) {
        val tipo = resolver.getType(uri)
        if (tipo != null && tipo !in tiposPermitidos) {
            error("El archivo debe ser JPG, PNG, WEBP o PDF.")
        }

        val bytes = resolver.openInputStream(uri)?.use { it.readBytes() }
            ?: error("No se pudo leer el archivo seleccionado.")

        if (bytes.size > maxBytes) {
            error("El archivo excede 10 MB. Usa una imagen o PDF más pequeño.")
        }
        bytes
    }

    private fun nombreDe(uri: Uri): String? = runCatching {
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }
    }.getOrNull()

    private fun extensionDe(uri: Uri): String {
        nombreDe(uri)?.substringAfterLast('.', "")?.takeIf { it.isNotBlank() }?.let { return it.lowercase() }
        return when (resolver.getType(uri)) {
            "image/png" -> "png"
            "image/webp" -> "webp"
            "application/pdf" -> "pdf"
            else -> "jpg"
        }
    }

    private fun aleatorio(): String =
        (1..8).map { ('a'..'z') .random() }.joinToString("")

    companion object {
        const val BUCKET_UNIDADES = "unidades"
        const val BUCKET_VIAJE = "documentos-viaje"
        const val BUCKET_OPERADORES = "operadores"
        const val BUCKET_EMPRESA = "documentos-empresa"
    }
}
