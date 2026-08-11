package mx.portgo.app.core

import io.github.jan.supabase.exceptions.HttpRequestException
import io.github.jan.supabase.exceptions.RestException
import java.io.IOException

/**
 * Traduce las fallas del backend a algo que un despachador pueda leer.
 *
 * Regla del proyecto que esta app hereda (ver CLAUDE.md): **toda** llamada que
 * escriba revisa el error y lo muestra. En este código base los fallos
 * silenciosos de RLS son el bug más caro que existe — una consulta bloqueada
 * por política devuelve 200 con lista vacía, y un update bloqueado no cambia
 * nada sin avisar. Nada de tragarse excepciones.
 */
sealed interface AppError {
    val mensaje: String

    /** Sin red, o el servidor no respondió. Reintentar tiene sentido. */
    data class Red(override val mensaje: String) : AppError

    /** La sesión caducó o el token ya no sirve. Hay que volver a entrar. */
    data class Sesion(override val mensaje: String) : AppError

    /**
     * Un guard trigger o una RPC rechazó la operación (código P0001). El texto
     * viene en español desde la base y está escrito para el usuario final, así
     * que se muestra tal cual.
     */
    data class Regla(override val mensaje: String) : AppError

    /** RLS bloqueó la escritura (42501). */
    data class Permiso(override val mensaje: String) : AppError

    /** El recurso ya está reservado en esas fechas. */
    data class RecursoOcupado(override val mensaje: String) : AppError

    data class Desconocido(override val mensaje: String) : AppError

    companion object {
        fun de(t: Throwable): AppError = when (t) {
            is IOException ->
                Red("Sin conexión. Revisa tu red e inténtalo de nuevo.")

            is HttpRequestException ->
                Red("No se pudo contactar al servidor. Inténtalo de nuevo.")

            is RestException -> mapearRest(t)

            else ->
                Desconocido(t.message ?: "Ocurrió un error inesperado.")
        }

        private fun mapearRest(e: RestException): AppError {
            val crudo = listOfNotNull(e.error, e.description, e.message)
                .joinToString(" ")

            return when {
                // Sentinela de check_reservacion_disponibilidad. Merece su
                // propio mensaje: "P0001" no le dice nada a nadie.
                crudo.contains("RECURSO_NO_DISPONIBLE") ->
                    RecursoOcupado("Esa unidad ya está reservada en esas fechas.")

                crudo.contains("42501") || crudo.contains("row-level security", ignoreCase = true) ->
                    Permiso("No tienes permiso para hacer esto.")

                crudo.contains("JWT") || crudo.contains("expired", ignoreCase = true) ->
                    Sesion("Tu sesión expiró. Vuelve a iniciar sesión.")

                // P0001 = RAISE EXCEPTION de nuestros guards y RPCs. El mensaje
                // ya está redactado en español para el usuario.
                crudo.contains("P0001") ->
                    Regla(limpiar(e.description ?: e.message.orEmpty()))

                crudo.contains("23505") ->
                    Regla("Ese registro ya existe.")

                crudo.contains("23503") ->
                    Regla("El registro está ligado a otro y no se puede modificar así.")

                crudo.contains("23514") ->
                    Regla("Alguno de los datos no es válido.")

                else ->
                    Desconocido(limpiar(e.description ?: e.message.orEmpty())
                        .ifBlank { "No se pudo completar la operación." })
            }
        }

        /** Quita el ruido de PostgREST alrededor del texto del RAISE. */
        private fun limpiar(texto: String): String = texto
            .substringAfter("ERROR:", texto)
            .replace(Regex("""\(SQLSTATE \w+\)"""), "")
            .trim()
            .ifBlank { "No se pudo completar la operación." }
    }
}

/**
 * Resultado de una operación. Se prefiere sobre exponer excepciones al
 * ViewModel: obliga a decidir explícitamente qué se le enseña al usuario.
 */
sealed interface Resultado<out T> {
    data class Ok<T>(val dato: T) : Resultado<T>
    data class Error(val error: AppError) : Resultado<Nothing>
}

inline fun <T> intentar(bloque: () -> T): Resultado<T> = try {
    Resultado.Ok(bloque())
} catch (t: Throwable) {
    // CancellationException tiene que seguir propagándose o se rompe la
    // cancelación estructurada de las corrutinas.
    if (t is kotlinx.coroutines.CancellationException) throw t
    Resultado.Error(AppError.de(t))
}
