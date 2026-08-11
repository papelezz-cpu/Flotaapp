package mx.portgo.app.data.repository

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.add
import mx.portgo.app.core.Resultado
import mx.portgo.app.core.intentar
import mx.portgo.app.data.model.EtapaExpediente
import mx.portgo.app.data.model.Expediente
import mx.portgo.app.data.model.ExpedienteDocumento
import mx.portgo.app.data.model.Reservacion
import mx.portgo.app.data.model.UsuarioActual

/**
 * Servicios contratados: listado, seguimiento, cierre, cancelación,
 * calificación y expedientes documentales.
 *
 * Todo lo que mueve estado va por RPC. `cancelar_reservacion` es el caso
 * extremo — siete escrituras que tienen que pasar juntas: cancelar, liberar la
 * unidad, reabrir el pedido, invalidar las ofertas y avisar a dos partes. En
 * la web eso vive suelto en el navegador y ya se rompió antes.
 */
class ReservacionesRepository(private val supabase: SupabaseClient) {

    /**
     * Reservaciones del usuario, según su lado de la operación.
     *
     * Para el cliente se filtra por `cliente_user_id` **o** `cliente_email`.
     * La web solo usa el correo (js/reservaciones.js:75), lo que hace que
     * alguien que cambió su correo pierda de vista su historial. Aquí se
     * consultan los dos para no heredar ese hueco.
     */
    suspend fun mias(usuario: UsuarioActual): Resultado<List<Reservacion>> = intentar {
        supabase.from("reservaciones").select {
            filter {
                if (usuario.esCliente) {
                    or {
                        eq("cliente_user_id", usuario.id)
                        eq("cliente_email", usuario.email)
                    }
                } else {
                    eq("propietario_id", usuario.id)
                }
            }
            order("created_at", Order.DESCENDING)
        }.decodeList()
    }

    suspend fun detalle(reservaId: String): Resultado<Reservacion?> = intentar {
        supabase.from("reservaciones")
            .select { filter { eq("id", reservaId) }; limit(1) }
            .decodeSingleOrNull<Reservacion>()
    }

    // ── Seguimiento ───────────────────────────────────────────────────────

    /**
     * Avanza un paso el seguimiento. Devuelve el nuevo estado.
     *
     * Cuál es el siguiente paso lo decide el servidor, no la app: la secuencia
     * depende del tipo de recurso y tenerla en tres lugares (web, Android, iOS)
     * es pedir que se desincronicen. La app la conoce solo para dibujar la
     * línea de tiempo.
     */
    suspend fun avanzarTracking(reservaId: String): Resultado<String> = intentar {
        supabase.postgrest.rpc(
            "avanzar_tracking",
            buildJsonObject { put("p_reserva_id", reservaId) },
        ).decodeAs<String>()
    }

    // ── Cierre del servicio ───────────────────────────────────────────────

    /**
     * Registra las evidencias ya subidas a Storage y, si la reserva estaba
     * activa, pide el cierre (pasa a `PorAprobar`).
     *
     * Los archivos se suben antes con [StorageRepository.subirEvidencia]; aquí
     * solo viajan las rutas. Separarlo es a propósito: subir cinco fotos por
     * una red de puerto puede tardar, y no se quiere una transacción de base de
     * datos abierta todo ese rato.
     */
    suspend fun registrarEvidencias(
        reservaId: String,
        rutas: List<String>,
    ): Resultado<Unit> = intentar {
        supabase.postgrest.rpc(
            "registrar_evidencias",
            buildJsonObject {
                put("p_reserva_id", reservaId)
                putJsonArray("p_paths") { rutas.forEach { add(it) } }
            },
        )
        Unit
    }

    // ── Cancelación ───────────────────────────────────────────────────────

    /** Empresa cancela una reserva activa. Reabre el pedido y libera la unidad. */
    suspend fun cancelar(reservaId: String, motivo: String?): Resultado<Unit> = intentar {
        supabase.postgrest.rpc(
            "cancelar_reservacion",
            buildJsonObject {
                put("p_reserva_id", reservaId)
                put("p_motivo", motivo)
            },
        )
        Unit
    }

    /**
     * Cliente pide cancelar. No cancela: lo resuelve el superadmin.
     *
     * La diferencia importa — cancelar de verdad implica liberar la unidad y
     * cerrar el pedido, y hubo un hueco en el que el cliente podía dejar todo
     * a medias por API directa (ver migración 20260729140000).
     */
    suspend fun solicitarCancelacion(
        reservaId: String,
        motivo: String,
        detalle: String?,
    ): Resultado<Unit> = intentar {
        supabase.postgrest.rpc(
            "solicitar_cancelacion",
            buildJsonObject {
                put("p_reserva_id", reservaId)
                put("p_motivo", motivo)
                put("p_detalle", detalle)
            },
        )
        Unit
    }

    // ── Calificación ──────────────────────────────────────────────────────

    suspend fun calificar(
        reservaId: String,
        estrellas: Int,
        comentario: String?,
    ): Resultado<Unit> = intentar {
        supabase.postgrest.rpc(
            "calificar_servicio",
            buildJsonObject {
                put("p_reserva_id", reservaId)
                put("p_rating", estrellas)
                put("p_comentario", comentario)
            },
        )
        Unit
    }

    // ── Expedientes documentales ──────────────────────────────────────────

    /** Expedientes de varias reservaciones de una sola consulta. */
    suspend fun expedientesDe(reservaIds: List<String>): Map<String, List<Expediente>> {
        if (reservaIds.isEmpty()) return emptyMap()
        return runCatching {
            supabase.from("expedientes")
                .select { filter { isIn("reserva_id", reservaIds) } }
                .decodeList<Expediente>()
                .groupBy { it.reservaId }
        }.getOrDefault(emptyMap())
    }

    suspend fun documentosDe(expedienteId: String): Resultado<List<ExpedienteDocumento>> = intentar {
        supabase.from("expediente_documentos").select {
            filter { eq("expediente_id", expedienteId) }
            order("orden", Order.ASCENDING)
        }.decodeList()
    }

    /** El transportista pide la documentación al cliente. Idempotente. */
    suspend fun abrirExpediente(
        reservaId: String,
        etapa: EtapaExpediente,
    ): Resultado<String?> = intentar {
        supabase.postgrest.rpc(
            "abrir_expediente",
            buildJsonObject {
                put("p_reserva_id", reservaId)
                put("p_etapa", etapa.db)
                put("p_solo_si_aplica", false)
            },
        ).decodeAsOrNull<String>()
    }

    /** El cliente adjunta el archivo de un renglón del checklist. */
    suspend fun adjuntarDocumento(
        documentoId: String,
        ruta: String,
        nombreArchivo: String,
    ): Resultado<Unit> = intentar {
        supabase.from("expediente_documentos").update(
            buildJsonObject {
                put("archivo_path", ruta)
                put("archivo_nombre", nombreArchivo)
                put("estado", "subido")
                put("nota_rechazo", null as String?)
            },
        ) {
            filter { eq("id", documentoId) }
        }
    }

    /**
     * El transportista dictamina un documento.
     *
     * El guard `guard_expediente_documento` impide que el cliente haga esto
     * aunque la app se lo permitiera: solo el transportista revisa.
     */
    suspend fun dictaminarDocumento(
        documentoId: String,
        aceptado: Boolean,
        notaRechazo: String? = null,
    ): Resultado<Unit> = intentar {
        supabase.from("expediente_documentos").update(
            buildJsonObject {
                put("estado", if (aceptado) "aceptado" else "rechazado")
                put("nota_rechazo", notaRechazo)
            },
        ) {
            filter { eq("id", documentoId) }
        }
    }
}
