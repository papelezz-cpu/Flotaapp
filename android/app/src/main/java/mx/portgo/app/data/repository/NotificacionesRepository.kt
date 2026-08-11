package mx.portgo.app.data.repository

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.realtime.PostgresAction
import io.github.jan.supabase.realtime.channel
import io.github.jan.supabase.realtime.decodeRecord
import io.github.jan.supabase.realtime.postgresChangeFlow
import io.github.jan.supabase.realtime.realtime
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.flow.onCompletion
import kotlinx.coroutines.flow.onStart
import mx.portgo.app.core.Resultado
import mx.portgo.app.core.intentar
import mx.portgo.app.data.model.Notificacion

/**
 * La campana.
 *
 * Sin push (fuera del MVP acordado), este es el único aviso en tiempo real:
 * Realtime con la app abierta, y una recarga al volver a primer plano. Es
 * exactamente lo que hace la web hoy.
 *
 * Se suscribe **solo** al canal de este usuario, no a las siete tablas que
 * escucha la web (`portgo-changes` en js/main.js). En un teléfono eso sería
 * batería y datos tirados: el resto de las pantallas se refresca al entrar y
 * con deslizar hacia abajo.
 */
class NotificacionesRepository(private val supabase: SupabaseClient) {

    /** Mismo tope que la web: las últimas 20. */
    private val limite = 20L

    suspend fun ultimas(miId: String): Resultado<List<Notificacion>> = intentar {
        supabase.from("notificaciones").select {
            filter { eq("user_id", miId) }
            order("created_at", Order.DESCENDING)
            limit(limite)
        }.decodeList()
    }

    suspend fun contarNoLeidas(miId: String): Int = runCatching {
        supabase.from("notificaciones").select {
            filter {
                eq("user_id", miId)
                eq("leido", false)
            }
            count(io.github.jan.supabase.postgrest.query.Count.EXACT)
        }.countOrNull()?.toInt() ?: 0
    }.getOrDefault(0)

    suspend fun marcarLeida(id: String): Resultado<Unit> = intentar {
        supabase.from("notificaciones").update(mapOf("leido" to true)) {
            filter { eq("id", id) }
        }
    }

    suspend fun marcarTodasLeidas(miId: String): Resultado<Unit> = intentar {
        supabase.from("notificaciones").update(mapOf("leido" to true)) {
            filter {
                eq("user_id", miId)
                eq("leido", false)
            }
        }
    }

    /**
     * Notificaciones nuevas dirigidas a este usuario.
     *
     * El filtro `user_id=eq.{uid}` se aplica del lado del servidor: es el
     * mismo canal `notif-{userId}` que arma la web.
     */
    fun enVivo(miId: String): Flow<Notificacion> {
        val canal = supabase.channel("notif-$miId")

        val cambios = canal.postgresChangeFlow<PostgresAction.Insert>(schema = "public") {
            table = "notificaciones"
            filter("user_id", io.github.jan.supabase.postgrest.query.filter.FilterOperator.EQ, miId)
        }

        return cambios
            .mapNotNull { accion -> runCatching { accion.decodeRecord<Notificacion>() }.getOrNull() }
            .onStart { canal.subscribe() }
            .onCompletion { runCatching { supabase.realtime.removeChannel(canal) } }
    }
}
