# Probar la Etapa 4 de H-04 en el preview de `dev`

Cinco pantallas, con los valores concretos que hay hoy en `portgo-pruebas` y lo
que tiene que salir en cada una.

**Qué se está probando:** cinco ficheros cambiaron de dónde leen las fechas de
vencimiento — antes de las columnas viejas, ahora de la tabla `vigencias`. Ya
está comprobado **por medición** que las consultas nuevas devuelven lo mismo que
las viejas. Lo que falta, y es lo único que esto prueba, es **que el código
corra**: una variable fuera de alcance o un argumento mal pasado no da error de
compilación y solo aparece al abrir la pantalla.

Despliegue verificado en `success` el 2026-09-23 19:21 UTC, commit `876cef3`.

## Antes de empezar

Entra al preview y **confirma que no es producción**:

```
https://portgo-git-dev-salvador-s-projects13.vercel.app/app.html
```

**Ctrl+Shift+R** (recarga forzada). Luego F12 → Console, pega esto:

```js
console.log(JSON.stringify({ base: sb.supabaseUrl,
  v: [...document.scripts].filter(s=>/pedidos|operadores|reservaciones/.test(s.src)).map(s=>s.src.split('/').pop())
}, null, 2))
```

Tiene que decir `xskgnudiznryhgagxadu` (si dice `xnyqsewaluezkkrlyhxg` **estás en
producción, para**), y las versiones tienen que ser **`pedidos.js?v=81`**,
**`operadores.js?v=17`** y **`reservaciones.js?v=57`**. Si alguna es menor, el
despliegue no ha llegado a tu navegador: vuelve a forzar recarga y no sigas.

---

## 1 · Catálogo de proveedores  ·  *como cliente*

Entra como **cliente** (`mariosilva@cliente.com`) → tarjeta **🏢 Catálogo**
(«Empresas verificadas») en la portada.

**Debe pasar:** la tarjeta de **Omar Silva Preciado** muestra estos cuatro
distintivos:

```
SCT ✓      Seg. RC ✓      Seg. Carga ✓      ✅ Docs al día
```

Las otras dos empresas (**Champi** y **Salvador Alejandro Corona Silva**) no
muestran ninguno de esos cuatro — no tienen documentos acreditados, y eso es
correcto.

> Esto es lo que prueba que la vista `empresas_publico` sirve bien las fechas
> desde `vigencias` a alguien que **no es el dueño** de esos documentos. Si los
> distintivos de Omar desaparecieran, la RLS estaría tapando lo que no debe.

Pulsa **Ver empresa** en la tarjeta de Omar.

**Debe pasar:** el modal lista estas tres filas con sus fechas:

| Fila | Fecha |
|---|---|
| 📋 Permiso SCT | Vence: 20/10/2027 ✓ |
| 🛡️ Seguro RC | 21/11/2027 ✓ |
| 📦 Seguro de carga | 22/12/2027 ✓ |

---

## 2 · Tarjetas de operador  ·  *como empresa*

Sal y entra como **empresa** (`omar_silvap@hotmail.com`) → tarjeta **Operadores**
(«Personal de conducción»).

**Debe pasar:** dos tarjetas, y la línea de licencia distinta en cada una:

| Operador | Línea de licencia |
|---|---|
| **Espejo Uno** (`OP-B54E541A`) | `Licencia vence: 16/06/2028` — sin aviso |
| **Ernesto Preciado** (`OP-A86E8DC0`) | **ninguna línea de licencia** (no tiene fecha) |

> Si la línea de Espejo Uno no aparece, el `Map` que ahora alimenta la tarjeta
> no está llegando: ese es exactamente el fallo que la medición no podía cazar.

### Y de paso, que el formulario siga leyendo lo suyo

Pulsa **✏ Editar** en **Espejo Uno**.

**Debe pasar:** los campos de fechas salen rellenos con lo que se capturó en las
pruebas del espejo:

| Campo | Valor esperado |
|---|---|
| Vencimiento de la licencia | `2028-06-16` |
| Examen médico | `2026-07-17` |
| Examen toxicológico | `2026-08-18` |
| Carta de antecedentes | `2026-09-19` |

Esto comprueba la decisión del 2026-09-23: **el formulario sigue leyendo las
columnas del operador**, que es donde escribe. Si salieran vacíos, se habría
migrado de más.

### Cómo salir sin guardar

**No guardes nada.** Pulsa **«Cancelar edición»**, el botón que está al lado de
«✏ Guardar cambios y enviar a aprobación».

Abandona la edición, vacía el formulario y **no guarda nada, no borra nada del
operador y no toca la base**: el operador se queda exactamente como estaba.

> **Ese botón decía «Limpiar» hasta el 2026-09-23**, y se cambió a raíz de esta
> misma prueba. La etiqueta estaba escrita para el modo *alta* —donde sí
> describe lo que hace— y el código renombraba solo el botón principal al entrar
> en edición, dejando el de al lado con la etiqueta del otro modo. Ahora se
> renombran los dos, y al salir vuelve a decir «Limpiar».
>
> **Compruébalo de paso:** tras pulsarlo, el botón de la izquierda tiene que
> volver a decir «Enviar a aprobación» y el de la derecha «Limpiar».

---

## 3 · Asignar chofer  ·  *como empresa*

Tarjeta **Reservaciones** («Viajes y servicios activos») → busca la reserva de la
unidad **`S-965A48AE`**, cliente **Mario Silva**, estado **Activa**.

> **El botón no dice «Asignar chofer»**: esa reserva ya tiene uno, así que el
> botón muestra **`👷 Ernesto Preciado`**. Ese es el que hay que pulsar.
> (La etiqueta «👷 Asignar chofer» solo sale cuando no hay chofer puesto.)

**Debe pasar:** el desplegable lista **los dos** operadores (Espejo Uno y
Ernesto Preciado), y aparece preseleccionado **Ernesto Preciado**, que es el que
ya tiene asignado.

> Aquí no se filtra por licencia HAZMAT porque el pedido de esa reserva **no es
> de carga peligrosa** (comprobado: `carga_peligrosa = false`). Lo que esta
> pantalla prueba es que la función corre y llena la lista. El filtro HAZMAT se
> prueba en el paso 5, que sí lo dispara.

**No guardes nada.** Cierra el modal.

---

## 4 · Crear el pedido de prueba  ·  *como cliente*, luego *superadmin*

Hoy **no hay ningún pedido abierto** en pruebas, así que hay que crear uno. Se
diseñó para disparar dos caminos a la vez: categoría **Hazmat** (activa el filtro
de choferes) con unidad **Torton** (saca los camiones que tienen fechas).

### a) Como cliente — publicar la solicitud

Entra como **cliente** → tarjeta **Solicitar servicio** («Transporte, custodia y
más»), con estos datos:

| Campo | Valor |
|---|---|
| Categoría de carga | **☣️ Hazmat** |
| Tipo de unidad | **Torton** |
| Origen / destino | lo que quieras (p. ej. `Manzanillo` → `Guadalajara`) |
| Fecha inicio | cualquiera dentro de los próximos días |
| Peso | cualquiera |
| Clase / UN de hazmat | lo que pida, p. ej. clase `3`, `UN1203` |

Publícala.

### b) Como superadmin — aprobarla

Entra como **superadmin** (`omarsilvap@gmail.com`) → tarjeta **Por aprobar**
(«Solicitudes y recursos pendientes») → la solicitud recién creada →
**✓ Aprobar y publicar**.

**Debe pasar:** el pedido pasa a **abierto** y desaparece de la cola.

---

## 5 · Hacer oferta  ·  *como empresa*  ·  **el paso que más cubre**

Entra como **empresa** → tarjeta **Solicitudes** («Ofertas y pedidos activos») →
el pedido que acabas de publicar → **💼 Hacer oferta**.

**Debe pasar, cuatro cosas:**

**1. El modal se abre con normalidad.** No sale el aviso rojo «⛔ No puedes hacer
ofertas — documentos de empresa vencidos». Esa comprobación ahora lee
`vigencias`, y las tres de Omar vencen en 2027, así que no bloquea.

**2. El desplegable de camión lista los dos Torton:**

```
🚛 T-46BC79F9 — Torton (… ton)
🚛 T-629F701C — Torton (… ton)
```

**3. Selecciona `T-629F701C`.** **No debe aparecer** el aviso «⚠ Esta unidad
tiene documentos vencidos». Esa unidad es el `ESP-001` de las pruebas del
espejo, y sus cinco fechas son futuras:

| Documento | Vence |
|---|---|
| Tarjeta de circulación | 2027-01-11 |
| Seguro | 2027-02-12 |
| Permiso SCT | 2027-03-13 |
| CAAT | 2028-04-14 |
| Verificación vehicular | 2027-05-15 |

> Este es el punto con más valor de todo el guion: esas cinco fechas son
> **distintas entre sí a propósito**, así que si el código hubiera confundido un
> tipo de documento con otro, el aviso saldría mal o saldría cuando no debe.

**4. El desplegable de chofer muestra SOLO a `Espejo Uno`.** **`Ernesto
Preciado` no debe aparecer**, porque no tiene licencia de materiales peligrosos
y el pedido es Hazmat. Espejo Uno sí la tiene, vigente hasta **2028-03-15**.

> Si aparecieran los dos, el filtro HAZMAT no está aplicándose. Si no apareciera
> ninguno, saldría el aviso «Ningún chofer registrado tiene licencia de
> materiales peligrosos vigente» y también sería un fallo.

**No envíes la oferta** — con abrir el modal y mirar los dos desplegables está
todo cubierto. Cierra.

---

## Si algo no cuadra

Antes de dar por roto el código, descarta lo de siempre:

1. **¿Estás en el preview y no en producción?** El bloque de la consola del
   principio lo dice.
2. **¿Te llegó la versión nueva?** Si `pedidos.js` no dice `?v=81`, estás viendo
   el fichero viejo en cache. Ctrl+Shift+R.

Si las dos están bien, es un fallo real: apunta **en qué paso**, **qué esperabas**
y **qué salió**, y con eso se arregla. No hace falta que investigues la causa.

## Lo que este guion NO prueba

Para que no se dé por cubierto lo que no lo está:

- **El filtro HAZMAT de `reservaciones.js`** (paso 3) no llega a dispararse,
  porque no hay ninguna reserva activa de carga peligrosa. Su equivalencia sí se
  midió: con licencia vigente el chofer sale, con licencia vencida no.
- **La rama de «documentos de empresa vencidos»** (paso 5, punto 1) tampoco se
  dispara, porque las tres vigencias de Omar son de 2027. Se midió con fechas
  simuladas: los tres documentos van cayendo uno a uno igual por los dos caminos.
- **`aprobaciones.js` y `vigencias.js`** todavía no se han migrado, así que sus
  pantallas siguen leyendo las columnas viejas. No hay nada que probar ahí.
