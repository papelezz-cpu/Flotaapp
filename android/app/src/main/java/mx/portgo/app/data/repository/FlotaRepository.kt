package mx.portgo.app.data.repository

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Order
import mx.portgo.app.core.Resultado
import mx.portgo.app.core.intentar
import mx.portgo.app.data.model.Camion
import mx.portgo.app.data.model.Operador

/**
 * Flota de la empresa: unidades y choferes.
 *
 * Alcance deliberado del MVP: **consulta y disponibilidad, no alta ni edición**.
 *
 * Dar de alta un camión son ~35 campos y cuatro documentos con sus vigencias
 * (tarjeta de circulación, seguro, permiso SCT, CAAT, verificación), y cada
 * cambio dispara de nuevo el flujo de aprobación del superadmin. Ese formulario
 * se llena una vez, sentado, y ya existe en la web. Lo que sí se hace desde el
 * teléfono, todos los días y desde el patio, es mirar qué unidad está libre,
 * cuál tiene un documento por vencer y elegir cuál asignar a una oferta.
 *
 * `marcarDisponibilidad` es la única escritura: es un solo UPDATE que el guard
 * `guard_fleet_resource_update` ya protege — impide auto-aprobarse y transferir
 * la propiedad, que son los dos abusos posibles.
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
}
