package mx.portgo.app.core

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.Locale

/**
 * Formato de fechas, precios y tiempos relativos.
 *
 * Réplica de fmtFecha(), formatPrecio() y fmtTimeAgo() de js/utils.js y
 * js/notificaciones.js. Están juntos aquí a propósito: si la app y la web
 * muestran el mismo dato distinto, el usuario cree que son dos sistemas.
 */
object Fmt {

    /** Zona del negocio. PortGo opera en puertos mexicanos; el servidor guarda `date` sin zona. */
    val ZONA: ZoneId = ZoneId.of("America/Mexico_City")

    private val agrupador = Locale.forLanguageTag("es-MX")

    /**
     * Fecha de hoy en formato `YYYY-MM-DD`, en hora de México.
     *
     * OJO — divergencia conocida con la web: `today()` en js/utils.js hace
     * `new Date().toISOString().split('T')[0]`, que es UTC. Entre las 18:00 y
     * la medianoche de México, la web ya cree que es el día siguiente. Aquí se
     * usa la fecha local, que es la correcta para un campo `date` que el
     * usuario elige en un calendario. La consecuencia práctica es mínima
     * (marcar una unidad como ocupada unas horas antes), pero está anotada en
     * el README para corregirla del lado web.
     */
    fun hoy(): String = LocalDate.now(ZONA).toString()

    /** `2026-07-29` o `2026-07-29T10:00:00Z` → `29/07/2026`. */
    fun fecha(iso: String?): String {
        if (iso.isNullOrBlank()) return "—"
        val partes = iso.take(10).split("-")
        if (partes.size != 3) return "—"
        return "${partes[2]}/${partes[1]}/${partes[0]}"
    }

    /** `29/07/2026 – 02/08/2026`, o solo la primera si no hay fin. */
    fun rangoFechas(ini: String?, fin: String?): String {
        val a = fecha(ini)
        if (fin.isNullOrBlank() || fin.take(10) == ini?.take(10)) return a
        return "$a – ${fecha(fin)}"
    }

    /** `1250` → `$1,250 MXN/día`. Devuelve null si no hay precio, igual que la web. */
    fun precioDia(valor: Double?): String? {
        if (valor == null || valor == 0.0) return null
        return "${pesos(valor)} MXN/día"
    }

    /** `1250` → `$1,250 MXN`. */
    fun precioMxn(valor: Double?): String {
        if (valor == null) return "—"
        return "${pesos(valor)} MXN"
    }

    /** `1250.0` → `$1,250` (sin decimales, como la web). */
    fun pesos(valor: Double): String =
        "$" + String.format(agrupador, "%,.0f", valor)

    /** `1250.5` → `1,250.5` — para pesos de carga y dimensiones. */
    fun numero(valor: Double?, decimales: Int = 1): String {
        if (valor == null) return "—"
        return if (valor % 1.0 == 0.0) String.format(agrupador, "%,.0f", valor)
        else String.format(agrupador, "%,.${decimales}f", valor)
    }

    /** `Ahora`, `Hace 5 min`, `Hace 3 h`, `Hace 2 días`. */
    fun hace(iso: String?): String {
        if (iso.isNullOrBlank()) return ""
        val instante = runCatching { Instant.parse(iso) }
            .recoverCatching {
                // PostgREST devuelve `2026-08-10T12:00:00.123456+00:00`, que
                // Instant.parse sí acepta, y a veces sin zona. Ese caso se
                // interpreta como hora del servidor (UTC).
                Instant.parse(iso.trimEnd('Z') + "Z")
            }
            .getOrNull() ?: return ""

        val minutos = ChronoUnit.MINUTES.between(instante, Instant.now())
        return when {
            minutos < 1 -> "Ahora"
            minutos < 60 -> "Hace $minutos min"
            minutos < 60 * 24 -> "Hace ${minutos / 60} h"
            else -> {
                val dias = minutos / (60 * 24)
                "Hace $dias día${if (dias > 1) "s" else ""}"
            }
        }
    }

    /** Días que faltan (negativo si ya pasó). Para vencimientos de pago y de vacíos. */
    fun diasHasta(fechaIso: String?): Long? {
        if (fechaIso.isNullOrBlank()) return null
        val fecha = runCatching { LocalDate.parse(fechaIso.take(10)) }.getOrNull() ?: return null
        return ChronoUnit.DAYS.between(LocalDate.now(ZONA), fecha)
    }
}
