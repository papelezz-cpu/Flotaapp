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
 * El diseño sustituyó las pestañas por chips de filtro. El cambio es a mejor:
 * las pestañas separaban en dos listas ("disponibles" y "mis ofertas") lo que
 * en realidad es una sola con distinto recorte, y obligaban a la empresa a
 * mirar en dos sitios para saber en qué anda.
 *
 * Los chips son distintos por rol porque el recorte útil lo es: el cliente
 * sigue el ciclo de vida de lo que publicó; la empresa distingue lo que puede
 * tomar de lo que ya tomó.
 */
class SolicitudesViewModel(
    private val repo: PedidosRepository,
    private val usuario: UsuarioActual,
) : ViewModel() {

    private val _filtro = MutableStateFlow(TODOS)
    val filtroTexto: StateFlow<String> = _filtro.asStateFlow()

    private val _estado = MutableStateFlow<EstadoCarga<List<PedidoConOfertas>>>(EstadoCarga.Cargando)
    val estado: StateFlow<EstadoCarga<List<PedidoConOfertas>>> = _estado.asStateFlow()

    private val _refrescando = MutableStateFlow(false)
    val refrescando: StateFlow<Boolean> = _refrescando.asStateFlow()

    private var pagina = 0
    private var hayMas = true
    private val acumulado = mutableListOf<PedidoConOfertas>()

    /** Chips que se ofrecen, según el rol. */
    val filtrosDisponibles: List<String>
        get() = if (usuario.esCliente) {
            listOf(TODOS, "Activos", "En revisión", "Acuerdos")
        } else {
            listOf(TODOS, "Para ofertar", "Mis ofertas")
        }

    init {
        cargar()
    }

    fun cambiarFiltro(valor: String) {
        if (_filtro.value == valor) return
        _filtro.value = valor
        // "Mis ofertas" se sirve de otra consulta, así que recarga; el resto
        // filtra sobre lo que ya está en memoria.
        if (!usuario.esCliente) cargar()
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

    fun cargarMas() {
        if (!hayMas || _estado.value is EstadoCarga.Cargando) return
        viewModelScope.launch {
            pagina++
            traerPagina()
        }
    }

    private suspend fun traerPagina() {
        val resultado = if (!usuario.esCliente && _filtro.value == "Mis ofertas") {
            hayMas = false // esta vista no pagina: son las ofertas propias
            repo.conMisOfertas(usuario.id)
        } else {
            repo.listar(
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

    /** Aplica el chip activo sobre lo ya cargado. */
    fun visibles(datos: List<PedidoConOfertas>): List<PedidoConOfertas> =
        when (_filtro.value) {
            "Activos" -> datos.filter { it.pedido.estadoEnum.admiteOfertas }
            "En revisión" -> datos.filter {
                it.pedido.estadoEnum in setOf(
                    EstadoPedido.PENDIENTE_REVISION,
                    EstadoPedido.PENDIENTE_ACUERDO,
                )
            }
            "Acuerdos" -> datos.filter {
                it.pedido.estadoEnum in setOf(EstadoPedido.ACORDADO, EstadoPedido.FINALIZADO)
            }
            "Para ofertar" -> datos.filter { item ->
                item.pedido.estadoEnum.admiteOfertas &&
                    item.ofertas.none { it.adminId == usuario.id && it.estadoEnum.esViva }
            }
            else -> datos
        }

    private companion object {
        const val TODOS = "Todos"
    }
}
