# Borrador — versión dorada

**Sin decidir.** La marca comiteada en `brand/` es la teal. Esto se guarda
porque se generó en un contenedor efímero y rehacerlo cuesta.

| Archivo | Qué es |
|---|---|
| `oro-icono.svg` | Marca completa sobre mosaico oscuro |
| `oro-isotipo.svg` | Marca completa, fondo transparente |
| `oro-favicon.svg` | Sin anillo ni arcos, mosaico oscuro — para 16-48 px |

Los genera `brand/fuente/oro.py` (necesita `gen.py` al lado).

## Lo que hay que saber antes de usarlos

**El oro exige fondo oscuro.** Los tonos salieron muestreados del archivo
original — `#644C33`, `#916E48`, `#BA9668` — y son oscuros y desaturados:
leen como oro solo contra negro. Sobre la arena `#faf8f3` de la app se ven
café. Por eso todas las variantes llevan su mosaico y no hay versión suelta
para fondo claro.

**Es una interpretación, no el archivo original.** Reproduce la geometría y
los tonos, no los reflejos de vidrio ni el bisel 3D: eso no existe en vector
plano y falsificarlo se ve peor que no tenerlo.

**La imagen original no sirve como archivo de marca.** El fondo no es negro
plano (las esquinas van de `srgb(2,2,4)` a `srgb(50,46,41)`), así que no se
puede recortar a transparente, y las zonas de vidrio contienen fondo. A 32 px
es una mancha.

Comparativa sobre la app real: `brand/comparativa-oro-teal.png`.
