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
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.add
import mx.portgo.app.core.Resultado
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.data.repository.FlotaRepository
import mx.portgo.app.data.repository.StorageRepository

/**
 * Alta y edición de una unidad desde el teléfono.
 *
 * El formulario va por pasos porque son ~30 campos: meterlos en una sola
 * pantalla obliga a un desplazamiento larguísimo y la gente abandona a la
 * mitad. Tres pasos con un objetivo claro cada uno se llenan de pie, en el
 * patio.
 */
class AltaCamionViewModel(
    private val flota: FlotaRepository,
    private val storage: StorageRepository,
    private val usuario: UsuarioActual,
) : ViewModel() {

    /** Documentos y fotos que se piden. La clave es también el nombre del archivo. */
    enum class Archivo(val clave: String, val etiqueta: String, val ayuda: String?) {
        TARJETA("imagen_tc", "Tarjeta de circulación", "Fotografíala completa y legible"),
        SEGURO("doc_seguro", "Póliza de seguro", null),
        PERMISO_SCT("doc_sct", "Permiso SCT", null),
        PELIGROSA("doc_permiso_peligrosa", "Permiso de materiales peligrosos", "Solo si la unidad los transporta"),
        FOTO_FRENTE("foto_frente", "Foto de frente", null),
        FOTO_LATERAL("foto_lateral", "Foto lateral", null),
        FOTO_TRASERA("foto_trasera", "Foto trasera", null),
        FOTO_PLACA("foto_placa", "Foto de la placa", null),
    }

    data class Formulario(
        // Paso 1 — identificación
        val numEconomico: String = "",
        val tipo: String = "",
        val placas: String = "",
        val tipoPlaca: String = "",
        val marca: String = "",
        val version: String = "",
        val modeloAnio: String = "",
        val color: String = "",
        val capacidad: String = "",
        val dimensiones: String = "",
        val precioDia: String = "",
        val numSerie: String = "",
        val numMotor: String = "",
        val combustible: String = "",
        val tiposCarga: Set<String> = emptySet(),

        // Paso 2 — documentos y vigencias
        val tarjetaCirculacion: String = "",
        val fechaExpedicionTc: String? = null,
        val venceTc: String? = null,
        val venceSeguro: String? = null,
        val vencePermisoSct: String? = null,
        val caat: String = "",
        val vigenciaCaat: String? = null,
        val venceVerificacion: String? = null,
        val vencePeligrosa: String? = null,
    ) {
        /** Lo mínimo sin lo cual la unidad no sirve para ofertar. */
        val identificacionCompleta: Boolean
            get() = numEconomico.isNotBlank() && tipo.isNotBlank()
    }

    private val _form = MutableStateFlow(Formulario())
    val form: StateFlow<Formulario> = _form.asStateFlow()

    /** Archivos elegidos y todavía sin subir. */
    private val _archivos = MutableStateFlow<Map<Archivo, Uri>>(emptyMap())
    val archivos: StateFlow<Map<Archivo, Uri>> = _archivos.asStateFlow()

    private val _guardando = MutableStateFlow(false)
    val guardando: StateFlow<Boolean> = _guardando.asStateFlow()

    /** Qué se está subiendo ahora, para que la espera no sea una rueda muda. */
    private val _progreso = MutableStateFlow<String?>(null)
    val progreso: StateFlow<String?> = _progreso.asStateFlow()

    private val _avisos = MutableSharedFlow<String>()
    val avisos: SharedFlow<String> = _avisos.asSharedFlow()

    private var editandoId: String? = null

    fun actualizar(bloque: (Formulario) -> Formulario) = _form.update(bloque)

    fun adjuntar(archivo: Archivo, uri: Uri) {
        _archivos.update { it + (archivo to uri) }
    }

    fun quitar(archivo: Archivo) {
        _archivos.update { it - archivo }
    }

    fun alternarTipoCarga(valor: String) {
        _form.update {
            it.copy(
                tiposCarga = if (valor in it.tiposCarga) it.tiposCarga - valor
                else it.tiposCarga + valor,
            )
        }
    }

    /**
     * Sube los archivos y guarda.
     *
     * Los archivos van primero y de uno en uno, informando cuál: subir ocho
     * fotos por la red de un puerto puede tardar, y una rueda girando sin
     * explicación hace que la gente cierre la app creyendo que se colgó.
     *
     * Si una subida falla, no se guarda nada. Es preferible dejar un archivo
     * huérfano en Storage a registrar una unidad con la mitad de sus papeles.
     */
    fun guardar(onListo: () -> Unit) = viewModelScope.launch {
        val f = _form.value
        if (!f.identificacionCompleta) {
            _avisos.emit("Falta el número económico y el tipo de unidad.")
            return@launch
        }
        if (_guardando.value) return@launch
        _guardando.value = true

        val subidos = mutableMapOf<String, String>()
        val fotos = mutableListOf<String>()

        for ((archivo, uri) in _archivos.value) {
            _progreso.value = "Subiendo ${archivo.etiqueta.lowercase()}…"
            when (
                val r = storage.subirArchivoUnidad(
                    miId = usuario.id,
                    unidadId = f.numEconomico.trim(),
                    etiqueta = archivo.clave,
                    uri = uri,
                )
            ) {
                is Resultado.Ok ->
                    // Las cuatro fotos de la unidad viajan juntas en `archivos`;
                    // los documentos van cada uno en su columna.
                    if (archivo.clave.startsWith("foto_")) fotos += r.dato
                    else subidos[archivo.clave] = r.dato

                is Resultado.Error -> {
                    _avisos.emit("No se pudo subir ${archivo.etiqueta}: ${r.error.mensaje}")
                    _guardando.value = false
                    _progreso.value = null
                    return@launch
                }
            }
        }

        _progreso.value = "Guardando la unidad…"
        when (val r = flota.guardarCamion(construirPayload(subidos, fotos), editandoId)) {
            is Resultado.Ok -> {
                _avisos.emit(
                    if (editandoId == null) "Unidad registrada. Queda pendiente de aprobación."
                    else "Unidad actualizada. Vuelve a revisión.",
                )
                onListo()
            }
            is Resultado.Error -> _avisos.emit(r.error.mensaje)
        }
        _guardando.value = false
        _progreso.value = null
    }

    private fun construirPayload(
        subidos: Map<String, String>,
        fotos: List<String>,
    ): JsonObject {
        val f = _form.value
        return buildJsonObject {
            put("id", f.numEconomico.trim())
            put("num_economico", f.numEconomico.trim())
            put("tipo", f.tipo)
            put("placas", f.placas)
            put("tipo_placa", f.tipoPlaca)
            put("marca", f.marca)
            put("version", f.version)
            put("modelo_anio", f.modeloAnio)
            put("color", f.color)
            put("capacidad", f.capacidad)
            put("dimensiones", f.dimensiones)
            put("precio_dia", f.precioDia)
            put("num_serie", f.numSerie)
            put("num_motor", f.numMotor)
            put("tipo_combustible", f.combustible)

            put("tarjeta_circulacion", f.tarjetaCirculacion)
            put("fecha_expedicion_tc", f.fechaExpedicionTc)
            put("fecha_vencimiento_tc", f.venceTc)
            put("fecha_vencimiento_seguro", f.venceSeguro)
            put("fecha_vencimiento_permiso_sct", f.vencePermisoSct)
            put("caat", f.caat)
            put("vigencia_caat", f.vigenciaCaat)
            put("fecha_vencimiento_verificacion", f.venceVerificacion)
            put("fecha_vencimiento_permiso_peligrosa", f.vencePeligrosa)

            subidos.forEach { (clave, ruta) -> put(clave, ruta) }

            if (f.tiposCarga.isNotEmpty()) {
                putJsonArray("tipo_carga") { f.tiposCarga.forEach { add(it) } }
            }
            if (fotos.isNotEmpty()) {
                putJsonArray("archivos") { fotos.forEach { add(it) } }
            }
        }
    }

    companion object {
        /** Se ofrecen los mismos tipos que el catálogo de unidades. */
        val TIPOS_CARGA = listOf(
            "General", "Refrigerada", "Peligrosa", "Contenedor",
            "Granel", "Sobredimensionada",
        )
        val TIPOS_PLACA = listOf("Federal", "Estatal", "Particular")
        val COMBUSTIBLES = listOf("Diésel", "Gasolina", "Gas LP", "Eléctrico")
    }
}
