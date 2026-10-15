# Ícono dorado — la imagen original, recortada

Es **el archivo que se envió**, sin redibujar: recorte cuadrado centrado en la
caja del logo (`1100×1100` desde `+114+35` del original de `1254×1254`) y
reescalado. No se le cambió un color.

| Archivo | Para |
|---|---|
| `portgo-oro-maestro.png` | Maestro 1100 px. De aquí sale todo lo demás |
| `icono-512.png` · `-192` · `-180` | PWA y `apple-touch-icon` |
| `icono-64` · `-32` · `-16` | Favicon |
| `favicon.ico` | Favicon clásico, 16+32+64 en un archivo |
| `icono-512-maskable.png` | Android recorta a círculo el 80% central; esta trae margen |

## Por qué no hay versión transparente

Se intentó de dos formas y las dos destruyen el logo:

- **Quitar el fondo por color** deja agujeros. El fondo no es negro plano (las
  esquinas van de `srgb(2,2,4)` a `srgb(50,46,41)`), y sobre todo las zonas de
  *vidrio* del logo literalmente contienen fondo: al quitarlo se vacían.
- **Luminancia como alfa** deja un fantasma grisáceo sobre fondo claro y un
  halo rectangular sobre oscuro.

Así que el ícono es **siempre un mosaico con su fondo oscuro**. En la app eso
no estorba: el CSS ya lo redondea y se lee como insignia.

## Límites conocidos

- **A 16 px es una mancha oscura.** Se distingue la silueta, no el detalle. Es
  lo que pasa con cualquier logo 3D de este nivel de detalle.
- **No escala hacia arriba.** 1100 px alcanza de sobra para cualquier uso en
  pantalla; para imprenta grande haría falta el vector.
- **No se puede recolorear.** Si algún día la app cambia de paleta, el ícono
  se queda como está.

La alternativa vectorial está en `brand/borrador-oro/` (redibujada, escala y
se puede recolorear, pero no tiene los reflejos de vidrio).
