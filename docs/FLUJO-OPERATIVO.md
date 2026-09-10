# Flujo operativo de PortGo

**Este documento es la fuente de verdad del negocio.** Describe qué puede hacer
cada rol, en qué orden, y qué regla del motor lo impide cuando no puede.

Todo lo que sigue está **leído del esquema y del código**, no recordado. Cada
afirmación se puede rastrear a un CHECK, un guard trigger, una política RLS o
una línea concreta. Donde no hay evidencia, se dice.

Última verificación contra el volcado de producción y `dev`: **10 de septiembre
de 2026**.

---

## Los tres roles

`perfiles.rol` solo admite tres valores (`perfiles_rol_check`):

| Rol | Quién es | Qué hace |
|---|---|---|
| `cliente` | Quien necesita mover carga | Publica solicitudes, acepta ofertas, contraoferta, sube documentos de viaje, califica |
| `admin` | La empresa transportista | Da de alta flota y operadores, oferta, ejecuta el servicio, pide documentos, cobra |
| `superadmin` | Control PortGo | Aprueba cuentas, recursos y solicitudes; resuelve cancelaciones y finalizaciones; desbloquea lo que el sistema frena |

`perfiles.aprobacion_cuenta` ∈ `null` (activa) · `pendiente` · `rechazada` ·
`suspendida`. **No tiene CHECK**: cualquier texto entra. `null` significa activa.

---

## Estados canónicos

Salen de los `CHECK` de la base. Si un estado no está aquí, no existe.

**`pedidos.estado`** — `pendiente_revision` · `abierto` · `en_negociacion` ·
`pendiente_acuerdo` · `acordado` · `finalizado` · `cancelado` · `rechazado` ·
`expirado`

**`ofertas.estado`** — `enviada` · `contra_oferta` · `aceptada` · `rechazada`
（`ronda` solo admite 1 o 2)

**`reservaciones.estado`** — `Pendiente` · `Activa` · `PorAprobar` ·
`CancelacionSolicitada` · `Completada` · `Cancelada` · `Rechazada`

**`reservaciones.recurso_tipo`** — `camion` · `custodio` · `patio` · `lavado`

**`expedientes`** — `etapa` ∈ `ingreso_puerto` · `entrega_vacios`;
`estado` ∈ `solicitado` · `en_revision` · `completo`

**`expediente_documentos.estado`** — `pendiente` · `subido` · `aceptado` ·
`rechazado`

**Flota** (`camiones`, `custodios`, `patios`, `lavados`, `operadores`) —
`estado` ∈ `disponible` · `ocupado` · `no_disponible`;
`aprobacion` ∈ `pendiente` · `aprobada` · `rechazada`

---

## 1. Alta de cuenta

```
CLIENTE/EMPRESA se registra
  → auth.users + perfiles(aprobacion_cuenta='pendiente') + solicitudes_cuenta('pendiente')
SUPERADMIN aprueba
  → perfiles.aprobacion_cuenta = null   (cuenta activa)
```

Las **tres** escrituras tienen que ocurrir. Si el perfil no se crea, la cuenta
queda inutilizable: la app decide el rol leyendo `perfiles`, así que sin fila no
se puede entrar aunque la solicitud esté aprobada.

**El globo de «Por aprobar» cuenta `perfiles.aprobacion_cuenta = 'pendiente'`,
no `solicitudes_cuenta`.** Si los dos números no coinciden, hay altas a medias.

El superadmin aprueba con verificación física o sin ella; eso escribe
`verificado` y `metodo_verificacion` ∈ `fisica` · `documental`.

---

## 2. Alta de recursos

Flota y operadores nacen en `aprobacion = 'pendiente'` y no sirven para nada
hasta que el superadmin los aprueba.

`guard_fleet_resource_update` vigila **solo dos cosas**: que nadie que no sea
superadmin cambie `aprobacion` a algo distinto de `pendiente`, y que nadie
transfiera `propietario_id`. Todo lo demás lo puede editar el dueño.

Editar un recurso aprobado lo devuelve a revisión: `es_edicion`,
`campos_editados` y `snapshot_anterior` guardan qué cambió para que el
superadmin lo compare.

### Fechas de vigencia

`js/vigencias.js` vigila `fecha_vencimiento`, `fecha_examen_medico`,
`fecha_examen_toxicologico` y `fecha_carta_antecedentes` filtrando con `.lte.`.
**Un campo nulo no entra nunca en esa comparación.**

Consecuencia: un documento sin fecha no se vigila jamás. El papel está, nadie
comprueba si sigue vigente, y el panel dice que todo está en orden. Por eso el
alta de operador exige las cuatro fechas junto con sus documentos.

---

## 3. Solicitud de servicio

```
CLIENTE publica          → pedidos.estado = 'pendiente_revision'
SUPERADMIN aprueba       → 'abierto'      ← recién aquí la ven las empresas
```

**Una solicitud en `pendiente_revision` no existe para las empresas.** La
política `ped_select` solo les deja ver las que están en `abierto` o
`en_negociacion`, o aquellas donde ya ofertaron. Si una empresa «no ve» una
solicitud, esto es lo primero que hay que mirar.

`ped_insert_own` obliga a que un cliente solo pueda crear pedidos suyos y
siempre en `pendiente_revision`.

### Categorías de carga

Deciden qué campos pide el formulario, y de eso dependen cosas más abajo:

| Categoría | Campos | ¿Abre expediente de vacíos? |
|---|---|---|
| General | peso, tarimas, contenedores, refri | Solo si se eligió tipo de contenedor |
| Contenerizada | peso, contenedores, refri | Siempre |
| Consolidada | peso, tarimas, refri | Nunca |
| Suelta | peso, tarimas, bultos, refri | Nunca |
| Sobredimensionada | peso, dimensiones | Nunca |
| Hazmat | peso, clase y UN | Nunca |

---

## 4. Negociación

```
EMPRESA oferta           → ofertas('enviada'), pedido → 'en_negociacion'
CLIENTE contraoferta     → 'contra_oferta'  (máximo 2 rondas)
```

`ofertas.expira_en` son 2 días por defecto. El cron `expire-stale-offers` corre
cada hora y marca `rechazada` las vencidas.

**Una empresa con documentos vencidos no puede ofertar.** `openHacerOferta`
comprueba las tres fechas del perfil antes de listar camiones: si alguna pasó,
vacía el desplegable y desactiva el botón. Es la primera de dos capas.

---

## 5. Cierre del acuerdo

**Cuando las dos partes aceptan, la reserva se crea. El superadmin no
interviene.** Decidido el 2026-09-09.

```
CLIENTE acepta la oferta        ─┐
                                 ├→ aceptar_y_cerrar_acuerdo()
EMPRESA acepta la contraoferta  ─┘     → oferta 'aceptada'
                                       → pedido 'acordado'
                                       → reservación 'Activa' con precio
                                       → demás ofertas 'rechazada' + aviso
```

Todo en una transacción. Si algo falla, no queda nada a medias.

**La excepción son los documentos vencidos.** `guard_oferta_update` bloquea la
aceptación con `DOCUMENTOS_VENCIDOS` si la empresa que emitió la oferta tiene
vencido el permiso SCT, el seguro RC o el seguro de carga. Entonces:

```
→ pedido 'pendiente_acuerdo', aviso al superadmin
→ el superadmin puede forzarlo: se le advierte y decide
```

Ese control **avisa pero no encierra**: sin la salida del superadmin, una
empresa con un papel vencido quedaría atrapada sin forma de desbloquearse.

### La unidad ocupada

`cerrar_acuerdo` marca el recurso `ocupado` **solo si `fecha_ini <= hoy`**. Un
viaje que empieza la semana que viene deja la unidad `disponible`, y eso es
correcto: hoy está libre.

La doble reserva **no depende de ese campo**. La impide
`reservaciones_sin_solape`, un `EXCLUDE` con GiST sobre unidad y rango de
fechas, activo para `Pendiente` y `Activa`.

> ⚠ **Hueco conocido:** nada marca la unidad `ocupado` cuando llega su fecha.
> Los cuatro puntos que lo hacen exigen `fecha_ini <= hoy` y ninguno vuelve a
> mirar después. El catálogo muestra como libre un camión en ruta. No hay
> riesgo de doble reserva; es un problema de visualización.

---

## 6. Reservación y seguimiento

Cinco pasos, **distintos por tipo de recurso**:

| Tipo | Secuencia |
|---|---|
| camión | Confirmado → En camino → En carga → En tránsito → **Entregado** |
| custodio | Confirmado → Asignado → En ruta → En servicio → **Finalizado** |
| patio | Confirmado → Listo → Recibido → En almacenaje → **Liberado** |
| lavado | Confirmado → Recibido → En lavado → Control → **Listo** |

Definidos en `TRACKING_POR_TIPO` (js/tracking.js) y duplicados en la función SQL
`tracking_pasos()`. **Cambiar uno obliga a cambiar el otro.**

Reglas encadenadas:

- **Sin chofer no se avanza del primer paso** (solo camiones). El botón es
  «👷 Asignar chofer».
- Al llegar al último paso, `avanzar_tracking` **abre solo el expediente de
  vacíos** si el pedido era `Contenerizada` o traía contenedores.

---

## 7. Expedientes documentales

Dos etapas, y se comportan distinto:

| Etapa | Cómo se abre | Quién |
|---|---|---|
| `ingreso_puerto` | A mano, botón «🛃 Solicitar · Puerto» | Solo la empresa |
| `entrega_vacios` | **Sola**, al llegar al último paso del tracking | El sistema |

El cliente **nunca ve el botón de solicitar** — pedir documentos es cosa de la
empresa. Solo ve la pastilla del expediente ya abierto, y al pulsarla se abre un
modal con el checklist.

El checklist se **copia** de `documentos_catalogo` al crear el expediente, nunca
se referencia. Editar el catálogo no reescribe expedientes pasados.

`abrir_expediente` es idempotente: `UNIQUE(reserva_id, etapa)` garantiza una
sola por etapa, y un segundo intento devuelve la existente.

En `entrega_vacios` corren las **demoras** a partir de `fecha_limite_vacios`.
Ahí es donde está el dinero.

---

## 8. Cierre del servicio

```
EMPRESA sube evidencia   → requiere tracking en el ÚLTIMO paso
CLIENTE sube la suya     → sin esa restricción
Ambas partes             → reserva 'PorAprobar'
SUPERADMIN aprueba       → 'Completada'
CLIENTE califica         → 1 sola vez (UNIQUE parcial por reservación)
```

Cada parte sube su propia evidencia: `evidencias` (empresa) y
`evidencias_cliente` (cliente), las dos arrays de **rutas** de Storage.

La restricción del último paso es **solo para la empresa al solicitar el
cierre**. Tiene sentido: no se cierra un servicio que no llegó.

`calificar_servicio` deriva el `admin_id` del propietario de la reserva, no de
lo que mande el navegador.

---

## 9. Cancelación

Dos caminos distintos, y conviene no confundirlos:

| Quién | Botón | Qué pasa |
|---|---|---|
| **Empresa** (dueña) | «Cancelar» | Cancela directo: libera el recurso y reabre el pedido |
| **Cliente** | «Solicitar cancelación» | Pide, y el superadmin resuelve |

Cuando el cliente solicita, `solicitar_cancelacion` **congela el punto del
viaje** en `cancelacion_tracking_estado`. No es un dato decorativo: al cancelar,
el camión puede estar parado en el patio o a mitad de carretera, y **esa
diferencia decide quién paga qué**. Si la empresa siguiera avanzando el
seguimiento, el superadmin ya no sabría dónde estaba.

Cancelar un acuerdo cerrado **invalida las ofertas** y marca
`permite_reoferta = false` para quien canceló: no puede volver a ofertar en esa
misma solicitud.

---

## 10. Cobro

Estado **derivado, nunca almacenado**. `estadoCobro()` lo calcula desde `pagado`
y `fecha_vencimiento_pago`, así que no hay tarea diaria que pueda quedarse
atrás.

`plazo_pago` se copia del pedido a la reservación al cerrar el acuerdo: el
plazo pactado no cambia porque el cliente edite su perfil después.

---

## Quién puede cambiar qué

Los **guard triggers** son la capa que RLS no puede dar. RLS decide *si* puedes
escribir una fila; los guards deciden *qué transición* es legal para ti.

| Guard | Sobre | Qué impide |
|---|---|---|
| `guard_pedido_update` | pedidos | Que un cliente marque `acordado`/`rechazado` sin pasar por el flujo; que un admin toque un pedido fuera de negociación |
| `guard_oferta_update` | ofertas | Aceptar con documentos vencidos; aceptar la oferta propia salvo respondiendo una contraoferta |
| `guard_reservacion_insert` | reservaciones | Que un cliente se cree una reserva ya confirmada y con precio puesto por él |
| `guard_reservacion_update` | reservaciones | Que el cliente toque precio, unidad o fechas; que suba la evidencia de la empresa; que cualquiera de los dos apruebe su propio cierre o resuelva su propia cancelación — eso lo hace el superadmin |
| `guard_fleet_resource_update` | flota | Auto-aprobarse un recurso; transferir la propiedad |
| `guard_perfil_self_update` | perfiles | Cambiarse el rol, el estado de aprobación de la cuenta o los campos de verificación |
| `guard_expediente_documento` | expediente_documentos | Que cada parte haga el trabajo de la otra: **solo el cliente sube**, **solo el transportista revisa** |
| `guard_operador_hazmat` | ofertas, reservaciones | Asignar a carga peligrosa un chofer sin licencia vigente |

**Todos leen `auth.uid()`**, así que siguen aplicando dentro de funciones
`SECURITY DEFINER`. Una transición ilegal revierte la transacción entera.

### Consecuencia que muerde

`psql` conecta **sin JWT**, así que `auth.uid()` es NULL y ningún guard te
reconoce. **Cualquier corrección de datos por SQL sobre una tabla con guard
falla con «No autorizado»**, y hay que apartar el trigger a propósito para esa
transacción.

Ya ocurrió dos veces: con la corrección de `refrigerado` y con la
sincronización de estados por cron.

---

## Cosas que no se ven, y hacen perder tiempo

Ninguna es un fallo; todas confunden si no se saben.

- **Los botones de acción viven detrás del `▾`** de cada fila de reservación.
  Los grupos *Documentos*, *Avisos* y *Cierre* no se dibujan si está plegada.
- **Las pastillas de filtro se traducen a un `WHERE estado = …`**, así que al
  cambiar de estado la reserva **sale de la lista**, no queda en gris.
- **Un botón que se convierte en texto suele ser la confirmación de que algo se
  guardó.** «⏳ Esperando aprobación» aparece porque hay evidencia; el botón de
  subir aparece porque no la hay.
- **La sesión vive en `sessionStorage`, que es por pestaña.** Dos pestañas dan
  dos sesiones distintas — útil para probar dos roles a la vez, siempre que la
  segunda se abra en blanco y no desde un enlace.

---

## Huecos conocidos

Verificados, sin resolver, y no deben confundirse con fallos nuevos:

1. **Nada marca la unidad `ocupado` al llegar su fecha** (ver §5).
2. **`perfiles.aprobacion_cuenta` no tiene CHECK**: acepta cualquier texto.
3. **`is_superadmin()` no se salta el RLS de `perfiles`.** Funciona en las ~70
   políticas de otras tablas; en una política *de perfiles* provoca recursión.
   Por eso lee de una vista interna.
4. **El estado de los pedidos avanza al pintar la lista** en el navegador. La
   migración que lo baja a pg_cron existe y está pendiente de aplicarse.
5. **`mensajes` no la usa la PWA.** Existe para el contrato móvil.
6. **El listado de camiones y el detalle de unidad son código muerto.** En
   `app.html`, `#truck-grid` y `#stats-row` viven dentro del Catálogo con
   `display:none` y el comentario «elementos ocultos referenciados por JS
   legacy». `renderCamiones()`, `renderCustodios()` y `renderPatios()` siguen
   pintando ahí dentro, y `openDetail()` — el modal con las pestañas
   **Unidad / Empresa / Disponibilidad** — solo se abre desde el botón «Ver
   detalle» de esas tarjetas invisibles. Nada en `app.html` llama a
   `cambiarTipoRecurso()`. **No hay forma de abrir una unidad por su ficha
   desde la app**; el Catálogo muestra empresas, no unidades. Las funciones
   se conservan porque `modal.js` aún invoca `filtrarRecursos()` al reservar.
7. **Las 11 RPC transaccionales: 7 en uso.** Quedan fuera `enviar_oferta`,
   `responder_oferta`, `responder_contraoferta` y `enviar_mensaje`.

---

## Cómo mantener este documento

Cuando una regla de negocio cambie, **se actualiza aquí en el mismo commit**.
Un documento que describe el flujo de hace tres semanas es peor que no tenerlo:
se cree.

Si al leerlo algo no cuadra con el código, **gana el código** — y hay que
corregir el documento, no ajustar el código a lo que dice el papel.
