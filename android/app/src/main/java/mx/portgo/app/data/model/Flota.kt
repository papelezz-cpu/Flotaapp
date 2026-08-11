package mx.portgo.app.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import mx.portgo.app.core.Fmt

/**
 * Perfil del usuario. Tabla `perfiles`, PK `user_id`.
 *
 * `aprobacionCuenta` es la que decide si la cuenta puede operar: null = activa.
 * Ese filtro hoy vive solo en el cliente (js/auth.js), no en RLS — está
 * documentado como gap G4 y quedó fuera del alcance por ahora, así que esta
 * app lo replica al iniciar sesión igual que la web. No es cosmético: es lo
 * único que impide entrar a una cuenta suspendida.
 */
@Serializable
data class Perfil(
    @SerialName("user_id") val userId: String,
    val nombre: String? = null,
    val rol: String? = null,
    @SerialName("aprobacion_cuenta") val aprobacionCuenta: String? = null,
    @SerialName("nota_rechazo_cuenta") val notaRechazoCuenta: String? = null,
    @SerialName("metodo_verificacion") val metodoVerificacion: String? = null,
    val verificado: Boolean = false,
    val telefono: String? = null,
    val descripcion: String? = null,
    @SerialName("razon_social") val razonSocial: String? = null,
    val rfc: String? = null,
    @SerialName("notif_email") val notifEmail: Boolean = true,
) {
    val rolEnum: Rol get() = Rol.de(rol)

    /** null = activa. Cualquier otro valor impide operar. */
    val cuentaActiva: Boolean get() = aprobacionCuenta == null

    val motivoBloqueo: String?
        get() = when (aprobacionCuenta) {
            "pendiente" ->
                "Tu cuenta está pendiente de aprobación. Te contactaremos cuando sea revisada."
            "rechazada" ->
                "Tu solicitud fue rechazada." +
                    (notaRechazoCuenta?.let { " Motivo: $it" } ?: " Contacta a soporte para más información.")
            "suspendida" ->
                "Tu cuenta ha sido suspendida. Contacta a soporte: soporte@portgo.mx"
            else -> null
        }
}

/** Usuario en sesión, tal como lo consume la UI. Espejo de `currentUser` en la web. */
data class UsuarioActual(
    val id: String,
    val email: String,
    val nombre: String,
    val rol: Rol,
    val metodoVerificacion: String? = null,
) {
    val esCliente: Boolean get() = rol == Rol.CLIENTE
    val esEmpresa: Boolean get() = rol == Rol.EMPRESA
}

/** Unidad de la flota. Tabla `camiones`, PK `id` (texto: el número económico). */
@Serializable
data class Camion(
    val id: String,
    @SerialName("propietario_id") val propietarioId: String? = null,
    val tipo: String? = null,
    val estado: String? = null,
    val aprobacion: String? = null,
    val emoji: String? = null,
    val placas: String? = null,
    val capacidad: String? = null,
    val dimensiones: String? = null,
    @SerialName("precio_dia") val precioDia: Double? = null,
    val marca: String? = null,
    val modelo: String? = null,
    @SerialName("modelo_anio") val modeloAnio: Int? = null,
    val color: String? = null,
    @SerialName("num_economico") val numEconomico: String? = null,
    val caat: String? = null,
    @SerialName("rechazo_nota") val rechazoNota: String? = null,
    @SerialName("fecha_vencimiento_tc") val venceTarjeta: String? = null,
    @SerialName("fecha_vencimiento_seguro") val venceSeguro: String? = null,
    @SerialName("fecha_vencimiento_permiso_sct") val vencePermisoSct: String? = null,
    @SerialName("fecha_vencimiento_verificacion") val venceVerificacion: String? = null,
) : RecursoFlota {
    override val identificador: String get() = id
    override val etiqueta: String get() = "${emoji ?: "🚛"} $id"
    override val subtitulo: String? get() = tipo
    override val aprobacionEstado: String? get() = aprobacion
    override val disponibilidad: String? get() = estado

    /** El documento más próximo a vencer, para el aviso de vigencias. */
    val proximoVencimiento: Pair<String, Long>?
        get() = listOfNotNull(
            venceTarjeta?.let { "Tarjeta de circulación" to it },
            venceSeguro?.let { "Seguro" to it },
            vencePermisoSct?.let { "Permiso SCT" to it },
            venceVerificacion?.let { "Verificación" to it },
        ).mapNotNull { (nombre, fecha) ->
            Fmt.diasHasta(fecha)?.let { nombre to it }
        }.minByOrNull { it.second }
}

/** Chofer. Tabla `operadores`. */
@Serializable
data class Operador(
    val id: String,
    @SerialName("propietario_id") val propietarioId: String? = null,
    val nombre: String? = null,
    val curp: String? = null,
    @SerialName("num_licencia") val numLicencia: String? = null,
    @SerialName("num_trabajador") val numTrabajador: String? = null,
    val telefono: String? = null,
    val estado: String? = null,
    val aprobacion: String? = null,
    @SerialName("foto_url") val fotoUrl: String? = null,
    @SerialName("rechazo_nota") val rechazoNota: String? = null,
    @SerialName("fecha_vencimiento_licencia") val venceLicencia: String? = null,
) : RecursoFlota {
    override val identificador: String get() = id
    override val etiqueta: String get() = nombre ?: id
    override val subtitulo: String? get() = numLicencia?.let { "Licencia $it" }
    override val aprobacionEstado: String? get() = aprobacion
    override val disponibilidad: String? get() = estado
}

/**
 * Lo común entre camiones, custodios, patios, lavados y operadores. Las cinco
 * tablas comparten `propietario_id`, `estado` y el flujo de `aprobacion`, y la
 * UI de flota las dibuja igual.
 */
interface RecursoFlota {
    val identificador: String
    val etiqueta: String
    val subtitulo: String?
    val aprobacionEstado: String?
    val disponibilidad: String?

    val aprobado: Boolean get() = aprobacionEstado == "aprobada"
    val enRevision: Boolean get() = aprobacionEstado == "pendiente"
    val rechazado: Boolean get() = aprobacionEstado == "rechazada"
    val ocupado: Boolean get() = disponibilidad == "ocupado"
}
