# Identidad PortGo

Traducción a vector plano del logo de brújula, en la paleta Marea de
`css/theme.css`. Solo colores declarados ahí: `#0d9488`, `#2dd4bf`, `#5eead4`,
`#102a26`, `#4f6661`.

## Archivos

| Archivo | Uso |
|---|---|
| `portgo-logo.svg` · `-inverso` | Lockup con bajada — landing, login, documentos |
| `portgo-horizontal.svg` · `-inverso` | Marca + nombre, sin bajada — cabecera de la app |
| `portgo-isotipo.svg` · `-inverso` | Marca completa, fondo transparente |
| `portgo-isotipo-simple.svg` · `-inverso` | Sin anillo ni arcos, transparente |
| `portgo-icono.svg` · `-claro` | **Favicon y PWA.** Mosaico redondeado, rosa con flecha |
| `portgo-icono-simple.svg` · `-claro` | Alternativa: rosa simétrica sin flecha, más legible a 16 px |

`muestrario.png` y `muestrario-iconos.png` son las pruebas de reducción.
`fuente/` tiene los scripts que generan los SVG: editar ahí y volver a correr
`python3 gen.py && python3 icono.py` mantiene todas las variantes coherentes.

## Decisiones

**La flecha es una punta de la rosa**, no un elemento encima. En la imagen
original la flecha cruza la brújula y se separa por volumen 3D; en plano eso
se convierte en una mancha. Aquí la punta del noreste se alarga en flecha y
sale por el hueco entre los dos arcos — por eso la rosa tiene solo tres
diagonales cortas en vez de cuatro.

**Dos variantes de ícono.** El anillo y los arcos se ensucian por debajo de
~32 px, así que el favicon usa una versión sin ellos. Es la práctica normal de
un logo responsivo.

## Pendiente

El texto va como fuente (Space Grotesk con pila de respaldo), no como curvas:
no hay `fonttools` ni la fuente instalada en el entorno donde se generó. Para
imprenta o para mandarlo a terceros hay que convertirlo a trazos.
