# Prueba del Paso 2 — el acuerdo se cierra solo, sin superadmin

Un solo caso, dos vueltas. Unos 10 minutos.

Prueba la corrección de `20260925140000` (ya aplicada a pruebas el 2026-09-25
21:55Z) **y, de paso, H-06**, que hasta ahora no se podía probar: el trigger de
doble reserva nunca llegaba a ejecutarse porque el cierre abortaba antes.

El resto de la cola de `dev` se prueba con
[PLAN-PRUEBAS-COLA-DEV.md](PLAN-PRUEBAS-COLA-DEV.md); aquí no está.

URL: `https://portgo-git-dev-salvador-s-projects13.vercel.app/app.html` · **Ctrl+Shift+R**

---

## Paso 0 — ¿build correcto? (30 s, obligatorio)

Pruebas es copia de producción: los datos no dicen en qué entorno ni en qué build
estás. Pega en la consola:

```js
console.log(JSON.stringify({ base: (typeof sb!=='undefined'&&sb.supabaseUrl)||'sb no definido',
  v: [...document.scripts].map(s=>s.src.split('/').pop()).filter(n=>/^pedidos\./.test(n)) }, null, 2));
```

Debe decir `base` terminando en **`xskgnudiznryhgagxadu`** y **`pedidos.js?v=84`**.
Si no, para: estás en producción o el despliegue no ha llegado.

---

## Datos fijos de las dos vueltas

| | |
|---|---|
| Camión | **`T-46BC79F9`** — Torton, de Omar Silva Preciado |
| Tipo a pedir en la solicitud | **Torton** (exacto, o el camión no sale en el desplegable) |
| Vuelta A — fechas | **05/11/2026 → 07/11/2026** |
| Vuelta B — fechas | **06/11/2026 → 08/11/2026** (solapan con A en el 6 y el 7) |

Esas fechas están elegidas: `T-46BC79F9` ya tiene una reservación **Activa del
10 al 12 de octubre**, y noviembre no la roza. Si usaras octubre, la vuelta A
fallaría por esa reserva vieja y no probarías nada.

---

## Vuelta A — el acuerdo debe cerrarse SOLO (esto es lo que se arregló)

| # | Rol | Dónde | Qué haces |
|---|---|---|---|
| 1 | cliente | inicio → **«Solicitar servicio»** | Camión **Torton**, **05/11/2026 → 07/11/2026**. Rellena origen y destino con lo que quieras. Botón **«📋 Publicar solicitud»** |
| 2 | superadmin | inicio → **«Por aprobar»** | **«✓ Aprobar y publicar»** |
| 3 | empresa (Omar) | inicio → **«Solicitudes»** | **«Hacer oferta»**, elige **«🚛 T-46BC79F9 — Torton (14 ton)»**, pon un precio, **«Enviar oferta»** |
| 4 | cliente | inicio → **«Mis solicitudes»** | **«✓ Aceptar $…»** → rellena el modal → **«✓ Guardar y confirmar»** |

**Resultados esperados, en este orden:**

| Paso | Debe salir |
|---|---|
| 1 | `✓ Solicitud enviada — un administrador la revisará pronto` |
| 3 | `✓ Oferta enviada al cliente` |
| 4 | **`✓ Acuerdo cerrado — ya tienes una reservación activa`** |

Y después del paso 4, **sin tocar nada más y sin entrar como superadmin**:

- la solicitud pasa a **`✓ Acordado`**;
- en **«Reservaciones»** aparece una reserva **Activa** del 05 al 07 de noviembre
  con el camión `T-46BC79F9`.

### Cómo se ve si la corrección NO está

Es justo lo que viste antes: la etiqueta se queda en **`⏳ Acuerdo en revisión`**,
no aparece reservación, y **hasta 15 minutos después** el pedido cae en tu cola de
«Por aprobar» para que lo cierres tú. Si eso pasa, para y dímelo: significa que el
preview no tiene el cambio o que la migración no está en esta base.

### La otra rama posible, para que no la confundas con un fallo

Si el camión o la empresa tuvieran un documento vencido, el paso 4 no cierra y
sale un aviso que **nombra el documento** (lo trae la RPC desde el guard), y el
pedido va a tu cola. Eso es correcto y es el único caso que sigue pasando por el
superadmin. No es este fallo.

---

## Vuelta B — la doble reserva debe frenar (H-06, por primera vez de verdad)

Repite los **mismos cuatro pasos**, con:

- fechas **06/11/2026 → 08/11/2026**
- **el mismo camión `T-46BC79F9`**

**En el paso 3 vas a poder elegirlo aunque ya esté reservado, y no es un fallo.**
Ofertar no reserva: el desplegable no mira fechas, y el cliente puede no aceptar
nunca. El freno está en el paso 4.

**Resultado esperado en el paso 4:**

> ❌ Ese recurso ya tiene una reserva en esas fechas. La oferta sigue vigente — elige otra o pide una nueva.

Y **nada debe haber cambiado**:

- **no** aparece una segunda reservación;
- la solicitud **sigue en negociación**, no en `⏳ Acuerdo en revisión`;
- **la oferta sigue viva** y el cliente puede volver a intentarlo o pedir otra.

Eso último es nuevo y merece mirarse: antes de la corrección, un intento fallido
dejaba la oferta marcada como aceptada y el pedido a medias. Ahora la transacción
revierte entera, así que el mensaje «la oferta sigue vigente» dice la verdad.

**Si el segundo acuerdo se cierra, para**: la protección contra doble reserva se
abrió.

---

## Rastro que dejan estas pruebas

En pruebas quedan dos solicitudes, sus ofertas y **una** reservación (la de la
vuelta A), y `T-46BC79F9` aparecerá ocupado del 05 al 07 de noviembre.

Queda además, de la sesión anterior, el pedido del **10–11 de octubre** que el
cron dejó en `pendiente_acuerdo` con su oferta aceptada. **No lo apruebes**: su
camión ya está reservado del 10 al 12, así que fallaría — y esta vez sí fallaría
de verdad, con el mensaje de recurso no disponible. Es el residuo del fallo, no
una prueba.

---

## Decisión ya tomada, para después de esta prueba

**No se debe poder ofertar una unidad que ya está reservada en esas fechas**
(decisión del usuario, 2026-09-25). Se implementa **después** de que esta prueba
pase, en su propio cambio, y mueve el freno del paso 4 al paso 3: la empresa se
enteraría al ofertar, no el cliente al aceptar. Ver la sección *La unidad ocupada*
de [FLUJO-OPERATIVO.md](../docs/FLUJO-OPERATIVO.md).
