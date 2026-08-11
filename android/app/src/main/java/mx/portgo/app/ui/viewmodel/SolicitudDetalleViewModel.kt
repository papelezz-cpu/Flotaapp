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
import mx.portgo.app.data.model.PedidoConOfertas
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.data.repository.FlotaRepository
import mx.portgo.app.data.repository.PedidosRepository

/**
 * Detalle de una solicitud: la ficha completa y la negociación.
 *
 * Todas las acciones van por RPC. Ninguna de ellas es un solo UPDATE — aceptar
 * una oferta mueve la oferta, el pedido y avisa a dos partes — y el servidor es
 * quien valida qué transición es legal. La app solo decide qué botones enseñar.
 */
class SolicitudDetalleViewModel(
    private val pedidos: PedidosRepository,
    private val flota: FlotaRepository,
    private val usuario: UsuarioActual,
    private val pedidoId: String,
) : ViewModel() {

    private val _estado = MutableStateFlow<EstadoCarga<PedidoConOfertas>>(EstadoCarga.Cargando)
    val estado: StateFlow<EstadoCarga<PedidoConOfertas>> = _estado.asStateFlow()

    private val _ocupado = MutableStateFlow(false)
    val ocupado: StateFlow<Boolean> = _ocupado.asStateFlow()

    private val _avisos = MutableSharedFlow<String>()
    val avisos: SharedFlow<String> = _avisos.asSharedFlow()

    /** Unidades y choferes disponibles, para el formulario de oferta. */
    private val _camiones = MutableStateFlow<List<Camion>>(emptyList())
    val camiones: StateFlow<List<Camion>> = _camiones.asStateFlow()

    private val _operadores = MutableStateFlow<List<Operador>>(emptyList())
    val operadores: StateFlow<List<Operador>> = _operadores.asStateFlow()

    init {
        cargar()
    }

    fun cargar() = viewModelScope.launch {
        when (val r = pedidos.detalle(pedidoId)) {
            is Resultado.Ok -> {
                val dato = r.dato
                if (dato == null) {
                    _estado.value = EstadoCarga.Fallo("Esta solicitud ya no está disponible.")
                } else {
                    _estado.value = EstadoCarga.Listo(dato)
                    if (usuario.esEmpresa) cargarFlotaOfertable(dato)
                }
            }
            is Resultado.Error -> _estado.value = EstadoCarga.Fallo(r.error.mensaje)
        }
    }

    /**
     * Solo se ofrecen unidades del tipo que pide la solicitud.
     *
     * La RPC `enviar_oferta` lo vuelve a verificar del lado del servidor; esto
     * es para no mostrarle a la empresa opciones que van a ser rechazadas.
     */
    private fun cargarFlotaOfertable(dato: PedidoConOfertas) = viewModelScope.launch {
        val tipo = dato.pedido.tipoCamion
        when (val r = flota.camionesOfertables(usuario.id, tipo)) {
            is Resultado.Ok -> _camiones.value = r.dato
            is Resultado.Error -> _avisos.emit(r.error.mensaje)
        }
        when (val r = flota.operadoresDisponibles(usuario.id)) {
            is Resultado.Ok -> _operadores.value = r.dato
            is Resultado.Error -> Unit // el chofer solo es obligatorio en camión
        }
    }

    // ── Acciones de la empresa ────────────────────────────────────────────

    fun enviarOferta(camionId: String, precio: Double, operadorId: String?, mensaje: String?) =
        ejecutar("Oferta enviada al cliente.") {
            val nombreOperador = _operadores.value.firstOrNull { it.id == operadorId }?.nombre
            pedidos.enviarOferta(
                pedidoId = pedidoId,
                camionId = camionId,
                precio = precio,
                operadorId = operadorId,
                operadorNombre = nombreOperador,
                mensaje = mensaje,
            )
        }

    fun responderContraoferta(ofertaId: String, aceptar: Boolean) =
        ejecutar(if (aceptar) "Contraoferta aceptada." else "Contraoferta rechazada.") {
            pedidos.responderContraoferta(ofertaId, aceptar)
        }

    // ── Acciones del cliente ──────────────────────────────────────────────

    fun aceptarOferta(ofertaId: String) =
        ejecutar("Oferta aceptada. Un administrador aprobará el acuerdo.") {
            pedidos.responderOferta(ofertaId, PedidosRepository.AccionOferta.ACEPTAR)
        }

    fun contraofertar(ofertaId: String, precio: Double) =
        ejecutar("Contraoferta enviada.") {
            pedidos.responderOferta(
                ofertaId, PedidosRepository.AccionOferta.CONTRAOFERTAR, contraPrecio = precio,
            )
        }

    fun rechazarOferta(ofertaId: String, nota: String?) =
        ejecutar("Oferta rechazada.") {
            pedidos.responderOferta(ofertaId, PedidosRepository.AccionOferta.RECHAZAR, nota = nota)
        }

    fun cancelarSolicitud() =
        ejecutar("Solicitud cancelada.") {
            pedidos.cancelarSolicitud(pedidoId)
        }

    /**
     * Envoltura común: bloquea la UI, ejecuta, avisa y recarga.
     *
     * Siempre recarga desde el servidor en vez de aplicar el cambio localmente.
     * Estas acciones mueven varias filas a la vez (la oferta, el pedido, las
     * otras ofertas), y adivinar el resultado en el cliente es justo lo que
     * produce pantallas que dicen algo distinto a la base.
     */
    private fun ejecutar(mensajeExito: String, bloque: suspend () -> Resultado<*>) =
        viewModelScope.launch {
            if (_ocupado.value) return@launch
            _ocupado.value = true
            when (val r = bloque()) {
                is Resultado.Ok -> {
                    _avisos.emit(mensajeExito)
                    cargar()
                }
                is Resultado.Error -> _avisos.emit(r.error.mensaje)
            }
            _ocupado.value = false
        }
}
