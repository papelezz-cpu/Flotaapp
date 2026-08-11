package mx.portgo.app.ui.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Assignment
import androidx.compose.material.icons.automirrored.filled.EventNote
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LocalShipping
import androidx.compose.material.icons.filled.Person
import androidx.compose.ui.graphics.vector.ImageVector
import mx.portgo.app.data.model.Rol

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
    const val NUEVA_SOLICITUD = "nueva_solicitud"

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

/** Entrada de la barra inferior. */
data class DestinoBarra(
    val ruta: String,
    val etiqueta: String,
    val icono: ImageVector,
)

/**
 * Qué pestañas ve cada rol.
 *
 * El cliente no tiene Flota — no tiene camiones — y su pestaña de solicitudes
 * es donde publica; la empresa las consume. Es la misma división que hace la
 * web con las clases `role-admin` / `role-superadmin` sobre el `<body>`, solo
 * que aquí se resuelve al construir la barra en vez de ocultando nodos.
 */
fun destinosDe(rol: Rol): List<DestinoBarra> = buildList {
    add(DestinoBarra(Rutas.INICIO, "Inicio", Icons.Default.Home))
    add(DestinoBarra(Rutas.SOLICITUDES, "Solicitudes", Icons.AutoMirrored.Filled.Assignment))
    add(DestinoBarra(Rutas.RESERVACIONES, "Servicios", Icons.AutoMirrored.Filled.EventNote))
    if (rol == Rol.EMPRESA) {
        add(DestinoBarra(Rutas.FLOTA, "Flota", Icons.Default.LocalShipping))
    }
    add(DestinoBarra(Rutas.PERFIL, "Perfil", Icons.Default.Person))
}
