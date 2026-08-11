package mx.portgo.app.data.repository

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.realtime.PostgresAction
import io.github.jan.supabase.realtime.channel
import io.github.jan.supabase.realtime.decodeRecord
import io.github.jan.supabase.realtime.postgresChangeFlow
import io.github.jan.supabase.realtime.realtime
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.flow.onCompletion
import kotlinx.coroutines.flow.onStart
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.add
import mx.portgo.app.core.Resultado
import mx.portgo.app.core.intentar
import mx.portgo.app.data.model.Mensaje

/**
 * Chat contextual a una solicitud o a una reservación.
 *
 * Un mismo pedido puede tener varios hilos 1-a-1 — uno por cada empresa que
 * ofertó — así que el hilo no lo define el contexto sino el par de
 * participantes. Por eso todas las consultas llevan `participantes @> [yo, el
 * otro]` además del `pedido_id` o `reserva_id`.
 *
 * El envío va por RPC por una razón concreta: el candado que impide compartir
 * números de teléfono. En la web vive solo en el navegador
 * (`_contieneTelefono`, js/chat.js), así que cualquier cliente que no lo
 * implemente lo salta — incluida esta app. Al bajarlo a `enviar_mensaje` el
 * candado aplica siempre, venga de donde venga.
 */
class ChatRepository(private val supabase: SupabaseClient) {

    /** Identifica un hilo: el contexto más las dos personas. */
    data class Hilo(
        val reservaId: String? = null,
        val pedidoId: String? = null,
        val participantes: List<String>,
    ) {
        init {
            require((reservaId == null) != (pedidoId == null)) {
                "Un hilo pertenece a una reserva o a una solicitud, no a ambas."
            }
        }

        val clave: String
            get() = (reservaId ?: pedidoId) + "-" + participantes.sorted().joinToString("-")
    }

    suspend fun historial(hilo: Hilo): Resultado<List<Mensaje>> = intentar {
        supabase.from("mensajes").select {
            filter {
                if (hilo.reservaId != null) eq("reserva_id", hilo.reservaId)
                else eq("pedido_id", hilo.pedidoId!!)
                contains("participantes", hilo.participantes)
            }
            order("created_at", Order.ASCENDING)
        }.decodeList()
    }

    suspend fun enviar(hilo: Hilo, texto: String): Resultado<Unit> = intentar {
        supabase.postgrest.rpc(
            "enviar_mensaje",
            buildJsonObject {
                put("p_texto", texto)
                putJsonArray("p_participantes") { hilo.participantes.forEach { add(it) } }
                put("p_reserva_id", hilo.reservaId)
                put("p_pedido_id", hilo.pedidoId)
            },
        )
        Unit
    }

    /**
     * Marca como leídos los mensajes del otro. Se llama al abrir el hilo.
     *
     * Se ignora el error a propósito: que falle en marcar leído no debe
     * impedirle a nadie leer la conversación.
     */
    suspend fun marcarLeidos(ids: List<String>) {
        if (ids.isEmpty()) return
        runCatching {
            supabase.from("mensajes").update(mapOf("leido" to true)) {
                filter { isIn("id", ids) }
            }
        }
    }

    /** Cuántos mensajes sin leer tiene cada reservación, para el badge de la lista. */
    suspend fun noLeidosPorReserva(miId: String, reservaIds: List<String>): Map<String, Int> {
        if (reservaIds.isEmpty()) return emptyMap()
        return runCatching {
            supabase.from("mensajes").select {
                filter {
                    isIn("reserva_id", reservaIds)
                    eq("leido", false)
                    neq("de_user_id", miId)
                }
            }.decodeList<Mensaje>()
                .filter { miId in it.participantes }
                .groupingBy { it.reservaId!! }
                .eachCount()
        }.getOrDefault(emptyMap())
    }

    /**
     * Mensajes nuevos del hilo, en vivo.
     *
     * El filtro del servidor solo puede ser por una columna, así que llega todo
     * lo del contexto y aquí se descartan los de otros hilos del mismo pedido:
     * un mensaje es de este hilo si comparte al menos dos participantes.
     *
     * El canal se cierra solo cuando el `Flow` se cancela — al salir de la
     * pantalla — para no dejar suscripciones colgadas consumiendo batería.
     */
    fun mensajesEnVivo(hilo: Hilo): Flow<Mensaje> {
        val canal = supabase.channel("chat-${hilo.clave}")

        val cambios = canal.postgresChangeFlow<PostgresAction.Insert>(schema = "public") {
            table = "mensajes"
        }

        return cambios
            .mapNotNull { accion -> runCatching { accion.decodeRecord<Mensaje>() }.getOrNull() }
            .filter { msg ->
                val mismoContexto = when {
                    hilo.reservaId != null -> msg.reservaId == hilo.reservaId
                    else -> msg.pedidoId == hilo.pedidoId
                }
                val mismoHilo = msg.participantes.count { it in hilo.participantes } >= 2
                mismoContexto && mismoHilo
            }
            .onStart { canal.subscribe() }
            .onCompletion { runCatching { supabase.realtime.removeChannel(canal) } }
    }
}
