# Estado de la instalación — leer antes de usar

Nota añadida al instalar, **no forma parte del skill**. Bórrala cuando el
paquete esté completo.

## Qué está instalado

Solo `SKILL.md`, el enrutador. Es el archivo que se pegó en el chat.

## Qué falta

`SKILL.md` enruta a cinco páginas que **no existen en este repo**:

    best-practices/index.md
    codex/index.md
    css-spring/index.md
    performance-audit/index.md
    transition-preview/index.md

No se pudieron descargar: `motion.dev` está bloqueado por la política de red
de este entorno (`curl https://motion.dev/docs/ai-kit` → sin respuesta). Hay
que copiarlas a mano desde el paquete oficial, respetando esos nombres y esa
estructura de carpetas.

Mientras falten, invocar el skill lleva a rutas muertas.

## Y el servidor MCP tampoco está

Búsqueda de documentación, generación de muelles CSS, el editor de
transiciones y las auditorías MotionScore necesitan el servidor MCP de Motion,
que no está conectado en esta sesión. Instrucciones:
https://motion.dev/docs/ai-kit

## Aviso sobre este proyecto

PortGo es JS plano sin npm ni empaquetador; `CLAUDE.md` dice explícitamente
"No npm packages — CDN `<script>` tags only if truly needed". La librería
Motion no se puede instalar aquí tal cual.

Lo que sí aplica sin librería ni servidor es la parte de **animación CSS**:
buenas prácticas y generación de `linear()` para muelles. Esa es la rebanada
útil para este repo — y vive en `best-practices/` y `css-spring/`, que son
justo dos de las carpetas que faltan.
