package mx.portgo.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import mx.portgo.app.core.Resultado
import mx.portgo.app.data.model.EstadoOferta
import mx.portgo.app.data.model.EstadoReserva
import mx.portgo.app.data.model.PedidoConOfertas
import mx.portgo.app.data.model.Reservacion
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.data.repository.ConfiguracionRepository
import mx.portgo.app.data.repository.PedidosRepository
import mx.portgo.app.data.repository.ReservacionesRepository

/**
 * Resumen de arranque.
 *
 * Contesta la única pregunta con la que alguien abre esta app: **qué me toca
 * hacer ahora**. Por eso no es un tablero de métricas — es la lista corta de
 * cosas que están esperando por ti, y el atajo para llegar a cada una.
 */
class InicioViewModel(
    private val pedidos: PedidosRepository,
    private val reservaciones: ReservacionesRepository,
    private val configuracion: ConfiguracionRepository,
    private val usuario: UsuarioActual,
) : ViewModel() {

    data class Resumen(
        /** Cosas que requieren acción de esta persona, en orden de urgencia. */
        val pendientes: List<Pendiente> = emptyList(),
        val serviciosActivos: List<Reservacion> = emptyList(),
        val solicitudesAbiertas: Int = 0,
    )

    data class Pendiente(
        val titulo: String,
        val detalle: String,
        val destino: Destino,
    )

    sealed interface Destino {
        data class Solicitud(val id: String) : Destino
        data class Servicio(val id: String) : Destino
        data class Seccion(val ruta: String) : Destino
    }

    private val _estado = MutableStateFlow<EstadoCarga<Resumen>>(EstadoCarga.Cargando)
    val estado: StateFlow<EstadoCarga<Resumen>> = _estado.asStateFlow()

    private val _refrescando = MutableStateFlow(false)
    val refrescando: StateFlow<Boolean> = _refrescando.asStateFlow()

    init {
        cargar()
    }

    fun refrescar() {
        _refrescando.value = true
        cargar()
    }

    fun cargar() = viewModelScope.launch {
        val resPedidos = pedidos.listar(
            rol = usuario.rol,
            pagina = 0,
            soloMias = usuario.esCliente,
            miId = usuario.id,
        )
        val resReservas = reservaciones.mias(usuario)

        // Si las dos fallan no hay nada que enseñar. Si falla una sola, se
        // muestra lo que sí llegó: media pantalla útil vale más que un error.
        if (resPedidos is Resultado.Error && resReservas is Resultado.Error) {
            _estado.value = EstadoCarga.Fallo(resPedidos.error.mensaje)
            _refrescando.value = false
            return@launch
        }

        val listaPedidos = (resPedidos as? Resultado.Ok)?.dato.orEmpty()
        val listaReservas = (resReservas as? Resultado.Ok)?.dato.orEmpty()

        _estado.value = EstadoCarga.Listo(
            Resumen(
                pendientes = construirPendientes(listaPedidos, listaReservas),
                serviciosActivos = listaReservas.filter {
                    it.estadoEnum == EstadoReserva.ACTIVA
                },
                solicitudesAbiertas = listaPedidos.count { it.pedido.estadoEnum.admiteOfertas },
            ),
        )
        _refrescando.value = false
    }

    private fun construirPendientes(
        listaPedidos: List<PedidoConOfertas>,
        listaReservas: List<Reservacion>,
    ): List<Pendiente> = buildList {

        if (usuario.esCliente) {
            // Ofertas esperando respuesta: es lo que traba el trato.
            listaPedidos.forEach { item ->
                val vivas = item.ofertas.count { it.estadoEnum == EstadoOferta.ENVIADA }
                if (vivas > 0) {
                    add(
                        Pendiente(
                            titulo = "$vivas oferta${if (vivas == 1) "" else "s"} por responder",
                            detalle = item.pedido.ruta,
                            destino = Destino.Solicitud(item.pedido.id),
                        ),
                    )
                }
            }

            // Servicios completados sin calificar.
            listaReservas.filter { it.estadoEnum == EstadoReserva.COMPLETADA && !it.calificado }
                .forEach {
                    add(
                        Pendiente(
                            titulo = "Califica el servicio",
                            detalle = it.unidad ?: "Servicio completado",
                            destino = Destino.Servicio(it.id),
                        ),
                    )
                }
        } else {
            // Contraofertas esperando respuesta de la empresa.
            listaPedidos.forEach { item ->
                item.ofertas.firstOrNull {
                    it.adminId == usuario.id && it.estadoEnum == EstadoOferta.CONTRA_OFERTA
                }?.let {
                    add(
                        Pendiente(
                            titulo = "Te contraofertaron",
                            detalle = item.pedido.ruta,
                            destino = Destino.Solicitud(item.pedido.id),
                        ),
                    )
                }
            }
        }

        // Ambos lados: cierres y cancelaciones en revisión, y viajes en curso
        // que ya llegaron al último paso y falta cerrar.
        listaReservas.forEach { r ->
            when {
                r.estadoEnum == EstadoReserva.POR_APROBAR &&
                    r.misEvidencias(usuario.esCliente).isEmpty() ->
                    add(
                        Pendiente(
                            titulo = "Sube tu evidencia del cierre",
                            detalle = r.unidad ?: "Servicio",
                            destino = Destino.Servicio(r.id),
                        ),
                    )

                r.estadoEnum == EstadoReserva.ACTIVA &&
                    r.enUltimoPaso(configuracion.catalogos.value) && !usuario.esCliente ->
                    add(
                        Pendiente(
                            titulo = "Marca el servicio como completado",
                            detalle = r.unidad ?: "Servicio",
                            destino = Destino.Servicio(r.id),
                        ),
                    )
            }
        }
    }
}
