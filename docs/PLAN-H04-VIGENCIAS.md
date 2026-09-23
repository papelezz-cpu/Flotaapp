# H-04 — Unificar «documento con vigencia» en una tabla

Plan por etapas. Escrito el 2026-09-18.

**Estado al 2026-09-22:**

| Etapa | |
|---|---|
| 1 · Crear | **aplicada a pruebas** |
| 2 · Copiar | **aplicada a pruebas** — 63 filas |
| 3 · Doble escritura | **aplicada a pruebas** — espejo vivo |
| 3b · Espejo tolerante | **escrita y probada**, sin aplicar |
| 3c · El espejo sigue los borrados | **escrita y probada en banco local**, sin aplicar |
| 4 · Cambiar lecturas | sin empezar |
| 5 · Guards | sin empezar |
| 6 · Retirar columnas | fuera de este plan |

La tabla existe en pruebas con 63 filas y **nadie la lee todavía**: ninguna
pantalla ha cambiado. **Producción no tiene ninguna de las tres** — llevarlas
allí es una promoción aparte, con su propia autorización (Regla #2).

---

## El problema, en una línea

El mismo concepto —un papel, su ruta en Storage y su fecha de caducidad— está
modelado **cinco veces** en unas 35 columnas, con cinco nomenclaturas
distintas. Añadir un tipo de documento son dos columnas, una migración, un
cambio de formulario y dos de consulta, **por cada tabla afectada**. Y ninguna
de esas fechas está indexada, así que las diez consultas de `js/vigencias.js`
hacen secuencial.

---

## Lo que el plan sabe, porque se midió

### Datos: la migración es diminuta

> ⚠ **Esta tabla es la estimación del 18/09 y se quedó corta.** Al copiar de
> verdad salieron **63 filas, no ~44**: contaba filas con alguna fecha,
> redondeaba a la baja, y no miraba los documentos con archivo pero sin
> vencimiento. Se conserva sin retocar porque es lo que se creyó al planificar;
> los números reales están en la Etapa 2.

| Tabla | Filas | Con alguna fecha | Filas que generaría |
|---|---|---|---|
| `perfiles` | 13 | **1** | ~3 |
| `camiones` | 12 | 7 | ~33 |
| `operadores` | 3 | 3 | ~8 |
| `custodios` | 6 | **0** | 0 |
| `patios` | 5 | **0** | 0 |

**Total: ~44 filas.** Copiar los datos no es el problema.

### Código: ahí está el coste

`fecha_vencimiento*`, `vigencia_caat`, `fecha_examen_*`, `fecha_carta_*`
aparecen **168 veces en 9 ficheros**:

| Fichero | Apariciones |
|---|---|
| `js/aprobaciones.js` | 48 |
| `js/admin.js` | 36 |
| `js/vigencias.js` | 29 |
| `js/pedidos.js` | 16 |
| `js/operadores.js` | 15 |
| `js/catalogo.js` | 11 |
| `js/reservaciones.js` | 7 |
| `js/cobros.js` · `js/detalle.js` | 3 cada uno |

### Y dos servicios están apagados

`custodios` y `patios` no tienen ni una fecha **y sus pantallas están ocultas**
(ver *Custodios, patios y lavados están apagados en la interfaz* en
[FLUJO-OPERATIVO.md](FLUJO-OPERATIVO.md)). Sus ramas de este trabajo son hoy
un no-op: se crean por completitud, no porque muevan nada.

---

## La restricción que no se puede romper

**H-02 se cerró haciendo que solo el superadmin pueda escribir una fecha de
vigencia**, sostenido por `guard_perfil_self_update` — porque RLS deja a la
empresa actualizar su propia fila, así que ocultar el campo en la interfaz no
habría servido de nada.

Una tabla `vigencias` nueva **empieza sin ese guard**. Si se migran las
lecturas antes de replicar la protección, una empresa podría acreditarse sus
propios seguros escribiendo en la tabla nueva: **H-02 reabierto, y esta vez
sin que nadie lo esté mirando.**

Lo mismo con `guard_oferta_update`, que hoy lee las tres
`perfiles.fecha_vencimiento_*` para decidir si una empresa puede cerrar trato.
Mientras haya doble escritura puede seguir leyendo `perfiles`; el día que se
retiren esas columnas, tiene que leer la tabla nueva — y ese cambio es de
seguridad, no de refactor.

---

## Etapas

Ninguna etapa retira nada. El `DROP` de columnas es una conversación aparte y
exige autorización explícita (Regla #1).

### Etapa 1 — Crear, sin que nadie la lea  ·  **ESCRITA Y PROBADA EN BANCO LOCAL**

**Está en `supabase/migrations/20260918160000_vigencias_etapa1_crear.sql`.** Lo
que sigue describe lo que esa migración hace; el SQL literal vive ahí y es el
que manda. Este boceto se corrigió el mismo día porque el primero, escrito
antes de construirla, ya no decía la verdad en tres puntos: proponía un
`fecha_vencimiento` (ver la sexta decisión), un `UNIQUE` simple (ver la
segunda) y un trigger donde acabó habiendo una clave foránea (la cuarta).

- `vigencias(id, entidad_tipo, entidad_id, tipo_documento, archivo_path,
  **fecha_documento**, estado, nota_rechazo, subido_en/por, revisado_en/por,
  cat_clave)`.
- **`cat_clave`** es una columna generada con valor constante
  `'vigencia_tipo'`, y existe solo para colgar la **FK compuesta** contra
  `catalogos(clave, valor)`. Probada en banco local: rechaza un tipo inventado.
- Cuatro `CHECK`: la lista de entidades, la de estados, «algo que guardar»
  (papel o fecha, no una fila vacía) y «un rechazo lleva motivo».
- **Dos índices únicos parciales** en lugar de un `UNIQUE`: uno por
  `estado = 'vigente'` y otro por `estado = 'pendiente'`.
- Índices sobre `fecha_documento` —el que hoy no existe en ninguna de las cinco
  tablas— y sobre `(entidad_tipo, entidad_id)`.
- `vigencia_vence_el(tipo, fecha)` aplica la regla del catálogo.
- RLS: lee el dueño o el superadmin; la empresa solo puede **insertar**
  `pendiente` sobre entidades suyas; el superadmin, todo.
- **El guard va en esta misma migración**, no después: `guard_vigencia_update`
  impide que una empresa pase su propia propuesta a `vigente`, firme la
  revisión o toque un documento ya acreditado.
- Un bloque de comprobación al final que hace fallar la migración si falta
  cualquiera de esas piezas, en vez de aplicarla a medias.

`entidad_id` es `text` porque las PK de flota lo son y las de `perfiles` son
`uuid`. No hay FK posible hacia la entidad — es el mismo problema que H-06 — y
por eso el dueño se resuelve con `vigencia_propietario()`, que consulta la
tabla que corresponda según `entidad_tipo`.

**Probada**: `pruebas/banco-local/h04-etapa1.sql`, 21 afirmaciones contra un
Postgres local con el esquema de producción cargado sin un solo error, en
transacción revertida. Nueve comprueban que **rechaza** lo que debe rechazar.

### Etapa 2 — Copiar  ·  **APLICADA A PRUEBAS el 2026-09-21**

`supabase/migrations/20260921120000_vigencias_etapa2_copiar.sql`. Un
`insert … select` por tabla de origen, re-aplicable. Reversible con un
`delete` acotado por `entidad_tipo`.

**Copió 63 filas, no las ~44 estimadas**, y la diferencia enseña algo:

| | Estimado | Real |
|---|---|---|
| perfil | ~3 | 3 |
| camión | ~33 | 48 |
| operador | ~8 | 12 |
| custodio · patio | 0 | 0 |

La estimación del 18/09 contaba **filas con alguna fecha** y además redondeaba
a la baja: las fechas eran 49, no 44. Los 14 restantes son documentos con
**archivo pero sin vencimiento**, que aquella cuenta ni miraba. `49 + 14 = 63`.

#### Lo que la tabla unificada hizo visible el primer día

Medido en pruebas el 2026-09-21, tras una réplica que dio paridad
`identicas` — las columnas de origen no las tocan estas migraciones, así que
son los datos de producción:

```
con archivo y SIN fecha de vencimiento   14   <- nada las vigila
con fecha y SIN archivo                  15
en estado 'pendiente'                     0

  camion/tarjeta_circulacion      5
  camion/seguro_unidad            3
  camion/permiso_sct_unidad       3
  operador/licencia               1
  operador/examen_toxicologico    1
  operador/carta_antecedentes     1
```

**Catorce papeles que nadie vigila.** El flujo operativo ya lo advertía como
regla —«un documento sin fecha no se vigila jamás»— pero hasta ahora nadie
podía contar cuántos eran sin un `UNION` de cinco ramas escrito a mano. Cinco
de ellos son tarjetas de circulación.

Y quince al revés: vencimiento declarado sin papel detrás.

**No es un defecto de la copia** —los trajo fielmente— ni algo que esta etapa
deba arreglar. Es una decisión de producto pendiente: o se exige la fecha al
subir el papel, o se asume que esos catorce no se vigilan. Queda anotado, sin
tocar.

### Etapa 3 — Doble escritura  ·  **ESCRITA Y PROBADA EN BANCO LOCAL**

`supabase/migrations/20260922120000_vigencias_etapa3_doble_escritura.sql`.
Las lecturas siguen en las columnas viejas. **Aquí se vive un tiempo.**

**Va en la base, no en el cliente**, y la razón es un número: los sitios que
escriben esas columnas hoy son **128** entre `admin.js` (44), `operadores.js`
(29) y `aprobaciones.js` (55). Duplicar la escritura ahí es tocar 128 puntos,
y olvidar uno no da error — deja las dos fuentes divergiendo en silencio, que
es justo lo que esta etapa existe para detectar. Además hay un escritor que el
navegador no cubre: los clientes nativos escriben por su cuenta contra la
misma base.

Un solo trigger `vigencias_espejo()` sobre las cinco tablas, con el mapeo como
datos y `to_jsonb(new)` para leer la columna por su nombre. Tres casos por
par: hay dato → upsert; no hay y antes sí → **borra la fila**, para no dejar un
documento fantasma vigilando; no hay y antes tampoco → nada.

#### El guard de la Etapa 1 estaba mal, y se corrige aquí

Al montar el espejo saltó `VIGENCIA_ACREDITADA` — reproducido en banco local
antes de tocar nada. **La causa no era el espejo: era el guard.** Aplicaba la
lección de H-02 —«solo el superadmin acredita»— a las cinco entidades por
igual, y las reglas reales no son iguales:

| | Quién puede escribir hoy la fecha |
|---|---|
| `perfiles` | **solo el superadmin** — `guard_perfil_self_update`, que es H-02 |
| flota y operadores | **el dueño** — `guard_fleet_resource_update` solo impide auto-aprobarse y transferir la propiedad; editar manda el recurso a `pendiente` |

Mi guard era más estricto que el sistema, así que el espejo no podía reflejar
una escritura que la fuente sí permite. Corregido para que diga lo mismo que
las reglas de origen. **Con eso el espejo no necesita ninguna puerta trasera**:
hereda la autorización de la fuente, porque esa escritura ya pasó por su
propio RLS y su propio guard.

#### Probado por los dos lados

`pruebas/banco-local/h04-etapa3.sql`, nueve afirmaciones: la empresa escribe
su camión y el espejo la sigue; cambiar la fecha actualiza y no duplica;
quitar el papel borra la fila; la empresa puede **proponer** pero no
acreditarse sola; el superadmin acredita el perfil y la empresa no puede
tocarlo (**H-02 no se reabre**); nadie muda un documento a otra entidad; y un
`INSERT` también se refleja.

`pruebas/14-sonda-espejo-vigencias.mjs` compara las dos fuentes par a par
contra una base real y falla nombrando entidad, documento y los dos valores.
Primera corrida contra pruebas: **63 pares, 63 filas, todas coinciden** — lo
que de paso confirma, con un mapeo reimplementado aparte, que la copia de la
Etapa 2 es fiel.

**Lo que esa sonda no puede comprobar**, y por eso hacen falta las dos: que el
trigger *dispare*. Compara estados, no eventos. Si el espejo estuviera roto
pero nadie hubiera escrito, saldría en verde igual.

### Etapa 3b — El espejo deja de tumbar la escritura de origen

`supabase/migrations/20260922130000_vigencias_espejo_tolerante.sql`.

La Etapa 3 lo dejó en «todo o nada»: trigger `AFTER` en la misma transacción,
así que un fallo del espejo tumba la escritura de origen. Medido rompiéndolo a
propósito:

```
La escritura de origen FALLO por culpa del espejo: VIGENCIA_TIPO_AJENO
```

**Ese precio lo paga la operación, no la integridad.** Mientras nadie lea
`vigencias`, un fallo del espejo no le quita un dato a ninguna pantalla, pero
sí le impide a una empresa guardar su camión. Se cambia «romper la operación»
por «divergir y que una sonda lo diga».

Cada documento va en su propio bloque, así que un tipo que falle no se lleva
por delante a los otros cinco de la misma unidad. Comprobado: con el espejo
roto para `seguro_unidad`, la escritura sobrevivió **y** `verificacion` se
reflejó igual.

> ⚠ **La Etapa 4 tiene que devolverlo a estricto.** Cuando las lecturas se
> muevan, una fuente sin espejo deja de ser una divergencia anotada y pasa a
> ser un dato que falta en pantalla.

### Etapa 3c — El espejo se entera de los borrados  ·  **PROBADA EN BANCO LOCAL**

`supabase/migrations/20260922140000_vigencias_espejo_borrado.sql`.

La Etapa 3 colgó el espejo de `after insert or update`. **Faltaba `delete`**, y
las cinco tablas de origen se borran de verdad desde el cliente:
[js/admin.js:840](../js/admin.js) (`eliminarUnidad`),
[js/admin.js:668](../js/admin.js) (`eliminarMiRecurso`),
[js/admin.js:1249](../js/admin.js) y [:1400](../js/admin.js)
(custodios, patios), [js/operadores.js:500](../js/operadores.js), y `perfiles`
en cascada al borrar el usuario de auth.

`vigencias.entidad_id` es `text` y polimórfico — apunta a cinco tablas con PK
distinta —, así que **no puede tener clave foránea** y no hay
`on delete cascade` que lo salve. Las únicas FK de la tabla son a `auth.users`
y al catálogo.

**Por qué no se vio antes, que es la parte que importa.** La sonda 14 sí caza
estos fantasmas: los cuenta como «filas de más». Pero nadie había borrado nada
desde la Etapa 2, así que salía verde. *Un verde no prueba que el caso esté
cubierto; prueba que el caso no ha ocurrido.*

Qué hace: `vigencias_espejo()` aprende `TG_OP = 'DELETE'` (lee OLD, borra las
filas de esa entidad **de cualquier estado**, también un `rechazado` que el
mapeo nunca escribe); los cinco triggers pasan a
`after insert or update or delete` con `create or replace trigger`, sin tirar
nada; y un barrido limpia las huérfanas que ya hubiera.

Sigue siendo **tolerante**: si el borrado del espejo falla, avisa y el borrado
de origen continúa.

Medido en banco local rehecho desde el volcado de producción
([pruebas/banco-local/h04-etapa3c.sql](../pruebas/banco-local/h04-etapa3c.sql)),
cinco bloques en verde:

- borrar un camión barre sus 4 filas (incluida la `rechazado`) y **no toca** las
  de otro camión,
- lo mismo para operador, custodio, patio y perfil,
- **con el trigger devuelto a `insert or update`, el fantasma se queda** — el
  hueco era real y la prueba sabe verlo,
- con el espejo roto a propósito, el camión se borra igual (el trato de 3b
  sigue en pie para el borrado),
- y el barrido de la migración encuentra las dos huérfanas que esa corrida
  dejó.

Y desde un banco limpio hasta 3b, con un fantasma real sembrado, la migración
imprimió `fantasmas barridos: 1`.

> ⚠ **La Etapa 4 sigue teniendo que devolver el espejo a estricto.** 3c no
> cambia ese pendiente.

### Etapa 4 — Cambiar lecturas, fichero a fichero

En este orden, de menos a más superficie: `catalogo.js` (11) → `detalle.js` y
`cobros.js` (3) → `reservaciones.js` (7) → `operadores.js` (15) →
`pedidos.js` (16) → `vigencias.js` (29) → `admin.js` (36) →
`aprobaciones.js` (48).

Las diez consultas de `js/vigencias.js` colapsan en una. Ese es el premio.

### Etapa 5 — Los guards

`guard_oferta_update` pasa a leer `vigencias`. **Con su propia prueba de que
sigue frenando**, por las dos direcciones: que una empresa con papel vencido
no pueda cerrar, y que una al día sí.

### Etapa 6 — Retirar columnas

**No forma parte de este plan.** Se plantea cuando lo nuevo lleve tiempo
funcionando, con la vía segura de H-15: confirmar cero lecturas, renombrar a
`zz_*`, dejar pasar un ciclo de despliegue, y solo entonces proponer el `DROP`
con autorización explícita.

---

## Decisiones tomadas

El usuario las delegó el 2026-09-18 («aplícalas de acuerdo a lo que funcione
mejor para el sistema y la base de datos»). Quedan escritas con su porqué, que
es lo que se pierde si solo queda el código.

1. **La tabla guarda documento Y fecha.** El concepto es «documento con
   vigencia»; separarlos conservaría la duplicación que el hallazgo denuncia.
   `archivo_path` es nulo cuando no hay papel.

2. **`*_pendiente` son dos filas**, distinguidas por `estado`, con **dos
   índices únicos parciales**: como mucho una `vigente` y como mucho una
   `pendiente` por documento. Un `UNIQUE(entidad, tipo)` a secas habría roto
   lo que hoy funciona — la empresa propone una renovación **sin destruir la
   que sigue valiendo**. Los `rechazado` no se limitan: son historial.

3. **Fechas sin papel: sí, como filas con `archivo_path` nulo**, más un
   `CHECK` de que al menos una de las dos cosas esté. Una fila sin papel y sin
   fecha no dice nada, y H-02 enseñó lo que cuesta un campo que existe vacío.

4. **`tipo_documento` sale de `catalogos`, con clave foránea de verdad.** Se
   probó en el banco local antes de escribirlo: una columna generada con valor
   constante (`cat_clave`) permite colgar una **FK compuesta** de
   `catalogos(clave, valor)`, y rechaza un tipo inventado. Es más fuerte que
   un trigger, que puede olvidarse de comprobar. Añadir un documento pasa a
   ser un `insert` en el catálogo.

5. **Custodios y patios entran en el modelo, no en el trabajo de código.**
   Están en el `CHECK` y en el catálogo porque incluirlos no cuesta nada y
   evita una segunda migración; sus ficheros JS no se tocan mientras sigan
   apagados y sin datos.

### Séptima: las fechas de expedición se quedan fuera del modelo

**Decisión del usuario, 2026-09-19: «solo nos interesa la fecha en la que
vence el documento; para la operación no es relevante cuándo fue emitido».**

Esto surgió porque al preparar la Etapa 2 apareció que dos columnas guardan
**emisión**, no caducidad, y sí se usan:

| Columna | Dónde |
|---|---|
| `camiones.fecha_expedicion_tc` | formulario de alta y de edición (`admin.js`), y una línea «TC expedición» que el superadmin ve al aprobar (`aprobaciones.js:688`) |
| `operadores.fecha_expedicion` | formulario de alta de operador (`operadores.js`) |

Comprobado una por una: **ninguna de las diez apariciones es una regla.** No
hay guard, política ni filtro que dependa de ellas; se capturan y se enseñan.

**Consecuencias, para que no se redescubran:**

1. **No se añade `fecha_expedicion` a `vigencias`.** La tabla se queda con una
   sola `fecha_documento`, tal como se aplicó. No hace falta una Etapa 1b.
2. **Las dos columnas se quedan donde están** y sus pantallas siguen
   funcionando igual. No son «documento con vigencia»: son un dato *sobre* el
   documento.
3. **Tampoco entran en la Etapa 6.** Cuando se plantee retirar columnas, estas
   dos no son candidatas — se siguen leyendo y escribiendo.

**Lo que esta decisión NO cambia:** los exámenes del operador siguen
capturándose por su fecha de realización y su caducidad se deriva, como
explica la sexta decisión. Ahí la fecha capturada es el único dato que existe;
no hay una caducidad que guardar en su lugar.

### Y una sexta, que no estaba en la lista y salió de leer el código

**Las columnas de hoy no guardan todas lo mismo.**
`fecha_vencimiento_seguro` es una caducidad, pero `fecha_examen_medico` es la
fecha **del examen**: `js/vigencias.js:69-72` le suma un año en JavaScript
para saber cuándo vence. Igual con el toxicológico y la carta de antecedentes.

Meterlas todas en un `fecha_vencimiento` perdería la diferencia, y calcular la
caducidad al copiar **hornearía la regla de negocio en los datos**: el día que
un examen valga dos años, las filas viejas quedarían mal y nadie sabría por
qué.

Así que se guarda **lo que el usuario capturó**, en `fecha_documento`, y la
regla vive en el catálogo (`meta->>'vigencia_meses'`; nulo = la fecha
capturada ya es la caducidad). La caducidad efectiva la calcula
`vigencia_vence_el(tipo, fecha)`. **Comprobado en el banco local: subir el
examen médico de 12 a 24 meses es un `UPDATE` a una fila de catálogo, no una
migración.** Ese es el beneficio que justifica el trabajo entero.

---

## Paridad

Lo medido aquí sale de `portgo-pruebas` con el sello en **`diverge`** (6
diferencias, 2026-09-18 22:24 UTC). Las diferencias son las cuatro de
`EXECUTE`/`service_role` y el hash de `notificaciones`, ninguna relacionada
con estas tablas — pero **antes de sembrar o probar nada de este plan hay que
replicar y volver a verificar**, como exige la Regla #3.
