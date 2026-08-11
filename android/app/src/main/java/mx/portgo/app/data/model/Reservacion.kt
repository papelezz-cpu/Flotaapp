package mx.portgo.app.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import mx.portgo.app.core.Fmt

/**
 * Servicio contratado y en curso. Tabla `reservaciones`.
 *
 * Se crea cuando el superadmin aprueba un acuerdo (`cerrarAcuerdo` en la web),
 * no cuando el cliente acepta la oferta. Esta app nunca la inserta: solo la
 * opera.
 *
 * `evidencias` es de la empresa y `evidencias_cliente` del cliente — el guard
 * de la base impide que uno escriba en la columna del otro. Ambas guardan
 * **rutas** del bucket privado `unidades`, no URLs: se firman al mostrarlas.
 */
@Serializable
data class Reservacion(
    val id: String,
    @SerialName("pedido_id") val pedidoId: String? = null,
    @SerialName("propietario_id") val propietarioId: String? = null,
    @SerialName("cliente_user_id") val clienteUserId: String? = null,
    val cliente: String? = null,
    @SerialName("cliente_email") val clienteEmail: String? = null,

    val unidad: String? = null,
    @SerialName("recurso_tipo") val recursoTipo: String? = null,
    val descripcion: String? = null,

    @SerialName("fecha_ini") val fechaIni: String? = null,
    @SerialName("fecha_fin") val fechaFin: String? = null,

    val estado: String? = null,
    @SerialName("tracking_estado") val trackingEstado: String? = null,
    @SerialName("precio_acordado") val precioAcordado: Double? = null,

    // ── Cierre del servicio ──
    val evidencias: List<String>? = null,
    @SerialName("evidencias_cliente") val evidenciasCliente: List<String>? = null,
    @SerialName("finalizacion_solicitada_por") val finalizacionSolicitadaPor: String? = null,
    @SerialName("finalizacion_nota") val finalizacionNota: String? = null,
    @SerialName("completado_en") val completadoEn: String? = null,

    // ── Cancelación ──
    @SerialName("cancelacion_solicitada_en") val cancelacionSolicitadaEn: String? = null,
    @SerialName("cancelacion_motivo") val cancelacionMotivo: String? = null,
    @SerialName("cancelacion_detalle") val cancelacionDetalle: String? = null,
    @SerialName("cancelacion_nota_resolucion") val cancelacionNotaResolucion: String? = null,

    // ── Cobro ──
    val pagado: Boolean = false,
    @SerialName("pagado_en") val pagadoEn: String? = null,
    @SerialName("plazo_pago") val plazoPago: String? = null,
    @SerialName("fecha_vencimiento_pago") val fechaVencimientoPago: String? = null,

    val calificado: Boolean = false,
    @SerialName("created_at") val creadoEn: String? = null,
) {
    val estadoEnum: EstadoReserva get() = EstadoReserva.de(estado)
    val recurso: RecursoTipo get() = RecursoTipo.de(recursoTipo)

    // El avance del seguimiento depende del catálogo, que ahora es remoto, así
    // que se resuelve con él en la mano en vez de con una tabla compilada.
    fun pasoActual(cat: Catalogos): Int = cat.indicePaso(recurso, trackingEstado)
    fun enUltimoPaso(cat: Catalogos): Boolean = cat.esUltimoPaso(recurso, trackingEstado)

    /** Evidencias que le tocan a este usuario según su lado de la operación. */
    fun misEvidencias(soyCliente: Boolean): List<String> =
        (if (soyCliente) evidenciasCliente else evidencias).orEmpty()

    fun evidenciasDelOtro(soyCliente: Boolean): List<String> =
        (if (soyCliente) evidencias else evidenciasCliente).orEmpty()

    /**
     * Estado del cobro, derivado igual que en la web: no hay un proceso que
     * cambie estados a diario, se calcula al mostrar.
     */
    val estadoCobro: EstadoCobro
        get() = when {
            pagado -> EstadoCobro.PAGADO
            estadoEnum != EstadoReserva.COMPLETADA -> EstadoCobro.NO_APLICA
            (Fmt.diasHasta(fechaVencimientoPago) ?: 0L) < 0L -> EstadoCobro.VENCIDO
            else -> EstadoCobro.POR_COBRAR
        }
}

enum class EstadoCobro(val etiqueta: String) {
    NO_APLICA("—"),
    POR_COBRAR("Por cobrar"),
    VENCIDO("Vencido"),
    PAGADO("Pagado"),
}

/** Expediente documental de una etapa del viaje. Tabla `expedientes`. */
@Serializable
data class Expediente(
    val id: String,
    @SerialName("reserva_id") val reservaId: String,
    val etapa: String,
    val estado: String? = null,
    @SerialName("solicitado_en") val solicitadoEn: String? = null,
    @SerialName("completado_en") val completadoEn: String? = null,
    val nota: String? = null,
    @SerialName("deposito_vacios") val depositoVacios: String? = null,
    @SerialName("fecha_limite_vacios") val fechaLimiteVacios: String? = null,
) {
    val etapaEnum: EtapaExpediente? get() = EtapaExpediente.de(etapa)
    val completo: Boolean get() = estado == "completo"

    /** Días para devolver el contenedor sin que corran demoras. */
    val diasParaVacios: Long? get() = Fmt.diasHasta(fechaLimiteVacios)
}

/** Renglón del checklist de un expediente. Tabla `expediente_documentos`. */
@Serializable
data class ExpedienteDocumento(
    val id: String,
    @SerialName("expediente_id") val expedienteId: String,
    val nombre: String,
    val descripcion: String? = null,
    val obligatorio: Boolean = true,
    val orden: Int = 0,
    val estado: String = "pendiente",
    @SerialName("archivo_path") val archivoPath: String? = null,
    @SerialName("archivo_nombre") val archivoNombre: String? = null,
    @SerialName("nota_rechazo") val notaRechazo: String? = null,
    @SerialName("subido_en") val subidoEn: String? = null,
) {
    val pendiente: Boolean get() = estado == "pendiente"
    val subido: Boolean get() = estado == "subido"
    val aceptado: Boolean get() = estado == "aceptado"
    val rechazado: Boolean get() = estado == "rechazado"
}

/** Calificación del cliente a la empresa. Tabla `calificaciones`. */
@Serializable
data class Calificacion(
    val id: String? = null,
    @SerialName("reservacion_id") val reservacionId: String? = null,
    @SerialName("admin_id") val adminId: String? = null,
    @SerialName("cliente_id") val clienteId: String? = null,
    val rating: Int,
    val comentario: String? = null,
    @SerialName("created_at") val creadoEn: String? = null,
)
