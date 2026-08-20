package mx.portgo.app.data.repository

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import mx.portgo.app.core.Resultado
import mx.portgo.app.core.intentar
import mx.portgo.app.data.model.Camion
import mx.portgo.app.data.model.Operador

/**
 * Flota de la empresa: unidades y choferes.
 *
 * Incluye el ALTA desde el telefono. La version anterior solo consultaba, con
 * el argumento de que dar de alta una unidad es "un tramite de escritorio que
 * se hace una vez". El argumento era malo: quien recibe una unidad nueva esta
 * en el patio, junto al camion, sin computadora. El tramite no se pospone,
 * simplemente no ocurre.
 *
 * Las altas van por RPC y no por INSERT directo porque escriben mas de una
 * fila. En el caso del operador eso incluye el consentimiento de datos
 * sensibles, que es obligacion legal: un expediente con examenes medicos y
 * antecedentes no debe poder existir sin la constancia que lo ampara.
 */
class FlotaRepository(private val supabase: SupabaseClient) {

    suspend fun camiones(propietarioId: String): Resultado<List<Camion>> = intentar {
        supabase.from("camiones").select {
            filter { eq("propietario_id", propietarioId) }
            order("id", Order.ASCENDING)
        }.decodeList()
    }

    /** Unidades que sí se pueden ofrecer: aprobadas y libres. */
    suspend fun camionesOfertables(
        propietarioId: String,
        tipoRequerido: String?,
    ): Resultado<List<Camion>> = intentar {
        supabase.from("camiones").select {
            filter {
                eq("propietario_id", propietarioId)
                eq("aprobacion", "aprobada")
                neq("estado", "no_disponible")
                // Mismo gate que la web: el camión ofertado debe ser del tipo
                // que pide la solicitud. La RPC `enviar_oferta` lo vuelve a
                // verificar; esto es para no mostrar opciones que van a fallar.
                if (!tipoRequerido.isNullOrBlank()) eq("tipo", tipoRequerido)
            }
            order("id", Order.ASCENDING)
        }.decodeList()
    }

    suspend fun operadores(propietarioId: String): Resultado<List<Operador>> = intentar {
        supabase.from("operadores").select {
            filter { eq("propietario_id", propietarioId) }
            order("nombre", Order.ASCENDING)
        }.decodeList()
    }

    suspend fun operadoresDisponibles(propietarioId: String): Resultado<List<Operador>> = intentar {
        supabase.from("operadores").select {
            filter {
                eq("propietario_id", propietarioId)
                eq("aprobacion", "aprobada")
            }
            order("nombre", Order.ASCENDING)
        }.decodeList()
    }

    /**
     * Marca una unidad como disponible o fuera de servicio.
     *
     * No toca `ocupado`: ese lo pone y lo quita el flujo de reservaciones, y
     * dejar que alguien lo cambie a mano desconectaría la unidad de su servicio
     * en curso.
     */
    suspend fun marcarDisponibilidad(
        camionId: String,
        disponible: Boolean,
    ): Resultado<Unit> = intentar {
        supabase.from("camiones").update(
            mapOf("estado" to if (disponible) "disponible" else "no_disponible"),
        ) {
            filter {
                eq("id", camionId)
                neq("estado", "ocupado")
            }
        }
    }

    /** Documentos por vencer en los próximos [dias], para el aviso del inicio. */
    suspend fun vigenciasPorVencer(
        propietarioId: String,
        dias: Long = 30,
    ): List<Pair<Camion, Pair<String, Long>>> = runCatching {
        supabase.from("camiones").select {
            filter { eq("propietario_id", propietarioId) }
        }.decodeList<Camion>()
            .mapNotNull { camion -> camion.proximoVencimiento?.let { camion to it } }
            .filter { (_, venc) -> venc.second <= dias }
            .sortedBy { (_, venc) -> venc.second }
    }.getOrDefault(emptyList())

    // ── Altas y edicion ───────────────────────────────────────────────────

    /**
     * Da de alta o edita una unidad. Devuelve su numero economico.
     *
     * Los archivos se suben antes y aqui solo viajan sus rutas. Al editar, los
     * campos de archivo que van en null NO borran lo que ya habia: si el
     * usuario no volvio a fotografiar la tarjeta de circulacion, se conserva.
     */
    suspend fun guardarCamion(
        datos: JsonObject,
        idExistente: String? = null,
    ): Resultado<String> = intentar {
        supabase.postgrest.rpc(
            "guardar_camion",
            buildJsonObject {
                put("p_datos", datos)
                put("p_id", idExistente)
            },
        ).decodeAs<String>()
    }

    /** Da de alta un chofer. Devuelve su identificador. */
    suspend fun altaOperador(datos: JsonObject): Resultado<String> = intentar {
        supabase.postgrest.rpc(
            "alta_operador",
            buildJsonObject {
                put("p_datos", datos)
                put("p_version_aviso", VERSION_AVISO_PRIVACIDAD)
            },
        ).decodeAs<String>()
    }

    /**
     * Baja de una unidad.
     *
     * Solo se permite si no esta ocupada: una unidad atada a un servicio en
     * curso dejaria la reservacion sin recurso asignado. La condicion va en el
     * filtro, asi que si esta ocupada no borra nada.
     */
    suspend fun eliminarCamion(id: String): Resultado<Unit> = intentar {
        supabase.from("camiones").delete {
            filter {
                eq("id", id)
                neq("estado", "ocupado")
            }
        }
    }

    suspend fun eliminarOperador(id: String): Resultado<Unit> = intentar {
        supabase.from("operadores").delete { filter { eq("id", id) } }
    }

    /**
     * Siguiente numero de trabajador libre, para proponerlo en el alta.
     * Replica la numeracion de js/operadores.js.
     */
    suspend fun siguienteNumTrabajador(propietarioId: String): String {
        val usados = runCatching {
            supabase.from("operadores")
                .select(Columns.list("num_trabajador")) { filter { eq("propietario_id", propietarioId) } }
                .decodeList<Operador>()
                .mapNotNull { it.numTrabajador?.filter(Char::isDigit)?.toIntOrNull() }
        }.getOrDefault(emptyList())
        return ((usados.maxOrNull() ?: 0) + 1).toString().padStart(3, '0')
    }

    companion object {
        /**
         * Version del aviso de privacidad que se registra con el consentimiento.
         * Debe coincidir con LEGAL_VERSION_PRIVACIDAD en js/auth.js: si las dos
         * se separan, no se puede saber a quien hay que volver a pedirselo.
         */
        const val VERSION_AVISO_PRIVACIDAD = "borrador-0"
    }

}
