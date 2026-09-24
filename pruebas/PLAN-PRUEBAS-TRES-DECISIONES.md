# Probar las tres decisiones del 2026-09-24 en el preview de `dev`

Guion para lo que se construyó a partir de tres decisiones de producto:

1. **El permiso hazmat del camión frena el trato** (antes se exigía al alta y
   nadie lo leía).
2. **Todo papel se sube con su fecha de vencimiento.**
3. **Todo recurso tiene dueño**, y los 7 huérfanos pasan a Omar Silva Preciado.

**Qué cubre este guion y qué no.** La decisión 2 es **enteramente validación de
formularios**, que es justo lo que ninguna medición alcanza: hay que teclear y
pulsar. La 1 y la 3 tienen su parte medida y su parte visible; aquí se comprueba
la visible. Lo que no se puede probar con estos datos está dicho al final, con su
motivo.

## Antes de empezar

Las dos migraciones tienen que estar aplicadas a pruebas:

```bash
bash supabase/aplicar-a-pruebas.sh supabase/migrations/20260924140000_recursos_con_dueno_obligatorio.sql
bash supabase/aplicar-a-pruebas.sh supabase/migrations/20260924150000_hazmat_del_camion_frena_el_trato.sql
```

Preview, **Ctrl+Shift+R**, y en la consola (F12):

```js
console.log(JSON.stringify({ base: sb.supabaseUrl,
  v: [...document.scripts].filter(s=>/admin|operadores|pedidos|vigencias|aprobaciones/.test(s.src)).map(s=>s.src.split('/').pop())
}, null, 2))
```

Debe decir `xskgnudiznryhgagxadu` y: **`admin.js?v=38`**, **`operadores.js?v=18`**,
**`pedidos.js?v=82`**, **`vigencias.js?v=7`**, **`aprobaciones.js?v=46`**.
Si alguna es menor, no sigas.

---

## 1 · Panel de Vigencias  ·  *como superadmin*

Aquí se ven las decisiones 1 y 3 a la vez. Portada → **Vigencias**.

**Debe pasar, en la sección «Documentos sin fecha»:**

| Grupo | Antes | Ahora |
|---|---|---|
| 🏢 Champi | 10 | **11** |
| 🏢 Omar Silva Preciado | 12 | **19** |
| 🏢 *(sin nombre)* | 7 | **desaparece** |
| **Total** | 29 | **30** |

Las tres cifras dicen cosas distintas:

- **Champi sube a 11** porque su camión `C-001` está marcado para carga
  peligrosa y **no tiene permiso de materiales peligrosos**. Antes ese documento
  no aparecía en ninguna pantalla; ahora sale como «Permiso de materiales
  peligrosos» sin fecha. Busca esa línea dentro del grupo de Champi.
- **Omar sube a 19** porque hereda los 7 recursos huérfanos: los custodios
  `CUS-001`, `CUS-002`, `CUS-003`, `CUS-006` y los patios `PAT-001`, `PAT-002`,
  `PAT-005`.
- **El grupo sin nombre desaparece**, porque ya no hay recursos sin dueño. Era el
  hueco 9: sus documentos solo los veía el superadmin y **ninguna empresa podía
  renovarlos**.

**Y lo que NO debe cambiar:** la sección de vencidos y próximos sigue en **8**, y
el globo de la portada en **3**. Los dos camiones hazmat de Salvador
(`F-68BB47D7` y `T-73D4-001`) tienen permiso vigente —2026-12-05 y 2029-01-01—,
así que no entran en la ventana de 30 días. Si alguno apareciera, la comparación
de fechas se habría vuelto más estricta de lo que debe.

---

## 2 · Ofertar en un pedido de carga peligrosa  ·  *como empresa*

Entra como **empresa** (`omar_silvap@hotmail.com`) → **Solicitudes**.

**Cuál es la fila, por lo que se ve en pantalla** (identificarla por «la que se
sembró el 2026-09-23» no servía: esa fecha no aparece en la lista):

| Dato | Valor |
|---|---|
| Cliente | **Mario Silva** |
| Ruta | **Manzanillo, Colima** → **San Isidro Mazatepec, Tala, Jalisco** |
| Fecha de inicio | **28/09/2026** |
| Tipo | Torton |

> ⚠ **Hay otra fila que confunde, y ya pasó:** Omar tiene una oferta **aceptada**
> en un pedido distinto —un «Sencillo porta contenedor 40/20», en estado
> `acordado`— que se muestra con etiqueta de aceptado y **sin** botón de ofertar.
> No es esa. La de esta prueba es la de Manzanillo → Tala del 28 de septiembre.

Pulsa **💼 Hacer oferta** en esa.

**Debe pasar:** el desplegable de camión sale **vacío**, con el texto
**«Sin camiones con permiso hazmat vigente»**, y arriba el aviso:

> ⚠ Este pedido es de carga peligrosa y ninguna de tus unidades del tipo
> solicitado tiene permiso de materiales peligrosos vigente. Actualízalo en Mis
> unidades para poder ofertar.

**Antes ofrecía dos Tortons** (`T-46BC79F9` y `T-629F701C`). Medido el
2026-09-24: ninguno tiene permiso de materiales peligrosos, y de hecho no están
marcados para moverla.

> Esto es la regla funcionando, no una regresión: el guard habría rechazado el
> trato **al cerrarlo**, así que ofertar era gastar una oferta para descubrirlo
> al final. Ahora se sabe antes. Es el mismo trato que ya se le daba al chofer
> sin licencia HAZMAT.

**Comprueba también que un pedido normal NO se ve afectado:** abre «Hacer
oferta» en cualquier pedido que no sea de carga peligrosa. El desplegable debe
seguir ofreciendo los camiones del tipo pedido, con permiso hazmat o sin él. Si
saliera vacío, el filtro se estaría aplicando donde no debe — y eso bloquearía
la mayoría de los tratos del sistema.

---

## 3 · La fecha es obligatoria al subir el papel  ·  *como empresa*

**Esta es la parte que solo se puede probar a mano.** Cuatro formularios, y en
todos el resultado esperado es **un rechazo con mensaje**, sin guardar nada.

### a) Alta de camión

**Mis unidades → dar de alta.** Llena lo obligatorio (tipo, capacidad, placas),
adjunta las fotos que pida y **la Tarjeta de Circulación**, pero **deja vacía su
fecha de vencimiento**. Guarda.

**Debe pasar:**

> Falta la fecha de vencimiento de la tarjeta de circulación. Sin ella el
> documento no se vigila en Vigencias.

**No se guarda nada.** Pon la fecha y vuelve a intentarlo: ahora sí debe avanzar
(y si falta otro papel, se quejará de ese).

> Aquí estaba el origen de los **14 documentos con papel y sin vencimiento**: el
> alta exigía los papeles de TC, SCT y seguro y **ninguna de sus tres fechas**.

### b) Edición de camión

Edita un camión que tenga **algún campo de fecha vacío** —por ejemplo la
verificación vehicular— y **adjunta ese documento dejando la fecha en blanco**.

**Debe pasar:**

> Adjuntaste el documento de verificación vehicular pero falta su fecha de
> vencimiento. Sin ella no se vigila en Vigencias.

> Este formulario ya tenía la regla en el otro sentido desde antes —cambiar una
> fecha exige adjuntar el documento renovado—; lo que faltaba era el sentido
> inverso.

### c) Perfil de empresa

**Mis unidades → Perfil de empresa → Documentos legales.** Adjunta **el
documento del Seguro RC** y **deja su fecha vacía**, pero pon una fecha en el
Permiso SCT. Pulsa **Enviar documentos para aprobación**.

**Debe pasar:**

> Adjuntaste el seguro RC pero falta su fecha de vencimiento. Sin ella el
> documento no se vigila en Vigencias.

> Antes esto pasaba: el formulario pedía «al menos una fecha» de las tres, así
> que el RC se subía sin la suya y quedaba sin vigilar.

### d) Alta de operador

**Operadores → dar de alta.** Llena las cuatro fechas que ya exigía, y además
**adjunta la licencia de materiales peligrosos dejando su fecha vacía**.

**Debe pasar:**

> Adjuntaste la licencia de materiales peligrosos pero falta su fecha de
> vencimiento. Sin ella el documento no se vigila en Vigencias.

**No guardes ninguno de los cuatro.** Con ver el rechazo está probado. Para salir
del formulario de operador, el botón es **«Cancelar edición»** si estabas
editando, o simplemente no guardes si era un alta.

---

## Si algo no cuadra

1. ¿Estás en el preview y no en producción?
2. ¿Te llegaron las cinco versiones nuevas? (`admin.js?v=38` es la que más
   importa para el paso 3.)

Si las dos están bien, es un fallo real: apunta **en qué paso**, **qué
esperabas** y **qué salió**.

## Lo que este guion NO prueba, y por qué

- **Que el guard hazmat frene de verdad al cerrar el trato.** Para verlo haría
  falta ofertar con una unidad hazmat sin permiso vigente, y el único camión así
  es `C-001`, que es **de Champi** — y no hay credenciales de esa empresa. Está
  cubierto por `pruebas/banco-local/hazmat-camion-frena.sql`, siete bloques,
  incluida la comprobación de que la prueba sabe fallar.
- **El aviso al superadmin al aprobar un acuerdo** con documentos vencidos:
  necesita un pedido en `pendiente_acuerdo`, que no se puede producir sin lo
  anterior.
- **Que el `NOT NULL` del dueño frene un alta sin propietario.** Ningún
  formulario permite enviar un recurso sin dueño —los cinco lo ponen solos—, así
  que desde la interfaz no hay forma de intentarlo. Cubierto por
  `pruebas/banco-local/dueno-obligatorio.sql`, que lo intenta en las cinco
  tablas.
- **Los 14 documentos que ya existen sin fecha.** La regla nueva no los toca: no
  se pueden rellenar inventando datos. Siguen ahí hasta que alguien los complete
  con el papel delante.
