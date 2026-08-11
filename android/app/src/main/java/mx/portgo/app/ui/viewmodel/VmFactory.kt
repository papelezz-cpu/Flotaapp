package mx.portgo.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider

/**
 * Fábrica de ViewModels para el grafo manual de dependencias.
 *
 * `viewModel(factory = vmFactory { MiViewModel(repo, usuario) })` — se pasa la
 * lambda que construye, y Compose se encarga del ciclo de vida. Evita repetir
 * un `object : ViewModelProvider.Factory` en cada pantalla.
 */
inline fun <VM : ViewModel> vmFactory(crossinline constructor: () -> VM) =
    object : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T = constructor() as T
    }

/**
 * Estado de una pantalla que carga datos.
 *
 * Los tres casos son excluyentes a propósito: una lista vacía por error no se
 * puede confundir con una lista vacía de verdad. En este backend esa distinción
 * es crítica — RLS devuelve 200 con lista vacía cuando bloquea una consulta.
 */
sealed interface EstadoCarga<out T> {
    data object Cargando : EstadoCarga<Nothing>
    data class Listo<T>(val datos: T) : EstadoCarga<T>
    data class Fallo(val mensaje: String) : EstadoCarga<Nothing>
}
