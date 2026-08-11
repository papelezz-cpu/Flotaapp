package mx.portgo.app.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Solicitud de transporte publicada por un cliente. Tabla `pedidos`.
 *
 * Casi todo es nullable a propósito. Dos razones:
 *   1. La tabla sirve a cuatro tipos de servicio (camión, custodio, patio,
 *      lavado) sobre las mismas columnas: lo que un camión llena, un lavado lo
 *      deja vacío.
 *   2. La línea base del esquema todavía no está en el repo (gap G3 del
 *      análisis), así que la nullability real está sin confirmar. Declarar
 *      opcional de más produce un `?` incómodo; declarar obligatorio de menos
 *      produce un crash al deserializar. Se corrige cuando llegue `db pull`.
 */
@Serializable
data class Pedido(
    val id: String,
    @SerialName("cliente_id") val clienteId: String? = null,
    @SerialName("cliente_nombre") val clienteNombre: String? = null,
    @SerialName("cliente_email") val clienteEmail: String? = null,

    val estado: String? = null,
    val descripcion: String? = null,
    @SerialName("created_at") val creadoEn: String? = null,

    // ── Servicio ──
    @SerialName("tipo_camion") val tipoCamion: String? = null,
    @SerialName("tipo_camion_sugerido") val tipoCamionSugerido: String? = null,
    @SerialName("categoria_carga") val categoriaCarga: String? = null,
    @SerialName("tipo_carga") val tipoCarga: String? = null,

    // ── Ruta ──
    val origen: String? = null,
    val destino: String? = null,
    @SerialName("origen_lat") val origenLat: Double? = null,
    @SerialName("origen_lng") val origenLng: Double? = null,
    @SerialName("destino_lat") val destinoLat: Double? = null,
    @SerialName("destino_lng") val destinoLng: Double? = null,

    // ── Fechas ──
    @SerialName("fecha_arribo_puerto") val fechaArriboPuerto: String? = null,
    @SerialName("fecha_ini") val fechaIni: String? = null,
    @SerialName("fecha_fin") val fechaFin: String? = null,

    // ── Carga ──
    @SerialName("peso_carga") val pesoCarga: Double? = null,
    @SerialName("num_tarimas") val numTarimas: Int? = null,
    @SerialName("volumen_m3") val volumenM3: Double? = null,
    @SerialName("num_bultos") val numBultos: Int? = null,
    @SerialName("capacidad_min") val capacidadMin: Int? = null,

    val refrigerado: Boolean = false,
    @SerialName("temp_min") val tempMin: Double? = null,
    @SerialName("temp_max") val tempMax: Double? = null,

    @SerialName("num_contenedores") val numContenedores: Int? = null,
    @SerialName("contenedor_1_tipo") val contenedor1Tipo: String? = null,
    @SerialName("contenedor_1_peso") val contenedor1Peso: Double? = null,
    @SerialName("contenedor_2_tipo") val contenedor2Tipo: String? = null,
    @SerialName("contenedor_2_peso") val contenedor2Peso: Double? = null,
    @SerialName("tipo_contenedor") val tipoContenedor: String? = null,

    @SerialName("largo_m") val largoM: Double? = null,
    @SerialName("ancho_m") val anchoM: Double? = null,
    @SerialName("alto_m") val altoM: Double? = null,

    @SerialName("hazmat_clase") val hazmatClase: String? = null,
    @SerialName("hazmat_un") val hazmatUn: String? = null,

    // ── Banderas ──
    @SerialName("carga_peligrosa") val cargaPeligrosa: Boolean = false,
    @SerialName("temp_controlada") val tempControlada: Boolean = false,
    @SerialName("requiere_seguro") val requiereSeguro: Boolean = false,
    @SerialName("requiere_factura") val requiereFactura: Boolean = false,
    @SerialName("entra_a_puerto") val entraAPuerto: Boolean = false,

    // ── Comercial ──
    @SerialName("precio_cliente") val precioCliente: Double? = null,
    @SerialName("plazo_pago") val plazoPago: String? = null,

    // ── Flujo ──
    @SerialName("oferta_pendiente_id") val ofertaPendienteId: String? = null,
    @SerialName("rechazo_nota") val rechazoNota: String? = null,

    // ── Otros servicios (custodio / patio / lavado) ──
    @SerialName("num_custodios") val numCustodios: Int? = null,
    @SerialName("zona_cobertura") val zonaCobertura: String? = null,
    @SerialName("horario_servicio") val horarioServicio: String? = null,
    @SerialName("num_vehiculos") val numVehiculos: Int? = null,
    @SerialName("tipo_vehiculos") val tipoVehiculos: String? = null,
    @SerialName("area_necesaria") val areaNecesaria: Double? = null,
) {
    val estadoEnum: EstadoPedido get() = EstadoPedido.de(estado)

    /** Trae medidas capturadas: es carga sobredimensionada, venga como venga la categoría. */
    val tieneDimensiones: Boolean
        get() = largoM != null && anchoM != null && altoM != null

    /** `Manzanillo → Guadalajara`, o solo el origen si no hay destino. */
    val ruta: String
        get() = when {
            origen.isNullOrBlank() -> "—"
            destino.isNullOrBlank() -> origen
            else -> "$origen → $destino"
        }

    /** El cliente cambió a mano la unidad que el sistema recomendó. */
    val unidadCorregida: Boolean
        get() = tipoCamionSugerido != null && tipoCamionSugerido != tipoCamion
}

/**
 * Oferta de una empresa sobre un pedido. Tabla `ofertas`.
 *
 * Ojo con `precioOferta` vs `contraPrecio`: cuando el cliente contraoferta, el
 * precio original se conserva y el nuevo va en `contra_precio`. La RPC
 * `responder_contraoferta` copia el segundo sobre el primero al aceptar, así
 * que después de cerrado `precio_oferta` es el precio pactado.
 */
@Serializable
data class Oferta(
    val id: String,
    @SerialName("pedido_id") val pedidoId: String,
    @SerialName("admin_id") val adminId: String? = null,
    @SerialName("admin_nombre") val adminNombre: String? = null,

    @SerialName("camion_id") val camionId: String? = null,
    @SerialName("operador_id") val operadorId: String? = null,
    @SerialName("operador_nombre") val operadorNombre: String? = null,

    @SerialName("precio_oferta") val precioOferta: Double? = null,
    @SerialName("contra_precio") val contraPrecio: Double? = null,
    val ronda: Int? = null,

    val estado: String? = null,
    val mensaje: String? = null,
    @SerialName("permite_reoferta") val permiteReoferta: Boolean = true,
    @SerialName("expira_en") val expiraEn: String? = null,
    @SerialName("created_at") val creadoEn: String? = null,
) {
    val estadoEnum: EstadoOferta get() = EstadoOferta.de(estado)

    /** El precio que está sobre la mesa ahora mismo. */
    val precioVigente: Double? get() = contraPrecio ?: precioOferta

    val venceEn: String? get() = expiraEn
}

/** Un pedido junto con sus ofertas, que es como se dibuja siempre en la UI. */
data class PedidoConOfertas(
    val pedido: Pedido,
    val ofertas: List<Oferta> = emptyList(),
) {
    val ofertasVivas: List<Oferta> get() = ofertas.filter { it.estadoEnum.esViva }
    val ofertaAceptada: Oferta? get() = ofertas.firstOrNull { it.estadoEnum == EstadoOferta.ACEPTADA }
    val mejorPrecio: Double? get() = ofertasVivas.mapNotNull { it.precioVigente }.minOrNull()
}

/** Plantilla de solicitud frecuente del cliente. Tabla `plantillas_pedido`. */
@Serializable
data class PlantillaPedido(
    val id: String,
    @SerialName("cliente_id") val clienteId: String? = null,
    val nombre: String,
    @SerialName("tipo_camion") val tipoCamion: String? = null,
    @SerialName("categoria_carga") val categoriaCarga: String? = null,
    @SerialName("tipo_carga") val tipoCarga: String? = null,
    val origen: String? = null,
    val destino: String? = null,
    @SerialName("peso_carga") val pesoCarga: Double? = null,
    @SerialName("num_tarimas") val numTarimas: Int? = null,
    val refrigerado: Boolean = false,
    @SerialName("temp_min") val tempMin: Double? = null,
    @SerialName("temp_max") val tempMax: Double? = null,
    @SerialName("num_contenedores") val numContenedores: Int? = null,
    @SerialName("contenedor_1_tipo") val contenedor1Tipo: String? = null,
    @SerialName("entra_a_puerto") val entraAPuerto: Boolean = false,
    @SerialName("precio_cliente") val precioCliente: Double? = null,
    @SerialName("plazo_pago") val plazoPago: String? = null,
    val descripcion: String? = null,
    @SerialName("veces_usada") val vecesUsada: Int = 0,
    @SerialName("ultima_vez_usada") val ultimaVezUsada: String? = null,
)
