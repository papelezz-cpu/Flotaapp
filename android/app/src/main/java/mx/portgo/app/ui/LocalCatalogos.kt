package mx.portgo.app.ui

import androidx.compose.runtime.staticCompositionLocalOf
import mx.portgo.app.data.model.Catalogos

/**
 * Catálogos vigentes, disponibles para cualquier pantalla.
 *
 * Van por `CompositionLocal` y no por parámetro porque son ambiente, no datos:
 * las necesitan pantallas muy separadas del árbol (la lista de servicios, el
 * formulario de solicitud, el detalle) y pasarlas de mano en mano por toda la
 * navegación solo añadiría ruido a las firmas.
 *
 * `static` porque cambian una vez al arrancar y después prácticamente nunca:
 * con `staticCompositionLocalOf`, Compose no rastrea lecturas individuales —
 * un cambio redibuja todo el subárbol, que es exactamente lo que se quiere
 * cuando llega un catálogo nuevo, y a cambio la lectura no cuesta nada.
 *
 * El valor por defecto es el respaldo compilado, así que una vista previa o un
 * test funcionan sin montar el repositorio.
 */
val LocalCatalogos = staticCompositionLocalOf { Catalogos.PorDefecto }
