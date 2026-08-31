package mx.portgo.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import mx.portgo.app.core.Resultado
import mx.portgo.app.data.model.EstadoCobro
import mx.portgo.app.data.model.EstadoReserva
import mx.portgo.app.data.model.Expediente
import mx.portgo.app.data.model.Reservacion
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.data.repository.AuthRepository
import mx.portgo.app.data.repository.ReservacionesRepository

/** Fila de la lista, con lo que hace falta para pintarla sin más consultas. */
data class FilaReservacion(
    val reservacion: Reservacion,
    val expedientes: List<Expediente> = emptyList(),
    /** Nombre de la contraparte: la empresa si soy cliente, el cliente si soy empresa. */
    val contraparte: String? = null,
)

class ReservacionesViewModel(
    private val repo: ReservacionesRepository,
    private val auth: AuthRepository,
    private val usuario: UsuarioActual,
) : ViewModel() {

    private val _estado = MutableStateFlow<EstadoCarga<List<FilaReservacion>>>(EstadoCarga.Cargando)
    val estado: StateFlow<EstadoCarga<List<FilaReservacion>>> = _estado.asStateFlow()

    private val _filtro = MutableStateFlow(ACTIVAS)
    val filtroTexto: StateFlow<String> = _filtro.asStateFlow()

    private val _refrescando = MutableStateFlow(false)
    val refrescando: StateFlow<Boolean> = _refrescando.asStateFlow()

    /** Chips del handoff. */
    val filtrosDisponibles = listOf(ACTIVAS, "Pendientes", "Completadas", "Por cobrar")

    init {
        cargar()
    }

    fun refrescar() {
        _refrescando.value = true
        cargar()
    }

    fun cambiarFiltro(valor: String) {
        _filtro.value = valor
    }

    fun cargar() = viewModelScope.launch {
        if (!_refrescando.value) _estado.value = EstadoCarga.Cargando

        when (val r = repo.mias(usuario)) {
            is Resultado.Ok -> {
                val reservas = r.dato
                val ids = reservas.map { it.id }

                // Las dos consultas de apoyo se toleran fallando: son adornos
                // de la fila —las pastillas de expediente, el nombre de la
                // contraparte— no la información principal.
                val expedientes = repo.expedientesDe(ids)
                val nombres = if (usuario.esCliente) {
                    auth.nombresDe(reservas.mapNotNull { it.propietarioId })
                } else {
                    emptyMap()
                }

                _estado.value = EstadoCarga.Listo(
                    reservas.map { res ->
                        FilaReservacion(
                            reservacion = res,
                            expedientes = expedientes[res.id].orEmpty(),
                            contraparte = if (usuario.esCliente) {
                                nombres[res.propietarioId]
                            } else {
                                res.cliente
                            },
                        )
                    },
                )
            }
            is Resultado.Error -> _estado.value = EstadoCarga.Fallo(r.error.mensaje)
        }
        _refrescando.value = false
    }

    /**
     * Aplica el chip activo.
     *
     * "Por cobrar" no es un estado de la reservación sino del dinero: son las
     * completadas que todavía no se pagan. Se deriva igual que en la web, sin
     * un campo aparte que pueda quedar desfasado.
     */
    fun visibles(datos: List<FilaReservacion>): List<FilaReservacion> =
        when (_filtro.value) {
            ACTIVAS -> datos.filter { it.reservacion.estadoEnum == EstadoReserva.ACTIVA }
            "Pendientes" -> datos.filter {
                it.reservacion.estadoEnum in setOf(
                    EstadoReserva.PENDIENTE,
                    EstadoReserva.POR_APROBAR,
                    EstadoReserva.CANCELACION_SOLICITADA,
                )
            }
            "Completadas" -> datos.filter {
                it.reservacion.estadoEnum == EstadoReserva.COMPLETADA
            }
            "Por cobrar" -> datos.filter {
                it.reservacion.estadoCobro in setOf(EstadoCobro.POR_COBRAR, EstadoCobro.VENCIDO)
            }
            else -> datos
        }

    private companion object {
        const val ACTIVAS = "Activas"
    }
}
