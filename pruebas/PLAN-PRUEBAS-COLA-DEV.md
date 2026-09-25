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

## Paso 0 — ¿estoy mirando el build nuevo? (30 s, obligatorio)

Pruebas es copia fiel de producción, así que **los datos no distinguen un entorno
del otro ni un build del otro**. El 2026-09-18 se gastaron tres rondas de pruebas
en un build que no llevaba el cambio. Pega esto en la consola:

```js
console.log(JSON.stringify({
  url:  location.href,
  base: (typeof sb !== 'undefined' && sb.supabaseUrl) || 'sb no definido',
  v:    [...document.scripts].map(s => s.src.split('/').pop())
          .filter(n => /^(pedidos|views|modal|detalle|vigencias)\./.test(n)),
  css:  [...document.styleSheets].map(s => (s.href||'').split('/').pop()).filter(n => /components/.test(n))
}, null, 2)); caches.keys().then(k => console.log('caches:', k));
```

Tiene que decir **exactamente** esto:

| Debe decir | Si dice otra cosa |
|---|---|
| `base` termina en `xskgnudiznryhgagxadu` | **estás en producción** — para y cambia de URL |
| `pedidos.js?v=84` | el despliegue no ha llegado; espera y recarga |
| `views.js?v=34`, `modal.js?v=14`, `detalle.js?v=15`, `vigencias.js?v=8` | idem |
| `components.css?v=37` | idem |
| `caches: ['portgo-v225']` | si hay varias, recarga otra vez |

**Si algo no cuadra, no sigas y no depures el código.** El despliegue tarda, y en
septiembre llegó a tardar 52 minutos.

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

**Antes de pulsar nada, lo que hay en esta base.** Medido el 2026-09-25 con la
cuenta de cliente de pruebas, para que no confundas «vacío» con «roto»:

| Pastilla | Solicitudes propias que existen |
|---|---:|
| Todos | 2 |
| Activos | 1 |
| En revisión | **0** |
| Acuerdos | 1 |
| Cancelados | **0** |

**«En revisión» y «Cancelados» van a salir vacías, y es correcto.** No hay ninguna
fila de esos estados. Lo que hay que comprobar es que las otras tres muestren
exactamente lo que dice la tabla.

**Y la sección «Otras solicitudes activas» NO va a aparecer en ninguna de las
cinco.** Eso también es correcto, y la versión anterior de este guion decía lo
contrario: esa sección pinta los pedidos abiertos de *otros* clientes, y en esta
base hay **0**, así que el código no llega ni a poner el título
(`if (otrosPedidos.length)`). Si algún día hay pedidos abiertos de otro cliente,
aparecerá **en las cinco pastillas**, porque no se filtra por estado a propósito —
todos están en «abierto», así que filtrar por «Cancelados» la vaciaría.

**Esperado:** cada pastilla muestra el número de la tabla, ni más ni menos, y
cambiar de pastilla no deja filas del filtro anterior en pantalla.

> ⚠ **Esta prueba NO puede detectar el defecto que H-11 arregló.** Hace falta que
> haya **más de 30 pedidos abiertos de otros clientes** para que la página se
> llene con ellos y las filas propias se queden fuera; aquí hay 0. Lo que esta
> prueba comprueba es que **no haya regresión**: que el filtro siga mostrando lo
> que debe. El defecto en sí se demostró sobre la semántica de la paginación, no
> en pantalla, y así quedó escrito en el commit de H-11.

**Nota sobre los números de arriba:** son de `portgo-pruebas`, y el sello de
paridad del 2026-09-24 dice **`diverge`** con 72 diferencias, así que **no son los
números de producción** — sirven solo para saber qué esperar en el preview.

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

## Prueba 4 — H-06: doble reserva (5 min, la más importante)

**Qué cambió:** las tres capas que impiden reservar dos veces el mismo recurso
comparaban solo `unidad`, que es un `text` con el id de un camión, un custodio, un
patio o un lavado. Ahora comparan también `recurso_tipo`.

**El caso que arregla no se puede provocar desde la app** —haría falta un patio
con el mismo id que un camión, y la app no deja crear eso—, y ya lo ejercitó la
comprobación de la migración. **Aquí se busca regresión: que la protección de
verdad siga en pie.**

> **Precondición, y no es formalismo: esta prueba MANDA CORREO.** Al guardar la
> reserva, `js/modal.js` dispara dos avisos por `enviar-notificacion` —uno al
> dueño de la unidad y otro al cliente— y **pruebas tiene las direcciones REALES
> de los clientes**. Lo único que lo impide es el secreto `CORREO_SALIDA` de esa
> Edge Function, que **no vive en Postgres y por tanto el sello de paridad no lo
> cubre**. Comprobado el 2026-09-25 con `node pruebas/05-sonda-correo.mjs`:
> salida **BLOQUEADA**, y `mailer_autoconfirm` coincide con producción. La sonda
> no provoca un envío para averiguarlo: le pregunta a la función en qué modo
> está. **Si ha pasado tiempo o se ha redesplegado esa función, vuelve a
> correrla antes del paso 2.**

1. Entra como **cliente** → tarjeta **«Catálogo»** → elige una empresa → elige una
   unidad → botón **«Agendar esta unidad»**.
   Hay **13 camiones disponibles** en esta base; sirve cualquiera, por ejemplo
   `C-002` o `T-001`. El botón solo se activa si la unidad está `disponible`;
   si no, dice **«⏳ No disponible»**.
2. Reserva con fechas, digamos, del **día 10 al 12** del mes que viene. Envía.
   **Esperado:** «✓ Solicitud enviada — la empresa confirmará pronto».
3. **Repite con la misma unidad** y fechas que solapen: del **11 al 13**.

**Esperado:** se rechaza, con este texto exacto:

> Este recurso ya está reservado del 10/… al 12/… Elige otras fechas.

Ese aviso lo da el navegador (la primera de las tres capas). **Si la segunda
reserva entra, párate**: la protección se abrió y eso bloquea la promoción.

4. Opcional, para ejercitar la capa de la base en vez del navegador: como
   **empresa**, acepta una oferta cuya unidad ya tenga una reserva solapada. El
   texto entonces es otro:

> ❌ Ese recurso ya tiene una reserva en esas fechas. La oferta sigue vigente — elige otra o pide una nueva.

**Deja rastro:** la reserva del punto 2 se queda en pruebas como `Pendiente`, y
su unidad aparecerá ocupada en esas fechas. No estorba a nada, pero conviénete
elegir fechas lejanas para no cruzarte con otras pruebas.

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

## Al terminar

Di qué pasó por cada prueba. Lo que decide la promoción es **1, 2 y 4**; 3, 5 y 6
son de confirmación.

Y recuerda el orden si se promueve: **las migraciones a producción primero, el
código después.** `js/views.js` llama a `pedidos_disponibles_para_mi()`, que en
producción **no existe** — si el código llega antes, el globo de la empresa se
rompe durante todo el hueco.
