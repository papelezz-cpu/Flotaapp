# Flujo operativo de PortGo

**Este documento es la fuente de verdad del negocio.** Describe qué hace cada
rol, en qué orden ocurren las cosas, y qué regla del motor lo impide cuando
algo no se puede.

Se lee **antes** de crear o modificar cualquier funcionalidad, para entender
cómo funciona ya el sistema, y se **actualiza** en el mismo commit que cambie
algo de lo que dice. Ver la regla #4 de `CLAUDE.md`.

Todo lo que sigue está **leído del esquema y del código**, no recordado. Cada
afirmación se puede rastrear a un CHECK, un guard trigger, una política RLS o
una línea concreta. Donde no hay evidencia, se dice.

Última verificación contra producción y `dev`: **11 de septiembre de 2026**, con
las seis migraciones de la ronda 2 ya aplicadas en ambas.

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

## Qué hace cada parte

Las diez etapas de más abajo cuentan el ciclo en orden. Esta sección lo cuenta
por actor: **qué ve, qué puede hacer, y qué no puede** — con quién se lo
impide, porque en este sistema casi nunca es la interfaz.

La visibilidad se decide con clases en `<body>` (`role-admin`,
`role-superadmin`) y las pantallas se listan en `C` dentro de `js/views.js`.
Pero eso es cosmética: **quien decide de verdad son las políticas RLS y los
guard triggers.** Ocultar un botón no protege nada.

### Cliente — `rol = 'cliente'`

Es quien tiene carga que mover. No posee recursos y nunca ejecuta un servicio.

**Sus pantallas:** Solicitar servicio · Mis solicitudes · Catálogo ·
Reservaciones · Mis pagos · Privacidad · Avisos.

**Puede:**

- Publicar solicitudes, siempre suyas y siempre en `pendiente_revision`
  (`ped_insert_own`), con fecha de carga de mañana en adelante.
- Guardar solicitudes frecuentes como plantillas — sin las fechas, a propósito.
- Ver el Catálogo de empresas y la ficha pública de cada una.
- Aceptar una oferta, o **contraofertar** un precio menor (máximo 2 rondas).
- Subir los documentos que le pida un expediente de viaje.
- Subir su propia evidencia de cierre, y **pedir** el cierre del servicio.
- **Solicitar** la cancelación — pedir, no cancelar.
- Calificar el servicio: una sola vez por reservación.
- Ejercer derechos ARCO sobre sus datos.

**No puede, y no por la interfaz:**

| Lo que no puede | Quién lo impide |
|---|---|
| Poner su pedido en `acordado` o `rechazado` por su cuenta | `guard_pedido_update` |
| Crearse una reserva ya confirmada y con precio puesto por él | `guard_reservacion_insert` |
| Tocar precio, unidad o fechas de una reserva | `guard_reservacion_update` |
| Subir la evidencia que le toca a la empresa | `guard_reservacion_update` |
| Aprobar su propio cierre o resolver su propia cancelación | `guard_reservacion_update` |
| **Pedir** un expediente de documentos | No tiene el botón: eso es de la empresa |
| Revisar o aceptar documentos de un expediente | `guard_expediente_documento` |
| Leer el perfil de otro usuario | RLS de `perfiles` — solo ve su fila |

### Empresa — `rol = 'admin'`

Es el transportista. Pone los recursos y ejecuta el servicio.

**Sus pantallas:** Solicitudes · Reservaciones · Mis unidades · Operadores ·
Vigencias · Mi desempeño · Cobros · Privacidad · Avisos.

**Puede:**

- Dar de alta camiones, custodios, patios, lavados y operadores — todos nacen
  en `aprobacion = 'pendiente'`.
- Mantener su **ficha pública** (Mis unidades → Perfil de empresa): años,
  unidades, permiso SCT, seguros, descripción.
- Ofertar sobre solicitudes en `abierto` o `en_negociacion`, y aceptar una
  contraoferta del cliente.
- Asignar chofer, avanzar el seguimiento y subir evidencia de cierre.
- **Pedir** expedientes de documentos al cliente, y aceptarlos o rechazarlos
  uno a uno.
- Mandar avisos fijos: documentos de carga, lugar y hora, retraso, cambio.
- **Cancelar** una reserva suya, directamente.
- Cobrar: registrar pagos y ver vencimientos.

**No puede:**

| Lo que no puede | Quién lo impide |
|---|---|
| Aprobarse sus propios recursos | `guard_fleet_resource_update` |
| Transferir un recurso a otro propietario | `guard_fleet_resource_update` |
| Ver solicitudes en `pendiente_revision` | `ped_select` — para ella no existen |
| Ofertar con permiso SCT o seguros vencidos | `openHacerOferta`, y de nuevo `guard_oferta_update` |
| Aceptar su propia oferta, salvo respondiendo una contraoferta | `guard_oferta_update` |
| Asignar a carga peligrosa un chofer sin licencia vigente | `guard_operador_hazmat` |
| Avanzar el seguimiento de un camión sin chofer asignado | La interfaz, en el primer paso |
| Subir evidencia antes del último paso del seguimiento | La interfaz |
| Aprobar el cierre de su propio servicio | `guard_reservacion_update` |
| Subir los documentos del expediente en lugar del cliente | `guard_expediente_documento` |

### Superadmin — `rol = 'superadmin'`

Control de PortGo. **No participa en la operación: la habilita y la desatasca.**

**Sus pantallas:** Por aprobar · Usuarios · Solicitudes · Reportes · Catálogo ·
Vigencias · Reservaciones · Historial · Cobros · Privacidad · Avisos.

**Cuatro cosas pasan por él, y solo cuatro:**

1. **Aprobar cuentas** — con verificación física o documental.
2. **Aprobar recursos** — flota y operadores, altas y ediciones.
3. **Aprobar y publicar solicitudes** — hasta entonces las empresas no las ven.
4. **Resolver los finales** — aprobar cierres y resolver cancelaciones pedidas
   por el cliente.

**Más dos salidas de emergencia**, que existen porque sin ellas alguien queda
encerrado:

- **Forzar un acuerdo** cuando la empresa tiene documentos vencidos
  (`pendiente_acuerdo`). Sin esto, esa empresa no podría cerrar nada.
- **Gestionar usuarios** con la Edge Function `gestionar-usuario`, que verifica
  el rol en el servidor y usa la clave de servicio.

**Lo que NO hace, y conviene tener claro:** no aprueba acuerdos. Desde el
2026-09-09, cuando las dos partes aceptan, la reserva se crea sola.

`is_superadmin()` le abre las ~70 políticas RLS del resto de tablas, y
`guard_*` le deja pasar en la primera línea de cada guard. **Es la única
identidad que los guards no cuestionan**, y por eso el trabajo de rutina no
debe hacerse con ella.

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

### Qué datos sobreviven al alta

El formulario de registro pide razón social, RFC y teléfono, pero los guarda
en `solicitudes_cuenta`. En `perfiles` solo escribe cuatro columnas: `user_id`,
`nombre`, `rol` y `aprobacion_cuenta`.

**Al aprobar, esos cuatro campos se copian a `perfiles`** — razón social, RFC,
teléfono y tipo de persona — y solo donde el perfil esté vacío, para que un
re-registro tras un rechazo no pise lo que la empresa ya haya editado.
Decidido el 2026-09-10.

Sin ese copiado, la empresa entregaba los datos, el superadmin los revisaba
para aprobarla, y su tarjeta del Catálogo nacía en blanco hasta que alguien
los tecleaba otra vez en **Mis unidades → Perfil de empresa**.

**Lo que sigue siendo tarea de la empresa:** años de operación, número de
unidades, permiso SCT, seguros y descripción. El registro no los pide, así que
una ficha recién aprobada está incompleta por diseño, no por fallo.

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

**Ningún servicio se puede pedir para el mismo día.** `js/pedidos.js` pone
`min = mañana` en los cuatro campos de fecha de alta (camión, custodio, patio,
lavado). Es una regla de negocio, no una validación del calendario: una
solicitud para hoy no le da margen a nadie para atenderla.

Consecuencia práctica: **una solicitud con fecha pasada no se puede crear desde
la app**, ni siquiera para probar. Hay que crearla con la fecha más temprana
que admita y retrasarla luego por SQL, apartando `trg_guard_pedido_update`.

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

**No hay punto intermedio.** El pedido no se queda en `en_negociacion` con una
oferta ya aceptada: eso solo lo producía el flujo viejo, cuando aceptar eran
tres escrituras sueltas y la pestaña podía cerrarse entre una y otra. La regla
(c) de `sincronizar_estados_pedidos()` sigue ahí para reparar esas filas
históricas, no porque el flujo actual las genere.

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

## Cómo se hablan entre ellos

**No hay chat.** El texto libre entre cliente y empresa se retiró a propósito y
se sustituyó por botones fijos que escriben una fila en `notificaciones`:
documentos de carga, lugar y hora, retraso y reporte de cambio
(`js/reservaciones.js`). La tabla `mensajes` sigue existiendo con sus políticas
y su RPC, pero **la PWA no la usa**: está para el contrato móvil.

Esto no es una limitación técnica, es una decisión: un aviso con forma fija
queda registrado, es auditable y no se presta a acordar cosas por fuera del
sistema.

Quién puede avisar a quién lo decide el RLS de `notificaciones`, y es
**restringido por relación**: solo puedes notificarte a ti mismo, a los
superadmins, o a la contraparte de tu reservación u oferta. Un flujo de aviso
nuevo tiene que encajar en una de esas tres, o hacerse desde un trigger.

Los avisos al superadmin van por `notificar_superadmins()`, que es la llamada
más repetida del código (15 sitios). Los de oferta y reserva los disparan
triggers de la base, no el navegador: así llegan aunque la pestaña se cierre.

Cada usuario puede silenciar **correos** por tipo (`perfiles.notif_email`),
pero **nunca la campana ni el correo transaccional** — ver `TIPOS_SILENCIABLES`
en la Edge Function `enviar-notificacion`.

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
4. **El estado de los pedidos avanza por dos vías a la vez.** Desde el
   2026-09-11, `sincronizar_estados_pedidos()` corre en pg_cron cada 15
   minutos en producción y en pruebas — pero las reglas equivalentes siguen
   en `renderPedidos()`. **Se dejaron a propósito:** son idempotentes y
   coinciden con las del cron, así que da igual quién las corra, y mientras
   estén las dos un fallo del cron no congela los estados. Retirarlas del
   navegador es decisión posterior, cuando el cron lleve tiempo funcionando.
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
7. **De las 11 RPC transaccionales, 6 se usan.** En uso:
   `cancelar_reservacion`, `solicitar_cancelacion`, `registrar_evidencias`,
   `avanzar_tracking`, `abrir_expediente` y `calificar_servicio`. Sin usar:
   `enviar_oferta`, `responder_oferta`, `responder_contraoferta`,
   `enviar_mensaje` y `recomendar_unidad` — esos caminos los sigue
   orquestando el navegador paso a paso, sin atomicidad.
   (`aceptar_y_cerrar_acuerdo`, `notificar_superadmins` e `ids_superadmins`
   también se usan, pero son posteriores y no formaban parte de esas 11.)

---

## Cómo mantener este documento

**Se lee antes de construir.** Cualquier funcionalidad nueva, o cualquier
cambio a una existente, empieza por entender qué hace ya el sistema: qué rol
la ejecuta, en qué estado tiene que estar la fila, y qué guard la vigila. Casi
todo lo que parece un hueco ya está resuelto en alguna parte, y casi todo lo
que parece fácil choca con un guard.

**Se actualiza en el mismo commit que lo cambia.** No después, no en una tarea
aparte. Un documento que describe el flujo de hace tres semanas es peor que no
tenerlo, porque se cree.

Qué obliga a tocarlo: un estado nuevo o retirado, un permiso que cambia de
rol, un guard nuevo o modificado, un paso que se añade o se salta, una
pantalla que aparece o muere, y cualquier decisión de negocio que se tome en
una conversación — esas son las que se pierden.

**Si al leerlo algo no cuadra con el código, gana el código** — y hay que
corregir el documento acto seguido, nunca ajustar el código a lo que dice el
papel.

Cada afirmación de aquí sale de un `CHECK`, una política, un guard o una línea
concreta. Al añadir algo, decir de dónde sale; si no se pudo verificar,
decirlo también. Una frase sin respaldo envenena el resto: si una es de
memoria, ninguna es fiable.
