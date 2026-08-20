package mx.portgo.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import mx.portgo.app.core.Resultado
import mx.portgo.app.data.model.EstadoPedido
import mx.portgo.app.data.model.EstadoReserva
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.data.repository.AuthRepository
import mx.portgo.app.data.repository.FlotaRepository
import mx.portgo.app.data.repository.PedidosRepository
import mx.portgo.app.data.repository.ReservacionesRepository

/**
 * Inicio: rejilla de accesos con conteos en vivo.
 *
 * El diseño convierte la pantalla de entrada en un lanzador de módulos, y los
 * badges son lo que evita que sea solo un menú: "Mis solicitudes · 2" dice que
 * hay dos esperando respuesta sin necesidad de entrar a mirar.
 *
 * Los conteos se derivan de los mismos datos que ya cargan las listas, así que
 * no hay una fuente aparte que pueda quedar desfasada.
 */
class InicioViewModel(
    private val pedidos: PedidosRepository,
    private val reservaciones: ReservacionesRepository,
    private val flota: FlotaRepository,
    private val auth: AuthRepository,
    private val usuario: UsuarioActual,
) : ViewModel() {

    data class Resumen(
        // Comunes
        val solicitudesPendientes: Int = 0,
        val reservasActivas: Int = 0,
        // Solo empresa
        val unidades: Int = 0,
        val ofertasActivas: Int = 0,
        val calificacion: Double? = null,
        val vigenciasPorVencer: Int = 0,
    )

    private val _estado = MutableStateFlow<EstadoCarga<Resumen>>(EstadoCarga.Cargando)
    val estado: StateFlow<EstadoCarga<Resumen>> = _estado.asStateFlow()

    private val _refrescando = MutableStateFlow(false)
    val refrescando: StateFlow<Boolean> = _refrescando.asStateFlow()

    /** Saludo según la hora, en la zona del negocio. */
    val saludo: String
        get() = when (java.time.LocalTime.now(mx.portgo.app.core.Fmt.ZONA).hour) {
            in 0..11 -> "Buenos días"
            in 12..18 -> "Buenas tardes"
            else -> "Buenas noches"
        }

    /** El cliente se saluda por su nombre de pila; la empresa por su razón social. */
    val titulo: String
        get() = if (usuario.esCliente) usuario.nombre.substringBefore(' ') else usuario.nombre

    init {
        cargar()
    }

    fun refrescar() {
        _refrescando.value = true
        cargar()
    }

    fun cargar() = viewModelScope.launch {
        val resReservas = reservaciones.mias(usuario)
        val listaReservas = (resReservas as? Resultado.Ok)?.dato.orEmpty()

        val resumen = if (usuario.esCliente) {
            val mias = pedidos.listar(
                rol = usuario.rol, pagina = 0, soloMias = true, miId = usuario.id,
            )
            val listaPedidos = (mias as? Resultado.Ok)?.dato.orEmpty()

            Resumen(
                // "Pendiente" para el cliente = algo que espera acción suya o
                // respuesta ajena: publicada, en negociación o por aprobar.
                solicitudesPendientes = listaPedidos.count {
                    it.pedido.estadoEnum in setOf(
                        EstadoPedido.ABIERTO,
                        EstadoPedido.EN_NEGOCIACION,
                        EstadoPedido.PENDIENTE_REVISION,
                        EstadoPedido.PENDIENTE_ACUERDO,
                    )
                },
                reservasActivas = listaReservas.count { it.estadoEnum == EstadoReserva.ACTIVA },
            )
        } else {
            val disponibles = pedidos.listar(rol = usuario.rol, pagina = 0, miId = usuario.id)
            val conOfertas = pedidos.conMisOfertas(usuario.id)
            val camiones = flota.camiones(usuario.id)

            Resumen(
                // Para la empresa el badge de Solicitudes es la oportunidad:
                // cuántas hay ahora mismo para ofertar.
                solicitudesPendientes = (disponibles as? Resultado.Ok)?.dato
                    ?.count { it.pedido.estadoEnum.admiteOfertas } ?: 0,
                reservasActivas = listaReservas.count { it.estadoEnum == EstadoReserva.ACTIVA },
                unidades = (camiones as? Resultado.Ok)?.dato?.size ?: 0,
                ofertasActivas = (conOfertas as? Resultado.Ok)?.dato
                    ?.sumOf { item ->
                        item.ofertas.count {
                            it.adminId == usuario.id && it.estadoEnum.esViva
                        }
                    } ?: 0,
                calificacion = auth.calificacionPromedio(usuario.id),
                vigenciasPorVencer = flota.vigenciasPorVencer(usuario.id).size,
            )
        }

        _estado.value = EstadoCarga.Listo(resumen)
        _refrescando.value = false
    }
}
