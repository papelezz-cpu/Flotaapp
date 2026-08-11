package mx.portgo.app.data.repository

import android.content.Context
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import mx.portgo.app.BuildConfig
import mx.portgo.app.data.model.Catalogos
import mx.portgo.app.data.model.EstadoApp
import mx.portgo.app.data.model.OpcionCatalogo

/**
 * Catálogos y configuración remota.
 *
 * Se resuelve todo en **una sola llamada** (`arranque_app`) porque esto corre
 * en el puerto, con señal mala: cada viaje de red extra en el arranque es otra
 * oportunidad de que la app se quede colgada en la pantalla inicial.
 *
 * Estrategia de caché, en este orden:
 *   1. Al construirse, lee el disco de inmediato (síncrono, es un archivo
 *      chico) para que la primera pantalla ya tenga datos reales.
 *   2. Pide al servidor en segundo plano y actualiza si llega algo.
 *   3. Si no hay red y no hay caché, quedan los valores por defecto
 *      compilados, que son idénticos a los que había antes de mover esto al
 *      servidor. La app **siempre** abre.
 */
class ConfiguracionRepository(
    private val supabase: SupabaseClient,
    context: Context,
) {

    private val archivo = File(context.applicationContext.filesDir, "catalogos.json")

    private val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        coerceInputValues = true
    }

    private val _catalogos = MutableStateFlow(leerDeDisco() ?: Catalogos.PorDefecto)
    val catalogos: StateFlow<Catalogos> = _catalogos.asStateFlow()

    private val _estado = MutableStateFlow(EstadoApp())
    val estado: StateFlow<EstadoApp> = _estado.asStateFlow()

    /**
     * Refresca desde el servidor. Se llama al arrancar y al volver a primer
     * plano.
     *
     * No devuelve error a la interfaz a propósito: si falla, la app sigue con
     * lo que ya tenía. Un catálogo que no se pudo actualizar no es motivo para
     * molestar a nadie ni para impedir trabajar.
     */
    suspend fun refrescar(): EstadoApp = withContext(Dispatchers.IO) {
        val respuesta = runCatching {
            supabase.postgrest.rpc(
                "arranque_app",
                buildJsonObject {
                    put("p_plataforma", "android")
                    put("p_version", BuildConfig.VERSION_NAME)
                },
            ).decodeAs<JsonObject>()
        }.getOrElse { return@withContext _estado.value }

        runCatching {
            _estado.value = json.decodeFromJsonElement(EstadoApp.serializer(), respuesta)
        }

        val crudos = respuesta["catalogos"] as? JsonObject
        if (crudos != null && crudos.isNotEmpty()) {
            val nuevos = construir(crudos)
            _catalogos.value = nuevos
            guardarEnDisco(crudos)
        }

        _estado.value
    }

    // ── Armado ────────────────────────────────────────────────────────────

    /**
     * Convierte el objeto plano `{clave: [opciones]}` que devuelve la base al
     * modelo de la app.
     *
     * Cada lista cae a su valor por defecto si viene vacía. Eso protege del
     * error de captura más probable: desactivar por accidente todas las filas
     * de un catálogo y dejar un desplegable vacío en producción.
     */
    private fun construir(crudos: JsonObject): Catalogos {
        fun lista(clave: String): List<OpcionCatalogo> = runCatching {
            (crudos[clave] as? JsonArray)
                ?.map { json.decodeFromJsonElement(OpcionCatalogo.serializer(), it) }
                .orEmpty()
        }.getOrDefault(emptyList())

        val porDefecto = Catalogos.PorDefecto

        val tracking = crudos.keys
            .filter { it.startsWith(Catalogos.PREFIJO_TRACKING) }
            .associate { clave ->
                clave.removePrefix(Catalogos.PREFIJO_TRACKING) to lista(clave)
            }
            .filterValues { it.size >= 2 }

        return Catalogos(
            plazosPago = lista(Catalogos.PLAZO_PAGO).ifEmpty { porDefecto.plazosPago },
            tiposContenedor = lista(Catalogos.TIPO_CONTENEDOR).ifEmpty { porDefecto.tiposContenedor },
            categoriasCarga = lista(Catalogos.CATEGORIA_CARGA).ifEmpty { porDefecto.categoriasCarga },
            tiposUnidad = lista(Catalogos.TIPO_UNIDAD).ifEmpty { porDefecto.tiposUnidad },
            tracking = porDefecto.tracking + tracking,
        )
    }

    // ── Caché en disco ────────────────────────────────────────────────────
    // Un archivo plano en filesDir: son unos pocos KB de listas públicas, no
    // hace falta base de datos ni cifrado (eso es para la sesión, que sí vive
    // en el Keystore).

    private fun guardarEnDisco(crudos: JsonObject) {
        runCatching { archivo.writeText(crudos.toString()) }
    }

    private fun leerDeDisco(): Catalogos? = runCatching {
        if (!archivo.exists()) return null
        construir(json.parseToJsonElement(archivo.readText()).jsonObject)
    }.getOrNull()
}
