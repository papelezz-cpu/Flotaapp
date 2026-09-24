# Probar el resto de la Etapa 4: vigencias y aprobaciones

Segunda tanda del guion de la Etapa 4. La primera
([PLAN-PRUEBAS-ETAPA4.md](PLAN-PRUEBAS-ETAPA4.md)) cubrió catálogo, operadores,
asignar chofer y hacer oferta. Falta lo que se migró después:

- **`js/vigencias.js`** — el panel de documentos por vencer y el globo de la
  portada, en los dos roles.
- **`js/aprobaciones.js`** — el aviso de empresa con documentos vencidos y las
  cuatro tarjetas de aprobación.

**Qué se está probando, exactamente.** Las consultas nuevas ya están
comprobadas por medición contra los datos reales de pruebas: el panel coincide
en 8 vencidos/próximos y 29 sin fecha, el globo en 3, y las tarjetas en 98
celdas comparadas sin una sola diferencia. **Lo que falta es que el código
corra.** En esta etapa ya aparecieron **dos** fallos que ninguna medición podía
ver: un bloque de llaves huérfano en `pedidos.js` y un `ep.nombre` sin definir
en `aprobaciones.js`, que solo habría fallado al pulsar el botón.

## Antes de empezar

Preview, **Ctrl+Shift+R**, y en la consola (F12):

```js
console.log(JSON.stringify({ base: sb.supabaseUrl,
  v: [...document.scripts].filter(s=>/vigencias|aprobaciones/.test(s.src)).map(s=>s.src.split('/').pop())
}, null, 2))
```

Debe decir `xskgnudiznryhgagxadu`, **`vigencias.js?v=6`** y
**`aprobaciones.js?v=45`**. Si alguna versión es menor, no sigas: estás viendo
el fichero viejo.

---

## 1 · Panel de Vigencias  ·  *como superadmin*

Portada → tarjeta **Vigencias** («Documentos vencidos o por vencer»).

### a) El globo, antes de entrar

En la portada, la tarjeta **Vigencias** debe llevar el número **3**.

> Son **recursos** afectados, no documentos: la camioneta de Champi tiene cinco
> papeles vencidos y cuenta como uno. Los tres son la camioneta de Champi, el
> operador Mauricio Ortega y el Rabón de Salvador. **Por eso el globo dice 3 y
> el panel lista 8 documentos: no son la misma cuenta.**

> ⚠ **Este globo estuvo roto desde que se creó el panel, y se arregló el
> 2026-09-23 al probar este paso** (`vigencias.js?v=6`). `.hc-badge` nace con
> `display:none` en el CSS, y `actualizarBadgeVigencias()` era el único de los
> seis globos de la portada que escribía el número **sin tocar `display`**: el
> "3" estaba dentro del elemento y no se veía. Si pruebas con `?v=5` o anterior,
> el globo seguirá sin aparecer y no es un fallo nuevo.

### b) Dentro del panel — vencidos y próximos

Agrupado por empresa. Tienen que salir **8 documentos** repartidos así:

**🏢 Champi** — ⛔ 6 vencidos

| Recurso | Documento | Fecha |
|---|---|---|
| Camioneta 1.5 ton caja seca (…) | Tarjeta de Circulación | 08/08/2026 |
| la misma | Seguro | 08/08/2026 |
| la misma | Permiso SCT | 08/08/2026 |
| la misma | CAAT | 08/08/2026 |
| la misma | Verificación vehicular | 08/08/2026 |
| Mauricio Ortega | Licencia de conducir | 08/08/2026 |

Todos dicen **«Venció hace 46 días»** (si pruebas otro día, el número cambia).

**🏢 Salvador Alejandro Corona Silva** — ⚠ 2 próximos

| Recurso | Documento | Fecha | Aviso |
|---|---|---|---|
| Rabón (R-245DDBE5) | Verificación vehicular | 03/10/2026 | Vence en 10 días |
| Rabón (R-245DDBE5) | Seguro | 23/10/2026 | Vence en 30 días |

> **El de 30 días es el borde exacto** de la ventana de alerta. Si desapareciera,
> la comparación se habría vuelto estricta donde antes no lo era.

### c) La sección «Documentos sin fecha»

Debajo, **29 documentos** sin fecha registrada, agrupados:

| Empresa | Documentos sin fecha |
|---|---|
| 🏢 Champi | 10 |
| 🏢 Omar Silva Preciado | 12 |
| 🏢 **null** | 7 |

> **El grupo «null» no es un fallo de esta migración.** Son 4 custodios
> (`CUS-001`, `CUS-002`, `CUS-003`, `CUS-006`) y 3 patios (`PAT-001`, `PAT-002`,
> `PAT-005`) que **no tienen propietario** en la base. El código anterior los
> agrupaba igual. Custodios y patios son los servicios apagados en la interfaz
> (ver FLUJO-OPERATIVO.md), y esto es dato viejo heredado del clon de
> producción. **Anótalo como observación, no como fallo** — si quieres se mira
> aparte.

---

## 2 · Panel de Vigencias  ·  *como empresa*

Sal y entra como **empresa** (`omar_silvap@hotmail.com`) → **Vigencias**.

**Debe pasar:**

- La tarjeta de la portada **no lleva número** (esta empresa no tiene nada
  vencido ni próximo).
- Dentro: **ninguna sección de vencidos ni de próximos**.
- Sí sale **«Documentos sin fecha registrada (12)»**, sin agrupar por empresa
  (esa agrupación es solo del superadmin).

> Esto también comprueba lo que no debe pasar: la empresa **no ve** los 6
> documentos vencidos de Champi ni los 2 de Salvador. Si aparecieran, la RLS de
> la vista `vigencias_caducidad` no estaría aplicándose — es la fuga que la
> prueba de banco local caza, verificada aquí con datos reales.

---

## 3 · Tarjetas de aprobación  ·  *empresa*, luego *superadmin*

Hoy **no hay ningún recurso pendiente de aprobación**, así que hay que crear
uno. La forma natural: editar un recurso aprobado lo devuelve a revisión.

### a) Como empresa — mandar un camión a revisión

**Mis unidades** → editar el camión **`T-629F701C`** (es el `ESP-001` de las
pruebas del espejo, el que tiene las cinco fechas).

Cambia **solo la Marca o el Color** — algo que no sea una fecha.

> **No toques ninguna fecha.** Hay un candado que exige adjuntar el documento
> renovado en cuanto una fecha cambia ([js/admin.js:534](../js/admin.js)).
> Cambiando la marca no se dispara.

Guarda. Debe decir que los cambios quedaron **pendientes de aprobación**.

### b) Como empresa — y un operador

**Operadores** → **✏ Editar** en **Espejo Uno** → cambia algo inocuo (el
teléfono, por ejemplo) → **Guardar cambios y enviar a aprobación**.

### c) Como superadmin — mirar las dos tarjetas

**Por aprobar** → busca la empresa **Omar Silva Preciado**.

**En la tarjeta del camión `T-629F701C`**, las cinco filas de vigencia, todas
**sin ⛔** porque son futuras:

| Fila | Debe decir |
|---|---|
| Tarjeta de circulación | 11/01/2027 |
| Seguro | 12/02/2027 |
| Permiso SCT | 13/03/2027 |
| CAAT | 14/04/2028 |
| Verificación vehicular | 15/05/2027 |

> Las cinco fechas son **distintas entre sí a propósito**: si el código hubiera
> confundido un tipo de documento con otro, aquí se vería.

**En la tarjeta del operador `Espejo Uno`** — y esto es lo más interesante del
guion:

| Fila | Debe decir |
|---|---|
| Licencia de conducir | **16/06/2028** |
| Examen médico | **17/07/2026 → vence 17/07/2027** |
| Examen toxicológico | **18/08/2026 → vence 18/08/2027** |
| Carta antecedentes | **19/09/2026 → vence 19/09/2027** |

Tres cosas que comprobar ahí:

1. **La licencia sale con una sola fecha** y los tres exámenes con la forma
   «capturada → vence». Eso ya no lo decide una lista escrita en el código:
   lo decide el dato, comparando la fecha capturada con la calculada.
2. **Los exámenes suman exactamente 12 meses**, y ese 12 sale del catálogo, no
   de un `365` escrito en JavaScript.
3. **Las etiquetas ya NO dicen «(1 año)»** — es un cambio hecho a propósito. La
   fila muestra las dos fechas, que dicen lo mismo y no pueden quedarse
   mintiendo si el catálogo cambia.

### d) Dejarlo como estaba

Aprueba los dos recursos desde esa misma pantalla, para que el camión y el
operador vuelvan a `aprobada`.

---

## 4 · El aviso de empresa con documentos vencidos

**No se puede probar hoy, y conviene saber por qué.** El aviso «⚠️ La empresa X
tiene documentos vencidos: … ¿Aprobar el acuerdo de todas formas?» solo aparece
si hay un pedido en `pendiente_acuerdo` de una empresa con algún documento
caducado. Hoy no hay ninguno, y la única empresa con documentos acreditados
(Omar) los tiene vigentes hasta 2027.

Es justo la línea donde apareció el `ep.nombre` huérfano, así que **queda como
hueco conocido de este guion**. Su equivalencia sí está medida: las tres
empresas dan el mismo resultado por los dos caminos.

---

## Si algo no cuadra

1. ¿Estás en el preview y no en producción? El bloque de la consola lo dice.
2. ¿Te llegaron `vigencias.js?v=5` y `aprobaciones.js?v=45`?

Si las dos están bien, es un fallo real: apunta **en qué paso**, **qué
esperabas** y **qué salió**. No hace falta que busques la causa.

## Lo que este guion NO prueba

- **El aviso de acuerdo con documentos vencidos** (paso 4), por falta de datos.
- **Las tarjetas de custodio y patio**: sus pantallas están apagadas en la
  interfaz, así que no hay forma de mandar uno a revisión. Su lógica es la misma
  función que la del camión, y quedó medida con las 98 celdas.
- **Que el globo baje a 0**: haría falta renovar documentos reales de Champi.
