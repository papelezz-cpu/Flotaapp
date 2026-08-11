package mx.portgo.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import mx.portgo.app.core.Resultado
import mx.portgo.app.data.model.EstadoReserva
import mx.portgo.app.data.model.Expediente
import mx.portgo.app.data.model.Reservacion
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.data.repository.ChatRepository
import mx.portgo.app.data.repository.ReservacionesRepository

/** Fila de la lista, con lo que hace falta para pintarla sin más consultas. */
data class FilaReservacion(
    val reservacion: Reservacion,
    val mensajesSinLeer: Int = 0,
    val expedientes: List<Expediente> = emptyList(),
)

class ReservacionesViewModel(
    private val repo: ReservacionesRepository,
    private val chat: ChatRepository,
    private val usuario: UsuarioActual,
) : ViewModel() {

    private val _estado = MutableStateFlow<EstadoCarga<List<FilaReservacion>>>(EstadoCarga.Cargando)
    val estado: StateFlow<EstadoCarga<List<FilaReservacion>>> = _estado.asStateFlow()

    private val _filtro = MutableStateFlow<EstadoReserva?>(null)
    val filtro: StateFlow<EstadoReserva?> = _filtro.asStateFlow()

    private val _refrescando = MutableStateFlow(false)
    val refrescando: StateFlow<Boolean> = _refrescando.asStateFlow()

    init {
        cargar()
    }

    fun refrescar() {
        _refrescando.value = true
        cargar()
    }

    fun cambiarFiltro(estado: EstadoReserva?) {
        _filtro.value = if (_filtro.value == estado) null else estado
    }

    fun cargar() = viewModelScope.launch {
        if (!_refrescando.value) _estado.value = EstadoCarga.Cargando

        when (val r = repo.mias(usuario)) {
            is Resultado.Ok -> {
                val reservas = r.dato
                val ids = reservas.map { it.id }

                // Las dos consultas de apoyo se toleran fallando: son adornos
                // de la fila (el globito de chat y las pastillas de expediente),
                // no la información principal. Que el badge no cargue no debe
                // impedir ver los servicios.
                val sinLeer = chat.noLeidosPorReserva(usuario.id, ids)
                val expedientes = repo.expedientesDe(ids)

                _estado.value = EstadoCarga.Listo(
                    reservas.map { res ->
                        FilaReservacion(
                            reservacion = res,
                            mensajesSinLeer = sinLeer[res.id] ?: 0,
                            expedientes = expedientes[res.id].orEmpty(),
                        )
                    },
                )
            }
            is Resultado.Error -> _estado.value = EstadoCarga.Fallo(r.error.mensaje)
        }
        _refrescando.value = false
    }

    fun visibles(datos: List<FilaReservacion>): List<FilaReservacion> {
        val f = _filtro.value ?: return datos
        return datos.filter { it.reservacion.estadoEnum == f }
    }

    val filtros = listOf(
        EstadoReserva.ACTIVA,
        EstadoReserva.POR_APROBAR,
        EstadoReserva.CANCELACION_SOLICITADA,
        EstadoReserva.COMPLETADA,
        EstadoReserva.CANCELADA,
    )
}
