package mx.portgo.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import mx.portgo.app.core.Resultado
import mx.portgo.app.data.model.Mensaje
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.data.repository.ChatRepository

class ChatViewModel(
    private val repo: ChatRepository,
    private val usuario: UsuarioActual,
    esReserva: Boolean,
    contextoId: String,
    otroUsuarioId: String,
) : ViewModel() {

    private val hilo = ChatRepository.Hilo(
        reservaId = if (esReserva) contextoId else null,
        pedidoId = if (esReserva) null else contextoId,
        participantes = listOf(usuario.id, otroUsuarioId).distinct(),
    )

    private val _estado = MutableStateFlow<EstadoCarga<List<Mensaje>>>(EstadoCarga.Cargando)
    val estado: StateFlow<EstadoCarga<List<Mensaje>>> = _estado.asStateFlow()

    private val _enviando = MutableStateFlow(false)
    val enviando: StateFlow<Boolean> = _enviando.asStateFlow()

    private val _avisos = MutableSharedFlow<String>()
    val avisos: SharedFlow<String> = _avisos.asSharedFlow()

    val miId: String get() = usuario.id

    init {
        cargar()
        escuchar()
    }

    fun cargar() = viewModelScope.launch {
        when (val r = repo.historial(hilo)) {
            is Resultado.Ok -> {
                _estado.value = EstadoCarga.Listo(r.dato)
                // Los del otro se dan por leídos al abrir el hilo.
                repo.marcarLeidos(
                    r.dato.filter { !it.esMio(usuario.id) && !it.leido }.map { it.id },
                )
            }
            is Resultado.Error -> _estado.value = EstadoCarga.Fallo(r.error.mensaje)
        }
    }

    private fun escuchar() = viewModelScope.launch {
        repo.mensajesEnVivo(hilo).collect { nuevo ->
            _estado.update { actual ->
                val previos = (actual as? EstadoCarga.Listo)?.datos.orEmpty()
                // El propio mensaje ya se agregó al enviarlo; Realtime lo
                // devuelve otra vez y sin esto aparecería duplicado.
                if (previos.any { it.id == nuevo.id }) actual
                else EstadoCarga.Listo(previos + nuevo)
            }
            if (!nuevo.esMio(usuario.id)) repo.marcarLeidos(listOf(nuevo.id))
        }
    }

    /**
     * Envía un mensaje.
     *
     * El candado anti-desintermediación (no compartir teléfonos) lo aplica la
     * RPC `enviar_mensaje` en el servidor, no esta app. Si viniera solo del
     * cliente, bastaría con no implementarlo aquí para saltárselo — que es
     * exactamente la situación de la web hoy.
     */
    fun enviar(texto: String) = viewModelScope.launch {
        val limpio = texto.trim()
        if (limpio.isEmpty() || _enviando.value) return@launch
        _enviando.value = true

        when (val r = repo.enviar(hilo, limpio)) {
            is Resultado.Ok -> Unit // llega por Realtime
            is Resultado.Error -> _avisos.emit(r.error.mensaje)
        }
        _enviando.value = false
    }
}
