# H-04 — Unificar «documento con vigencia» en una tabla

Plan por etapas. **Nada de esto está implementado.** Escrito el 2026-09-18 con
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

### Etapa 1 — Crear, sin que nadie la lea

```sql
create table public.vigencias (
  id              uuid primary key default gen_random_uuid(),
  entidad_tipo    text not null check (entidad_tipo in
                    ('perfil','camion','operador','custodio','patio')),
  entidad_id      text not null,
  tipo_documento  text not null,
  archivo_path    text,
  fecha_vencimiento date,
  estado          text,
  subido_en       timestamptz not null default now(),
  subido_por      uuid references auth.users(id) on delete set null,
  unique (entidad_tipo, entidad_id, tipo_documento)
);
create index on public.vigencias (fecha_vencimiento)
  where fecha_vencimiento is not null;
```

Más: RLS con las mismas reglas que la tabla de origen de cada `entidad_tipo`,
y **el guard equivalente a `guard_perfil_self_update` desde el primer día**,
no después.

`entidad_id` es `text` porque las PK de flota lo son y las de `perfiles` son
`uuid`. No hay FK posible — es el mismo problema que H-06, y se sostiene con
un trigger que resuelve la tabla según `entidad_tipo`.

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

## Decisiones que hacen falta antes de la Etapa 1

Ninguna es técnica; las cinco son de producto o de criterio.

1. **¿La tabla guarda el documento o solo la fecha?** La ficha propone
   `archivo_path`, o sea las dos cosas. Eso absorbe también las columnas
   `doc_*`, `imagen_*` y `foto_*` — más beneficio y más superficie.

2. **¿Qué pasa con las variantes `*_pendiente` de `perfiles`?** Son el flujo
   de «la empresa propone, el superadmin acredita». ¿Se modelan como una fila
   con `estado = 'pendiente'`, o como una segunda fila?

3. **Fechas sin documento.** `operadores.fecha_examen_medico` y hermanas son
   fechas que hoy no tienen papel asociado. ¿Filas con `archivo_path` nulo, o
   quedan fuera del modelo?

4. **El catálogo de tipos de documento.** ¿`tipo_documento` es texto libre con
   `CHECK`, o una fila en la tabla `catalogos` que ya existe? Lo segundo es lo
   que haría que «añadir un documento» deje de ser una migración — que es el
   beneficio que justifica todo esto.

5. **Custodios y patios.** ¿Se incluyen ahora, estando apagados y sin datos, o
   se dejan para cuando se reactiven?

---

## Paridad

Lo medido aquí sale de `portgo-pruebas` con el sello en **`diverge`** (6
diferencias, 2026-09-18 22:24 UTC). Las diferencias son las cuatro de
`EXECUTE`/`service_role` y el hash de `notificaciones`, ninguna relacionada
con estas tablas — pero **antes de sembrar o probar nada de este plan hay que
replicar y volver a verificar**, como exige la Regla #3.
