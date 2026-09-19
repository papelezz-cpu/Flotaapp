# H-04 — Unificar «documento con vigencia» en una tabla

Plan por etapas. **La Etapa 1 está escrita y probada en banco local; no se ha aplicado a ninguna base real.** El resto no está implementado. Escrito el 2026-09-18 con
los datos medidos ese día contra `portgo-pruebas` (sello `diverge`, 6
diferencias — ver §Paridad).

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

### Etapa 2 — Copiar

Un `insert … select` por tabla de origen. ~44 filas. Reversible con un
`delete` acotado por `entidad_tipo`.

### Etapa 3 — Doble escritura

Todo lo que hoy escribe una `fecha_vencimiento_*` escribe además la fila de
`vigencias`. Las lecturas siguen en las columnas viejas. **Aquí se vive un
tiempo**: si la copia diverge, se ve sin que nadie pierda nada.

Una sonda compara las dos fuentes fila a fila y falla si difieren, igual que
`12-sonda-propietario-reserva.mjs` hizo para H-06 (b).

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
