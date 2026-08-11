package mx.portgo.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import mx.portgo.app.core.Resultado
import mx.portgo.app.data.model.Notificacion
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.data.repository.NotificacionesRepository

/**
 * La campana. Vive a nivel del andamio, no de una pantalla, porque el contador
 * se ve desde todas y no tiene sentido abrir un canal de Realtime por pantalla.
 */
class NotificacionesViewModel(
    private val repo: NotificacionesRepository,
    private val usuario: UsuarioActual,
) : ViewModel() {

    private val _lista = MutableStateFlow<EstadoCarga<List<Notificacion>>>(EstadoCarga.Cargando)
    val lista: StateFlow<EstadoCarga<List<Notificacion>>> = _lista.asStateFlow()

    private val _noLeidas = MutableStateFlow(0)
    val noLeidas: StateFlow<Int> = _noLeidas.asStateFlow()

    init {
        cargar()
        escuchar()
    }

    fun cargar() = viewModelScope.launch {
        when (val r = repo.ultimas(usuario.id)) {
            is Resultado.Ok -> {
                _lista.value = EstadoCarga.Listo(r.dato)
                _noLeidas.value = r.dato.count { !it.leido }
            }
            is Resultado.Error -> _lista.value = EstadoCarga.Fallo(r.error.mensaje)
        }
    }

    /**
     * Suscripción a las notificaciones nuevas de este usuario.
     *
     * Es el único canal de Realtime permanente de la app. La web además escucha
     * siete tablas completas (`portgo-changes`), que en un teléfono sería
     * gastar batería para refrescar pantallas que casi nunca están visibles.
     */
    private fun escuchar() = viewModelScope.launch {
        repo.enVivo(usuario.id).collect { nueva ->
            _lista.update { actual ->
                val previas = (actual as? EstadoCarga.Listo)?.datos.orEmpty()
                if (previas.any { it.id == nueva.id }) actual
                else EstadoCarga.Listo((listOf(nueva) + previas).take(20))
            }
            if (!nueva.leido) _noLeidas.update { it + 1 }
        }
    }

    /**
     * Al abrir el panel se dan por vistas: se apaga el contador y se marcan en
     * segundo plano, pero la lista NO se redibuja — así el usuario todavía
     * distingue cuáles eran nuevas durante esta apertura. Mismo criterio que
     * `_marcarNotifsVistas()` en la web.
     */
    fun marcarTodasVistas() = viewModelScope.launch {
        if (_noLeidas.value == 0) return@launch
        _noLeidas.value = 0
        repo.marcarTodasLeidas(usuario.id)
    }

    fun marcarLeida(id: String) = viewModelScope.launch {
        _lista.update { actual ->
            val previas = (actual as? EstadoCarga.Listo)?.datos ?: return@update actual
            EstadoCarga.Listo(previas.map { if (it.id == id) it.copy(leido = true) else it })
        }
        _noLeidas.update { (it - 1).coerceAtLeast(0) }
        repo.marcarLeida(id)
    }
}
