package mx.portgo.app.ui.viewmodel

import android.content.Context
import android.content.Intent
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
import mx.portgo.app.data.model.ExpedienteDocumento
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.data.repository.ReservacionesRepository
import mx.portgo.app.data.repository.StorageRepository

class ExpedienteViewModel(
    private val repo: ReservacionesRepository,
    private val storage: StorageRepository,
    private val usuario: UsuarioActual,
    private val reservaId: String,
    private val etapaClave: String,
) : ViewModel() {

    private val _estado = MutableStateFlow<EstadoCarga<List<ExpedienteDocumento>>>(EstadoCarga.Cargando)
    val estado: StateFlow<EstadoCarga<List<ExpedienteDocumento>>> = _estado.asStateFlow()

    private val _ocupado = MutableStateFlow(false)
    val ocupado: StateFlow<Boolean> = _ocupado.asStateFlow()

    private val _avisos = MutableSharedFlow<String>()
    val avisos: SharedFlow<String> = _avisos.asSharedFlow()

    /** URL firmada que hay que abrir; la pantalla la consume y la limpia. */
    private val _abrirUrl = MutableSharedFlow<String>()
    val abrirUrl: SharedFlow<String> = _abrirUrl.asSharedFlow()

    private var expedienteId: String? = null

    init {
        cargar()
    }

    fun cargar() = viewModelScope.launch {
        val etapa = EtapaExpediente.de(etapaClave)
        if (etapa == null) {
            _estado.value = EstadoCarga.Fallo("Etapa de expediente no reconocida.")
            return@launch
        }

        val exp = repo.expedientesDe(listOf(reservaId))[reservaId]
            ?.firstOrNull { it.etapa == etapaClave }

        if (exp == null) {
            _estado.value = EstadoCarga.Fallo(
                "Todavía no se ha abierto este expediente para el servicio.",
            )
            return@launch
        }
        expedienteId = exp.id

        when (val r = repo.documentosDe(exp.id)) {
            is Resultado.Ok -> _estado.value = EstadoCarga.Listo(r.dato)
            is Resultado.Error -> _estado.value = EstadoCarga.Fallo(r.error.mensaje)
        }
    }

    /** El cliente adjunta el archivo de un renglón del checklist. */
    fun adjuntar(documentoId: String, uri: Uri) = viewModelScope.launch {
        val expId = expedienteId ?: return@launch
        if (_ocupado.value) return@launch
        _ocupado.value = true

        when (val subida = storage.subirDocumentoViaje(expId, uri)) {
            is Resultado.Ok -> {
                val (ruta, nombre) = subida.dato
                when (val r = repo.adjuntarDocumento(documentoId, ruta, nombre)) {
                    is Resultado.Ok -> {
                        _avisos.emit("Documento subido.")
                        cargar()
                    }
                    is Resultado.Error -> _avisos.emit(r.error.mensaje)
                }
            }
            is Resultado.Error -> _avisos.emit(subida.error.mensaje)
        }
        _ocupado.value = false
    }

    /** El transportista da por bueno o devuelve un documento. */
    fun dictaminar(documentoId: String, aceptado: Boolean, nota: String?) = viewModelScope.launch {
        if (_ocupado.value) return@launch
        _ocupado.value = true
        when (val r = repo.dictaminarDocumento(documentoId, aceptado, nota)) {
            is Resultado.Ok -> {
                _avisos.emit(if (aceptado) "Documento aceptado." else "Documento devuelto al cliente.")
                cargar()
            }
            is Resultado.Error -> _avisos.emit(r.error.mensaje)
        }
        _ocupado.value = false
    }

    /**
     * Firma la ruta y pide abrirla.
     *
     * El bucket `documentos-viaje` es privado: un pedimento y una factura
     * comercial son datos fiscales sensibles, así que nunca hay una URL
     * permanente que alguien pueda reenviar.
     */
    fun abrirArchivo(doc: ExpedienteDocumento) = viewModelScope.launch {
        val ruta = doc.archivoPath ?: return@launch
        val url = storage.urlFirmada(ruta, StorageRepository.BUCKET_VIAJE)
        if (url == null) {
            _avisos.emit("No se pudo abrir el archivo.")
        } else {
            _abrirUrl.emit(url)
        }
    }
}

/** Abre una URL en el visor del sistema. */
fun abrirEnNavegador(contexto: Context, url: String) {
    contexto.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
}
