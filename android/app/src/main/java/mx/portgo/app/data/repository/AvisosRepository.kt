package mx.portgo.app.data.repository

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.functions.functions
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import mx.portgo.app.core.Fmt
import mx.portgo.app.core.Resultado
import mx.portgo.app.core.intentar

/**
 * Los avisos fijos entre cliente y empresa.
 *
 * Sustituyen al chat, que se dio de baja en la web (commit 6b8beee) y ahora
 * también aquí. La razón de fondo es que un chat libre en una operación
 * portuaria genera acuerdos que no quedan en ninguna parte: "te lo dejo en la
 * puerta 4" dicho por mensaje no cambia el pedido ni avisa al administrador, y
 * cuando algo sale mal nadie puede reconstruir qué se pactó. Un botón fijo
 * escribe un aviso con tipo, va a la campana y al correo, y —en el caso de
 * lugar y hora— **modifica el dato de verdad** en el pedido.
 *
 * Cada texto es el mismo que manda la web. No es casual: los dos clientes
 * escriben en la misma tabla `notificaciones`, y si divergieran, un cliente
 * vería "El cliente actualizó el viaje" y el otro algo distinto para el mismo
 * hecho.
 *
 * ⚠️ Esta lógica vive en el cliente porque así vive en la web, y duplicarla era
 * la opción con menos riesgo hoy. El sitio natural es una RPC —igual que
 * `enviar_oferta` o `cancelar_reservacion`— y ahí debería acabar: el conjunto
 * de destinatarios (la empresa **y** todos los superadmins) es una regla de
 * negocio, no presentación.
 */
class AvisosRepository(private val supabase: SupabaseClient) {

    // ── Filas mínimas que hacen falta; no se traen las ~40 columnas enteras ──

    @Serializable
    private data class ReservaAviso(
        @SerialName("cliente_user_id") val clienteUserId: String? = null,
        @SerialName("propietario_id") val propietarioId: String? = null,
        @SerialName("pedido_id") val pedidoId: String? = null,
        val unidad: String? = null,
        val cliente: String? = null,
    )

    @Serializable
    private data class PedidoAviso(
        @SerialName("detalles_lugar") val detallesLugar: String? = null,
        @SerialName("detalles_hora") val detallesHora: String? = null,
        val origen: String? = null,
        @SerialName("fecha_ini") val fechaIni: String? = null,
    )

    @Serializable
    private data class PerfilId(@SerialName("user_id") val userId: String)

    /** Lugar y hora que el viaje tiene ahora mismo. */
    data class DetallesViaje(val lugar: String?, val hora: String?)

    /** Motivos fijos del reporte del cliente. Mismos textos que `_RC_MOTIVOS`. */
    enum class MotivoReporte(val clave: String, val etiqueta: String, val texto: String) {
        CARGA(
            "carga",
            "Problema con la carga o los documentos",
            "📦 El cliente reporta un problema con la carga o los documentos.",
        ),
        OTRO(
            "otro",
            "Problema urgente, que me contacten",
            "⚠ El cliente reporta un problema urgente y pide que lo contacten.",
        ),
    }

    // ══════════════════════════════════════════════════════════════════════
    // EMPRESA → CLIENTE
    // ══════════════════════════════════════════════════════════════════════

    /** La empresa pide la Carta Porte y los documentos de la carga. */
    suspend fun solicitarDocumentosCarga(reservaId: String, miNombre: String): Resultado<Unit> =
        intentar {
            val r = reserva(reservaId)
            val destino = requireNotNull(r.clienteUserId) { "La reservación no tiene cliente." }

            val mensaje = "$miNombre necesita la Carta Porte y/o documentos de carga para el " +
                "servicio \"${r.unidad.orEmpty()}\". Súbelos desde Reservaciones."

            avisar(
                destinos = listOf(destino),
                tipo = "documentos_carga_solicitados",
                titulo = "📄 Documentos de carga solicitados",
                mensaje = mensaje,
                tituloCorreo = "Documentos de carga solicitados",
                aprobado = true,
            )
        }

    /**
     * La empresa pide al cliente que confirme lugar y hora.
     *
     * Usa los detalles que el cliente capturó al aceptar la oferta; si no los
     * hay, cae al origen y la fecha del pedido. Mandar el aviso sin ningún dato
     * concreto obliga al cliente a ir a buscarlo, que es justo lo que este
     * botón intenta evitar.
     */
    suspend fun confirmarLugarHora(reservaId: String, miNombre: String): Resultado<Unit> =
        intentar {
            val r = reserva(reservaId)
            val destino = requireNotNull(r.clienteUserId) { "La reservación no tiene cliente." }

            val p = r.pedidoId?.let { pedido(it) }
            val lugar = p?.detallesLugar?.ifBlank { null } ?: p?.origen?.ifBlank { null }
            val hora = p?.detallesHora?.ifBlank { null }
                ?: p?.fechaIni?.let { Fmt.fecha(it) }?.ifBlank { null }

            val detalle = listOfNotNull(
                lugar?.let { "lugar: $it" },
                hora?.let { "hora: $it" },
            ).joinToString(", ")

            val mensaje = "$miNombre quiere confirmar contigo" +
                (if (detalle.isNotBlank()) " — $detalle" else "") +
                " para el servicio \"${r.unidad.orEmpty()}\". " +
                "Si algo cambió, repórtalo desde Reservaciones."

            avisar(
                destinos = listOf(destino),
                tipo = "confirmar_lugar_hora",
                titulo = "📍 Confirma lugar y hora",
                mensaje = mensaje,
                tituloCorreo = "Confirma lugar y hora",
                aprobado = true,
            )
        }

    /** Aviso de retraso. El detalle es opcional: a veces no hay nada que explicar. */
    suspend fun avisarRetraso(reservaId: String, nota: String?): Resultado<Unit> = intentar {
        val r = reserva(reservaId)
        val destino = requireNotNull(r.clienteUserId) { "La reservación no tiene cliente." }

        val extra = nota?.trim()?.ifBlank { null }
        val mensaje = "El transporte de tu servicio \"${r.unidad.orEmpty()}\" va a llegar tarde." +
            (if (extra != null) " $extra" else "")

        avisar(
            destinos = listOf(destino),
            tipo = "aviso_retraso",
            titulo = "⏰ Aviso de retraso",
            mensaje = mensaje,
            tituloCorreo = "Aviso de retraso",
            aprobado = false,
        )
    }

    // ══════════════════════════════════════════════════════════════════════
    // CLIENTE → EMPRESA + SUPERADMINS
    // ══════════════════════════════════════════════════════════════════════

    /**
     * El cliente cambia el lugar o la hora de la recogida.
     *
     * Esto sí escribe en `pedidos`: el aviso solo no serviría, porque la
     * empresa lee el dato del pedido, no del historial de la campana. Primero
     * se guarda y luego se avisa — si el guardado falla no debe salir un aviso
     * anunciando un cambio que no ocurrió.
     */
    suspend fun actualizarLugarHora(
        reservaId: String,
        lugar: String?,
        hora: String?,
    ): Resultado<Unit> = intentar {
        val l = lugar?.trim()?.ifBlank { null }
        val h = hora?.trim()?.ifBlank { null }
        require(l != null || h != null) { "Indica el lugar y/o la hora." }

        val r = reserva(reservaId)
        val pedidoId = requireNotNull(r.pedidoId) {
            "Este servicio no viene de una solicitud, no hay lugar ni hora que actualizar."
        }

        // `select()` no es un adorno: si RLS bloquea este UPDATE no falla —
        // afecta 0 filas y devuelve error nulo. Sin comprobar que volvió una
        // fila, la app anunciaría el cambio y mandaría el aviso mientras el
        // pedido conserva el lugar viejo. Es el equivalente de
        // `actualizarConfirmado()` de la web.
        val filas = supabase.from("pedidos").update(
            buildJsonObject {
                put("detalles_lugar", l)
                put("detalles_hora", h)
            },
        ) {
            select()
            filter { eq("id", pedidoId) }
        }.decodeList<JsonObject>()

        require(filas.isNotEmpty()) {
            "No se pudo guardar el cambio: la solicitud ya no admite modificaciones."
        }

        val detalle = listOfNotNull(
            l?.let { "lugar: $it" },
            h?.let { "hora: $it" },
        ).joinToString(", ")

        avisar(
            destinos = empresaYSuperadmins(r),
            tipo = "cambio_reportado",
            titulo = "✏️ El cliente actualizó lugar/hora",
            mensaje = "✏️ El cliente actualizó el viaje — $detalle.",
            tituloCorreo = "El cliente actualizó lugar/hora",
            aprobado = false,
        )
    }

    /** El cliente reporta un problema. El motivo es fijo; el detalle, opcional. */
    suspend fun reportarProblema(
        reservaId: String,
        motivo: MotivoReporte,
        nota: String?,
    ): Resultado<Unit> = intentar {
        val r = reserva(reservaId)
        val extra = nota?.trim()?.ifBlank { null }

        val mensaje = motivo.texto +
            (if (extra != null) " $extra" else "") +
            " Servicio \"${r.unidad.orEmpty()}\" — ${r.cliente ?: "cliente"}."

        avisar(
            destinos = empresaYSuperadmins(r),
            tipo = "cambio_reportado",
            titulo = "⚠ Cliente reporta un problema",
            mensaje = mensaje,
            tituloCorreo = "Cliente reporta un problema",
            aprobado = false,
        )
    }

    /**
     * Lo que hay guardado, para precargar el formulario.
     *
     * No es un adorno: `actualizarLugarHora` escribe los dos campos, así que un
     * formulario vacío en el que solo se teclea la hora borraría el lugar que
     * ya estaba. Precargar es lo que impide perder el dato.
     *
     * Si no hay detalles capturados cae al origen del pedido, igual que la web.
     */
    suspend fun detallesViaje(reservaId: String): Resultado<DetallesViaje> = intentar {
        val r = reserva(reservaId)
        val p = r.pedidoId?.let { pedido(it) }
        DetallesViaje(
            lugar = p?.detallesLugar?.ifBlank { null } ?: p?.origen?.ifBlank { null },
            hora = p?.detallesHora?.ifBlank { null },
        )
    }

    // ══════════════════════════════════════════════════════════════════════
    // INTERNOS
    // ══════════════════════════════════════════════════════════════════════

    private suspend fun reserva(reservaId: String): ReservaAviso =
        supabase.from("reservaciones").select(
            Columns.list("cliente_user_id", "propietario_id", "pedido_id", "unidad", "cliente"),
        ) {
            filter { eq("id", reservaId) }
        }.decodeSingle()

    private suspend fun pedido(pedidoId: String): PedidoAviso? =
        supabase.from("pedidos").select(
            Columns.list("detalles_lugar", "detalles_hora", "origen", "fecha_ini"),
        ) {
            filter { eq("id", pedidoId) }
        }.decodeSingleOrNull()

    /**
     * La empresa dueña del servicio y todos los superadmins.
     *
     * Los superadmins van incluidos porque son quienes resuelven: un problema
     * con la carga puede acabar en cancelación, y esa la aprueban ellos. Que se
     * enteren cuando el cliente ya se quejó por teléfono es tarde.
     */
    private suspend fun empresaYSuperadmins(r: ReservaAviso): List<String> {
        val empresa = requireNotNull(r.propietarioId) { "La reservación no tiene empresa." }
        val supers = runCatching {
            supabase.from("perfiles").select(Columns.list("user_id")) {
                filter { eq("rol", "superadmin") }
            }.decodeList<PerfilId>().map { it.userId }
        }.getOrDefault(emptyList())
        return (listOf(empresa) + supers).distinct()
    }

    /**
     * Escribe la campana y dispara el correo.
     *
     * El orden importa: la campana es la que tiene que quedar sí o sí, así que
     * su error se propaga. El correo va después y su fallo se traga a
     * propósito —igual que en la web— porque el aviso ya está entregado; que el
     * proveedor de correo esté caído no debe hacerle creer al usuario que su
     * aviso no salió.
     */
    private suspend fun avisar(
        destinos: List<String>,
        tipo: String,
        titulo: String,
        mensaje: String,
        tituloCorreo: String,
        aprobado: Boolean,
    ) {
        supabase.from("notificaciones").insert(
            destinos.map { uid ->
                buildJsonObject {
                    put("user_id", uid)
                    put("tipo", tipo)
                    put("titulo", titulo)
                    put("mensaje", mensaje)
                    put("leido", false)
                }
            },
        )
        correo(destinos, tituloCorreo, mensaje, aprobado)
    }

    private suspend fun correo(
        destinos: List<String>,
        titulo: String,
        mensaje: String,
        aprobado: Boolean,
    ) {
        runCatching {
            supabase.functions.invoke(
                function = "enviar-notificacion",
                body = cuerpoCorreo(destinos, titulo, mensaje, aprobado),
            )
        }
    }

    private fun cuerpoCorreo(
        destinos: List<String>,
        titulo: String,
        mensaje: String,
        aprobado: Boolean,
    ): JsonObject = buildJsonObject {
        put("tipo", "resolucion")
        putJsonArray("destinoIds") { destinos.forEach { add(it) } }
        put("titulo", titulo)
        put("mensaje", mensaje)
        put("aprobado", aprobado)
    }
}
