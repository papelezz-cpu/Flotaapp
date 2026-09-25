# Prueba de la aprobación de acuerdos por el superadmin

Cubre el cambio de `2c1fa56`: `_ejecutarAprobarAcuerdo()` pasó de la función JS de
seis escrituras encadenadas a la RPC `cerrar_acuerdo()`, en una transacción.

URL: `https://portgo-git-dev-salvador-s-projects13.vercel.app/app.html` · **Ctrl+Shift+R**

---

## Lo primero, porque cambia el plan: hoy esa cola está vacía, y no por casualidad

Medido en pruebas el 2026-09-25:

- **0 pedidos en `pendiente_acuerdo`** — la cola de «Por aprobar → Acuerdos» no
  tiene nada.
- **0 documentos de empresa registrados** en `vigencias` (`entidad_tipo = 'perfil'`).
- **0 camiones con permiso de materiales peligrosos** registrado.

Y con el cierre arreglado, **lo único que mete un pedido en esa cola es un documento
vencido**. Sin documentos registrados, el desvío no se dispara: por eso la vuelta A
de la prueba anterior cerró sola. Las otras dos vías están cerradas también:

- la regla (c) del cron necesita un pedido `en_negociacion` con una oferta
  aceptada, y eso ya no ocurre: el cierre funciona, y si falla revierte entero;
- por carga peligrosa no se llega, porque el desplegable **excluye** las unidades
  sin permiso hazmat vigente, así que con cero permisos no hay nada que ofertar.

**Consecuencia honesta: esta prueba no se puede hacer sin montar antes un documento
vencido.** Está en la sección de abajo, marcada como montaje.

---

## Qué está ya probado sin hacer nada, y qué no

`cerrar_acuerdo()` —la RPC a la que ahora llama el superadmin— **ya se ejercitó**:
es la que usa por dentro el camino del cliente, y ese camino cerró bien en el
preview y en producción. La función no está en duda.

Lo que **nadie ha ejecutado todavía** son las ~20 líneas de JavaScript nuevas:

| Qué | Por qué importa |
|---|---|
| El par de campanas retirado | La RPC ya avisa a las dos partes. Si me equivoqué, cada uno recibe **dos** |
| El chequeo del id devuelto | Si la RPC devuelve NULL debe avisar, no seguir como si nada |
| La apertura de expedientes | La hacía la función vieja y la RPC no; se movió aquí |
| El mensaje de recurso ocupado | Cambió de `catch (e)` a `error` de la RPC |

---

## Paso 0 — ¿build correcto? (30 s)

```js
console.log(JSON.stringify({ base: (typeof sb!=='undefined'&&sb.supabaseUrl)||'sb no definido',
  v: [...document.scripts].map(s=>s.src.split('/').pop()).filter(n=>/^(aprobaciones|pedidos)\./.test(n)) }, null, 2));
```

Debe decir `base` terminando en **`xskgnudiznryhgagxadu`**, **`aprobaciones.js?v=47`**
y **`pedidos.js?v=86`**. Si no, para.

---

## Montaje — hacer que un documento de empresa quede vencido (5 min)

No es parte del flujo: es lo que hace falta para que exista un acuerdo que aprobar.
**Se deshace al final**, y conviene hacerlo con **Omar Silva Preciado** para no
tocar otras empresas.

1. Como **empresa (Omar)** → tarjeta **«Mis unidades»** → sección **«🏢 Perfil de
   empresa»** → bloque **«📋 Documentos legales — requieren revisión del
   superadmin»**.
2. En el campo **«Seguro RC — vencimiento»** pon una fecha **ya pasada** —por
   ejemplo **01/01/2026**— y pulsa **«📤 Enviar documentos para aprobación»**.
   Ese botón está **debajo** de los campos de documentos; **no es «Guardar
   perfil»**, que está más arriba y no manda nada a revisión.
3. Como **superadmin** → **«Por aprobar»** → bloque de documentos de empresa →
   **«✓ Aprobar documentos»**.

> **Si el formulario no te deja poner la fecha sin adjuntar el archivo**, para y
> dímelo: desde el 2026-09-24 se exige la fecha al subir el papel, y puede que
> exija el papel para aceptar la fecha. No fuerces nada; se resuelve de otra forma.

Ahora Omar tiene un documento vencido, y **cualquier oferta suya que el cliente
acepte irá a tu cola en vez de cerrarse**. Eso es correcto: es el único caso que
sigue pasando por el superadmin.

---

## La prueba (5 min)

Unidad: cualquiera de Omar del tipo que pidas. Fechas: **usa un rango libre**, por
ejemplo **12/12/2026 → 14/12/2026** — el Rabón `R-A330E825` ya está ocupado del 5
al 7 de noviembre.

| # | Rol | Qué haces | Qué debe salir |
|---|---|---|---|
| 1 | cliente | publica una solicitud del tipo de esa unidad, 12–14 dic → **«📋 Publicar solicitud»** | `✓ Solicitud enviada — un administrador la revisará pronto` |
| 2 | superadmin | **«✓ Aprobar y publicar»** | — |
| 3 | empresa (Omar) | **«Hacer oferta»** con esa unidad → **«Enviar oferta»** | `✓ Oferta enviada al cliente` |
| 4 | cliente | **«✓ Aceptar $…»** → **«✓ Guardar y confirmar»** | un aviso que **nombra el documento vencido** — no «Acuerdo cerrado» |
| 5 | superadmin | **«Por aprobar»** → el acuerdo → **«✓ Aprobar acuerdo»** | `✓ Acuerdo aprobado. Reservación creada` |

**Después del paso 5, esto es lo que hay que mirar de verdad:**

1. En **«Reservaciones»** aparece la reserva **Activa** del 12 al 14 de diciembre.
2. **La campana del cliente tiene UN aviso de acuerdo cerrado, no dos.** Entra como
   cliente y cuéntalos. Es el detalle que más fácil se me pudo escapar: la RPC ya
   inserta ese par y yo retiré el que se insertaba a mano.
3. **La campana de la empresa, igual: uno, no dos.**
4. La solicitud queda en **`✓ Acordado`**.

**Si ves dos campanas iguales, no es grave pero es un fallo mío** — dímelo y lo
arreglo en un minuto.

### El caso de error, y por qué no te pido que lo provoques

El cambio también protege el fallo: si al aprobar el recurso ya estuviera reservado,
antes el pedido quedaba en **`acordado` sin reservación** (pasó de verdad hoy con
`d40dd97d`), y ahora la RPC revierte entera y no queda nada escrito.

Para provocarlo harían falta dos acuerdos solapados sobre la misma unidad, y **el
desplegable ya impide ofertar una unidad ocupada**, así que desde la interfaz no se
llega. Esa parte queda cubierta por la comprobación de la migración de H-06, que
apaga el trigger para probar cada capa por separado. No lo fuerces.

---

## Deshacer el montaje (2 min) — no lo dejes puesto

Repite los tres pasos del montaje poniendo en **«Seguro RC — vencimiento»** una
fecha **futura** —por ejemplo **31/12/2027**— y aprobándola como superadmin.

Si no lo deshaces, **todos los acuerdos de Omar seguirán pasando por tu cola** en
las pruebas siguientes, y el próximo que lea esto pensará que el cierre está roto
otra vez.

---

## Rastro

Queda una solicitud, su oferta y una reservación del 12 al 14 de diciembre, y la
unidad usada aparecerá ocupada esas fechas.
