package mx.portgo.app.data.model

/**
 * Los estados se guardan como `text` libre en la base, no como enums de
 * Postgres. Aquí se modelan como enums de Kotlin con un `desconocido` de
 * respaldo: si mañana la web agrega un estado nuevo, esta app lo muestra
 * neutro en vez de reventar al deserializar una fila publicada.
 *
 * Regla: los modelos guardan el `String` crudo de la base; estos enums son
 * para decidir en la UI. Nunca se escribe de vuelta el nombre del enum.
 */

enum class Rol(val db: String) {
    CLIENTE("cliente"),
    EMPRESA("admin"),          // en la base es 'admin'; en el negocio, la empresa transportista
    SUPERADMIN("superadmin"),
    DESCONOCIDO("");

    companion object {
        fun de(valor: String?) = entries.firstOrNull { it.db == valor } ?: DESCONOCIDO
    }
}

enum class EstadoPedido(val db: String, val etiqueta: String) {
    PENDIENTE_REVISION("pendiente_revision", "En revisión"),
    ABIERTO("abierto", "Abierta"),
    EN_NEGOCIACION("en_negociacion", "En negociación"),
    PENDIENTE_ACUERDO("pendiente_acuerdo", "Acuerdo por aprobar"),
    ACORDADO("acordado", "Acordada"),
    FINALIZADO("finalizado", "Finalizada"),
    EXPIRADO("expirado", "Expirada"),
    CANCELADO("cancelado", "Cancelada"),
    RECHAZADO("rechazado", "Rechazada"),
    DESCONOCIDO("", "—");

    /** Admite ofertas nuevas. */
    val admiteOfertas: Boolean get() = this == ABIERTO || this == EN_NEGOCIACION

    /** Ya no va a cambiar más. */
    val esTerminal: Boolean
        get() = this in setOf(FINALIZADO, EXPIRADO, CANCELADO, RECHAZADO)

    companion object {
        fun de(valor: String?) = entries.firstOrNull { it.db == valor } ?: DESCONOCIDO
    }
}

enum class EstadoOferta(val db: String, val etiqueta: String) {
    ENVIADA("enviada", "Enviada"),
    CONTRA_OFERTA("contra_oferta", "Contraoferta"),
    ACEPTADA("aceptada", "Aceptada"),
    RECHAZADA("rechazada", "Rechazada"),
    DESCONOCIDO("", "—");

    val esViva: Boolean get() = this == ENVIADA || this == CONTRA_OFERTA

    companion object {
        fun de(valor: String?) = entries.firstOrNull { it.db == valor } ?: DESCONOCIDO
    }
}

enum class EstadoReserva(val db: String, val etiqueta: String) {
    PENDIENTE("Pendiente", "Pendiente"),
    ACTIVA("Activa", "Activa"),
    POR_APROBAR("PorAprobar", "Cierre en revisión"),
    CANCELACION_SOLICITADA("CancelacionSolicitada", "Cancelación en revisión"),
    COMPLETADA("Completada", "Completada"),
    CANCELADA("Cancelada", "Cancelada"),
    RECHAZADA("Rechazada", "Rechazada"),
    DESCONOCIDO("", "—");

    val esTerminal: Boolean get() = this in setOf(COMPLETADA, CANCELADA, RECHAZADA)

    companion object {
        fun de(valor: String?) = entries.firstOrNull { it.db == valor } ?: DESCONOCIDO
    }
}

enum class RecursoTipo(val db: String, val etiqueta: String) {
    CAMION("camion", "Camión"),
    CUSTODIO("custodio", "Custodio"),
    PATIO("patio", "Patio"),
    LAVADO("lavado", "Lavado");

    /** Tabla de flota correspondiente. Espejo de tabla_recurso() en la base. */
    val tabla: String
        get() = when (this) {
            CAMION -> "camiones"
            CUSTODIO -> "custodios"
            PATIO -> "patios"
            LAVADO -> "lavados"
        }

    companion object {
        fun de(valor: String?) = entries.firstOrNull { it.db == valor } ?: CAMION
    }
}

// Los pasos del seguimiento y las categorías de carga ya NO viven aquí: son
// catálogos que la app lee del servidor (ver data/model/Catalogos.kt).
//
// El motivo es el historial de este proyecto: cinco de los últimos quince
// commits tocan el formulario de solicitud. Cada uno de esos cambios, con las
// listas compiladas, habría sido una versión nueva en las tiendas y meses de
// usuarios viendo opciones distintas según cuándo instalaron la app.
//
// Lo que sí sigue aquí son los estados del flujo, porque no son una lista de
// opciones editable: cada uno tiene código que reacciona a él. Agregar un
// estado nuevo en la base es seguro (caen en `DESCONOCIDO`); quitarlos no.

/** Etapas del expediente documental del viaje. */
enum class EtapaExpediente(val db: String, val etiqueta: String) {
    INGRESO_PUERTO("ingreso_puerto", "Ingreso a puerto"),
    ENTREGA_VACIOS("entrega_vacios", "Entrega de vacíos");

    companion object {
        fun de(valor: String?) = entries.firstOrNull { it.db == valor }
    }
}
