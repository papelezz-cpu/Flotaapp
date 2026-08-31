package mx.portgo.app.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Aviso de la campana. Tabla `notificaciones`.
 *
 * `meta` es jsonb libre. Lo escribía el chat, que ya no existe en ningún
 * cliente; se conserva la lectura porque las filas viejas siguen ahí y romper
 * al deserializarlas dejaría la campana en blanco.
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
            // El chat se dio de baja. Los avisos que lo sustituyen y los
            // `nuevo_mensaje` que quedaron de antes llevan a Reservaciones, que
            // es donde está el servicio del que hablan.
            "nuevo_mensaje", "documentos_carga_solicitados", "confirmar_lugar_hora",
            "aviso_retraso", "cambio_reportado",
            -> DestinoNotificacion.Reservaciones

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
    Solicitudes, Reservaciones, Flota, Ninguno
}
