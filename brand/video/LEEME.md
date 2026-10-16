# Video publicitario PortGo

Tres proporciones del mismo anuncio, 27.2 s, 30 fps, H.264 `yuv420p` con
`faststart`. Sin audio.

| Archivo | Medidas | Para |
|---|---|---|
| `portgo-vertical.mp4`   | 1080×1920 | WhatsApp Estados, Reels, TikTok |
| `portgo-horizontal.mp4` | 1920×1080 | LinkedIn, YouTube, la landing |
| `portgo-cuadrado.mp4`   | 1080×1080 | Feed de Instagram, Facebook, LinkedIn |

Usa el tema Evolución (teal + bronce) y el emblema de `img/logo.png`, así que
va a juego con lo que el usuario ve al entrar.

## Qué afirma, y de dónde sale

Nada del guion es invento. Cada afirmación está respaldada:

| En pantalla | Respaldo |
|---|---|
| Varias empresas cotizan, se comparan, hay contraoferta | `ofertas` · `FLUJO-OPERATIVO.md` |
| Permiso SCT y seguros revisados | `guard_oferta_update` manda el pedido a `pendiente_acuerdo` si están vencidos |
| Seguimiento de la recolección a la entrega | `tracking_estado`, cinco pasos por `recurso_tipo` |
| Fecha límite de vacíos y las demoras | `expedientes.fecha_limite_vacios`; `estadoVacios()` en `js/expedientes.js` le muestra al cliente «Devolver antes del …» con cuenta de días |

**El guion anterior decía «chat directo con el transportista». Eso ya no
existe**: el texto libre se retiró a propósito y se sustituyó por botones de
aviso con forma fija (`FLUJO-OPERATIVO.md`, «Cómo se hablan entre ellos`).
Prometerlo mandaba al cliente a buscar una pantalla que no está.

## Cómo se vuelve a generar

`escena.html` es el video. No usa animaciones de CSS: expone `seek(t)`, que
deja la escena en el segundo `t`. Por eso la captura cuadro a cuadro sale
idéntica sin importar lo que tarde el navegador. El reparto de escenas está en
la constante `ESCENAS`, en segundos.

Para rehacerlo: abrirlo en Chromium a la medida deseada, llamar `seek(i/30)`
por cada cuadro, guardar PNG, y

    ffmpeg -framerate 30 -i %05d.png -c:v libx264 -preset slow -crf 19 \
           -pix_fmt yuv420p -movflags +faststart -y salida.mp4

`logo.png` es copia de `img/logo.png`, para que el archivo se pueda abrir
suelto sin depender de la raíz del repo.

## Pendiente

**Verificar `portgo.mx` antes de publicar.** Se usa porque el correo de
soporte vive en ese dominio, pero la app se sirve desde Vercel. Si no apunta
a la app, cambiar el `<div class="url">` del final.
