# Video publicitario PortGo

Tres proporciones del mismo anuncio, 23.5 s, 30 fps, H.264 `yuv420p` con
`faststart` (arranca sin descargar todo). Sin audio.

| Archivo | Medidas | Para |
|---|---|---|
| `portgo-vertical.mp4`   | 1080×1920 | WhatsApp Estados, Reels, TikTok |
| `portgo-horizontal.mp4` | 1920×1080 | LinkedIn, YouTube, la landing |
| `portgo-cuadrado.mp4`   | 1080×1080 | Feed de Instagram, Facebook, LinkedIn |

## Cómo se hizo y cómo se cambia

`escena.html` es el video. No usa animaciones de CSS: expone `seek(t)`, que
deja la escena en el segundo `t`. Por eso la captura cuadro a cuadro sale
idéntica sin importar lo que tarde el navegador.

Para cambiar textos, tiempos o colores se edita ese archivo y se vuelve a
renderizar: abrirlo en Chromium a la medida deseada, llamar `seek(i/30)` para
cada cuadro, guardar PNG, y

    ffmpeg -framerate 30 -i %05d.png -c:v libx264 -preset slow -crf 19 \
           -pix_fmt yuv420p -movflags +faststart -y salida.mp4

El reparto de escenas está en la constante `ESCENAS`, en segundos.

## Sobre el contenido

El guion solo menciona cosas que la app hace de verdad — ofertas de varias
empresas, contraoferta, seguimiento hasta la entrega, revisión de permiso SCT
y seguros, chat y calificación. No se prometen pagos protegidos ni nada que no
esté construido.

**Verificar `portgo.mx` antes de publicar.** Se usó porque el correo de
soporte vive en ese dominio (`SOPORTE_EMAIL` en `js/config.js`), pero la app
se sirve desde `portgo-six.vercel.app`. Si el dominio no apunta a la app, hay
que cambiar esa línea — es el `<div class="url">` del final.
