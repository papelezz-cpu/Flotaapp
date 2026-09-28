# Pruebas manuales de la cola de `dev` — 2026-09-25

Para: quien va a probar en el preview de `dev` antes de promover a producción.

Cubre los **seis cambios** que hay en `dev` y no en producción. Está ordenado de
más barato a más caro, y el paso 0 no es opcional: sin él, cualquier resultado de
abajo puede ser de otro build.

> Lo que se busca aquí es sobre todo **regresión**. Tres de los seis cambios no
> tienen nada nuevo que enseñar en pantalla: su prueba es que todo siga igual.
> Decirlo por adelantado evita ir a buscar un botón nuevo que no existe.

URL: `https://portgo-git-dev-salvador-s-projects13.vercel.app/app.html`
Primero **Ctrl+Shift+R**.

---

## Qué hay en `dev` y qué cubre este guion (2026-09-25)

La cola creció durante el día. Esta tabla existe para que las pruebas no se queden
cortas **por construcción**:

| Cambio en `dev` | Dónde se prueba |
|---|---|
| R-09 — el globo de la empresa | prueba 1, aquí |
| H-11 — el filtro de estado del cliente | prueba 2, aquí |
| El render ya no escribe | prueba 3, aquí |
| H-06 (a) — doble reserva por tipo | prueba 4, aquí |
| H-20 — techo de avisos | prueba 5, aquí |
| Vigencias legible | prueba 6, aquí |
| **H-22 — el archivado no manda la fecha** | **prueba 7, nueva** |
| **El desplegable de ofertas: `recurso_tipo` y la rama de lavado** | **prueba 8, nueva** |
| La aprobación del superadmin por RPC | [PLAN-PRUEBAS-APROBAR-ACUERDO.md](PLAN-PRUEBAS-APROBAR-ACUERDO.md) — aparte, porque necesita montaje |
| El Paso 2 del cierre | [PLAN-PRUEBAS-PASO2.md](PLAN-PRUEBAS-PASO2.md) — **ya pasada**, y aplicada a producción |
| **El conflicto tardío: oferta viva + unidad ocupada** | **prueba 9, nueva** — el único caso que no se puede montar desde la interfaz |

**Dos cambios NO se pueden probar, y no hay que buscarlos:** los de
[js/modal.js](../js/modal.js) y [js/detalle.js](../js/detalle.js) están en **código
muerto** — el modal de reserva directa y la ficha de unidad no se pueden abrir desde
la app (*hueco 6* del flujo operativo). Se arreglaron por consistencia con H-06, por
si ese camino se revive. Si alguien va a buscar el botón «Agendar», no existe.

**H-19 (`updated_at`) tampoco tiene prueba de pantalla** y es correcto: la migración
añade la columna y el trigger, pero **no cambia el orden de ninguna cola**. Su
comprobación se ejecuta dentro de la propia migración al aplicarla.

---

## Paso 0 — ¿estoy mirando el build nuevo? (30 s, obligatorio)

Pruebas es copia fiel de producción, así que **los datos no distinguen un entorno
del otro ni un build del otro**. El 2026-09-18 se gastaron tres rondas de pruebas
en un build que no llevaba el cambio.

**Este bloque no lleva números escritos a mano — se compara solo.** La versión
anterior sí los llevaba y se quedó vieja en tres días: decía `pedidos.js?v=84`
cuando ya iba por 86, y el usuario tuvo que preguntar si el guion estaba al día.

```js
fetch('app.html', { cache: 'no-store' }).then(r => r.text()).then(html => {
  const pide = {};
  for (const m of html.matchAll(/(?:js|css)\/([\w.-]+)\?v=(\d+)/g)) pide[m[1]] = m[2];
  const carga = {};
  for (const el of [...document.scripts, ...document.styleSheets]) {
    const m = (el.src || el.href || '').match(/(?:js|css)\/([\w.-]+)\?v=(\d+)/);
    if (m) carga[m[1]] = m[2];
  }
  const mal = Object.keys(carga).filter(f => pide[f] && pide[f] !== carga[f])
                    .map(f => `${f}: cargado v${carga[f]}, app.html pide v${pide[f]}`);
  console.log(JSON.stringify({
    base:     (typeof sb !== 'undefined' && sb.supabaseUrl) || 'sb no definido',
    ficheros: Object.keys(carga).length + ' comparados',
    desfase:  mal.length ? mal : 'ninguno'
  }, null, 2));
  caches.keys().then(k => console.log('caches:', k));
});
```

**Qué tiene que salir:**

| Campo | Debe decir |
|---|---|
| `base` | termina en **`xskgnudiznryhgagxadu`**. Si termina en `xnyqsewaluezkkrlyhxg` **estás en producción** — para y cambia de URL |
| `desfase` | **`"ninguno"`**. Si lista algo, el navegador sirve ficheros viejos: **Ctrl+Shift+R** otra vez |
| `caches` | **una sola** entrada `portgo-vNNN`. Si hay varias, recarga otra vez |

> **Lo que este bloque NO puede comprobar, y lo cubro yo:** si el despliegue de
> Vercel llegó. Compara lo que el navegador cargó contra el `app.html` **que
> Vercel está sirviendo**, así que si el despliegue va con retraso los dos son
> viejos y el desfase sale «ninguno» igualmente. Eso se comprueba desde fuera,
> contra el estado del commit en GitHub, y es lo primero que hago antes de pedirte
> que pruebes.

---

## Prueba 1 — R-09: el globo de «Solicitudes» de la empresa (2 min)

**Qué cambió:** el número del globo lo contaba el navegador descargando todos los
pedidos abiertos y todas las ofertas de la empresa. Ahora lo cuenta la base con
una RPC. **El número tiene que ser el MISMO** — si cambia, el globo y el panel
dejaron de contar lo mismo, que es peor que no tener globo.

1. Entra como **empresa**.
2. En el inicio, mira la tarjeta **«Solicitudes»** («Ofertas y pedidos activos»).
   **Anota el número del globo.**
3. Abre esa tarjeta y cuenta las tarjetas bajo el título **«Solicitudes
   disponibles»**.

**Esperado:** los dos números coinciden.
**Si el globo no aparece:** la RPC falla. Mira la consola — un 404 sobre
`pedidos_disponibles_para_mi` significa que la migración no está en esta base.
**Si el globo dice un número distinto** al de la lista: párate y anótalo, es el
fallo que esta prueba busca.

---

## Prueba 2 — H-11: el filtro de estado del cliente (3 min)

**Qué cambió:** las pastillas filtraban **la página** de 30, no la lista. Al
filtrar por «Cancelados», la página se llenaba con los pedidos abiertos de los
demás clientes y los cancelados propios se quedaban fuera.

1. Entra como **cliente**.
2. Abre la tarjeta **«Mis solicitudes»**.
3. Ve pulsando, una por una, las cinco pastillas:
   **Todos · Activos · En revisión · Acuerdos · Cancelados**

**No compares contra números escritos aquí: compara contra una invariante.** La
versión anterior de este guion traía una tabla de cuántas hay por pastilla, medida
el 2026-09-25. Tres días después ya estaba vieja (decía Activos 1, Acuerdos 1,
Cancelados 0; eran 2, 5 y 1), porque cada prueba crea solicitudes.

**Lo que tiene que cumplirse, y no caduca:**

> **La suma de «Activos» + «En revisión» + «Acuerdos» + «Cancelados» tiene que dar
> exactamente lo mismo que «Todos».**

Los cuatro grupos parten los nueve estados sin solaparse y sin dejar ninguno fuera,
así que si la suma no cuadra, el filtro está perdiendo filas — que es justo el
defecto que H-11 arregló. Una pastilla vacía no es un fallo: significa que no tienes
ninguna en esos estados.

**Dos cosas que hacen fácil contar mal, y las dos son de la interfaz, no del filtro:**

- **El «Historial» está al final de la página**, después de «Mis solicitudes», con un
  hueco por delante. Con «Todos» es fácil contar solo lo de arriba y dar un número
  mucho más bajo. Baja hasta el fondo.
- **`expirado` cuenta como «Acuerdos».** El grupo es `acordado` + `finalizado` +
  `expirado`, así que una pastilla que dice «Acuerdos» lista también solicitudes
  vencidas que nunca llegaron a acuerdo. Es lo que hay hoy, a propósito; ver la nota
  al final de esta prueba.

> ⚠ **Esta prueba NO puede detectar el defecto que H-11 arregló.** Hace falta que
> haya **más de 30 pedidos abiertos de otros clientes** para que la página se
> llene con ellos y las filas propias se queden fuera; aquí hay 0. Lo que esta
> prueba comprueba es que **no haya regresión**: que el filtro siga mostrando lo
> que debe. El defecto en sí se demostró sobre la semántica de la paginación, no
> en pantalla, y así quedó escrito en el commit de H-11.

#### Lo que salió al probarla el 2026-09-28, y es decisión del usuario

Al contar las pastillas apareció que **«Acuerdos» lista también las `expirado`**, y
que eso desconcierta: de 5 filas, 3 eran solicitudes vencidas que nunca llegaron a
acuerdo. El grupo está definido así en `PED_ESTADOS_POR_FILTRO`
(`acordado` + `finalizado` + `expirado`) y no es un fallo — pero la etiqueta promete
otra cosa.

Opciones, sin tocar nada todavía: renombrar la pastilla («Cerradas», «Historial»),
o sacar `expirado` a su propio grupo. Lo primero es una palabra; lo segundo añade una
pastilla y cambia lo que el cliente ve. **No se decide de paso en una prueba.**

---

## Prueba 3 — el render ya no escribe (2 min, es una prueba de «nada cambió»)

**Qué cambió:** dibujar la lista de Solicitudes hacía cinco escrituras en la base
(caducar ofertas, reabrir pedidos, marcar expirados). Ya no hace ninguna: eso lo
hace `sincronizar_estados_pedidos()` en pg_cron cada 15 minutos.

1. Abre **«Solicitudes»** (como cliente y como empresa).

**Esperado: se ve exactamente igual que antes.** La normalización se conserva en
memoria, así que un pedido con todas sus ofertas rechazadas se sigue mostrando
como abierto, y un acuerdo con fecha pasada como expirado.

**La diferencia está solo en la base, y tarda hasta 15 minutos.** Si quieres
verla: fíjate en una solicitud que la pantalla muestre ya corregida y consúltala
en la base — debe seguir con el estado viejo hasta que pase el cron. **Antes de
este cambio estaría ya cambiada.** No es imprescindible para promover.

---

## Prueba 4 — H-06: doble reserva (10 min, la más importante)

**Qué cambió:** las capas que impiden reservar dos veces el mismo recurso
comparaban solo `unidad`, que es un `text` con el id de un camión, un custodio, un
patio o un lavado. Ahora comparan también `recurso_tipo`.

**Dos cosas antes de empezar, porque la primera versión de este guion las tenía
mal y te mandó a buscar un botón que no existe:**

- **No hay «Agendar esta unidad», ni reserva directa.** Ese modal existe pero
  **no se puede abrir**: sus botones viven en la rejilla oculta del Catálogo
  (*hueco 6* del flujo operativo). Lo saqué de `js/detalle.js`, que es código
  muerto. En el Catálogo los botones reales son **«📋 Publicar solicitud»**,
  **«Ver empresa»** y **«Ver N reseñas»**.
- **El único camino que crea una reservación hoy es el acuerdo**, y por eso la
  capa que de verdad vigila es el trigger de la base, no el navegador.

### El camino real, con las etiquetas tal como están en pantalla

Hay que llegar a **dos acuerdos sobre el MISMO camión con fechas que solapen**. La
segunda vez tiene que fallar.

| # | Rol | Dónde | Botón |
|---|---|---|---|
| 1 | cliente | Catálogo, o inicio → «Solicitar servicio» | **«📋 Publicar solicitud»** |
| 2 | superadmin | inicio → **«Por aprobar»** | **«✓ Aprobar y publicar»** |
| 3 | empresa | inicio → **«Solicitudes»** | **«Hacer oferta»** |
| 4 | cliente | inicio → **«Mis solicitudes»** | **«✓ Aceptar $…»** y luego **«✓ Guardar y confirmar»** |

### Qué camión usar, y por qué importa

El desplegable de **«Hacer oferta»** filtra por **dueño** y por **tipo exacto**
(`.eq('propietario_id', …).eq('tipo', tipo)`), así que si la solicitud y el camión
no coinciden en tipo, el camión **no aparece** y parece que algo está roto.

Unidades de **Omar Silva Preciado** en esta base, con su tipo exacto:

| id | tipo (el que hay que pedir en la solicitud) |
|---|---|
| `T-46BC79F9` | Torton |
| `T-629F701C` | Torton |
| `R-A330E825` | Rabón |
| `S-965A48AE` | Sencillo porta contenedor 40/20 |
| `C-CBFCC424` | Camioneta 1.5 ton caja seca |

Usa **`T-46BC79F9`** y pide la solicitud de tipo **Torton**. Hay dos Tortones, así
que en la segunda vuelta el desplegable te dejará elegir **el mismo**, que es lo
que la prueba necesita.

Los ids y los dueños de esta tabla son de `portgo-pruebas`, leídos el 2026-09-25 con
sesión de superadmin. El sello de paridad del 2026-09-24 dice **`diverge`** con 72
diferencias, así que **en producción la flota puede no ser esta**. Si vas a repetir
la prueba allí, mira primero «Mis unidades».

> `T-001` **no sirve y la primera versión de este guión lo daba por bueno**: es de
> **Champi**, no de Omar, y además su tipo es «Torton caja seca», no «Torton». No
> habría aparecido en el desplegable ni entrando como Champi con una solicitud de
> Torton.

1. **Primera solicitud.** Como cliente, publica una de camión tipo **Torton** con
   fechas del **día 10 al 12 del mes que viene**. Ojo: **no se admite el mismo
   día**, los campos de fecha llevan `min = mañana`.
2. Como **superadmin**, apruébala con **«✓ Aprobar y publicar»**.
3. Como **empresa (Omar Silva Preciado)**, entra en **«Solicitudes»**, pulsa
   **«Hacer oferta»** y elige **`T-46BC79F9`**. En el desplegable se lee
   **«🚛 T-46BC79F9 — Torton (14 ton)»**.

   > **La oferta con una unidad ya comprometida SE PERMITE, y no es un fallo.**
   > En la segunda vuelta vas a poder elegir el mismo camión aunque ya tenga una
   > reserva solapada, y el desplegable no te dirá nada. Es correcto:
   > `_enviarOfertaCore()` valida el **tipo** del camión, la **licencia hazmat**
   > del chofer y que no tengas ya una oferta activa **en esa misma solicitud** —
   > y nada más. Una oferta no es una reserva: el cliente puede no aceptarla
   > nunca. **El choque salta al cerrar el acuerdo**, en el paso 4.
4. Como **cliente**, en **«Mis solicitudes»**, **«✓ Aceptar $…»** → **«✓ Guardar y
   confirmar»**.
   **Esperado:** el acuerdo se cierra y aparece la reservación.
5. **Repite los pasos 1–4** con una segunda solicitud, **el mismo camión
   `T-46BC79F9`** y fechas que solapen: del **11 al 13**.

**Esperado en el paso 4 de la segunda vuelta — al pulsar «✓ Guardar y confirmar»,
no antes:** el acuerdo NO se cierra, y sale este texto:

> ❌ Ese recurso ya tiene una reserva en esas fechas. La oferta sigue vigente — elige otra o pide una nueva.

**Si el segundo acuerdo se cierra, párate**: la protección contra doble reserva se
abrió y eso bloquea la promoción. Es lo único que esta prueba busca.

> **El caso que H-06 arregla no se puede provocar desde la app** —haría falta un
> patio con el mismo id que un camión, y la app no deja crear eso—. Ya lo ejercitó
> la comprobación de la migración, que además apaga el trigger para probar la
> restricción por separado. **Aquí solo se busca regresión.**

> **Sobre el correo:** este camino sí manda avisos (oferta nueva, acuerdo
> cerrado), y pruebas tiene las direcciones **REALES** de los clientes. Lo único
> que lo impide es el secreto `CORREO_SALIDA` de `enviar-notificacion`, que **no
> vive en Postgres, así que el sello de paridad no lo cubre**. Comprobado el
> 2026-09-25 con `node pruebas/05-sonda-correo.mjs`: salida **BLOQUEADA**, y
> `mailer_autoconfirm` coincide con producción. La sonda no provoca un envío para
> averiguarlo. **Vuelve a correrla si se redespliega esa función.**

**Deja rastro:** quedan dos solicitudes, sus ofertas y una reservación `Activa` en
pruebas, y el camión `T-46BC79F9` aparecerá ocupado en esas fechas. Elige fechas
lejanas para no cruzarte con otras pruebas.

---

## Prueba 5 — H-20: el techo de avisos al superadmin (1 min, solo regresión)

**Qué cambió:** `notificar_superadmins()` tiene un techo de 60 llamadas/hora por
cuenta. El uso normal está muy por debajo — el máximo medido en todo el histórico
de producción es **17 llamadas en una hora**, y eso sumando todas las cuentas.

1. Haz cualquier acción que avise al superadmin: da de alta una unidad como
   empresa, o publica una solicitud como cliente.
2. Entra como **superadmin** y mira la campana.

**Esperado:** el aviso llega, como siempre. Esta prueba solo confirma que el techo
no estorba al uso normal; que descarta por encima de 60 ya lo comprobó la
migración, y provocarlo a mano son 60 acciones seguidas.

---

## Prueba 6 — Vigencias, legibilidad (1 min, visual)

**Qué cambió:** el nombre del documento y su fecha en el panel de Vigencias tenían
un contraste de 2,47:1 — se leían mal y pasaban desapercibidos. Se subió el tamaño
y se oscureció el color; las fechas que faltan llevan además un fondo tenue.

1. Entra como **empresa** (o superadmin) → tarjeta **«Vigencias»**.

**Esperado:** debajo de cada empresa/unidad, el nombre del documento y su fecha se
leen sin esfuerzo. En el grupo de una unidad con carga peligrosa debe verse
**«Permiso de materiales peligrosos»** — esa línea existía antes y no se veía.

---

## Prueba 7 — H-22: el archivado ya no manda la fecha (3 min)

**Qué cambió:** al archivar una reservación, el cliente mandaba
`archivado_at: new Date()` —el reloj del navegador—. Ya no manda nada: la pone el
`DEFAULT now()` del servidor. Eso permitió renombrar la columna a `archivado_en`
sin ventana de rotura, pero **si me equivoqué, el histórico se queda sin fecha**.

> **El botón se llama «🗑 Eliminar» y NO elimina: archiva.** La confirmación lo
> dice: «¿Archivar esta reservación? Se moverá al historial y desaparecerá de la
> lista activa.» Es seguro pulsarlo, y solo lo ve el superadmin.

1. Como **superadmin** → **«Reservaciones»** → elige una reservación cualquiera
   (sirve la de la prueba 4) → en el grupo *Superadmin*, **«🗑 Eliminar»** →
   confirma.
2. Entra en la tarjeta **«Historial»** («Reservaciones archivadas»).

**Esperado:** la reservación aparece en el historial **la primera**, y la columna
**«Archivado» muestra la fecha de HOY**.

> Hasta el 2026-09-28 esto fallaba por dos sitios a la vez, y los dos se
> arreglaron ese día al probarlo: la tabla se ordenaba por `created_at` —cuándo se
> creó la reservación, no cuándo se archivó— y la columna «Archivado» **pintaba
> también `created_at`**. Así que al archivar una reserva creada semanas antes,
> esa columna seguía mostrando la fecha vieja y parecía que la fila no había
> llegado. Sí había llegado. Si sale vacía o sin fecha, para y dímelo: significa que el `DEFAULT` no
está haciendo su trabajo, o que la migración de H-22 no está aplicada en esta base.

**Ojo con el orden:** esta prueba necesita que **`20260925160000` esté aplicada a
pruebas**. Si no lo está, el cliente no manda la fecha y la columna vieja
`archivado_at` se queda NULL — que es exactamente el fallo que buscas. Comprueba
primero que la migración está puesta.

---

## Prueba 8 — el desplegable de ofertas (2 min, solo si hay servicios de lavado)

**Qué cambió:** el filtro de disponibilidad del desplegable comparaba solo
`unidad`, y asumía **tres** tipos de recurso cuando hay cuatro. Sin la rama de
lavado, un servicio de lavado buscaba conflictos con `recurso_tipo = 'camion'`, no
encontraba ninguno, y **el filtro de disponibilidad dejaba de actuar en silencio**.

1. Como **cliente**, publica una solicitud de **lavado** con fechas en las que el
   lavado `LAV-001` ya esté reservado (si no lo está, esta prueba no aplica).
2. Como la **empresa dueña de ese lavado**, pulsa **«Hacer oferta»**.

**Esperado:** el lavado ocupado **no aparece**, y si era el único, el aviso dice
**«No tienes lavados disponibles…»** — no «camiones», que es lo que decía antes y
mandaba a mirar la flota equivocada.

**Si no hay ningún lavado con reserva, sáltala.** Lo que sí queda comprobado sin
hacer nada: el filtro por fechas funciona para camiones — se vio en la prueba del
Paso 2, cuando el desplegable negó el Rabón ya reservado.

---

## Prueba 9 — el conflicto tardío: una oferta cuya unidad se ocupó después (8 min)

**Es el único escenario que las tres capas de la base existen para cubrir**, y el
único que no se puede provocar por el camino corto: el desplegable de «Hacer
oferta» impide ofertar una unidad **ya reservada**, así que una oferta viva sobre
una unidad ocupada solo aparece si **la reserva llegó después de la oferta**.

> **Se monta con dos solicitudes, y la segunda se cierra primero.** Funciona porque
> el desplegable mira `reservaciones`, no ofertas: mientras la primera oferta solo
> está *enviada*, la unidad sigue contando como libre.
>
> La versión anterior de este guion usaba un caso que había quedado servido de
> rebote. **Se caducó solo el 2026-09-27**: el cron expiró esa oferta (regla a) y
> reabrió el pedido (regla b). Funcionó como debía, y se llevó el caso por delante
> — de ahí que ahora se monte a propósito.

Fechas y unidad: **Rabón** (la única de Omar es `R-A330E825`, libre en diciembre).

| # | Rol | Qué haces |
|---|---|---|
| 1 | cliente | publica **solicitud A** de **Rabón**, **20/12/2026 → 22/12/2026** |
| 2 | superadmin | **«✓ Aprobar y publicar»** la A |
| 3 | empresa (Omar) | **«Hacer oferta»** en la A con el Rabón → **«Enviar oferta»**. **NO la aceptes todavía** |
| 4 | cliente | publica **solicitud B** de **Rabón**, **21/12/2026 → 23/12/2026** (solapa con A en el 21 y el 22) |
| 5 | superadmin | **«✓ Aprobar y publicar»** la B |
| 6 | empresa (Omar) | **«Hacer oferta»** en la B **con el mismo Rabón**. **Debe dejarte**: la unidad no tiene reserva todavía, solo una oferta pendiente |
| 7 | cliente | acepta la **B** → **«✓ Guardar y confirmar»** → `✓ Acuerdo cerrado — ya tienes una reservación activa` |
| 8 | cliente | **ahora acepta la A** → **«✓ Guardar y confirmar»** |

**Esperado en el paso 8:**

> ❌ Ese recurso ya tiene una reserva en esas fechas. La oferta sigue vigente — elige otra o pide una nueva.

Y **nada debe haber cambiado**, que es lo que de verdad se comprueba:

- **no** aparece una segunda reservación;
- la solicitud **A sigue en negociación** — ni «⏳ Acuerdo en revisión», ni «✓ Acordado»;
- **la oferta de A sigue viva** (`enviada`), así que el cliente puede pedir otra unidad.

**Si A queda en «✓ Acordado» sin reservación, para.** Es exactamente el daño que
hubo el 2026-09-25 por la ruta no atómica, y significaría que el arreglo del Paso 2
no está haciendo efecto en esta base.

**Si el paso 6 NO te deja ofertar**, para también y dímelo: significaría que el
desplegable está mirando ofertas además de reservaciones, y entonces este escenario
no puede existir — que sería una buena noticia, pero cambia lo que protege la base.

**Rastro:** quedan dos solicitudes de diciembre y una reservación del 21 al 23; el
Rabón aparecerá ocupado esas fechas.

---

## Resultados — corrida del 2026-09-28

Preview `dev`, build comprobado: `base` = `xskgnudiznryhgagxadu`, sin desfase de
ficheros.

| # | Qué | Resultado |
|---|---|---|
| 0 | build y entorno | ✅ correcto |
| 1 | R-09 — el globo de la empresa | ✅ **pasa** |
| 2 | H-11 — filtro de estado del cliente | ✅ **pasa** — activos 2, revisión 0, acuerdos 5, cancelados 1, total 8; la suma cuadra |
| 3 | el render ya no escribe | ✅ **pasa** |
| 4 | H-06 — doble reserva | no aplica: no se puede provocar desde la interfaz; la cubre la 9 |
| 5 | H-20 — techo de avisos | ✅ **pasa** |
| 6 | Vigencias legible | ✅ **pasa** |
| 7 | H-22 — archivado | ✅ **pasa** con `reservaciones.js?v=59`. La primera pasada destapó **dos defectos de la pantalla** —la columna «Archivado» pintaba `created_at` y la tabla se ordenaba por `created_at`—, arreglados el 28. El archivado en sí nunca falló |
| 8 | desplegable, rama de lavado | ⚠ no se pudo cerrar, pero **destapó un callejón sin salida** en el modal de «Guardar y confirmar» — arreglado el 28, ver abajo |
| 9 | conflicto tardío | ✅ **pasa**, y es el resultado más fuerte de la corrida — ver abajo |

**Decide la promoción: 1, 2, 7 y 9.** Las demás son de confirmación.

### El callejón sin salida que encontró la prueba 8 (2026-09-28)

Cuando el cierre del acuerdo falla —por ejemplo porque el recurso ya está
reservado— **el modal «Datos adicionales del servicio» no se podía cerrar**. Sus dos
botones eran «Omitir», que **no cancela**: pide confirmación y vuelve a intentar el
cierre, que falla igual; y «✓ Guardar y confirmar», que falla otra vez. Y en esta
app **no hay cierre por Escape ni por clic en el fondo**. Hubo que recargar la
página.

Lo curioso: **la función de cierre ya existía** — `closeDetallesServicio()`, que
cierra, reabre el detalle del pedido y limpia el estado pendiente. Estaba escrita
para esto y **ningún botón la llamaba**. Ahora la llaman dos: una **✕** en la
cabecera, como el resto de los modales, y un **«Cancelar»** explicito junto a
«Omitir detalles» — que se renombró así, porque «Omitir» a secas se lee como una
salida y no lo es.

Se revisaron los otros 37 modales: los diez sin `btn-cancel` tienen todos salida
(«✕» o «Cerrar»). Este era el único atrapado, y precisamente porque su botón
**parecía** un cancelar.

### La prueba 9, medida en la base tras el paso 8

El aviso salió, pero lo que la prueba comprueba de verdad es que **no quedara nada
escrito**. Medido:

| | Estado | Oferta | Reservación |
|---|---|---|---|
| **A** (20–22 dic) | `en_negociacion` | **`enviada` — viva** | **ninguna** |
| **B** (21–23 dic) | `acordado` | `aceptada` | Activa 21–23 dic |

Y `R-A330E825` quedó con **exactamente dos** reservaciones (5–7 nov y 21–23 dic). Sin
una tercera.

Eso prueba tres cosas de golpe, y por el camino real de la interfaz:

1. el **Paso 2** cierra el acuerdo sin que el superadmin intervenga (la B);
2. el **trigger de H-06** salta en el conflicto tardío, que es el caso para el que
   existen las capas de la base;
3. y la **transacción revierte entera** — la oferta de A sigue viva, así que el
   mensaje «la oferta sigue vigente» dice la verdad. Antes del 2026-09-25 un intento
   fallido dejaba la oferta aceptada y el pedido a medias.

---

## Al terminar

Di qué pasó por cada prueba. Lo que decide la promoción es **1, 2 y 4**; 3, 5 y 6
son de confirmación.

Y recuerda el orden si se promueve: **las migraciones a producción primero, el
código después.** `js/views.js` llama a `pedidos_disponibles_para_mi()`, que en
producción **no existe** — si el código llega antes, el globo de la empresa se
rompe durante todo el hueco.
