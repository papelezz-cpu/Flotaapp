package mx.portgo.app.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Mensaje de un hilo de chat. Tabla `mensajes`.
 *
 * El hilo se identifica por el par (contexto, participantes): un mismo pedido
 * puede tener varias conversaciones 1-a-1, una por cada empresa que ofertó.
 * Por eso las consultas filtran por `participantes @> [yo, elOtro]` y no solo
 * por `pedido_id`.
 */
@Serializable
data class Mensaje(
    val id: String,
    @SerialName("de_user_id") val deUserId: String,
    @SerialName("de_nombre") val deNombre: String? = null,
    val texto: String,
    @SerialName("reserva_id") val reservaId: String? = null,
    @SerialName("pedido_id") val pedidoId: String? = null,
    val participantes: List<String> = emptyList(),
    val leido: Boolean = false,
    @SerialName("created_at") val creadoEn: String? = null,
) {
    fun esMio(miId: String?): Boolean = deUserId == miId
}

/**
 * Aviso de la campana. Tabla `notificaciones`.
 *
 * `meta` es jsonb libre. Hoy solo lo usa el tipo `nuevo_mensaje`, que trae
 * `ctx_tipo` / `ctx_id` / `de_user_id` para poder abrir el hilo correcto.
 */
@Serializable
data class Notificacion(
    val id: String,
    @SerialName("user_id") val userId: String,
    val tipo: String? = null,
    val titulo: String? = null,
    val mensaje: String? = null,
    val leido: Boolean = false,
    val meta: JsonObject? = null,
    @SerialName("created_at") val creadoEn: String? = null,
) {
    private fun metaTexto(clave: String): String? =
        runCatching { meta?.get(clave)?.jsonPrimitive?.content }.getOrNull()

    val ctxTipo: String? get() = metaTexto("ctx_tipo")
    val ctxId: String? get() = metaTexto("ctx_id")
    val deUserId: String? get() = metaTexto("de_user_id")
    val deNombre: String? get() = metaTexto("de_nombre")

    /**
     * A dónde lleva tocar la notificación. Espejo de onNotifClick() en
     * js/notificaciones.js, recortado a lo que existe en el móvil: los tipos
     * del superadmin no navegan a ningún lado porque ese rol no entra aquí.
     */
    val destino: DestinoNotificacion
        get() = when (tipo) {
            "nuevo_mensaje" -> DestinoNotificacion.Chat

            "nueva_oferta", "respuesta_oferta", "respuesta_contra_oferta",
            "oferta_no_seleccionada", "pedido_cancelado", "negociacion_cerrada",
            "nueva_solicitud", "acuerdo_rechazado", "solicitud_rechazada",
            -> DestinoNotificacion.Solicitudes

            "reserva_pendiente", "reserva_aceptada", "reserva_rechazada",
            "reserva_cancelada", "tracking_actualizado", "servicio_completado",
            "finalizacion_solicitada", "finalizacion_rechazada", "acuerdo_aprobado",
            "cancelacion_solicitada", "documentos_solicitados", "nueva_calificacion",
            -> DestinoNotificacion.Reservaciones

            "recurso_aprobado", "recurso_rechazado" -> DestinoNotificacion.Flota

            else -> DestinoNotificacion.Ninguno
        }
}

enum class DestinoNotificacion {
    Solicitudes, Reservaciones, Chat, Flota, Ninguno
}
