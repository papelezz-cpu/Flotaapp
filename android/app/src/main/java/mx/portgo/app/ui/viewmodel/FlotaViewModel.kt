package mx.portgo.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import mx.portgo.app.core.Resultado
import mx.portgo.app.data.model.Camion
import mx.portgo.app.data.model.Operador
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.data.repository.FlotaRepository

class FlotaViewModel(
    private val repo: FlotaRepository,
    private val usuario: UsuarioActual,
) : ViewModel() {

    private val _camiones = MutableStateFlow<EstadoCarga<List<Camion>>>(EstadoCarga.Cargando)
    val camiones: StateFlow<EstadoCarga<List<Camion>>> = _camiones.asStateFlow()

    private val _operadores = MutableStateFlow<EstadoCarga<List<Operador>>>(EstadoCarga.Cargando)
    val operadores: StateFlow<EstadoCarga<List<Operador>>> = _operadores.asStateFlow()

    /** Documentos por vencer en 30 días, para el aviso de arriba de la lista. */
    private val _vigencias = MutableStateFlow<List<Pair<Camion, Pair<String, Long>>>>(emptyList())
    val vigencias: StateFlow<List<Pair<Camion, Pair<String, Long>>>> = _vigencias.asStateFlow()

    private val _refrescando = MutableStateFlow(false)
    val refrescando: StateFlow<Boolean> = _refrescando.asStateFlow()

    private val _avisos = MutableSharedFlow<String>()
    val avisos: SharedFlow<String> = _avisos.asSharedFlow()

    init {
        cargar()
    }

    fun refrescar() {
        _refrescando.value = true
        cargar()
    }

    fun cargar() = viewModelScope.launch {
        when (val r = repo.camiones(usuario.id)) {
            is Resultado.Ok -> _camiones.value = EstadoCarga.Listo(r.dato)
            is Resultado.Error -> _camiones.value = EstadoCarga.Fallo(r.error.mensaje)
        }
        when (val r = repo.operadores(usuario.id)) {
            is Resultado.Ok -> _operadores.value = EstadoCarga.Listo(r.dato)
            is Resultado.Error -> _operadores.value = EstadoCarga.Fallo(r.error.mensaje)
        }
        _vigencias.value = repo.vigenciasPorVencer(usuario.id)
        _refrescando.value = false
    }

    fun cambiarDisponibilidad(camionId: String, disponible: Boolean) = viewModelScope.launch {
        when (val r = repo.marcarDisponibilidad(camionId, disponible)) {
            is Resultado.Ok -> {
                _avisos.emit(
                    if (disponible) "Unidad marcada como disponible."
                    else "Unidad fuera de servicio.",
                )
                cargar()
            }
            is Resultado.Error -> _avisos.emit(r.error.mensaje)
        }
    }
}
