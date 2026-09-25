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

**Alcance: la plataforma web.** Es lo primero que sale, y lo que este documento
describe. Las aplicaciones móviles se construyen después, cuando la web funcione
por completo — así que **nada se diseña hoy «para móvil más adelante»** ni se
justifica dejando código preparado para un cliente que aún no existe.
Decidido el 2026-09-11.

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

### Custodios, patios y lavados están apagados en la interfaz

**Todo lo que este documento cuenta sobre custodios, patios y lavados describe
un producto que hoy el usuario no puede tocar.** No está retirado del esquema
ni de la lógica: está oculto con CSS, en un bloque de `css/base.css` rotulado
*«Custodios / Patios / Lavados — deshabilitados temporalmente»* que aplica
`display: none !important` a:

- las píldoras de filtro de Solicitudes y de Catálogo (`[data-tipo=…]`,
  `[data-filter=…]`),
- los botones de alta de ese tipo de solicitud (`openNuevoPedido('custodio')`
  y sus dos hermanos),
- las pestañas y paneles de esos recursos en Mis unidades,
- los modales de edición y el de rechazo de recurso,
- las secciones del formulario de solicitud (`#np-group-custodio`, `-patio`,
  `-lavado`).

**Qué sigue vivo por debajo**, y por eso el resto del documento no se retira:
las tablas, el RLS, los guards, las cuatro secuencias de `tracking_estado` por
`recurso_tipo`, las colas de aprobación y los pedidos ya existentes de esos
tipos — que **se siguen pintando** en la lista bajo «Todos», porque lo apagado
es el filtro, no la tarjeta.

**Consecuencia práctica al probar:** de las cinco píldoras de tipo, solo
**Todos** y **Camión** son pulsables. Verificado el 2026-09-18 en el DOM del
preview: las cinco existen, y `custodio`, `patio` y `lavado` salen con
`offsetParent === null` y ancho 0. Un plan de pruebas que las incluya manda a
alguien a buscar botones que no están — pasó ese mismo día, por no tener esto
escrito aquí.

### Cliente — `rol = 'cliente'`

Es quien tiene carga que mover. No posee recursos y nunca ejecuta un servicio.

**Sus pantallas:** Solicitar servicio · Mis solicitudes · Catálogo ·
Reservaciones · Mis pagos · Privacidad · Avisos.

**Puede:**

- Publicar solicitudes, siempre suyas y siempre en `pendiente_revision`
  (`ped_insert_own`), con fecha de carga de mañana en adelante.
- Guardar solicitudes frecuentes como plantillas — sin las fechas, a propósito.
  Desde el 2026-09-15 los valores viven en `plantillas_pedido.datos` (jsonb), no
  en 49 columnas que copiaban el esquema de `pedidos`: **añadir un campo al
  formulario ya no necesita migración**. Es el único sitio del esquema donde
  `jsonb` está justificado — esos valores no se filtran, no se agregan y no se
  unen con nada, solo se recuperan enteros para rellenar el formulario. Las 49
  columnas siguen en la tabla, sin que nadie las escriba, como red para revertir.
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
- Mantener su **ficha pública** (Mis unidades → Perfil de empresa): razón
  social, RFC, teléfono, años, unidades, descripción.
- **Proponer** sus documentos legales — permiso SCT, seguro RC, seguro de
  carga — cada uno con su número, su vigencia y su archivo. Los propone, no
  los acredita: ver *Los seguros se acreditan, no se declaran*.
- Ofertar sobre solicitudes en `abierto` o `en_negociacion`, y aceptar una
  contraoferta del cliente.
- Filtrar la lista de Solicitudes por **tipo de servicio** —en la interfaz
  hoy solo se ven **Todos** y **Camión**; las píldoras Custodia, Patio y
  Lavado existen en el HTML pero están ocultas, ver *Custodios, patios y
  lavados están apagados en la interfaz*— y por **zona** (texto libre contra
  `origen`,
  `destino` y `zona_cobertura`). Desde el 2026-09-18 los dos filtros se
  aplican **en la consulta, no sobre la página ya descargada** — antes
  filtraban solo las 30 filas traídas, así que pedir un tipo podía devolver
  vacío habiendo solicitudes de ese tipo más abajo.
  **Con qué rol se nota, y con cuál no:** el superadmin lanza además una
  consulta paralela de acuerdos con `limit 100`, así que con poco volumen ya
  se trae el histórico entero y el defecto no se le manifiesta. Se manifiesta
  en el rol empresa, cuya lista es solo la página de 30. Medido el 2026-09-18
  sobre esa página: Custodia 0 de 4, Patio 0 de 1, Camión 30 de 36. La
  equivalencia entre el filtro viejo y el nuevo sí está comprobada en 85 casos
  (`pruebas/10-sonda-filtros-pedidos.mjs`); que el arreglo *cambie lo que se
  ve* pide más volumen del que había ese día. El grupo
  «Camión» se define **por negación** de los otros tres, no por una lista de
  tipos: el catálogo vive en la tabla `catalogos` y crece sin avisar.
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
| **Acreditarse sus propios seguros o su permiso SCT** — ni marcarlos, ni ponerse una vigencia | `guard_perfil_self_update` |
| Ver solicitudes en `pendiente_revision` | `ped_select` — para ella no existen |
| Ofertar con permiso SCT o seguros vencidos | `openHacerOferta`, y de nuevo `guard_oferta_update` |
| Aceptar su propia oferta, salvo respondiendo una contraoferta | `guard_oferta_update` |
| Asignar a carga peligrosa un chofer sin licencia vigente | `guard_operador_hazmat` |
| **Cerrar un trato de carga peligrosa con una unidad sin permiso hazmat vigente** | `guard_oferta_update` — y aquí «sin permiso» cuenta igual que «vencido» |
| Avanzar el seguimiento de un camión sin chofer asignado | La interfaz, en el primer paso |
| Subir evidencia antes del último paso del seguimiento | La interfaz |
| Aprobar el cierre de su propio servicio | `guard_reservacion_update` |
| Subir los documentos del expediente en lugar del cliente | `guard_expediente_documento` |

### Superadmin — `rol = 'superadmin'`

Control de PortGo. **No participa en la operación: la habilita y la desatasca.**

**Sus pantallas:** Por aprobar · Usuarios · Solicitudes · Reportes · Catálogo ·
Vigencias · Reservaciones · Historial · Cobros · Privacidad · Avisos.

**En Solicitudes no ve las canceladas ni las rechazadas, y es deliberado.**
La pantalla arma tres secciones —*Solicitudes activas* (`abierto`,
`en_negociacion`, `pendiente_revision`, `pendiente_acuerdo`), *Acuerdos
activos* (`acordado`) y *Finalizados y expirados*— y `cancelado` y `rechazado`
no caen en ninguna. Medido el 2026-09-18: de 41 solicitudes, 15 estaban en
esos dos estados y no se pintaban en ningún sitio, así que la pantalla
enseñaba 26. **Decisión del 2026-09-18: se deja como está** — a un rol que
monitorea no le aporta la cola de lo ya muerto. Queda escrito porque, sin
esto, la próxima vez que alguien cuente las tarjetas va a creer que falta
una sección.

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

### El globo cuenta once colas, y son las que el panel lista

El número rojo de «Por aprobar» sale de `cola_superadmin()` — una sola llamada
que devuelve el desglose y el total. El panel (`renderAprobaciones()`) carga
**once** colas, y la función cuenta **esas once**, ni una más ni una menos:

| Cola | De dónde sale |
|---|---|
| Cuentas | `perfiles.aprobacion_cuenta = 'pendiente'` **∪** `solicitudes_cuenta.estado = 'pendiente'` |
| Camiones · Operadores · Custodios · Patios · Lavados | `aprobacion = 'pendiente'` en cada tabla |
| Solicitudes | `pedidos.estado = 'pendiente_revision'` |
| Acuerdos forzados | `pedidos.estado = 'pendiente_acuerdo'` |
| Documentos de empresa | `perfiles.perfil_docs_pendiente` |
| **Cierres** | `reservaciones.estado = 'PorAprobar'` |
| Cancelaciones | `reservaciones.estado = 'CancelacionSolicitada'` |

**Que coincidan no es cosmética.** Un globo oculto y una cola vacía se ven
exactamente igual, así que una cola que el globo no cuenta es una cola que
nadie tiene motivo para ir a mirar. Hasta el 2026-09-18 los cierres en
`PorAprobar` eran justo eso: el panel los listaba y el globo no los veía.

**Las cuentas se cuentan de dos tablas a propósito.** El panel lista
`solicitudes_cuenta`, pero contar solo eso perdería un perfil `pendiente` sin
solicitud —el alta que se cortó a la mitad, ver §1—, y esa persona no puede
entrar y nadie se entera. La unión no se queda corta por ningún lado, y el
`UNION` por `user_id` evita contar dos veces el caso normal.

Si se añade una cola al panel, **se añade también a la función**, o el número
vuelve a mentir. Es lo único que hay que recordar de esta sección.


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
unidades, descripción, y **subir sus documentos legales**. El registro no los
pide, así que una ficha recién aprobada está incompleta por diseño, no por
fallo.

### Los seguros se acreditan, no se declaran

Hasta el 2026-09-15, la tarjeta *Perfil de empresa* hacía la misma pregunta dos
veces con rigor distinto: arriba una **casilla** «Seguro RC» y el número de
permiso en texto libre, abajo el bloque *Documentos legales* con archivo, fecha
y revisión del superadmin. **El catálogo leía la de arriba.** Es decir, el chip
`Seg. RC ✓` que veía el cliente significaba *«la empresa marcó una casilla»*, no
*«alguien vio la póliza»*, y las dos cosas se veían idénticas.

Y el camino riguroso **no premiaba**: rellenarlo no añadía ningún distintivo,
solo podía quitártelo al vencer. Por eso las tres empresas de producción tenían
cero fechas y cero documentos, y por eso `pendiente_acuerdo` era inalcanzable —
`guard_oferta_update` compara `IS NOT NULL AND < current_date`, y con todo a
NULL no dispara nunca.

Desde `20260915120000_los_seguros_se_acreditan_no_se_declaran`:

- **La casilla no existe.** `guardarPerfilEmpresa()` ya no envía `seguro_rc`,
  `seguro_carga` ni `permiso_sct`, y el número de permiso vive junto a su fecha
  y su archivo.
- **La fuente de verdad es la fecha de vigencia**, y solo la escribe
  `aprobarDocsEmpresa()` al promover un documento revisado. Por eso el catálogo
  puede confiar en ella sin ver el documento: le basta `empresas_publico`.
- **`guard_perfil_self_update` sostiene todo lo demás.** RLS deja a la empresa
  actualizar su propia fila, así que sin ese guard bastaba una llamada al API
  —sin pasar por ninguna pantalla— para ponerse una vigencia inventada. Bloquea
  las seis columnas reales; las `*_pendiente` siguen abiertas, que es donde la
  empresa propone.
- **El booleano dice que hay documento aprobado. Que esté vigente lo dice la
  fecha**, que cambia sola con el calendario y por eso no cabe en un booleano.

> ⚠ **Ojo:** `camiones.fecha_vencimiento_permiso_sct` es otra cosa — el permiso
> del camión, no el de la empresa. No lo toca nada de esto.

---

## 2. Alta de recursos

Flota y operadores nacen en `aprobacion = 'pendiente'` y no sirven para nada
hasta que el superadmin los aprueba.

`guard_fleet_resource_update` vigila **solo dos cosas**: que nadie que no sea
superadmin cambie `aprobacion` a algo distinto de `pendiente`, y que nadie
transfiera `propietario_id`. Todo lo demás lo puede editar el dueño.

**Todo recurso tiene dueño, y es obligatorio.** Desde el 2026-09-24
`propietario_id` es `NOT NULL` en las cinco tablas de flota
(`20260924140000_recursos_con_dueno_obligatorio.sql`). Antes admitía nulos y
había siete recursos sin dueño —era el hueco 9, ahora cerrado—; los siete se
asignaron a **Omar Silva Preciado** por decisión del usuario ese mismo día.

Por qué importa más de lo que parece: `vigencia_propietario()` devuelve `NULL`
para un recurso sin dueño, y la política `vigencia_propietario(...) = auth.uid()`
compara contra `NULL`, que **nunca da verdadero**. Un recurso huérfano tenía sus
documentos visibles solo para el superadmin y **ninguna empresa podía
renovarlos**.

Editar un recurso aprobado lo devuelve a revisión: `es_edicion`,
`campos_editados` y `snapshot_anterior` guardan qué cambió para que el
superadmin lo compare.

### Fechas de vigencia

`js/vigencias.js` vigila `fecha_vencimiento`, `fecha_examen_medico`,
`fecha_examen_toxicologico` y `fecha_carta_antecedentes` filtrando con `.lte.`.
**Un campo nulo no entra nunca en esa comparación.**

Consecuencia: un documento sin fecha no se vigila jamás. El papel está, nadie
comprueba si sigue vigente, y el panel dice que todo está en orden.

#### Todo papel se sube con su fecha (decisión del usuario, 2026-09-24)

La regla ya iba en un sentido —**no se acredita una vigencia sin enseñar el
documento**, el candado de [js/admin.js:534](../js/admin.js)— y ahora va en los
dos: **adjuntar un papel sin su fecha de vencimiento queda rechazado**, en los
cinco sitios donde se podía:

| Formulario | Qué exigía antes | Qué exige ahora |
|---|---|---|
| Alta de camión | los papeles de TC, SCT y seguro; **ninguna de sus fechas** | la fecha de cada papel que se adjunte |
| Edición de camión | fecha ⇒ papel | y también papel ⇒ fecha |
| Perfil de empresa | «al menos una fecha» de las tres | la fecha de cada documento que se adjunte |
| Alta de operador | las cuatro fechas | y también la de la licencia hazmat, si se adjunta |

De ahí salían los **14 documentos con papel y sin vencimiento** que la Etapa 2
de H-04 hizo visibles: el alta de camión pedía tres documentos obligatorios y
ninguna de sus fechas.

> ⚠ **Esto no arregla los 14 que ya existen.** No se pueden rellenar inventando
> fechas: es el dato que después alguien mira para decidir si una unidad puede
> trabajar. Siguen ahí hasta que alguien los complete con el papel delante. La
> regla nueva evita que el número crezca.

#### El catálogo público ya lee la tabla `vigencias` (H-04, 2026-09-23)

El distintivo que el cliente ve en el catálogo de proveedores («SCT ✓»,
«Seg. RC ⛔ vencido», «✅ Docs al día») sale de la vista `empresas_publico`, y
desde la Etapa 4 esa vista toma las tres fechas de la **fila `vigente` de
`vigencias`**, no de las columnas de `perfiles`. Consecuencias de negocio:

- **Una propuesta no acredita.** Solo cuenta la fila en estado `vigente`; una
  en `pendiente` —lo que la empresa sube desde *Perfil de empresa → Enviar
  documentos para aprobación*— no pinta ningún distintivo hasta que el
  superadmin la acredita. Es la misma regla de H-02, ahora sostenida también
  del lado de la lectura.
- **El espejo de `vigencias` volvió a ser estricto.** Si el reflejo de un
  documento falla, la escritura de origen falla entera y el usuario ve el
  error: guardar un camión, dar de alta un operador o acreditar un perfil se
  cae en vez de guardarse a medias. Durante las Etapas 3b y 3c era al revés
  —se guardaba y la divergencia quedaba anotada—, y se cambió porque ya hay
  una pantalla que depende de esa tabla: un fallo callado sería un distintivo
  mal mostrado a un cliente.

### Una fecha de vigencia de camión no se puede vaciar desde la interfaz

Verificado el 2026-09-22 leyendo el código, después de que un guion de pruebas
pidiera hacerlo y resultara imposible para todos los roles:

- **La empresa** llega al formulario (*Mis unidades → ✏ Editar*), pero el
  candado de [js/admin.js:534](../js/admin.js) le exige adjuntar el documento
  renovado *en cuanto la fecha cambia* — y borrarla cuenta como cambio. El
  mensaje es «Para renovar la vigencia de … debes adjuntar el documento
  renovado», que describe la renovación y no el borrado, pero corta los dos.
- **El superadmin** se salta ese candado (`dateChanged && !esSuperAdmin`), pero
  **no tiene ruta al formulario**: su lista de accesos en
  [js/views.js:93-104](../js/views.js) no incluye «Mis unidades» ni
  «Operadores», y `editarCamion()` solo se llama desde la tarjeta de esa lista
  ([js/admin.js:147](../js/admin.js)). El código de `renderAdmin()` sí prevé
  que el superadmin vea toda la flota ([js/admin.js:118-120](../js/admin.js)),
  y `.admin-only` sí es visible para `role-superadmin`
  ([css/base.css:80-82](../css/base.css)) — lo que falta es la puerta.

Consecuencia práctica: una fecha equivocada se puede **cambiar** (adjuntando
algo), nunca **quitar**. Lo más cercano a quitarla es borrar la unidad entera
([js/admin.js:836](../js/admin.js)), que sí es un `DELETE` de verdad.

No está decidido si esto es un hueco o el comportamiento querido — un
documento acreditado que desaparece sin dejar rastro tampoco es deseable. Se
anota aquí para que la siguiente sesión no lo descubra otra vez desde cero.

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

### Lo que el cliente ve en «Solicitudes», y qué filtra el filtro

La pantalla del cliente son **cuatro secciones**, en este orden, y salen de
`renderPedidos()` en [js/pedidos.js](../js/pedidos.js):

| Sección | Qué lleva |
|---|---|
| Mis negociaciones | las propias en `en_negociacion` o `pendiente_acuerdo` — las que piden que el cliente haga algo |
| Mis solicitudes | el resto de las propias activas: `abierto`, `pendiente_revision`, `rechazado` |
| Otras solicitudes activas | los `abierto` **de otros clientes**, en modo lectura (`'publico'`) |
| Historial | las propias en `acordado`, `cancelado`, `finalizado`, `expirado` |

**El cliente ve las solicitudes abiertas de los demás clientes, a propósito.**
No es una fuga: `ped_select` deja leer todo pedido en `abierto` a cualquier
autenticado, y la sección existe para que el cliente vea qué se está moviendo.
Se pinta con la plantilla `'publico'`, que no entra en ninguna de las ramas de
botones de `pedidoCardHTML()` —así que la tarjeta no lleva ninguna acción— y
además **oculta el conteo de ofertas**: la etiqueta dice `Abierta` a secas, no
«N ofertas». Es deliberado: `of_select` solo enseña a cada uno sus propias
ofertas, así que el número ahí daría siempre cero y decir «Sin ofertas aún» en
una solicitud que tiene cinco no es ocultar, es mentir.

**Las pastillas de estado filtran solo lo propio** (`PED_ESTADOS_POR_FILTRO`).
«Otras solicitudes activas» no se filtra por estado — todas están en `abierto`,
así que filtrar por «Cancelados» la vaciaría — pero sí respeta los filtros de
tipo y zona.

**«Cargar más» trae más de lo propio, no de lo ajeno.** Decisión del usuario del
2026-09-24: «Otras solicitudes activas» se queda en las 30 más recientes y no
crece al paginar; es la sección exploratoria. Hasta ese día las dos secciones
compartían una sola consulta que añadía `abierto` siempre, y por eso al filtrar
por «Cancelados» la página de 30 se llenaba con los abiertos de los demás
clientes y los cancelados propios no aparecían. Son dos consultas desde
entonces.

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

**Y solo una de las dos vías gana.** Las dos pueden dispararse a la vez sobre el
mismo pedido —el cliente acepta la oferta A mientras la empresa Y acepta la
contraoferta de su oferta B—, y son dos personas distintas haciendo cada una
algo permitido. Desde el 2026-09-11 `aceptar_y_cerrar_acuerdo` y
`cerrar_acuerdo` bloquean la fila del pedido (`FOR UPDATE`) antes de comprobar
su estado, así que la segunda espera, re-lee el pedido ya en `acordado` y sale
con *«Esta solicitud ya no está en negociación»*. Debajo, el índice parcial
`uq_reservaciones_pedido_vivo` lo impide de forma declarativa.

Se bloquea el **pedido** y no la oferta porque las dos vías entran por ofertas
distintas: el pedido es su único punto común. El índice es **parcial**
(`estado not in ('Cancelada','Rechazada')`) porque cancelar reabre el pedido y
otra empresa puede ganarlo después — ver §9.

**No hay punto intermedio.** El pedido no se queda en `en_negociacion` con una
oferta ya aceptada: eso solo lo producía el flujo viejo, cuando aceptar eran
tres escrituras sueltas y la pestaña podía cerrarse entre una y otra. La regla
(c) de `sincronizar_estados_pedidos()` sigue ahí para reparar esas filas
históricas, no porque el flujo actual las genere.

**La excepción son los documentos vencidos.** `guard_oferta_update` bloquea la
aceptación con `DOCUMENTOS_VENCIDOS` en **dos casos**:

1. **La empresa** que emitió la oferta tiene vencido el permiso SCT, el seguro
   RC o el seguro de carga. **Desde H-04 etapa 5 eso se mide sobre la tabla
   `vigencias`, en estado `vigente`**: una renovación que la empresa haya subido
   y el superadmin no haya acreditado **no desbloquea nada**. Un documento con
   papel pero sin fecha sigue sin bloquear, porque sigue sin vigilarse.
2. **El pedido es de carga peligrosa y la unidad ofertada no tiene permiso de
   materiales peligrosos vigente** (desde el 2026-09-24,
   `20260924150000_hazmat_del_camion_frena_el_trato.sql`). Aquí la regla es
   **más estricta a propósito: un permiso que no existe bloquea igual que uno
   vencido**, porque el alta ya lo exige y solo le alcanza a unidades
   heredadas. Solo se aplica si el recurso ofertado es de verdad un camión —
   `ofertas.camion_id` puede guardar un custodio o un patio, y sin esa
   comprobación un servicio de custodia para carga peligrosa quedaría bloqueado
   sin motivo.

En los dos casos, entonces:

```
→ pedido 'pendiente_acuerdo', aviso al superadmin
→ el superadmin puede forzarlo: se le advierte y decide
```

Ese control **avisa pero no encierra**: sin la salida del superadmin, una
empresa con un papel vencido quedaría atrapada sin forma de desbloquearse.

**Y el aviso dice cuál de los dos casos fue.** La RPC copia el motivo que trae
el guard —sin el prefijo técnico— al mensaje que reciben los superadmins y al
`motivo` que devuelve al cliente. Antes decía «pero la empresa tiene documentos
vencidos», fijo: con la regla del camión eso habría mandado al superadmin a
revisar los papeles equivocados la mitad de las veces.

### La unidad ocupada

`cerrar_acuerdo` marca el recurso `ocupado` **solo si `fecha_ini <= hoy`**. Un
viaje que empieza la semana que viene deja la unidad `disponible`, y eso es
correcto: hoy está libre.

La doble reserva **no depende de ese campo**, y la impiden **dos capas que
tienen que mirar lo mismo**:

| Capa | Qué es | Quién la ve |
|---|---|---|
| `check_reservacion_disponibilidad()` | trigger `BEFORE INSERT OR UPDATE` | es la que **lanza `RECURSO_NO_DISPONIBLE`**, el mensaje que llega al usuario |
| `reservaciones_sin_solape` | `EXCLUDE` con GiST, activo solo para `Pendiente` y `Activa` | nadie, salvo en una carrera: dos inserciones simultáneas que ambas pasan el trigger |

Las dos comparan **`recurso_tipo` Y `unidad`** más el solape de fechas (desde el
2026-09-25, H-06). Antes comparaban solo `unidad`, y como `unidad` es un `text`
que guarda el id de un camión, un custodio, un patio o un lavado según
`recurso_tipo`, **un patio y un camión que compartieran cadena de id se
estorbaban**: reservar uno daba `RECURSO_NO_DISPONIBLE` sobre el otro, que estaba
libre. Hoy no ocurría —medido en el volcado del 2026-09-21: ninguna colisión de
id entre las cinco tablas, y ninguna `unidad` usada con más de un
`recurso_tipo`— pero nada en el esquema lo impedía.

**El orden importa al arreglar esto.** El trigger es `BEFORE`, así que salta antes
de que la restricción se evalúe: tocar solo la restricción —que es lo que pedía
la ficha de H-06— habría dejado el falso positivo igual de visible y con
apariencia de arreglado. Y al revés: un `EXCLUDE` mal escrito puede pasar meses
sin dar la cara porque el trigger lo tapa, por eso la comprobación de la
migración **apaga el trigger** y repite la prueba contra la restricción sola.

Lo que sostiene la referencia sin clave foránea sigue siendo
`trg_guard_unidad_existe`, que resuelve la tabla con `tabla_recurso(recurso_tipo)`
y exige que el id exista allí.

> **Con `unidad` en NULL ninguna de las dos capas actúa** —`NULL = NULL` no es
> cierto— y la columna es nullable. Es anterior a H-06 y H-06 no lo empeora.
> Medido: 0 de las filas en `Pendiente`/`Activa` tenían `unidad` NULL.

**El CHECK de prefijos que proponía H-06 (c) no se hizo, y no por coste.** El
convenio no es por tabla: en `camiones` hay **cinco** prefijos (C, T, R, F, S)
porque el prefijo codifica el **tipo de camión**, no la tabla, así que un CHECK
tendría que enumerar los cinco de hoy y rompería con el sexto tipo que alguien
diera de alta. Y con `recurso_tipo` en las dos capas, una colisión entre tablas
ya no tiene consecuencia: el convenio dejó de sostener nada.

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
EL PRIMERO que suba      → reserva 'Activa' → 'PorAprobar'
SUPERADMIN aprueba       → 'Completada'   (rechaza → vuelve a 'Activa')
CLIENTE califica         → 1 sola vez (UNIQUE parcial por reservación)
```

Cada parte sube su propia evidencia: `evidencias` (empresa) y
`evidencias_cliente` (cliente), las dos arrays de **rutas** de Storage.

**No hacen falta las dos para que la reserva avance.** Hasta el 2026-09-11 este
documento decía «ambas partes → `PorAprobar`», y era falso: lo desmiente
`registrar_evidencias`, que es quien manda.

```sql
v_solicitando := (v_r.estado = 'Activa');
...
estado = CASE WHEN v_solicitando THEN 'PorAprobar' ELSE estado END
```

El primero que sube estando la reserva en `Activa` la mueve a `PorAprobar`; el
segundo ya la encuentra ahí y solo añade sus archivos. **Y el superadmin puede
aprobar con una sola evidencia**: `aprobarFinalizacion()` no comprueba que estén
las dos, el panel únicamente pinta `⚠️ falta` junto a la que no llegó. Quien
aprueba decide si eso basta.

Consecuencia para quien pruebe esto a mano: tras el cierre de la empresa, la
reserva **ya no está en el filtro `Activa`** — se ha ido a `PorAprobar`, y ahí
es donde el cliente encuentra su botón.

La restricción del último paso es **solo para la empresa al solicitar el
cierre**. Tiene sentido: no se cierra un servicio que no llegó. Y solo aplica
cuando la reserva está `Activa`: si ya está en `PorAprobar` porque el cliente se
adelantó, la empresa añade evidencia sin volver a comprobarse el seguimiento.

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

## 11. Los dos paneles de números

Dos pantallas enseñan agregados, y **desde el 2026-09-18 los calcula la base,
no el navegador**: `reporte_kpis(p_desde, p_hasta)` para Reportes del
superadmin, y `desempeno_empresa()` para «Mi desempeño» de la empresa. Antes
las dos se descargaban el conjunto entero y sumaban en JavaScript.

### Reportes — solo superadmin

| Cifra | De dónde sale |
|---|---|
| Total solicitudes | `pedidos` del rango |
| Acordadas | estado ∈ `acordado` · `finalizado` · `expirado` |
| Abiertas | estado `abierto` |
| Tasa de cierre | acordadas ÷ total, **redondeada en el navegador** |
| Reservaciones · Ingreso estimado | `reservaciones` del rango; `precio_acordado` nulo suma 0 |
| Solicitudes por mes | mapa `YYYY-MM` → pedidos |
| Admins más activos | top 5 por reservaciones, nombre desde `empresas_publico` |
| Servicios más solicitados | top 5 por `tipo_camion` |

### Mi desempeño — la empresa que mira

Ofertas enviadas y aceptadas, tasa de cierre, reservaciones y completadas,
ingreso total, calificación promedio, e ingresos por mes de los últimos seis.
**No tiene rango de fechas: es el historial completo de la empresa**, y por eso
era la peor de las dos.

`desempeno_empresa()` **no recibe el id de la empresa**: lo saca de
`auth.uid()`. Con un parámetro, cualquier empresa podría pedir los ingresos de
otra — la misma razón por la que `calificar_servicio` deriva el `admin_id` del
propietario de la reserva.

### Cosas que sorprenden si no se avisan

- **El rango superior es `hasta || 'T23:59:59'`.** Una fila creada en el último
  segundo del día no entra. Venía así del navegador y se reprodujo tal cual
  para que los números cuadraran con los de antes; corregirlo es cambiar el
  comportamiento, no arreglarlo.
- **Los meses se agrupan en UTC**, porque el cliente agrupaba por
  `created_at.substring(0, 7)` sobre la cadena ISO, que viene en UTC. En la
  frontera del mes, una fila puede caer en el mes anterior al que dice el reloj
  de quien mira.
- **La tasa de cierre y la calificación media se redondean en el navegador.**
  Las funciones devuelven conteos y sumas, no porcentajes: `Math.round` de
  JavaScript y `round()` de PostgreSQL no coinciden en los empates.
- **Los empates del ranking ya no dependen del orden de descarga, y eso cambia
  qué fila sale, no solo en qué orden.** La consulta que hacía el navegador no
  llevaba `ORDER BY`, así que un empate lo decidía el orden que devolviera
  PostgreSQL — que no está garantizado entre dos cargas de la misma pantalla.
  En un top 5, eso decide quién entra y quién se queda fuera: verificado el
  2026-09-18 en pruebas, con tres tipos empatados a 3 pedidos, el cálculo
  viejo enseñaba «Sencillo porta contenedor 40/20» y el nuevo enseña «Full».
  Ahora se desempata por ingreso y luego por nombre: reproducible.
- **`cancelados` se calcula y no se pinta.** Estaba así desde siempre; la
  función lo devuelve por si la tarjeta vuelve.

---

## Cómo se hablan entre ellos

**No hay chat.** El texto libre entre cliente y empresa se retiró a propósito y
se sustituyó por botones fijos que escriben una fila en `notificaciones`:
documentos de carga, lugar y hora, retraso y reporte de cambio
(`js/reservaciones.js`). La tabla `mensajes` sigue existiendo con sus políticas
y su RPC, pero **no se usa**: quedó de la versión con chat y se conserva
porque retirarla obliga a tocar políticas de acceso que nadie necesita mover
hoy. No es un hueco que llenar.

Esto no es una limitación técnica, es una decisión: un aviso con forma fija
queda registrado, es auditable y no se presta a acordar cosas por fuera del
sistema.

Quién puede avisar a quién lo decide el RLS de `notificaciones`, y es
**restringido por relación**: solo puedes notificarte a ti mismo, a los
superadmins, o a la contraparte de tu reservación u oferta. Un flujo de aviso
nuevo tiene que encajar en una de esas tres, o hacerse desde un trigger.

**Desde el 2026-09-11 el correo obedece esa misma regla.** Antes no: los
destinatarios llegaban en el cuerpo de la petición a `enviar-notificacion` y se
usaban tal cual, así que cualquiera con una cuenta podía hacer que PortGo
mandara un correo con su texto a cualquier usuario registrado —o, vía
`clienteEmail`, a cualquier dirección de internet— con el dominio y el DKIM de
PortGo detrás. Ahora la función separa los destinatarios por procedencia:

| Procedencia | Ejemplos | Se comprueba |
|---|---|---|
| Los elige el servidor | empresas del ramo (`nueva_solicitud`), superadmins (`revision_solicitud`, `acuerdo`) | No hace falta: el cuerpo de la petición no influye en quiénes son |
| Vienen en la petición | `destinoIds`, `clienteEmail`, `propietario_id`, `clienteId`, `adminId` | **Sí**, uno a uno contra `puede_notificar()`, con la identidad de quien llama |

Un destinatario que no pase se descarta en silencio para él y queda contado en
`descartados` de la respuesta. Y `clienteEmail` ya no admite una dirección
suelta: se traduce a usuario, y si no corresponde a ninguno no se manda nada.

**Consecuencia para quien añada un aviso nuevo:** si el correo no llega, mirar
primero si el emisor y el destinatario tienen relación. Es el mismo motivo por
el que no llegaría la campana.

Los avisos al superadmin van por `notificar_superadmins()`, que es la llamada
más repetida del código (15 sitios). Los de oferta y reserva los disparan
triggers de la base, no el navegador: así llegan aunque la pestaña se cierre.

### El techo de 60 avisos/hora por cuenta (H-20, 2026-09-25)

`notificar_superadmins()` está concedida a `authenticated` y escribe saltándose
`puede_notificar()`, porque tiene que poder: el RLS de `notificaciones` es por
relación y un cliente no podría avisar al superadmin de otro modo. Lo que no
tenía era techo, así que cualquier cuenta con sesión podía llenarle el panel del
texto que quisiera.

Ahora cada cuenta tiene **60 llamadas por hora**. Por encima de eso el aviso se
**descarta** y la función vuelve.

**No lanza excepción, y eso es lo importante.** Cuatro RPC de negocio la llaman
con `PERFORM` dentro de su propia transacción —`aceptar_y_cerrar_acuerdo`,
`cancelar_reservacion`, `registrar_evidencias`, `solicitar_cancelacion`—, así que
una excepción ahí tumbaría la transacción entera: el cliente no podría aceptar
una oferta porque un contador de avisos dijo que no.

**Un aviso descartado no esconde trabajo.** `cola_superadmin()` no lee
`notificaciones`: el globo y el panel «Por aprobar» se calculan sobre las tablas
de negocio. Se pierde la campanita, no la tarea. El correo va por otro camino
(`enviar-notificacion` desde el cliente) y tampoco depende de esto. El descarte
deja un `warning` en el log de Postgres.

**El contador no vive en `notificaciones`.** Esa tabla no guarda quién generó la
fila —`user_id` es el destinatario—, y guardarlo en `meta` sería explotable: la
política de INSERT solo restringe el destinatario, y `puede_notificar()` deja a
cualquiera notificarse a sí mismo, así que una cuenta podría insertarse 60 filas
con el uuid de otra en `meta` y **dejarla muda una hora**. El contador vive en
`public.avisos_superadmin`, con RLS activo, **cero políticas** y privilegios
revocados a `anon`, `authenticated` y `service_role`: solo la escribe la propia
función. Una fila por llamada aceptada.

**De dónde sale el 60:** del volcado de producción del 2026-09-21. En todo el
histórico hay 132 llamadas; por hora la mediana es 1, el p90 es 4 y el máximo
**17**. El techo es 3,5× ese máximo, que deja sitio a la ráfaga legítima — un
alta de flota de N unidades dispara N avisos seguidos. No es una medición por
usuario: hasta esta migración no se guardaba el autor, así que 17 es el máximo de
todas las cuentas juntas y por tanto una cota superior de lo que hizo cualquiera.


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
| `guard_oferta_update` | ofertas | Aceptar con documentos de empresa vencidos; **aceptar un pedido de carga peligrosa con una unidad sin permiso hazmat vigente**; aceptar la oferta propia salvo respondiendo una contraoferta |
| `guard_reservacion_insert` | reservaciones | Que un cliente se cree una reserva ya confirmada y con precio puesto por él |
| `guard_reservacion_update` | reservaciones | Que el cliente toque precio, unidad o fechas; que suba la evidencia de la empresa; que cualquiera de los dos apruebe su propio cierre o resuelva su propia cancelación — eso lo hace el superadmin |
| `guard_fleet_resource_update` | flota | Auto-aprobarse un recurso; transferir la propiedad |
| `guard_perfil_self_update` | perfiles | Cambiarse el rol, el estado de aprobación de la cuenta o los campos de verificación. **Se dispara en toda actualización de `perfiles`, no solo en la propia** — ver abajo |
| `guard_expediente_documento` | expediente_documentos | Que cada parte haga el trabajo de la otra: **solo el cliente sube**, **solo el transportista revisa** |
| `guard_operador_hazmat` | ofertas, reservaciones | Asignar a carga peligrosa un chofer sin licencia vigente |

### Una vista no tiene RLS detrás, y nace escribible

`empresas_publico` es la ficha pública del transportista: una vista sobre
`perfiles` con 15 columnas, que existe para que el Catálogo no lea `perfiles`
entera. Corre con `security_invoker` en su valor por omisión (`false`) **a
propósito**, porque así no aplica el RLS de `perfiles` — que solo deja ver la
fila propia — y el catálogo puede enseñar las fichas ajenas.

Eso está bien para leer. El problema es que **una vista simple sobre una sola
tabla es auto-actualizable**: un `INSERT`/`UPDATE`/`DELETE` contra ella se
traduce a la tabla base, y sin `security_invoker` tampoco pasa por el RLS.

Y las vistas **nacen escribibles**. El esquema lleva puesto
`ALTER DEFAULT PRIVILEGES … GRANT ALL ON TABLES TO authenticated`, y en
PostgreSQL «TABLES» incluye las vistas. Por eso `empresas_publico` tenía
`INSERT`, `UPDATE` y `DELETE` concedidos a `authenticated` desde que se creó:
`20260831210000` hizo `revoke all … from anon, public` y luego
`grant select … to authenticated`, pero el `REVOKE` nunca apuntó a
`authenticated`, y un `GRANT SELECT` no retira lo que ya estaba dentro de
`ALL`. Retirado el 2026-09-14 por `20260914130000_la_vista_no_se_escribe`.

Mientras estuvo abierto, `guard_perfil_self_update` sí se disparaba y frenaba
el rol, `aprobacion_cuenta` y los campos de verificación. No frenaba el resto —
incluidas las tres `fecha_vencimiento_*` que lee `guard_oferta_update` para
decidir si una empresa puede cerrar un trato. Y el `DELETE` no lo frenaba nada:
**`perfiles` no tiene ninguna política `FOR DELETE`**, así que la vista era el
único camino de borrado que existía para `authenticated`.

**Consecuencia para quien cree la próxima vista:** los privilegios por omisión
no se han tocado —cambiarlos alcanzaría también a las tablas futuras, que sí
necesitan esos permisos porque ahí RLS es la frontera—, así que **toda vista
nueva en `public` sigue naciendo escribible**. Crear la vista y poner
`grant select` **no basta**: hay que retirar la escritura explícitamente. El
bloque 2 de esa migración es idempotente y sirve de red: volver a ejecutarlo
después de crear una vista la deja limpia. Y
`supabase/sondas/escritura-en-vistas.sql` lo detecta en cualquiera de los dos
proyectos, sin comparar bases.

**Y `authenticated` no era el único rol.** El mismo `ALTER DEFAULT PRIVILEGES`
alcanza a `service_role`, y ni el barrido de H-01 ni las migraciones de H-10 lo
tocaron: la sonda tampoco lo miraba, porque recorría solo `anon` y
`authenticated`. Resultado, medido el 2026-09-18 con un `PATCH` cuyo filtro no
casa con ninguna fila: `empresas_publico` aceptaba escrituras de la clave de
servicio en **los dos proyectos**, y las cuatro `*_publico` de flota en
producción sí y en pruebas no — que es como salió a la luz, al fallar la
paridad por 24 diferencias.

**No concede privilegio nuevo**, y conviene decirlo para no confundir el
tamaño: la clave de servicio ya se salta el RLS y tiene `ALL` sobre las tablas
base, así que quien la tenga puede escribirlas de todos modos. Importa por dos
razones más modestas: una vista declarada de solo lectura tiene que serlo para
todos los roles, y mientras los dos proyectos no coincidan la paridad falla por
algo conocido, que es como se acaba ignorando la paridad.

**Lo que la verificación de paridad no ve:** `pg_default_acl` no es ninguna de
sus 18 dimensiones. Una diferencia en los privilegios por omisión es invisible
hasta que alguien crea un objeto nuevo, y entonces aparece como diferencia *de
ese objeto*. Si una vista nueva sale con permisos distintos entre proyectos,
mirar ahí antes que en la migración que la creó.

### La flota ajena se lee por vista, no por tabla

Cuatro políticas dejaban ver la **fila entera** de cada recurso aprobado a
cualquier usuario con sesión: `camiones_public_read` y sus tres hermanas. RLS
decide *qué filas* ves, no *qué columnas*, así que «ver el catálogo» y «leer el
expediente de la unidad» eran el mismo permiso.

Comprobado el 2026-09-17 con una sesión de empresa normal y una sola petición:
`select=*` sobre camiones ajenos devolvía **9 unidades con sus 48 columnas** —
VIN, número de motor, placas, tarjeta de circulación, precio por día y las rutas
de los documentos SCT y de seguro.

Desde `20260917120000` existen `camiones_publico`, `custodios_publico`,
`patios_publico` y `lavados_publico`, con **solo lo que el catálogo pinta** y el
filtro `aprobacion = 'aprobada'` dentro.

**Quién lee qué, y por qué no es uniforme:**

| Quién | De dónde | Por qué |
|---|---|---|
| Catálogo (cualquiera) | vista | no es dueño; no necesita el expediente |
| Reservaciones, rama **cliente** | vista | tampoco es dueño |
| Reservaciones, rama **empresa/superadmin** | **tabla** | el dueño la ve por `*_owner_read` sin importar el `aprobacion`, y **editar una unidad la devuelve a revisión**: con la vista, una reserva activa de una unidad en edición se quedaría sin nombre |
| Mis unidades, ofertar | tabla | son sus propias unidades |

⚠ **Las cuatro políticas `*_public_read` siguen abiertas**: mientras estén, la
vista es solo una forma más limpia de leer, no una frontera. Retirarlas es un
borrado y necesita autorización explícita.

### El rol solo se cambia por `cambiar_rol()`

`guard_perfil_self_update` se dispara en **toda** actualización de `perfiles`, y
su única salida era `is_superadmin()`, que lee `auth.uid()`. La Edge Function
`gestionar-usuario` escribe con la **clave de servicio**, donde `auth.uid()` es
NULL — así que el guard trataba al superadmin que edita a otro como si fuera un
usuario intentando ascenderse, y lo rechazaba con *«No autorizado: no puedes
cambiar tu rol»*.

**Cambiar el rol de un usuario no había funcionado nunca.** No se veía porque
`gestionar-usuario` no comprobaba el resultado del UPDATE y devolvía `ok:true`
igual: la pantalla decía «Usuario actualizado» y el rol seguía como estaba.
Verificado a mano en pruebas el 2026-09-14.

Desde entonces el rol se cambia por `cambiar_rol(p_user_id, p_rol)`, que
enciende la marca `portgo.cambio_rol` —local a la transacción, como
`portgo.sync` y `portgo.cierre_acuerdo`— y el guard la reconoce. Está concedida
**solo a `service_role`**: un usuario con sesión no puede llamarla. La
autorización sigue viviendo en la Edge Function, que verifica el JWT; lo que
comprueba la función de base es lo que no depende de quién llame — que el rol
sea válido y que no se quede la plataforma sin superadmin.

**Orden de escritura en `editar`:** primero el perfil, después las credenciales.
El perfil es el que puede ser rechazado, así que va delante; al revés, un rol
rechazado dejaba el correo ya cambiado.

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
4. ~~**El estado de los pedidos avanza por dos vías a la vez.**~~ **CERRADO el
   2026-09-25.** `sincronizar_estados_pedidos()` corre en pg_cron cada 15 minutos
   en producción y en pruebas desde el 2026-09-11, y desde hoy es **la única vía**:
   `renderPedidos()` ya no escribe. Conserva la normalización **en memoria** —la
   pantalla enseña el estado corregido al instante— pero no vuelve a la base.

   Se comprobó antes de quitarlas que el cron cubre **las cinco** reglas del
   render, no cuatro: el archivo `20260810130000_sincronizar_estados_OPCIONAL.sql`
   lleva cuatro, y la función **viva** lleva cinco y devuelve
   `solicitudes_vencidas`, con el comentario «FALTABA en 20260810130000: esta
   regla se anadio al navegador despues». **Si hay que verificarlo otra vez, se
   lee `pg_get_functiondef`, no el `.sql`** — leer el archivo fue el error que
   casi dejó este cambio con una regla sin cubrir.

   Lo que cuesta: un estado rancio tarda hasta 15 minutos en cuadrar en la base
   en vez de cuadrar al repintar. Lo que gana: dos pestañas abiertas ya no emiten
   los mismos `UPDATE` en carrera —26 sitios llaman a `renderPedidos()`—, y
   desaparece el impedimento para publicar `pedidos`/`ofertas` en Realtime
   (hueco 14).
5. **La tabla `mensajes` no se usa.** Resto de la versión con chat; se
   conserva con sus políticas porque retirarla no aporta nada hoy.
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

   **Y eso arrastra más de lo que parece** — verificado el 2026-09-14, al
   intentar probarlo a mano:

   - El modal **«Agendar unidad»** (`#modal-reserva`) solo lo abren
     `openReserva()` y `openReservaRecurso()`, y sus únicos botones se pintan
     dentro de esa rejilla oculta (`js/camiones.js:152`, `js/recursos.js:91`
     y `:169`). **El modal existe y no se puede abrir.**
   - `js/modal.js:97` es lo **único** en todo el sistema que crea una
     reservación en `Pendiente`. Ningún INSERT de SQL la produce, y
     `cerrar_acuerdo` las crea directamente en `Activa`.
   - Por tanto **`Pendiente` es un estado inalcanzable hoy**, y con él muere
     la rama `esDueno && esPendiente` de `js/reservaciones.js:428` — los
     botones **«✓ Aceptar»** y **«✕ Rechazar»** de una reserva.
   - Y con ella, cuatro tipos de correo que ya no puede disparar nadie:
     `solicitud_recibida`, `nueva_reserva`, `reserva_aceptada` y
     `reserva_rechazada`.

   Nada de esto está roto: es la consecuencia de que el negocio pasara a girar
   sobre el pedido y la oferta en vez de sobre la reserva directa. Se documenta
   para que nadie vuelva a perder una tarde buscando el botón «Agendar», y para
   que quien decida retirar código muerto sepa de qué tamaño es el bloque.
7. **De las 11 RPC transaccionales, 6 se usan.** En uso:
   `cancelar_reservacion`, `solicitar_cancelacion`, `registrar_evidencias`,
   `avanzar_tracking`, `abrir_expediente` y `calificar_servicio`. Sin usar:
   `enviar_oferta`, `responder_oferta`, `responder_contraoferta`,
   `enviar_mensaje` y `recomendar_unidad` — esos caminos los sigue
   orquestando el navegador paso a paso, sin atomicidad.
   (`aceptar_y_cerrar_acuerdo`, `notificar_superadmins` e `ids_superadmins`
   también se usan, pero son posteriores y no formaban parte de esas 11.)

   **Las dos que contradecían la regla del 9-sep ya no lo hacen.** Hasta el
   2026-09-11, la rama `aceptar` de `responder_oferta` y de
   `responder_contraoferta` escribía el flujo viejo —pedido a
   `pendiente_acuerdo`, sin reservación— y las dos siguen concedidas a
   `authenticated`, así que eran alcanzables sin pasar por ninguna interfaz.
   Ahora esa rama delega en `aceptar_y_cerrar_acuerdo()`; las ramas de
   contraofertar y rechazar no cambiaron. Con eso heredan el bloqueo del
   pedido y, sobre todo, el desvío por documentos vencidos: **por esa vía una
   empresa con el permiso SCT vencido cerraba el trato sin que nadie lo
   mirara.**
8. **`aprobarCuenta()` escribe dos tablas y solo mira el error de una.**
   `js/aprobaciones.js` actualiza `perfiles` y `solicitudes_cuenta` en el
   mismo `Promise.all` y comprueba únicamente el de `perfiles`. Si el segundo
   falla, la cuenta queda aprobada y la solicitud sigue `pendiente`: el panel
   la lista para siempre. **El globo ya no miente por esto** —desde el
   2026-09-18 cuenta la unión de las dos tablas, ver §Superadmin— pero la
   causa sigue ahí. No se ha dado en producción: las 7 solicitudes están
   `aprobada` y ningún perfil quedó `pendiente`. Arreglarlo es mover la
   pareja a una RPC o usar `actualizarConfirmado()` en las dos.
9. ~~**Hay recursos sin propietario.**~~ **CERRADO el 2026-09-24.** Eran 7 —los
   custodios `CUS-001/002/003/006` y los patios `PAT-001/002/005`—, y el
   problema no era cosmético: `vigencia_propietario()` devolvía `NULL`, la
   política comparaba contra `NULL` y **ninguna empresa podía renovar sus
   documentos**. Se asignaron a Omar Silva Preciado y `propietario_id` pasó a
   ser `NOT NULL` en las cinco tablas. Ver *Alta de recursos*.
10. **Un operador al que le falte una fecha no se puede editar.** Desde el
    2026-09-10 (`64ceb7c`) el formulario exige **las cuatro fechas** —examen
    médico, toxicológico, carta de antecedentes y vencimiento de licencia—
    antes de guardar: *«Falta la fecha del examen toxicológico. Sin ella el
    documento no se vigila en Vigencias»* ([js/operadores.js:367](../js/operadores.js)).

    La validación protege el control de vigencias, y el hueco 6 de arriba
    explica por qué hacía falta. Pero **bloquea de paso cualquier corrección**:
    un operador dado de alta antes de esa fecha, o al que le falte un dato, no
    admite ni arreglarle un teléfono o un apellido mal escrito sin rellenarle
    antes lo que falte. Comprobado en producción el 2026-09-24 con «Ernesto
    Preciado Soto», que no tiene fecha de examen toxicológico.

    **Rellenar una fecha inventada para desbloquear el formulario no es una
    salida**: es precisamente el dato que después alguien mira para decidir si
    ese chofer puede trabajar.
11. **Hay DOS formularios de edición de camión, y el normal expone menos
    campos.** No es que a uno se le olvide algo: son formularios distintos.

    - *Mis unidades → ✏ Editar* (`editarCamion()`) abre el modal `editar-*`.
    - Editar una unidad **rechazada** (`editarCamionRechazado()`) rellena el
      formulario de **alta** completo, con sus 32 campos.

    Lo que solo se puede corregir **si la unidad fue rechazada**: color, año del
    modelo, versión, las cuatro fotos, y **el permiso de materiales peligrosos
    con su fecha**. Al revés, el modal normal tiene dos que el alta no: operador
    asignado y precio por día.

    Consecuencia práctica: una unidad aprobada con el color mal puesto se queda
    así para siempre, y su permiso hazmat no se puede renovar por el camino
    normal. Verificado el 2026-09-24 comparando los campos que rellena cada
    función.
12. **El permiso de materiales peligrosos del camión se exige y nadie lo lee.**
    `admin.js:902` lo hace obligatorio al dar de alta una unidad hazmat, se
    guarda en `doc_permiso_peligrosa` / `fecha_vencimiento_permiso_peligrosa`, y
    el espejo de H-04 lo refleja a `vigencias` como `permiso_peligrosa`.

    **Y ahí muere.** Verificado el 2026-09-24 con `grep`: las únicas apariciones
    en todo el cliente son de escritura. No lo lista el panel de Vigencias —su
    bloque de camiones vigila tarjeta de circulación, seguro, permiso SCT, CAAT
    y verificación, no este—, no lo mira el aviso de «esta unidad tiene
    documentos vencidos» al ofertar, y no lo consulta ningún guard.

    **El contraste es lo que lo hace grave:** para carga peligrosa el sistema
    **sí** exige que el chofer tenga licencia HAZMAT vigente —filtra el
    desplegable y lo vuelve a comprobar al enviar la oferta— pero **no** mira si
    el camión tiene su permiso en regla. Se pide el papel al alta y después se
    ignora, que es el mismo patrón que el hueco 6 describe para las fechas
    nulas.

    **CERRADO EN PARTE el 2026-09-24.** Decisión del usuario: *«se debe frenar
    el trato»*. `guard_oferta_update` ya bloquea aceptar un pedido de carga
    peligrosa cuando la unidad ofertada no tiene permiso vigente, con un permiso
    inexistente contando igual que uno vencido
    (`20260924150000_hazmat_del_camion_frena_el_trato.sql`).

    **Y CERRADO DEL TODO el mismo día**, con las cuatro pantallas:

    - **Panel de Vigencias**: `permiso_peligrosa` se lista, y es obligatorio
      **solo en las unidades que declaran mover carga peligrosa** — en las demás
      no tenerlo no es un hueco, y listarlo sería ruido en 10 de 13.
    - **Al ofertar**: si el pedido es de carga peligrosa, el desplegable **filtra
      las unidades sin permiso vigente**, igual que ya filtraba los choferes sin
      licencia HAZMAT. Medido el 2026-09-24 en pruebas: para el pedido hazmat
      sembrado, el select pasó de ofrecer 2 Tortons a ofrecer 0, porque ninguno
      tiene permiso. Es la regla funcionando: el guard habría rechazado el trato
      igual al cerrarlo, y así se sabe antes de gastar la oferta.
    - **Al aprobar el acuerdo**: el superadmin ve el permiso de la unidad en la
      lista de documentos vencidos. Sin eso forzaba a ciegas — el pedido llegaba
      a su cola por un motivo que su pantalla no nombraba.
    - **El mensaje al cliente** usa el `motivo` que devuelve la RPC en vez de
      decir «la empresa» fijo.

13. **El alta de flota del cliente nativo apunta a RPC que producción no tiene.**
    `android/.../FlotaRepository.kt` llama a `guardar_camion` y `alta_operador`
    (no hace `INSERT` directo), y **ninguna de las dos existe en producción**:
    verificado el 2026-09-24 contra el volcado. Las define
    `20260812120000_alta_flota.sql`, que nunca se aplicó allí.

    Consecuencia: el lado empresa del móvil no puede dar de alta una unidad ni
    un chofer en producción, aunque el contrato lo prometa
    ([CONTRATO-MOVIL.md](CONTRATO-MOVIL.md), §6: *Flota (camiones/operadores) —
    empresa ✓*). Salió al medir si el `NOT NULL` de `propietario_id` podía
    romper ese camino: no puede, porque el camino no existe — y si algún día se
    aplica esa migración, su cabecera dice que **fuerza**
    `propietario_id = auth.uid()`, así que será compatible.

14. **La lista de Solicitudes no se actualiza en vivo, y es una decisión, no un
    olvido.** `js/main.js` se suscribe por Realtime a ocho tablas; la publicación
    `supabase_realtime` de producción lleva **seis** —las cuatro de flota,
    `reservaciones` y `notificaciones`—. `pedidos` y `ofertas` **no están
    publicadas, así que esas dos suscripciones nunca han disparado.** Verificado
    el 2026-09-25 cruzando el código contra el volcado de producción del
    2026-09-21 (`supabase/espejo/08-realtime.sql`, que sale de
    `pg_publication_tables` de producción y no lleva `for all tables`). No hay
    ninguna suscripción a `mensajes`.

    Consecuencia para el usuario: cuando un cliente publica una solicitud o una
    empresa oferta, la pantalla del otro **no se entera hasta que vuelve a
    entrar en la vista** o recarga. Todo lo demás —flota, reservaciones,
    campana— sí va en vivo.

    **Por qué se queda así** (decidido el 2026-08-28, migración
    `20260828120000_publicacion_realtime_declarativa.sql`): `renderPedidos()`
    ejecuta hasta cuatro `UPDATE` sobre `pedidos` como efecto secundario de
    dibujar la lista — es la misma máquina de estados del §«El estado de los
    pedidos avanza por dos vías a la vez» (hueco 4). Publicar la tabla haría que
    cada cambio despertara a **todos** los navegadores conectados, cada uno
    escribiría, y cada escritura generaría más eventos. Un bucle de
    realimentación, no una lista más viva.

    **Ese requisito previo se cumplió el 2026-09-25: el render ya no escribe**
    (hueco 4). Publicarlas ya no crearía el bucle. Queda como decisión, no como
    impedimento técnico — y con un matiz que cambia la respuesta: **la campana
    ya cubre el caso mejor.** Al aprobarse una solicitud, `aprobarSolicitud()`
    avisa **solo a las empresas con flota de ese tipo**, y `notificaciones` sí
    está publicada, así que la empresa se entera en vivo y filtrado; pulsar el
    aviso llama a `showView('pedidos')`, que repinta. Publicar `pedidos` sería
    difundir a **todas** las sesiones para entregar información **menos**
    dirigida que la que ya llega. `ofertas` sí tendría sentido —`of_select` la
    acota a las dos partes, así que el reparto es de 2-3 sesiones— y necesitaría
    `REPLICA IDENTITY FULL`, porque [js/pedidos.js](../js/pedidos.js) borra
    ofertas y sin FULL un DELETE no se puede evaluar contra RLS.

    **Dos afirmaciones que circulaban sobre esto y son falsas.** La primera: que
    el requisito previo era aplicar la migración de pg_cron. No lo era —esa **sí
    estaba aplicada**, el volcado de cron de producción lista
    `portgo-sincronizar-estados │ */15 * * * * │ activo=true`—; añadir el cron
    duplicó el trabajo en vez de moverlo, y lo que faltaba era quitar las
    escrituras del render, hecho el 2026-09-25. La segunda: el commit de la sonda
    de Realtime (2026-09-14) dijo que «esa razón dejó de existir el 8 de
    septiembre, cuando la máquina de estados bajó a pg_cron» — era falso entonces,
    porque el render seguía escribiendo, y dio la fecha equivocada por casi tres
    semanas.

    **Ojo con el hallazgo H-16 de la auditoría**, que describe esto al revés:
    dice que «Realtime reparte cada cambio de pedidos y ofertas a todas las
    empresas conectadas» y lo cifra en 800 consultas por solicitud con 200
    empresas. Esa aritmética parte de que los eventos llegan, y no llegan: las
    dos tablas no están publicadas. La ficha ya concluía «no procede aún» y
    dejaba un umbral de vigilancia (~50 empresas conectadas); el umbral que de
    verdad importa es otro, y es el requisito previo de arriba. Y para `ofertas`
    el reparto tampoco sería a todos aunque se publicara: `of_select` está
    acotada a las partes. No se reporta como hallazgo nuevo ni se «arregla».


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
