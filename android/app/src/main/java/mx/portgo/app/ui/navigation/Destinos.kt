package mx.portgo.app.ui.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Assignment
import androidx.compose.material.icons.filled.EventAvailable
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import mx.portgo.app.data.model.Rol
import mx.portgo.app.ui.components.PestanaBarra

/**
 * Rutas de navegación.
 *
 * Las que llevan argumentos los codifican en la ruta porque son identificadores
 * cortos. El título del chat viaja codificado en URL: los nombres de empresa
 * traen espacios, acentos y a veces "/" y "&", que romperían la ruta.
 */
object Rutas {
    const val INICIO = "inicio"
    const val SOLICITUDES = "solicitudes"
    const val RESERVACIONES = "reservaciones"
    const val FLOTA = "flota"
    const val PERFIL = "perfil"

    const val NOTIFICACIONES = "notificaciones"

    // Modulos que el diseno pone en la rejilla de inicio. Los que todavia no
    // estan construidos muestran PantallaPendiente, que dice con claridad que
    // esa seccion sigue solo en la web en vez de fingir que existe.
    const val CATALOGO = "catalogo"
    const val PAGOS = "pagos"
    const val PRIVACIDAD = "privacidad"
    const val VIGENCIAS = "vigencias"
    const val OPERADORES = "operadores"
    const val COBROS = "cobros"
    const val NUEVA_SOLICITUD = "nueva_solicitud"
    const val ALTA_CAMION = "alta_camion"
    const val ALTA_OPERADOR = "alta_operador"

    fun solicitud(id: String) = "solicitud/$id"
    const val SOLICITUD_PATRON = "solicitud/{pedidoId}"

    fun reservacion(id: String) = "reservacion/$id"
    const val RESERVACION_PATRON = "reservacion/{reservaId}"

    /**
     * @param contexto "reserva" o "pedido"
     * @param otroId con quién se conversa
     */
    fun chat(contexto: String, ctxId: String, otroId: String, titulo: String) =
        "chat/$contexto/$ctxId/$otroId/${java.net.URLEncoder.encode(titulo, "UTF-8")}"

    const val CHAT_PATRON = "chat/{contexto}/{ctxId}/{otroId}/{titulo}"

    fun expediente(reservaId: String, etapa: String) = "expediente/$reservaId/$etapa"
    const val EXPEDIENTE_PATRON = "expediente/{reservaId}/{etapa}"
}

/**
 * Pestañas de la barra inferior, según el diseño 1b.
 *
 * Son CUATRO y las mismas para ambos roles: dos a cada lado del botón central.
 * Flota salió de la barra —ahora se llega por la tarjeta "Mis unidades" del
 * inicio— porque el diseño reserva el centro para la acción principal y
 * cinco pestañas más el FAB no caben sin apretarlo todo.
 *
 * La acción central cambia por rol: el cliente publica solicitudes, la empresa
 * agrega unidades.
 */
fun pestanasDe(rol: Rol): List<PestanaBarra> = listOf(
    PestanaBarra(Rutas.INICIO, "Inicio", Icons.Default.Home),
    PestanaBarra(Rutas.SOLICITUDES, "Solicitudes", Icons.AutoMirrored.Filled.Assignment),
    PestanaBarra(Rutas.RESERVACIONES, "Reservas", Icons.Default.EventAvailable),
    PestanaBarra(Rutas.PERFIL, "Perfil", Icons.Default.Person),
).also { require(rol != Rol.SUPERADMIN) { "El superadmin todavía no entra a la app." } }

/** Etiqueta del botón central. */
fun etiquetaAccion(rol: Rol): String =
    if (rol == Rol.CLIENTE) "Publicar" else "Agregar"

/**
 * A dónde lleva el botón central.
 *
 * Para la empresa el handoff dejaba la acción "a definir con el equipo". Se
 * eligió el alta de unidad porque es lo que la empresa hace fuera de la
 * oficina, con el camión enfrente — ofertar requiere antes elegir una
 * solicitud, así que no funciona como acción suelta desde cualquier pantalla.
 */
fun rutaAccion(rol: Rol): String =
    if (rol == Rol.CLIENTE) Rutas.NUEVA_SOLICITUD else Rutas.ALTA_CAMION
