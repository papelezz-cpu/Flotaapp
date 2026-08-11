package mx.portgo.app.data.repository

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import mx.portgo.app.core.Resultado
import mx.portgo.app.core.intentar
import mx.portgo.app.data.model.EstadoPedido
import mx.portgo.app.data.model.Oferta
import mx.portgo.app.data.model.Pedido
import mx.portgo.app.data.model.PedidoConOfertas
import mx.portgo.app.data.model.PlantillaPedido
import mx.portgo.app.data.model.Rol

/**
 * Solicitudes y ofertas.
 *
 * Las lecturas van directo a PostgREST: RLS ya filtra qué pedidos ve cada
 * quien (la política `ped_select` deja al cliente los suyos, y a la empresa
 * los abiertos, los que están en negociación y aquellos donde ya ofertó).
 *
 * Las escrituras que mueven estado van por RPC. No es preferencia de estilo:
 * enviar una oferta son dos escrituras (insertar la oferta y pasar el pedido a
 * `en_negociacion`) y aceptar una son tres. Hacerlas sueltas desde el
 * dispositivo es lo que dejó pedidos colgados en la web, y además obligaría a
 * repetir las mismas reglas en Kotlin y en Swift.
 */
class PedidosRepository(private val supabase: SupabaseClient) {

    /** Cuántas solicitudes trae cada página. Igual que PEDIDOS_PAGE en la web. */
    private val tamPagina = 20L

    /**
     * Página de solicitudes visibles para el rol, con sus ofertas.
     *
     * Se hacen dos consultas en vez de un join anidado: PostgREST puede
     * incrustar `ofertas(*)`, pero cuando RLS bloquea la tabla incrustada
     * devuelve la fila padre con el hijo vacío y sin decir por qué. Dos
     * consultas explícitas fallan de forma visible, que es lo que se quiere.
     */
    suspend fun listar(
        rol: Rol,
        pagina: Int = 0,
        soloMias: Boolean = false,
        miId: String? = null,
    ): Resultado<List<PedidoConOfertas>> = intentar {
        val desde = pagina * tamPagina
        val hasta = desde + tamPagina - 1

        val pedidos = supabase.from("pedidos").select {
            filter {
                if (soloMias && miId != null) eq("cliente_id", miId)
                if (rol == Rol.EMPRESA && !soloMias) {
                    // La empresa solo tiene algo que hacer con las que admiten
                    // oferta; el resto solo llena la lista. RLS ya le deja ver
                    // también aquellas donde ofertó, y esas llegan por
                    // `misOfertas()`.
                    isIn("estado", listOf(EstadoPedido.ABIERTO.db, EstadoPedido.EN_NEGOCIACION.db))
                }
            }
            order("created_at", Order.DESCENDING)
            range(desde, hasta)
        }.decodeList<Pedido>()

        if (pedidos.isEmpty()) return@intentar emptyList()

        val ofertas = ofertasDe(pedidos.map { it.id })
        pedidos.map { PedidoConOfertas(it, ofertas[it.id].orEmpty()) }
    }

    suspend fun detalle(pedidoId: String): Resultado<PedidoConOfertas?> = intentar {
        val pedido = supabase.from("pedidos")
            .select { filter { eq("id", pedidoId) }; limit(1) }
            .decodeSingleOrNull<Pedido>() ?: return@intentar null

        PedidoConOfertas(pedido, ofertasDe(listOf(pedidoId))[pedidoId].orEmpty())
    }

    private suspend fun ofertasDe(pedidoIds: List<String>): Map<String, List<Oferta>> {
        if (pedidoIds.isEmpty()) return emptyMap()
        return supabase.from("ofertas").select {
            filter { isIn("pedido_id", pedidoIds) }
            order("created_at", Order.ASCENDING)
        }.decodeList<Oferta>().groupBy { it.pedidoId }
    }

    /** Solicitudes donde esta empresa ya ofertó, para la pestaña "Mis ofertas". */
    suspend fun conMisOfertas(miId: String): Resultado<List<PedidoConOfertas>> = intentar {
        val mias = supabase.from("ofertas").select {
            filter { eq("admin_id", miId) }
            order("created_at", Order.DESCENDING)
        }.decodeList<Oferta>()

        if (mias.isEmpty()) return@intentar emptyList()

        val ids = mias.map { it.pedidoId }.distinct()
        val pedidos = supabase.from("pedidos")
            .select { filter { isIn("id", ids) } }
            .decodeList<Pedido>()
            .associateBy { it.id }

        // Todas las ofertas de esos pedidos, no solo las mías: la empresa
        // necesita ver contra cuántas compite.
        val todas = ofertasDe(ids)

        ids.mapNotNull { id ->
            pedidos[id]?.let { PedidoConOfertas(it, todas[id].orEmpty()) }
        }
    }

    // ── Acciones (RPC) ────────────────────────────────────────────────────

    /** Empresa oferta por una solicitud. Devuelve el id de la oferta creada. */
    suspend fun enviarOferta(
        pedidoId: String,
        camionId: String,
        precio: Double,
        operadorId: String?,
        operadorNombre: String?,
        mensaje: String?,
    ): Resultado<String> = intentar {
        supabase.postgrest.rpc(
            "enviar_oferta",
            buildJsonObject {
                put("p_pedido_id", pedidoId)
                put("p_camion_id", camionId)
                put("p_precio", precio)
                put("p_operador_id", operadorId)
                put("p_operador_nombre", operadorNombre)
                put("p_mensaje", mensaje)
            },
        ).decodeAs<String>()
    }

    /** Cliente responde una oferta: aceptar, contraofertar o rechazar. */
    suspend fun responderOferta(
        ofertaId: String,
        accion: AccionOferta,
        contraPrecio: Double? = null,
        nota: String? = null,
    ): Resultado<Unit> = intentar {
        supabase.postgrest.rpc(
            "responder_oferta",
            buildJsonObject {
                put("p_oferta_id", ofertaId)
                put("p_accion", accion.db)
                put("p_contra_precio", contraPrecio)
                put("p_nota", nota)
            },
        )
        Unit
    }

    /** Empresa responde la contraoferta del cliente. */
    suspend fun responderContraoferta(
        ofertaId: String,
        aceptar: Boolean,
    ): Resultado<Unit> = intentar {
        supabase.postgrest.rpc(
            "responder_contraoferta",
            buildJsonObject {
                put("p_oferta_id", ofertaId)
                put("p_accion", if (aceptar) "aceptar" else "rechazar")
            },
        )
        Unit
    }

    /**
     * Cliente cancela su solicitud.
     *
     * Es un solo UPDATE que RLS y `guard_pedido_update` ya cubren, así que no
     * necesita RPC.
     */
    suspend fun cancelarSolicitud(pedidoId: String): Resultado<Unit> = intentar {
        supabase.from("pedidos").update(mapOf("estado" to EstadoPedido.CANCELADO.db)) {
            filter { eq("id", pedidoId) }
        }
    }

    // ── Plantillas ────────────────────────────────────────────────────────

    suspend fun plantillas(clienteId: String): Resultado<List<PlantillaPedido>> = intentar {
        supabase.from("plantillas_pedido").select {
            filter { eq("cliente_id", clienteId) }
            order("veces_usada", Order.DESCENDING)
            order("created_at", Order.DESCENDING)
        }.decodeList()
    }

    suspend fun eliminarPlantilla(id: String): Resultado<Unit> = intentar {
        supabase.from("plantillas_pedido").delete { filter { eq("id", id) } }
    }

    /**
     * Publica una solicitud.
     *
     * Es el único flujo de escritura que no pasa por RPC: es un solo INSERT que
     * RLS cubre, y envolverlo obligaría a versionar las ~60 columnas de
     * `pedidos` dentro de una función de Postgres cada vez que la web agrega un
     * campo. El aviso a los superadmins sí se inserta aparte — si fallara, la
     * solicitud ya quedó publicada, que es lo que importa.
     */
    suspend fun crear(payload: JsonObject): Resultado<Unit> = intentar {
        supabase.from("pedidos").insert(payload)

        runCatching {
            val supers = supabase.from("perfiles")
                .select { filter { eq("rol", Rol.SUPERADMIN.db) } }
                .decodeList<mx.portgo.app.data.model.Perfil>()

            if (supers.isNotEmpty()) {
                supabase.from("notificaciones").insert(
                    supers.map { s ->
                        buildJsonObject {
                            put("user_id", s.userId)
                            put("tipo", "revision_solicitud")
                            put("titulo", "Nueva solicitud para revisar")
                            put("mensaje", "Una solicitud nueva requiere tu revisión antes de publicarse.")
                            put("leido", false)
                        }
                    },
                )
            }
        }
    }

    enum class AccionOferta(val db: String) {
        ACEPTAR("aceptar"),
        CONTRAOFERTAR("contraofertar"),
        RECHAZAR("rechazar"),
    }
}
