package mx.portgo.app.ui.theme

import android.app.Activity
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import mx.portgo.app.R

// ══════════════════════════════════════════════════════════════════════════
// TIPOGRAFÍA
// ══════════════════════════════════════════════════════════════════════════
//
// Se empaquetan TTF estáticos, uno por peso, en vez de la fuente variable:
// las fuentes variables solo funcionan desde API 26 y el minSdk es 24. Con
// estáticas los pesos se ven correctos también en Android 7, que es donde
// están los teléfonos de patio.
//
// Tampoco se usan Downloadable Fonts: dependerían de Google Play Services y de
// tener red la primera vez. En el puerto eso significa abrir la app con la
// tipografía equivocada.

/** Títulos, nombres, cifras y precios. */
val SpaceGrotesk = FontFamily(
    Font(R.font.space_grotesk_400, FontWeight.Normal),
    Font(R.font.space_grotesk_500, FontWeight.Medium),
    Font(R.font.space_grotesk_600, FontWeight.SemiBold),
    Font(R.font.space_grotesk_700, FontWeight.Bold),
)

/** Texto de cuerpo, subtítulos, descripciones y etiquetas. */
val DMSans = FontFamily(
    Font(R.font.dm_sans_300, FontWeight.Light),
    Font(R.font.dm_sans_400, FontWeight.Normal),
    Font(R.font.dm_sans_500, FontWeight.Medium),
    Font(R.font.dm_sans_600, FontWeight.SemiBold),
)

// ══════════════════════════════════════════════════════════════════════════
// COLOR
// ══════════════════════════════════════════════════════════════════════════
//
// Valores exactos del handoff. Es una identidad de marca fija, así que
// **Material You queda fuera**: en Android 12+ el color dinámico toma la
// paleta del fondo de pantalla del usuario y sustituiría el teal por lo que
// el teléfono decida. Con una marca definida eso no es personalización, es
// perder la marca.

object PortGoColor {
    val Arena = Color(0xFFFAF8F3)          // fondo de pantalla
    val Teal = Color(0xFF0D9488)           // primario: acciones, activos, FAB
    val TealOscuro = Color(0xFF0F766E)     // precios, énfasis
    val TealTenue = Color(0xFFE3F1EE)      // fondo de iconos de tarjeta
    val Tinta = Color(0xFF102A26)          // texto principal
    val TextoSecundario = Color(0xFF7C8A85)
    val TextoTerciario = Color(0xFF9AA6A1) // inactivo
    val Superficie = Color(0xFFFFFFFF)     // tarjetas, barra inferior
    val BordeTarjeta = Color(0xFFE6E1D6)
    val BordeBarra = Color(0xFFECE7DA)
    val Divisor = Color(0xFFF0ECE2)        // línea interna de tarjeta
}

/**
 * Colores de estado. Van fuera del esquema de Material a propósito: los
 * estados del negocio (en revisión, activa, en tránsito) son un vocabulario
 * propio, no "primary" ni "error", y tienen que leerse igual sin importar qué
 * pase con el tema.
 */
object ColoresEstado {
    val exito = Color(0xFF15924E)          // "Activa"
    val exitoSuave = Color(0xFFE4F2EA)
    val alerta = Color(0xFFC77C11)         // "En revisión" / "Pendiente"
    val alertaSuave = Color(0xFFFAF1DF)
    val info = PortGoColor.Teal
    val infoSuave = PortGoColor.TealTenue
    val peligro = Color(0xFFC0573A)        // badges de conteo, "En tránsito"
    val peligroSuave = Color(0xFFFBEEE8)
    val neutro = PortGoColor.TextoSecundario
    val neutroSuave = Color(0xFFF0ECE2)
}

private val EsquemaPortGo = lightColorScheme(
    primary = PortGoColor.Teal,
    onPrimary = Color.White,
    primaryContainer = PortGoColor.TealTenue,
    onPrimaryContainer = PortGoColor.TealOscuro,
    secondary = PortGoColor.TealOscuro,
    onSecondary = Color.White,
    secondaryContainer = PortGoColor.TealTenue,
    onSecondaryContainer = PortGoColor.Tinta,
    tertiary = ColoresEstado.alerta,
    tertiaryContainer = ColoresEstado.alertaSuave,
    onTertiaryContainer = PortGoColor.Tinta,
    error = ColoresEstado.peligro,
    onError = Color.White,
    errorContainer = ColoresEstado.peligroSuave,
    onErrorContainer = Color(0xFF7A2E1C),
    background = PortGoColor.Arena,
    onBackground = PortGoColor.Tinta,
    surface = PortGoColor.Superficie,
    onSurface = PortGoColor.Tinta,
    // surfaceVariant se usa como fondo suave en varias pantallas; se ata al
    // arena para que no aparezca el gris azulado que trae Material por defecto.
    surfaceVariant = PortGoColor.Arena,
    onSurfaceVariant = PortGoColor.TextoSecundario,
    outline = PortGoColor.BordeTarjeta,
    outlineVariant = PortGoColor.Divisor,
    scrim = Color(0x66102A26),
)

/**
 * Escala tipográfica del handoff, mapeada a los roles de Material 3.
 *
 * Space Grotesk para lo que se lee de un vistazo —saludo, títulos, cifras,
 * precios— y DM Sans para lo que se lee con calma. La mezcla no es decorativa:
 * hace que el precio de una oferta y el nombre de una ruta salten sobre la
 * descripción sin necesidad de más color.
 */
private val TipografiaPortGo = Typography(
    // Saludo del inicio: 22px
    headlineMedium = TextStyle(
        fontFamily = SpaceGrotesk, fontWeight = FontWeight.Bold,
        fontSize = 22.sp, lineHeight = 25.sp,
    ),
    // Nombre de empresa en el inicio: 20px
    headlineSmall = TextStyle(
        fontFamily = SpaceGrotesk, fontWeight = FontWeight.Bold,
        fontSize = 20.sp, lineHeight = 24.sp,
    ),
    // Título de pantalla y wordmark: 17-18px
    titleLarge = TextStyle(
        fontFamily = SpaceGrotesk, fontWeight = FontWeight.Bold,
        fontSize = 17.sp, lineHeight = 22.sp,
    ),
    // Título de tarjeta de lista: 14px
    titleMedium = TextStyle(
        fontFamily = SpaceGrotesk, fontWeight = FontWeight.SemiBold,
        fontSize = 14.sp, lineHeight = 19.sp,
    ),
    // Nombre de tarjeta de acceso rápido: 13.5px
    titleSmall = TextStyle(
        fontFamily = SpaceGrotesk, fontWeight = FontWeight.SemiBold,
        fontSize = 13.5.sp, lineHeight = 18.sp,
    ),
    bodyLarge = TextStyle(
        fontFamily = DMSans, fontWeight = FontWeight.Normal,
        fontSize = 13.sp, lineHeight = 19.sp,
    ),
    // Meta de tarjeta, subtítulos: 12-12.5px
    bodyMedium = TextStyle(
        fontFamily = DMSans, fontWeight = FontWeight.Normal,
        fontSize = 12.5.sp, lineHeight = 18.sp,
    ),
    // Descripción de acceso rápido: 11px
    bodySmall = TextStyle(
        fontFamily = DMSans, fontWeight = FontWeight.Normal,
        fontSize = 11.sp, lineHeight = 15.sp,
    ),
    // Label de sección en mayúsculas: 11px + letter-spacing .06em
    labelLarge = TextStyle(
        fontFamily = DMSans, fontWeight = FontWeight.Medium,
        fontSize = 11.sp, lineHeight = 14.sp, letterSpacing = 0.66.sp,
    ),
    // Badge: 11px
    labelMedium = TextStyle(
        fontFamily = DMSans, fontWeight = FontWeight.SemiBold,
        fontSize = 11.sp, lineHeight = 13.sp,
    ),
    // Etiqueta de pestaña: 10px
    labelSmall = TextStyle(
        fontFamily = DMSans, fontWeight = FontWeight.Medium,
        fontSize = 10.sp, lineHeight = 12.sp,
    ),
)

/** Separaciones del handoff. */
object Espacio {
    val xs = 4.dp
    val s = 8.dp
    val m = 16.dp     // padding lateral de contenido
    val l = 24.dp
    val xl = 32.dp
    val gapRejilla = 12.dp
}

/** Radios del handoff. */
object Radio {
    val tarjeta = 16.dp
    val stat = 14.dp
    val iconoTarjeta = 12.dp
    val botonHeader = 11.dp
    val pill = 999.dp
}

@Composable
fun PortGoTheme(
    content: @Composable () -> Unit,
) {
    val vista = LocalView.current
    if (!vista.isInEditMode) {
        SideEffect {
            val ventana = (vista.context as Activity).window
            // La paleta es clara en toda la app, así que los iconos de la barra
            // de estado van oscuros siempre.
            WindowCompat.getInsetsController(ventana, vista)
                .isAppearanceLightStatusBars = true
        }
    }

    MaterialTheme(
        colorScheme = EsquemaPortGo,
        typography = TipografiaPortGo,
        content = content,
    )
}

// Modo oscuro: PENDIENTE a propósito.
//
// El handoff define una sola paleta clara. Inventar un oscuro a partir de
// estos tokens daría contrastes que nadie revisó — el arena y el teal tenue no
// tienen equivalente evidente sobre fondo negro. Mejor dejarlo explícito que
// entregar un oscuro improvisado.
