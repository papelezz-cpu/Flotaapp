package mx.portgo.app.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Listas de negocio que la app **lee del servidor** en vez de traerlas
 * compiladas.
 *
 * La razón es concreta: una app publicada queda congelada en el teléfono del
 * usuario. En la web, cambiar "metros cúbicos" por "tarimas" fue un commit y
 * 30 segundos; en móvil sería un build, la revisión de la tienda, y después
 * los equipos que nunca actualizan. De los últimos 15 commits de este repo,
 * cinco tocan el formulario de solicitud — es justo lo que no puede vivir
 * dentro del binario.
 *
 * Todo tiene un valor por defecto idéntico a lo que hoy está en el código, así
 * que la app arranca y funciona aunque nunca haya hablado con el servidor. Los
 * catálogos remotos **sustituyen** ese respaldo, no lo complementan.
 */
@Serializable
data class OpcionCatalogo(
    val valor: String,
    val etiqueta: String,
    val ayuda: String? = null,
    val meta: JsonObject? = null,
) {
    private fun metaTexto(clave: String): String? =
        runCatching { meta?.get(clave)?.jsonPrimitive?.content }.getOrNull()

    /** Icono del paso de seguimiento, cuando el catálogo lo trae. */
    val icono: String? get() = metaTexto("icono")

    /**
     * Qué campos pide una categoría de carga: `["peso","tarimas","refri"]`.
     * Es lo que hoy está duplicado en `NP_CARGA` (js/pedidos.js) y en las
     * propiedades `pide*` del formulario.
     */
    val campos: List<String>
        get() = runCatching {
            meta?.get("campos")
                ?.let { it as? kotlinx.serialization.json.JsonArray }
                ?.map { e -> e.jsonPrimitive.content }
                .orEmpty()
        }.getOrDefault(emptyList())
}

data class Catalogos(
    val plazosPago: List<OpcionCatalogo>,
    val tiposContenedor: List<OpcionCatalogo>,
    val categoriasCarga: List<OpcionCatalogo>,
    val tiposUnidad: List<OpcionCatalogo>,
    /** Pasos de seguimiento por tipo de recurso: `camion`, `custodio`, `patio`, `lavado`. */
    val tracking: Map<String, List<OpcionCatalogo>>,
) {

    /** Pasos del seguimiento para un recurso. Nunca devuelve lista vacía. */
    fun pasos(tipo: RecursoTipo): List<OpcionCatalogo> =
        tracking[tipo.db]?.takeIf { it.size >= 2 }
            ?: PorDefecto.tracking[tipo.db]
            ?: PorDefecto.tracking.getValue(RecursoTipo.CAMION.db)

    /** Índice del paso actual; 0 si el valor guardado no está en el catálogo. */
    fun indicePaso(tipo: RecursoTipo, estado: String?): Int =
        pasos(tipo).indexOfFirst { it.valor == estado }.coerceAtLeast(0)

    fun esUltimoPaso(tipo: RecursoTipo, estado: String?): Boolean =
        indicePaso(tipo, estado) == pasos(tipo).lastIndex

    fun siguientePaso(tipo: RecursoTipo, estado: String?): OpcionCatalogo? =
        pasos(tipo).getOrNull(indicePaso(tipo, estado) + 1)

    /** Etiqueta legible de una categoría de carga. */
    fun categoria(valor: String?): OpcionCatalogo? =
        categoriasCarga.firstOrNull { it.valor == valor }

    companion object {
        /**
         * Respaldo local: exactamente los valores que estaban escritos en el
         * código antes de mover esto al servidor.
         *
         * Se usa en tres momentos: el primerísimo arranque antes de la primera
         * respuesta, cuando no hay red y todavía no hay nada en caché, y si el
         * catálogo remoto llegara vacío por un error de captura. En puerto la
         * señal es mala; la app tiene que abrir de todos modos.
         */
        val PorDefecto = Catalogos(
            plazosPago = listOf(
                "Anticipado", "Contra entrega", "15 días", "30 días", "45 días", "60 días",
            ).map { OpcionCatalogo(it, it) },

            tiposContenedor = listOf(
                "20'" to "20 pies",
                "40'" to "40 pies",
                "40' HC" to "40 pies High Cube",
                "Reefer 20'" to "Reefer 20 pies",
                "Reefer 40'" to "Reefer 40 pies",
                "Open top" to "Open top",
                "Flat rack" to "Flat rack",
            ).map { (v, e) -> OpcionCatalogo(v, e) },

            categoriasCarga = listOf(
                Triple("General", "Carga general", "Tarimas, cajas, mercancía empacada"),
                Triple("Consolidada", "Consolidada", "Varios embarques en la misma unidad"),
                Triple("Suelta", "Carga suelta", "Granel, sacos, material sin empacar"),
                Triple("Sobredimensionada", "Sobredimensionada", "Excede medidas o peso estándar"),
                Triple("Hazmat", "Materiales peligrosos", "Requiere permiso y unidad certificada"),
                Triple("Contenerizada", "Contenerizada", "Contenedor de 20 o 40 pies"),
            ).map { (v, e, a) -> OpcionCatalogo(v, e, a) },

            tiposUnidad = listOf(
                "Camioneta 1.5 ton caja seca" to "Camioneta 1.5 ton",
                "Camioneta 3.5 ton caja seca" to "Camioneta 3.5 ton",
                "Rabón" to "Rabón",
                "Torton caja seca" to "Torton caja seca",
                "Torton plataforma" to "Torton plataforma",
                "Full" to "Full",
                "Full porta contenedor 40/20" to "Full porta contenedor",
                "Sencillo porta contenedor 40/20" to "Sencillo porta contenedor",
                "Plataforma de 3 ejes (sobrepeso)" to "Plataforma 3 ejes",
                "Lowboy" to "Lowboy / cama baja",
                "HAZMAT" to "HAZMAT",
            ).map { (v, e) -> OpcionCatalogo(v, e) },

            tracking = mapOf(
                "camion" to listOf(
                    OpcionCatalogo("Confirmado", "Confirmado"),
                    OpcionCatalogo("En camino", "En camino al origen"),
                    OpcionCatalogo("En carga", "En carga"),
                    OpcionCatalogo("En tránsito", "En tránsito"),
                    OpcionCatalogo("Entregado", "Entregado"),
                ),
                "custodio" to listOf(
                    OpcionCatalogo("Confirmado", "Confirmado"),
                    OpcionCatalogo("Asignado", "Custodio asignado"),
                    OpcionCatalogo("En ruta", "En ruta al punto"),
                    OpcionCatalogo("En servicio", "En servicio"),
                    OpcionCatalogo("Finalizado", "Servicio finalizado"),
                ),
                "patio" to listOf(
                    OpcionCatalogo("Confirmado", "Confirmado"),
                    OpcionCatalogo("Listo", "Patio listo"),
                    OpcionCatalogo("Recibido", "Vehículo recibido"),
                    OpcionCatalogo("En almacenaje", "En almacenaje"),
                    OpcionCatalogo("Liberado", "Vehículo liberado"),
                ),
                "lavado" to listOf(
                    OpcionCatalogo("Confirmado", "Confirmado"),
                    OpcionCatalogo("Recibido", "Vehículo recibido"),
                    OpcionCatalogo("En lavado", "En proceso de lavado"),
                    OpcionCatalogo("Control", "Control de calidad"),
                    OpcionCatalogo("Listo", "Listo para entrega"),
                ),
            ),
        )

        /** Claves con las que viajan los catálogos en la respuesta de `arranque_app`. */
        const val PLAZO_PAGO = "plazo_pago"
        const val TIPO_CONTENEDOR = "tipo_contenedor"
        const val CATEGORIA_CARGA = "categoria_carga"
        const val TIPO_UNIDAD = "tipo_unidad"
        const val PREFIJO_TRACKING = "tracking_"
    }
}

/** Aviso que el superadmin puede mostrar en el arranque sin publicar una versión. */
@Serializable
data class AvisoGlobal(
    val titulo: String,
    val mensaje: String,
    /** `info` | `alerta` */
    val tipo: String = "info",
)

/**
 * Lo que el servidor contesta al abrir la app.
 *
 * `soportada = false` es el interruptor de emergencia: bloquea las versiones
 * anteriores a `versionMinima` en la pantalla de arranque, antes de que puedan
 * escribir nada. No evita publicar versiones — hace que publicarlas sea seguro.
 */
@Serializable
data class EstadoApp(
    val soportada: Boolean = true,
    @SerialName("version_minima") val versionMinima: String? = null,
    @SerialName("url_descarga") val urlDescarga: String? = null,
    val aviso: AvisoGlobal? = null,
    val flags: Map<String, Boolean> = emptyMap(),
) {
    fun bandera(nombre: String, porDefecto: Boolean = false): Boolean =
        flags[nombre] ?: porDefecto
}
