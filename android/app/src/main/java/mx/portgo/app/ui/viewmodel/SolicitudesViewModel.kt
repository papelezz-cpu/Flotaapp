package mx.portgo.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import mx.portgo.app.core.Resultado
import mx.portgo.app.data.model.EstadoPedido
import mx.portgo.app.data.model.PedidoConOfertas
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.data.repository.PedidosRepository

/**
 * Lista de solicitudes.
 *
 * Las pestañas cambian por rol porque el trabajo es distinto: el cliente mira
 * las suyas, la empresa mira el mercado abierto y, aparte, aquellas donde ya
 * puso precio. Un solo listado mezclado obligaría a ambos a filtrar a mano lo
 * que casi siempre quieren ver.
 */
class SolicitudesViewModel(
    private val repo: PedidosRepository,
    private val usuario: UsuarioActual,
) : ViewModel() {

    enum class Pestana(val etiqueta: String) {
        /** Cliente: sus solicitudes. Empresa: el mercado abierto. */
        PRINCIPAL(""),

        /** Solo empresa: donde ya ofertó. */
        MIS_OFERTAS("Mis ofertas"),
    }

    private val _pestana = MutableStateFlow(Pestana.PRINCIPAL)
    val pestana: StateFlow<Pestana> = _pestana.asStateFlow()

    private val _filtro = MutableStateFlow<EstadoPedido?>(null)
    val filtro: StateFlow<EstadoPedido?> = _filtro.asStateFlow()

    private val _estado = MutableStateFlow<EstadoCarga<List<PedidoConOfertas>>>(EstadoCarga.Cargando)
    val estado: StateFlow<EstadoCarga<List<PedidoConOfertas>>> = _estado.asStateFlow()

    private val _refrescando = MutableStateFlow(false)
    val refrescando: StateFlow<Boolean> = _refrescando.asStateFlow()

    private var pagina = 0
    private var hayMas = true
    private val acumulado = mutableListOf<PedidoConOfertas>()

    val etiquetaPrincipal: String
        get() = if (usuario.esCliente) "Mis solicitudes" else "Disponibles"

    init {
        cargar()
    }

    fun cambiarPestana(nueva: Pestana) {
        if (_pestana.value == nueva) return
        _pestana.value = nueva
        cargar()
    }

    fun cambiarFiltro(estado: EstadoPedido?) {
        _filtro.value = if (_filtro.value == estado) null else estado
    }

    fun refrescar() {
        _refrescando.value = true
        cargar()
    }

    fun cargar() = viewModelScope.launch {
        pagina = 0
        hayMas = true
        acumulado.clear()
        if (!_refrescando.value) _estado.value = EstadoCarga.Cargando
        traerPagina()
        _refrescando.value = false
    }

    /** Se llama al llegar al final de la lista. */
    fun cargarMas() {
        if (!hayMas || _estado.value is EstadoCarga.Cargando) return
        viewModelScope.launch {
            pagina++
            traerPagina()
        }
    }

    private suspend fun traerPagina() {
        val resultado = when (_pestana.value) {
            Pestana.MIS_OFERTAS -> {
                hayMas = false // esta vista no pagina: son las ofertas propias
                repo.conMisOfertas(usuario.id)
            }
            Pestana.PRINCIPAL -> repo.listar(
                rol = usuario.rol,
                pagina = pagina,
                soloMias = usuario.esCliente,
                miId = usuario.id,
            )
        }

        when (resultado) {
            is Resultado.Ok -> {
                if (resultado.dato.isEmpty()) hayMas = false
                val nuevos = resultado.dato.filter { nuevo ->
                    acumulado.none { it.pedido.id == nuevo.pedido.id }
                }
                acumulado += nuevos
                _estado.value = EstadoCarga.Listo(acumulado.toList())
            }
            is Resultado.Error -> {
                // Si ya había datos en pantalla no se sustituyen por un error:
                // se conserva lo visible y el fallo se reporta aparte.
                if (acumulado.isEmpty()) {
                    _estado.value = EstadoCarga.Fallo(resultado.error.mensaje)
                }
            }
        }
    }

    /** Aplica el filtro de estado sobre lo ya cargado. */
    fun visibles(datos: List<PedidoConOfertas>): List<PedidoConOfertas> {
        val f = _filtro.value ?: return datos
        return datos.filter { it.pedido.estadoEnum == f }
    }

    /** Estados que tiene sentido ofrecer como filtro, según el rol. */
    val filtrosDisponibles: List<EstadoPedido>
        get() = if (usuario.esCliente) {
            listOf(
                EstadoPedido.PENDIENTE_REVISION,
                EstadoPedido.ABIERTO,
                EstadoPedido.EN_NEGOCIACION,
                EstadoPedido.PENDIENTE_ACUERDO,
                EstadoPedido.ACORDADO,
                EstadoPedido.FINALIZADO,
            )
        } else {
            listOf(EstadoPedido.ABIERTO, EstadoPedido.EN_NEGOCIACION)
        }
}
