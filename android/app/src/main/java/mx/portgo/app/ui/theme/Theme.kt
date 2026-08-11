package mx.portgo.app.ui.theme

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat

// ── Paleta ────────────────────────────────────────────────────────────────
// El azul es el de la marca (#1a4fd6 en la web y en los correos). El resto se
// derivó alrededor de él siguiendo los roles de Material 3, para que la app se
// vea PortGo sin romper el contraste que M3 garantiza.

private val AzulPortGo = Color(0xFF1A4FD6)
private val AzulClaro = Color(0xFFAFC6FF)
private val AzulProfundo = Color(0xFF002A78)

private val EsquemaClaro = lightColorScheme(
    primary = AzulPortGo,
    onPrimary = Color.White,
    primaryContainer = Color(0xFFDCE1FF),
    onPrimaryContainer = AzulProfundo,
    secondary = Color(0xFF00668B),
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFC3E8FF),
    onSecondaryContainer = Color(0xFF001E2C),
    tertiary = Color(0xFF6B5E00),
    tertiaryContainer = Color(0xFFF8E36B),
    onTertiaryContainer = Color(0xFF211C00),
    error = Color(0xFFBA1A1A),
    errorContainer = Color(0xFFFFDAD6),
    onErrorContainer = Color(0xFF410002),
    background = Color(0xFFFDFBFF),
    onBackground = Color(0xFF1B1B1F),
    surface = Color(0xFFFDFBFF),
    onSurface = Color(0xFF1B1B1F),
    surfaceVariant = Color(0xFFE2E1EC),
    onSurfaceVariant = Color(0xFF45464F),
    outline = Color(0xFF767680),
)

private val EsquemaOscuro = darkColorScheme(
    primary = AzulClaro,
    onPrimary = Color(0xFF002C71),
    primaryContainer = Color(0xFF0040A0),
    onPrimaryContainer = Color(0xFFDCE1FF),
    secondary = Color(0xFF77D1FF),
    onSecondary = Color(0xFF003549),
    secondaryContainer = Color(0xFF004C69),
    onSecondaryContainer = Color(0xFFC3E8FF),
    tertiary = Color(0xFFDBC750),
    tertiaryContainer = Color(0xFF514700),
    onTertiaryContainer = Color(0xFFF8E36B),
    error = Color(0xFFFFB4AB),
    errorContainer = Color(0xFF93000A),
    onErrorContainer = Color(0xFFFFDAD6),
    background = Color(0xFF1B1B1F),
    onBackground = Color(0xFFE4E1E6),
    surface = Color(0xFF1B1B1F),
    onSurface = Color(0xFFE4E1E6),
    surfaceVariant = Color(0xFF45464F),
    onSurfaceVariant = Color(0xFFC6C5D0),
    outline = Color(0xFF90909A),
)

/**
 * Colores de estado, fuera del esquema de M3.
 *
 * Los estados de una solicitud o una reserva no son "primary" ni "error": son
 * un vocabulario propio (abierta, en negociación, acordada, cancelada) que
 * tiene que leerse igual en claro y en oscuro. Van aparte para que ningún
 * cambio de tema los altere sin querer.
 */
object ColoresEstado {
    val exito = Color(0xFF16A34A)
    val exitoSuave = Color(0x2216A34A)
    val alerta = Color(0xFFB45309)
    val alertaSuave = Color(0x22B45309)
    val info = Color(0xFF1A4FD6)
    val infoSuave = Color(0x221A4FD6)
    val peligro = Color(0xFFDC2626)
    val peligroSuave = Color(0x22DC2626)
    val neutro = Color(0xFF64748B)
    val neutroSuave = Color(0x2264748B)
}

private val TipografiaPortGo = Typography(
    headlineSmall = TextStyle(fontSize = 24.sp, fontWeight = FontWeight.Bold, lineHeight = 32.sp),
    titleLarge = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.SemiBold, lineHeight = 28.sp),
    titleMedium = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold, lineHeight = 24.sp),
    bodyLarge = TextStyle(fontSize = 16.sp, lineHeight = 24.sp),
    bodyMedium = TextStyle(fontSize = 14.sp, lineHeight = 20.sp),
    bodySmall = TextStyle(fontSize = 12.sp, lineHeight = 16.sp),
    labelLarge = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.SemiBold),
    labelSmall = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Medium),
)

/** Separación estándar entre bloques. Evita números mágicos regados por la UI. */
object Espacio {
    val xs = 4.dp
    val s = 8.dp
    val m = 16.dp
    val l = 24.dp
    val xl = 32.dp
}

@Composable
fun PortGoTheme(
    oscuro: Boolean = isSystemInDarkTheme(),
    /**
     * Material You. Se respeta el color del sistema en Android 12+, que es lo
     * que la guía de Material recomienda, pero se puede apagar: hay clientes
     * que prefieren ver el azul de la marca.
     */
    colorDinamico: Boolean = true,
    content: @Composable () -> Unit,
) {
    val contexto = LocalContext.current
    val esquema = when {
        colorDinamico && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
            if (oscuro) dynamicDarkColorScheme(contexto) else dynamicLightColorScheme(contexto)
        oscuro -> EsquemaOscuro
        else -> EsquemaClaro
    }

    val vista = LocalView.current
    if (!vista.isInEditMode) {
        SideEffect {
            val ventana = (vista.context as Activity).window
            WindowCompat.getInsetsController(ventana, vista)
                .isAppearanceLightStatusBars = !oscuro
        }
    }

    MaterialTheme(
        colorScheme = esquema,
        typography = TipografiaPortGo,
        content = content,
    )
}
