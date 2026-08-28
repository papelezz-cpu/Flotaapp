package mx.portgo.app.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import mx.portgo.app.core.Resultado
import mx.portgo.app.data.model.UsuarioActual
import mx.portgo.app.data.repository.AuthRepository
import mx.portgo.app.di.AppContainer

/**
 * Estado de sesión de toda la app.
 *
 * El flujo de arranque tiene un paso que no existe en la web: **Bloqueada**.
 * Como el refresh token persiste cifrado entre aperturas, hay un momento en
 * que la sesión es válida pero la app todavía no debe mostrar nada — hasta que
 * el dueño del teléfono se identifique con huella, rostro o PIN. Ese es el
 * trato que sustituye al `sessionStorage` de la web.
 */
class SesionViewModel(private val auth: AuthRepository) : ViewModel() {

    sealed interface Estado {
        /** Restaurando la sesión guardada. Dura lo que tarde el Keystore. */
        data object Cargando : Estado

        /** No hay sesión: hay que teclear correo y contraseña. */
        data class SinSesion(val mensaje: String? = null) : Estado

        /** Hay sesión válida, falta que el dueño del teléfono se identifique. */
        data class Bloqueada(val usuario: UsuarioActual) : Estado

        data class Dentro(val usuario: UsuarioActual) : Estado
    }

    private val _estado = MutableStateFlow<Estado>(Estado.Cargando)
    val estado: StateFlow<Estado> = _estado.asStateFlow()

    private val _ocupado = MutableStateFlow(false)
    val ocupado: StateFlow<Boolean> = _ocupado.asStateFlow()

    /**
     * El usuario llegó por el enlace del correo de recuperación y hay que
     * pedirle una contraseña nueva.
     *
     * Se alimenta de `sesionesExternas`, no del callback de `handleDeeplinks`:
     * el StateFlow de la sesión conserva su valor, así que da igual que el
     * intercambio del código termine antes de que la interfaz esté lista.
     */
    private val _recuperacion = MutableStateFlow(false)
    val recuperacion: StateFlow<Boolean> = _recuperacion.asStateFlow()

    val correoRecordado: String? get() = auth.correoRecordado
    var biometriaActiva: Boolean
        get() = auth.biometriaActiva
        set(value) { auth.biometriaActiva = value }

    init {
        restaurar()
        viewModelScope.launch {
            auth.sesionesExternas.collect { _recuperacion.value = true }
        }
    }

    /** La pantalla de contraseña nueva terminó (se guardó o se canceló). */
    fun cerrarRecuperacion() {
        _recuperacion.value = false
    }

    private fun restaurar() = viewModelScope.launch {
        when (val r = auth.restaurarSesion()) {
            is Resultado.Ok -> {
                val acceso = r.dato
                _estado.value = when (acceso) {
                    null -> Estado.SinSesion()
                    is AuthRepository.Acceso.Bloqueado -> Estado.SinSesion(acceso.motivo)
                    is AuthRepository.Acceso.Concedido ->
                        // Si el usuario no activó la biometría, entra directo.
                        // Sigue siendo mejor que la web: la sesión está cifrada
                        // en el Keystore, no en un almacén del navegador.
                        if (auth.biometriaActiva) Estado.Bloqueada(acceso.usuario)
                        else Estado.Dentro(acceso.usuario)
                }
            }
            // Sin red al arrancar no debe expulsar a nadie: se pide login, que
            // es lo único que se puede hacer sin conexión de todos modos.
            is Resultado.Error -> _estado.value = Estado.SinSesion()
        }
    }

    fun iniciarSesion(correo: String, contrasena: String, onError: (String) -> Unit) {
        if (_ocupado.value) return
        viewModelScope.launch {
            _ocupado.value = true
            when (val r = auth.iniciarSesion(correo, contrasena)) {
                is Resultado.Ok -> when (val acceso = r.dato) {
                    is AuthRepository.Acceso.Concedido -> _estado.value = Estado.Dentro(acceso.usuario)
                    is AuthRepository.Acceso.Bloqueado -> onError(acceso.motivo)
                }
                is Resultado.Error -> onError(
                    // GoTrue devuelve "Invalid login credentials", que no dice
                    // nada útil en español a quien se equivocó de contraseña.
                    if (r.error.mensaje.contains("credential", ignoreCase = true) ||
                        r.error.mensaje.contains("Invalid", ignoreCase = true)
                    ) "Correo o contraseña incorrectos."
                    else r.error.mensaje,
                )
            }
            _ocupado.value = false
        }
    }

    /** El gate biométrico salió bien. */
    fun desbloquear() {
        _estado.update { actual ->
            if (actual is Estado.Bloqueada) Estado.Dentro(actual.usuario) else actual
        }
    }

    /** El usuario canceló la biometría: se sale, no se entra a medias. */
    fun cancelarDesbloqueo() = cerrarSesion()

    fun cerrarSesion() = viewModelScope.launch {
        auth.cerrarSesion()
        _estado.value = Estado.SinSesion()
    }

    fun recuperarContrasena(correo: String, onResultado: (String) -> Unit) {
        viewModelScope.launch {
            when (val r = auth.recuperarContrasena(correo)) {
                is Resultado.Ok -> onResultado("Revisa tu correo para restablecer tu contraseña.")
                is Resultado.Error -> onResultado(r.error.mensaje)
            }
        }
    }

    /** Se llama cuando el deep link `portgo://auth` trajo una sesión de recuperación. */
    fun cambiarContrasena(nueva: String, onResultado: (Boolean, String) -> Unit) {
        viewModelScope.launch {
            _ocupado.value = true
            when (val r = auth.cambiarContrasena(nueva)) {
                is Resultado.Ok -> onResultado(true, "Contraseña actualizada.")
                is Resultado.Error -> onResultado(false, r.error.mensaje)
            }
            _ocupado.value = false
        }
    }

    companion object {
        fun factory(container: AppContainer) = object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T =
                SesionViewModel(container.auth) as T
        }
    }
}
