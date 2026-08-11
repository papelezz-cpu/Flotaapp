package mx.portgo.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import mx.portgo.app.core.Fmt
import mx.portgo.app.core.Resultado
import mx.portgo.app.core.intentar
import mx.portgo.app.data.model.Catalogos
import mx.portgo.app.data.model.OpcionCatalogo
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.data.repository.PedidosRepository

/**
 * Formulario de nueva solicitud.
 *
 * La solicitud se arma desde la CARGA, no desde el camión: el cliente describe
 * lo que va a mover y el sistema propone la unidad. Antes tenía que saber qué
 * es un "Full porta contenedor 40/20", que es conocimiento de transportista,
 * no de quien manda mercancía.
 *
 * La recomendación la calcula el servidor (`recomendar_unidad`), no esta app.
 * Es la regla que decide qué empresas reciben el aviso y quién puede ofertar;
 * tenerla escrita en Kotlin además de en JS garantiza que un día diverjan y el
 * mismo embarque proponga cosas distintas según por dónde se capture.
 */
@OptIn(FlowPreview::class)
class NuevaSolicitudViewModel(
    private val repo: PedidosRepository,
    private val supabase: SupabaseClient,
    private val usuario: UsuarioActual,
) : ViewModel() {

    @Serializable
    private data class Recomendacion(
        @SerialName("tipo") val tipo: String? = null,
        @SerialName("razon") val razon: String? = null,
    )

    data class Formulario(
        /** Valor del catálogo `categoria_carga`, no un enum: la lista es remota. */
        val categoria: String = "General",
        /** Qué campos pide esta categoría, según el catálogo. */
        val campos: List<String> = listOf("peso", "tarimas", "refri"),
        val origen: String = "",
        val destino: String = "",
        val fechaArriboPuerto: String? = null,
        val fechaIni: String = Fmt.hoy(),
        val fechaFin: String? = null,
        val pesoTon: String = "",
        val numTarimas: String = "",
        val numBultos: String = "",
        val refrigerado: Boolean = false,
        val tempMin: String = "",
        val tempMax: String = "",
        val numContenedores: String = "",
        val contenedor1Tipo: String = "",
        val largoM: String = "",
        val anchoM: String = "",
        val altoM: String = "",
        val hazmatClase: String = "",
        val hazmatUn: String = "",
        val entraAPuerto: Boolean = false,
        val presupuesto: String = "",
        val plazoPago: String = "",
        val descripcion: String = "",
        /** Si el cliente cambió la unidad a mano, se respeta sobre la sugerida. */
        val unidadManual: String? = null,
    ) {
        val peso: Double? get() = pesoTon.toDoubleOrNull()
        val tarimas: Int? get() = numTarimas.toIntOrNull()
        val contenedores: Int? get() = numContenedores.toIntOrNull()
        val alto: Double? get() = altoM.toDoubleOrNull()

        // Qué campos pide la categoría ya no se decide aquí: viene en
        // `meta.campos` del catálogo. Antes esta regla estaba escrita dos veces
        // —en NP_CARGA de js/pedidos.js y aquí— y cambiarla obligaba a publicar
        // la app. Ahora es un UPDATE en `catalogos`.
        val pidePeso: Boolean get() = "peso" in campos
        val pideTarimas: Boolean get() = "tarimas" in campos
        val pideBultos: Boolean get() = "bultos" in campos
        val pideRefri: Boolean get() = "refri" in campos
        val pideContenedores: Boolean get() = "contenedores" in campos
        val pideDimensiones: Boolean get() = "dim" in campos
        val pideHazmat: Boolean get() = "hazmat" in campos
    }

    private val _form = MutableStateFlow(Formulario())
    val form: StateFlow<Formulario> = _form.asStateFlow()

    private val _unidadSugerida = MutableStateFlow<Pair<String?, String?>>(null to null)
    val unidadSugerida: StateFlow<Pair<String?, String?>> = _unidadSugerida.asStateFlow()

    private val _publicando = MutableStateFlow(false)
    val publicando: StateFlow<Boolean> = _publicando.asStateFlow()

    private val _avisos = MutableSharedFlow<String>()
    val avisos: SharedFlow<String> = _avisos.asSharedFlow()

    init {
        // Se recalcula al escribir, con un respiro para no llamar al servidor
        // en cada tecla mientras alguien teclea "12500".
        viewModelScope.launch {
            _form.drop(1).debounce(400).collect { recalcularUnidad(it) }
        }
    }

    fun actualizar(bloque: (Formulario) -> Formulario) {
        _form.update(bloque)
    }

    fun elegirCategoria(cat: OpcionCatalogo) {
        // Al cambiar de categoría se limpian los campos de la anterior: si no,
        // una solicitud "General" podría viajar con la clase HAZMAT que quedó
        // escrita antes.
        _form.update {
            it.copy(
                categoria = cat.valor,
                campos = cat.campos,
                numTarimas = "", numBultos = "", numContenedores = "", contenedor1Tipo = "",
                largoM = "", anchoM = "", altoM = "", hazmatClase = "", hazmatUn = "",
                refrigerado = false, tempMin = "", tempMax = "",
                unidadManual = null,
            )
        }
    }

    /**
     * Ajusta el formulario a los catálogos que llegaron del servidor.
     *
     * Hace falta porque el estado inicial usa el respaldo compilado: si el
     * catálogo remoto cambió qué campos pide "General", el formulario tiene
     * que enterarse sin que el usuario tenga que tocar la categoría.
     */
    fun sincronizarConCatalogos(catalogos: Catalogos) {
        val actual = catalogos.categoria(_form.value.categoria)
            ?: catalogos.categoriasCarga.firstOrNull()
            ?: return
        _form.update { it.copy(categoria = actual.valor, campos = actual.campos) }
    }

    fun elegirUnidadManual(tipo: String?) {
        _form.update { it.copy(unidadManual = tipo) }
    }

    private suspend fun recalcularUnidad(f: Formulario) {
        val r = intentar {
            supabase.postgrest.rpc(
                "recomendar_unidad",
                buildJsonObject {
                    put("p_categoria", f.categoria)
                    put("p_peso_ton", f.peso)
                    put("p_num_tarimas", f.tarimas)
                    put("p_num_contenedores", f.contenedores)
                    put("p_alto_m", f.alto)
                },
            ).decodeList<Recomendacion>().firstOrNull()
        }
        if (r is Resultado.Ok) {
            _unidadSugerida.value = (r.dato?.tipo to r.dato?.razon)
        }
        // Si falla, se queda la sugerencia anterior. No vale la pena molestar
        // con un error por una ayuda: el cliente puede elegir la unidad a mano.
    }

    val tipoFinal: String?
        get() = _form.value.unidadManual ?: _unidadSugerida.value.first

    fun puedePublicar(): Boolean {
        val f = _form.value
        return f.origen.isNotBlank() && f.destino.isNotBlank() &&
            f.fechaIni.isNotBlank() && tipoFinal != null && !_publicando.value
    }

    fun publicar(onListo: () -> Unit) = viewModelScope.launch {
        if (!puedePublicar()) {
            _avisos.emit("Completa la ruta, la fecha de carga y el tipo de unidad.")
            return@launch
        }
        _publicando.value = true

        when (val r = repo.crear(construirPayload())) {
            is Resultado.Ok -> {
                _avisos.emit("Solicitud enviada. Un administrador la revisará pronto.")
                onListo()
            }
            is Resultado.Error -> _avisos.emit(r.error.mensaje)
        }
        _publicando.value = false
    }

    /**
     * Arma el payload de `pedidos`.
     *
     * Escribe también las columnas heredadas (`carga_peligrosa`,
     * `temp_controlada`, `volumen_m3`, `tipo_contenedor`) porque hay pedidos
     * históricos y vistas de la web que las leen. Se derivan de los campos
     * nuevos, exactamente igual que en `crearPedido()`.
     */
    private fun construirPayload(): JsonObject {
        val f = _form.value
        val sugerida = _unidadSugerida.value.first

        return buildJsonObject {
            put("cliente_id", usuario.id)
            put("cliente_nombre", usuario.nombre)
            put("cliente_email", usuario.email)
            put("estado", "pendiente_revision")

            put("tipo_camion", tipoFinal)
            put("tipo_camion_sugerido", sugerida)
            put("categoria_carga", f.categoria)

            put("origen", f.origen.trim())
            put("destino", f.destino.trim())
            put("fecha_arribo_puerto", f.fechaArriboPuerto)
            put("fecha_ini", f.fechaIni)
            put("fecha_fin", f.fechaFin ?: f.fechaIni)

            put("peso_carga", f.peso)
            put("num_tarimas", f.tarimas)
            // 1 tarima ≈ 1.8 m³ (tarima mexicana de 1.2 × 1.0 m apilada a ~1.5 m).
            // Se guarda derivado para los reportes; la decisión se toma con las
            // tarimas, que es lo que la gente sí sabe cuántas trae.
            put("volumen_m3", f.tarimas?.let { Math.round(it * 1.8 * 10) / 10.0 })
            put("num_bultos", f.numBultos.toIntOrNull())

            put("refrigerado", f.refrigerado)
            put("temp_controlada", f.refrigerado)
            put("temp_min", f.tempMin.toDoubleOrNull())
            put("temp_max", f.tempMax.toDoubleOrNull())

            put("num_contenedores", f.contenedores)
            put("contenedor_1_tipo", f.contenedor1Tipo.ifBlank { null })
            put("tipo_contenedor", f.contenedor1Tipo.ifBlank { null })

            put("largo_m", f.largoM.toDoubleOrNull())
            put("ancho_m", f.anchoM.toDoubleOrNull())
            put("alto_m", f.alto)

            put("hazmat_clase", f.hazmatClase.ifBlank { null })
            put("hazmat_un", f.hazmatUn.ifBlank { null })
            // Se deriva de que la categoría pida datos de hazmat, no de su
            // nombre: así sigue funcionando si mañana la categoría se llama
            // distinto en el catálogo.
            put("carga_peligrosa", f.pideHazmat)

            put("entra_a_puerto", f.entraAPuerto)
            // El seguro y la factura se asumen: en el mercado mexicano son
            // estándar y preguntarlo cada vez era ruido.
            put("requiere_seguro", true)
            put("requiere_factura", true)

            put("precio_cliente", f.presupuesto.toDoubleOrNull())
            put("plazo_pago", f.plazoPago.ifBlank { null })
            put("descripcion", f.descripcion.trim().ifBlank { null })
        }
    }

    // Las listas de plazos de pago, tipos de contenedor y tipos de unidad ya no
    // viven aquí: vienen del catálogo (LocalCatalogos). Agregar "90 días" al
    // plazo de pago pasó de ser una versión en las tiendas a un INSERT.
}
