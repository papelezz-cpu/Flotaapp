package mx.portgo.app.ui.viewmodel

import android.net.Uri
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
import mx.portgo.app.data.model.EtapaExpediente
import mx.portgo.app.data.model.Expediente
import mx.portgo.app.data.model.Reservacion
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.data.repository.AuthRepository
import mx.portgo.app.data.repository.AvisosRepository
import mx.portgo.app.data.repository.ReservacionesRepository
import mx.portgo.app.data.repository.StorageRepository

class ReservacionDetalleViewModel(
    private val repo: ReservacionesRepository,
    private val storage: StorageRepository,
    private val auth: AuthRepository,
    private val avisosRepo: AvisosRepository,
    private val usuario: UsuarioActual,
    private val reservaId: String,
) : ViewModel() {

    data class Detalle(
        val reservacion: Reservacion,
        val expedientes: List<Expediente> = emptyList(),
        val nombreContraparte: String? = null,
        /** URLs firmadas de mis evidencias y de las de la otra parte. */
        val misEvidenciasUrl: List<String?> = emptyList(),
        val evidenciasOtroUrl: List<String?> = emptyList(),
    )

    private val _estado = MutableStateFlow<EstadoCarga<Detalle>>(EstadoCarga.Cargando)
    val estado: StateFlow<EstadoCarga<Detalle>> = _estado.asStateFlow()

    private val _ocupado = MutableStateFlow(false)
    val ocupado: StateFlow<Boolean> = _ocupado.asStateFlow()

    private val _subiendo = MutableStateFlow(false)
    val subiendo: StateFlow<Boolean> = _subiendo.asStateFlow()

    private val _avisos = MutableSharedFlow<String>()
    val avisos: SharedFlow<String> = _avisos.asSharedFlow()

    val soyCliente: Boolean get() = usuario.esCliente

    init {
        cargar()
    }

    fun cargar() = viewModelScope.launch {
        when (val r = repo.detalle(reservaId)) {
            is Resultado.Ok -> {
                val res = r.dato
                if (res == null) {
                    _estado.value = EstadoCarga.Fallo("Este servicio ya no está disponible.")
                    return@launch
                }

                val contraparteId = if (soyCliente) res.propietarioId else res.clienteUserId
                val nombre = if (soyCliente) {
                    contraparteId?.let { auth.nombresDe(listOf(it))[it] }
                } else {
                    res.cliente
                }

                // Las URLs se firman aquí y no al pintar: una hora de vigencia
                // alcanza de sobra para la pantalla, y evita disparar una firma
                // por cada recomposición.
                val mias = storage.urlsFirmadas(res.misEvidencias(soyCliente))
                val otras = storage.urlsFirmadas(res.evidenciasDelOtro(soyCliente))

                _estado.value = EstadoCarga.Listo(
                    Detalle(
                        reservacion = res,
                        expedientes = repo.expedientesDe(listOf(reservaId))[reservaId].orEmpty(),
                        nombreContraparte = nombre,
                        misEvidenciasUrl = mias,
                        evidenciasOtroUrl = otras,
                    ),
                )
            }
            is Resultado.Error -> _estado.value = EstadoCarga.Fallo(r.error.mensaje)
        }
    }

    val contraparteId: String?
        get() = (_estado.value as? EstadoCarga.Listo)?.datos?.reservacion?.let {
            if (soyCliente) it.propietarioId else it.clienteUserId
        }

    // ── Acciones ──────────────────────────────────────────────────────────

    fun avanzarTracking() = ejecutar {
        when (val r = repo.avanzarTracking(reservaId)) {
            is Resultado.Ok -> {
                _avisos.emit("Seguimiento actualizado: ${r.dato}")
                Resultado.Ok(Unit)
            }
            is Resultado.Error -> r
        }
    }

    /**
     * Sube las evidencias y luego registra las rutas.
     *
     * Los dos pasos están separados a propósito: subir cinco fotos por la red
     * de un puerto puede tardar, y no conviene tener abierta una transacción de
     * base de datos todo ese rato. Si alguna subida falla, no se registra nada
     * — mejor que quede un archivo huérfano en Storage a que la reserva pase a
     * revisión con la mitad de la evidencia.
     */
    fun subirEvidencias(uris: List<Uri>) = viewModelScope.launch {
        if (uris.isEmpty() || _subiendo.value) return@launch
        _subiendo.value = true

        val rutas = mutableListOf<String>()
        for (uri in uris) {
            when (val r = storage.subirEvidencia(usuario.id, reservaId, uri)) {
                is Resultado.Ok -> rutas += r.dato
                is Resultado.Error -> {
                    _avisos.emit("No se pudo subir un archivo: ${r.error.mensaje}")
                    _subiendo.value = false
                    return@launch
                }
            }
        }

        when (val r = repo.registrarEvidencias(reservaId, rutas)) {
            is Resultado.Ok -> {
                _avisos.emit("Evidencias registradas.")
                cargar()
            }
            is Resultado.Error -> _avisos.emit(r.error.mensaje)
        }
        _subiendo.value = false
    }

    fun cancelar(motivo: String?) = ejecutar("Reserva cancelada. La solicitud se reabrió.") {
        repo.cancelar(reservaId, motivo)
    }

    fun solicitarCancelacion(motivo: String, detalle: String?) =
        ejecutar("Solicitud enviada. Un administrador la revisará.") {
            repo.solicitarCancelacion(reservaId, motivo, detalle)
        }

    fun calificar(estrellas: Int, comentario: String?) =
        ejecutar("¡Gracias por calificar!") {
            repo.calificar(reservaId, estrellas, comentario)
        }

    fun abrirExpediente(etapa: EtapaExpediente) =
        ejecutar("Documentación solicitada al cliente.") {
            repo.abrirExpediente(reservaId, etapa)
        }

    // ── Avisos fijos, los que sustituyen al chat ─────────────────────────

    /** No nulo mientras el formulario de lugar/hora está abierto. */
    private val _viajeEnEdicion = MutableStateFlow<AvisosRepository.DetallesViaje?>(null)
    val viajeEnEdicion: StateFlow<AvisosRepository.DetallesViaje?> = _viajeEnEdicion.asStateFlow()

    // Se consultan los detalles ANTES de abrir: el formulario tiene que nacer
    // con lo que ya está guardado, o al escribir solo la hora se perdería el
    // lugar.
    fun abrirActualizarViaje() = viewModelScope.launch {
        when (val r = avisosRepo.detallesViaje(reservaId)) {
            is Resultado.Ok -> _viajeEnEdicion.value = r.dato
            is Resultado.Error -> _avisos.emit(r.error.mensaje)
        }
    }

    fun cerrarActualizarViaje() {
        _viajeEnEdicion.value = null
    }

    fun solicitarDocumentosCarga() =
        ejecutar("Solicitud enviada al cliente.") {
            avisosRepo.solicitarDocumentosCarga(reservaId, usuario.nombre)
        }

    fun confirmarLugarHora() =
        ejecutar("Aviso enviado al cliente.") {
            avisosRepo.confirmarLugarHora(reservaId, usuario.nombre)
        }

    fun avisarRetraso(nota: String?) =
        ejecutar("Aviso de retraso enviado.") {
            avisosRepo.avisarRetraso(reservaId, nota)
        }

    fun actualizarLugarHora(lugar: String?, hora: String?) {
        _viajeEnEdicion.value = null
        ejecutar("Guardado. La empresa ya fue avisada.") {
            avisosRepo.actualizarLugarHora(reservaId, lugar, hora)
        }
    }

    fun reportarProblema(motivo: AvisosRepository.MotivoReporte, nota: String?) =
        ejecutar("Reporte enviado a la empresa y al administrador.") {
            avisosRepo.reportarProblema(reservaId, motivo, nota)
        }

    private fun ejecutar(mensajeExito: String? = null, bloque: suspend () -> Resultado<*>) =
        viewModelScope.launch {
            if (_ocupado.value) return@launch
            _ocupado.value = true
            when (val r = bloque()) {
                is Resultado.Ok -> {
                    mensajeExito?.let { _avisos.emit(it) }
                    cargar()
                }
                is Resultado.Error -> _avisos.emit(r.error.mensaje)
            }
            _ocupado.value = false
        }
}
