# Auditoría maestra de PortGo

**Qué es este archivo.** El consolidado de las **cuatro auditorías** que se le han hecho a
PortGo, con el estado real de cada hallazgo y —lo que más se usa a diario— **las reglas de
construcción que salieron de ellos**. No sustituye a los informes originales: los resume,
los contrasta entre sí y dice cuál de sus afirmaciones sigue siendo cierta hoy.

**Para qué sirve.** Para que un cambio nuevo no reintroduzca un fallo ya pagado. Cada regla
del §4 existe porque algo se rompió de esa manera exacta, y lleva el hallazgo que la produjo
entre paréntesis. Una regla sin hallazgo detrás no debería estar aquí.

**Última revisión:** 2026-09-28. Los hallazgos antiguos se re-midieron ese día contra el
volcado de producción `supabase/espejo/` (28/09) y contra el código de `dev`; donde una
auditoría anterior decía algo que ya no se cumple, este archivo lo dice y lo marca.

---

## 0. Cómo se usa

Este archivo es **uno de los tres maestros**, y el orden entre ellos importa — está fijado
en la [Regla #5 de CLAUDE.md](../CLAUDE.md):

| Archivo | Responde a |
|---|---|
| **`CLAUDE.md`** | Qué está prohibido, qué exige permiso, y cómo se despliega. Manda sobre los otros dos. |
| **`docs/FLUJO-OPERATIVO.md`** | Qué hace el sistema: qué rol, qué estado, qué guard, en qué orden. |
| **`docs/AUDITORIA.md`** (este) | Qué ya se rompió antes, qué sigue abierto, y qué regla evita repetirlo. |

**Si los tres se contradicen entre sí, gana el código** — y entonces hay que corregir el
documento que se equivocó, en el mismo commit. Nunca ajustar el código al papel.

### Antes de construir

Con este archivo delante, hay que poder responder:

1. **¿Lo que voy a tocar está en §3 (abierto)?** Entonces no es un hallazgo nuevo: es uno
   conocido, con su decisión ya tomada o pendiente. Se propone, no se arregla de tapadillo.
2. **¿Está en §5 (revisado y correcto)?** Entonces **no se toca.** Esa lista existe para que
   nadie «arregle» lo que ya está bien; cada entrada costó una auditoría averiguar por qué
   está así.
3. **¿Qué reglas del §4 aplican a lo que voy a escribir?** Si la respuesta es «ninguna», es
   casi seguro que no se leyeron: hay reglas para migraciones, permisos, consultas, código de
   cliente, estados, pruebas, despliegue y datos personales.

### Antes de dar algo por probado

§4.6 y §7. El resumen, porque es lo que más ha fallado en este proyecto: **una prueba que no
puede fallar no es una prueba**, y hay tres ejemplos medidos de verde sin evidencia.

### Después de cambiar

Se actualiza **en el mismo commit**, igual que `FLUJO-OPERATIVO.md`. Obligan a tocarlo: un
hallazgo cerrado, un hallazgo nuevo, una regla nueva, y **cualquier afirmación de aquí que
resulte falsa al medirla** — esa es la más importante, porque un informe que se corrige en
silencio no sirve para auditar nada.

### Lo que este archivo NO es

- **No es el informe.** Los cuatro originales siguen en el repositorio (§1) y conservan su
  redacción, incluidas las partes que resultaron equivocadas. Se conservan a propósito: el
  error de un informe es dato para el siguiente.
- **No es una lista de tareas.** El orden de trabajo lo decide el usuario. Aquí está el
  estado, no la prioridad.
- **No autoriza nada.** Que un hallazgo esté abierto no es permiso para cerrarlo: las Reglas
  #1 y #2 de `CLAUDE.md` siguen mandando.

---

## 1. Las cuatro auditorías, y qué puede afirmar cada una

| # | Fecha | Alcance | Fuente de verdad | Hallazgos | Dónde vive |
|---|---|---|---|---|---|
| **1ª — Pentest** | 2026-08-24 | Seguridad de la app (PWA + Supabase), ejercitada | **Ejecución real** contra `portgo-pruebas` con sesiones de 5 cuentas; escrituras no destructivas | 9 · `F-01`…`F-09` | [`security-findings.md`](../security-findings.md) |
| **2ª — Base de datos** | 2026-08-28 | Esquema + código + Android | **La base viva**: `pg_catalog`, `pg_stat_statements`, `pg_stat_user_tables`, `EXPLAIN ANALYZE` | 44 · `C1`…`B11` | [`auditoria-2.md`](../auditoria-2.md) |
| **3ª — Plataforma web** | 2026-09-11 | BD + `js/` + `app.html` + `sw.js` + Edge Functions + coherencia con el flujo | Volcado del 08/09 con sello de paridad `identicas` 18/18. **Sin ejecución** | 22 · `C1`,`C2`,`A1`…`A6`,`M1`…`M8`,`B1`…`B6` + 3 `N` | [`auditoria-3.md`](../auditoria-3.md) |
| **4ª — Base de datos (encargo de 25 apartados)** | 2026-09-14, remediación al 28 | Esquema, 74 políticas, 24 guards, 352 consultas del cliente | Volcado del 14/09. **Sin `EXPLAIN` ni `pg_stat_statements`** | 22 · `H-01`…`H-22` + 20 `R` | Artifact (ver abajo) |

**El encargo de la 4ª** está en [`Auditoriabd.md`](../Auditoriabd.md): 25 apartados, desde
normalización hasta escalabilidad. Es la plantilla a usar si se encarga una quinta.

> ⚠ **Dos de los cuatro informes NO están en Git, y no deben subirse.** Este repositorio es
> público. `security-findings.md` lleva un RFC y un teléfono reales de un cliente en su
> evidencia, y `auditoria-2.md` lleva nombres de usuarios reales con su actividad en
> producción. Están en el disco y fuera del control de versiones **a propósito**, así que sus
> enlaces de arriba funcionan en local y no para quien clone el repositorio. Si alguna vez hay
> que versionarlos, primero se anonimizan.
>
> De los cuatro, **solo `auditoria-3.md` está en Git hoy**. `Auditoriabd.md` es el único otro
> publicable —es el encargo, no tiene ni un dato— y sigue sin subir; subirlo es decisión del
> usuario. Y este archivo, que es el que sí se versiona, **se escribió sin un solo dato
> personal a propósito**: ni nombres, ni RFC, ni correos, ni teléfonos.

**El informe de la 4ª no está en el repositorio, vive en un artifact** y es el único con el
estado de remediación al día:
`https://claude.ai/artifact/ECNDyAMoTyavND4qjmEoRJ`
Los `R-01`…`R-20` son **defectos que ninguna auditoría vio y que aparecieron al arreglar
otra cosa**; los `N1`…`N3` de la 3ª son lo mismo en su ronda. Son, con diferencia, la parte
más útil de las dos rondas.

### Por qué no se fusionan los textos originales

Porque cada uno midió con instrumentos distintos y **lo que puede afirmar depende de eso**:

- La **2ª** es la única con medición de ejecución real de la base. Su hallazgo dominante
  —Realtime consumiendo el 84 % del CPU— **no se ha podido volver a medir desde entonces**,
  y ninguna auditoría posterior tiene con qué contradecirlo ni confirmarlo.
- La **3ª** y la **4ª** leyeron un volcado. Son fuertes en esquema, permisos, RLS, triggers y
  funciones, y **no pueden decir nada sobre coste real**. Las dos lo declaran.
- El **pentest** es el único que ejercitó la API con sesiones reales. Cuando contradice a otra
  auditoría sobre si algo es alcanzable, suele ganar él — pero solo para **los roles que
  probó**. Ver el caso de `C3` en §3, que es exactamente esa trampa.

---

## 2. Marcador consolidado

**97 hallazgos numerados en cuatro auditorías, más 23 defectos que salieron al arreglar
(`R-01`…`R-20`, `N1`…`N3`).** No son 120 defectos distintos: hay una decena que las cuatro
auditorías encontraron por separado y numeraron de nuevo cada vez. La tabla de equivalencias
está en §8.1.

**Un marcador honesto no es un porcentaje.** Solo la 4ª auditoría tiene su estado verificado
al día, hallazgo por hallazgo. De las otras tres, lo que se puede afirmar es esto:

| Auditoría | Total | Estado que se puede afirmar |
|---|---:|---|
| 1ª · Pentest, 24/08 | 9 | **Cerrados los dos peores**: `F-01` (lectura anónima de `ofertas`) y `F-02` (PII de `perfiles`), más `F-03` (el relay de correo, que la 3ª levantó como `C1`). De `F-08` se cerró la mitad de `camiones` con `H-10`; lo de `calificaciones` no se ha vuelto a mirar. **Abiertos y medidos hoy**: `F-04`, `F-05`, `F-06`, `F-07`. `F-09` es informativo, no un defecto |
| 2ª · Base de datos, 28/08 | 44 | **Cerrado su hallazgo dominante** (`C1`, la publicación de Realtime) y la mayoría de los 🟠. **Abiertos y medidos hoy**: `C2`, `C3`, `C5` (a medias), `M6`, `M11`, `M13`, `M14`, `M10`. Los 🟢 `B1`,`B2`,`B5`,`B7`,`B10`,`B11` **no se han vuelto a verificar desde el 28/08** |
| 3ª · Plataforma web, 11/09 | 22 + 3 `N` | **Los once críticos y altos se cerraron el mismo día de la auditoría** y se verificaron a mano entre el 11 y el 14. `A5` es **inaplicable** (`ERROR 42501`) y queda vigilado. `B1` cerrado, medido hoy. `B2`,`B3`,`B4` abiertos |
| 4ª · Base de datos, 14/09 | 22 + 20 `R` | **16 cerrados · 2 cerrados al medirlos · 3 acotados · 1 abierto.** De los 20 `R`: 18 resueltos, 1 documentado (`R-02`), 1 abierto a propósito (`R-20`) |

**Donde este archivo no dice nada, es porque nadie lo ha vuelto a medir** — y eso cuenta como
desconocido, no como cerrado. Es la misma regla que aplica `verificar-paridad.sh` con una
dimensión que no pudo leer.

**Y el dato que importa más que cualquier recuento:** de los 23 defectos `R`/`N`, **ninguno
estaba en las listas de las auditorías**. Salieron ejecutando. Y los tres que más costaron
—`R-10`, `R-11`, `R-18`— los encontró el usuario probando a mano, no una comprobación
automática.

---

## 3. Lo que sigue abierto

Medido el 2026-09-28 contra el volcado de producción y el código de `dev`. Es la única parte
de este archivo que hay que leer para trabajar hoy.

### 3.1 Los cuatro que conviene mirar antes que nada

#### ✓ `A2-C3` — La política de `pedidos` fue declarada cerrada y **no lo estaba** · **cerrado el 02/10**

Una auditoría dijo que estaba resuelto, y al medirlo no lo está. Es el motivo por el que
este archivo existe.

> **Actualización 01–02/10 (6ª auditoría): CERRADO. En producción el 02/10 21:25 UTC** (con permiso
> explícito; el bloque pasó allí; antes se comprobó por hash que el guard de producción era el
> mismo que se transformó en pruebas).
> Ejecutado por primera vez en banco local con el esquema de producción: una empresa cambió
> origen, destino, `precio_cliente = 1`, fechas y `cliente_email` de la solicitud abierta de
> un cliente ajeno. `20261001150000_empresa_no_reescribe_pedidos_ajenos.sql` lo cierra en
> el guard, no en la política (la empresa sí tiene que escribir `estado` en solicitudes
> ajenas, y una política no compara `OLD` con `NEW`): en la rama de empresa solo puede
> cambiar `estado`, y `oferta_pendiente_id` solo a `NULL`. Inventario previo de todos los
> escritores con JWT de empresa (web, Android, las 7 funciones con `UPDATE pedidos`): solo
> escriben esas dos. Bloque insertado sobre la definición viva; 8 casos; dos sabotajes en
> banco local la abortan; `cancelar_reservacion()` como empresa sigue funcionando.
> **Aplicada en pruebas el 01/10; medido por API con la empresa de pruebas:** cambiar precio
> u origen de una solicitud ajena da HTTP 400 con hint `A2-C3` y la solicitud queda intacta.
> **Probada en pantalla en `dev` el 02/10:** la empresa oferta, contraoferta, se cierra el
> acuerdo, la empresa cancela la reservación y el cliente edita la suya, sin errores.
> Lo de abajo es el diagnóstico original y se conserva.

- **La 2ª auditoría (28/08)** lo levantó: `ped_update` concede `UPDATE` a cualquier
  `admin`/`superadmin` sin `WITH CHECK`, y `guard_pedido_update` **solo vigila transiciones
  de `estado`**. Una empresa podría reescribir `origen`, `destino`, `precio_cliente`,
  `fecha_ini` o el contacto de la solicitud abierta de un competidor.
- **La 3ª auditoría (11/09) §7 lo dio por «cerrado y verificado».**
- **Medido el 28/09 contra el volcado:** la política sigue igual salvo el `TO authenticated`
  (que llegó por `A3-M7`), sigue **sin `WITH CHECK`**, y el guard sigue haciendo
  `RETURN NEW` para un `admin` cuando `OLD.estado IN ('abierto','en_negociacion')`. Ninguna
  de las otras 62 columnas está protegida para ese rol.

```
ped_update  FOR UPDATE TO authenticated
  USING  auth.uid() = cliente_id  OR  EXISTS(perfiles … rol IN ('admin','superadmin'))
  CHECK  —                                          ← no hay

guard_pedido_update:  IF es_admin AND OLD.estado IN ('abierto','en_negociacion') THEN
                        …solo comprueba NEW.estado…  RETURN NEW;   ← acepta lo demás
```

- **Por qué no es tan simple como «la 3ª se equivocó».** El pentest del 24/08 verificó
  *ejecutando* que el IDOR de escritura cruzada en `pedidos` está **bloqueado**… con las
  cuentas que probó. La 2ª describe el camino del rol `admin`. Las dos afirmaciones caben a
  la vez, y **nadie ha ejercitado el camino de `admin` sobre un pedido ajeno**. Este archivo
  no afirma que sea explotable: afirma que el esquema lo permite y que no se ha probado.
- **Y la buena noticia, que es nueva:** la política tuvo que abrirse porque
  `renderPedidos()` escribía sobre pedidos ajenos desde el navegador de cualquiera. **Eso
  dejó de ocurrir el 25/09** (verificado: el render no ejecuta ni un `update`). El
  impedimento para cerrarla **ya no existe**.
- **Lo que hace falta, en este orden:** (1) ejercitar el camino con una sesión de empresa
  real en `portgo-pruebas` y medir si el `PATCH` pasa; (2) si pasa, restringir `ped_update` a
  `cliente_id = auth.uid() OR is_superadmin()` con `WITH CHECK` idéntico, o proteger las
  columnas en el guard; (3) comprobar que ninguna ruta legítima de empresa escribe en
  `pedidos`. **No se toca sin autorización: es producción y es la Regla #2.**

#### `A2-C2` — El archivado de una reservación pierde 36 de 51 columnas, y no es transaccional

- **Medido el 28/09:** `reservaciones` tiene **51** columnas; `reservaciones_historico`,
  **15**. `eliminarReserva()` ([js/reservaciones.js:708](../js/reservaciones.js#L708)) sigue
  siendo `SELECT *` → `INSERT` de 14 campos → `DELETE`, **tres viajes sin transacción**.
- **Lo que se pierde:** `precio_acordado`, `propietario_id`, `pedido_id`, todo el bloque de
  pago (`pagado`, `pagado_en`, `pago_metodo`, `pago_referencia`, `plazo_pago`,
  `fecha_vencimiento_pago`), `evidencias`, `evidencias_cliente`, `completado_en`,
  `finalizacion_*` y todo `cancelacion_*`. Es el registro económico y probatorio del
  servicio.
- **Y cascadea:** `expedientes` (`ON DELETE CASCADE`) → `expediente_documentos`, y
  `mensajes` (`CASCADE`). `calificaciones` es `SET NULL`: la calificación sobrevive huérfana.
- **Falla a medias:** `pagos` y `documentos_fiscales` son `NO ACTION`. Con una factura
  detrás, el `DELETE` aborta **después** del `INSERT`, y el reintento choca con la PK
  duplicada. Sin salida por interfaz.
- **Cabo suelto de `A2-B4`, medido hoy:** la línea `empresa: r.empresa || null` copia una
  columna **que no existe en `reservaciones`**, así que el histórico archiva siempre `NULL`.
  (La otra mitad de `B4` sí se cerró el 28/09: la columna «Archivado» ya muestra
  `archivado_en` y la lista ordena por él.)
- **Lo propuesto, sin hacer:** o una RPC `archivar_reservacion()` que copie **todas** las
  columnas en una transacción, o —mejor— dejar de mover filas y usar una marca
  `archivada_en`. Ninguna de las dos se ha escrito.

#### `A2-C5` — Referencias polimórficas de texto: cerrado a medias

- **Cerrado:** `reservaciones.unidad` ya no puede colisionar entre tipos. `H-06` (28/09)
  añadió `recurso_tipo` a las **tres** capas que vigilan el solape —
  `check_reservacion_disponibilidad()`, el `EXCLUDE` `reservaciones_sin_solape`, y la
  consulta del cliente.
- **Abierto, medido el 28/09:** `ofertas.camion_id` sigue siendo `text` **sin columna que
  diga de qué tabla se trata**, y guarda `PAT-004` y `CUS-005` — el nombre miente sobre su
  contenido. No hay ningún trigger `BEFORE DELETE` en las cuatro tablas de flota, así que
  **nada impide borrar un recurso referenciado**: es exactamente lo que produjo el huérfano
  `F-303` que la 2ª auditoría encontró en producción.
- Lo barato e intermedio que sigue sin hacerse: renombrar a `recurso_id`, añadir
  `recurso_tipo`, extender `guard_unidad_existe` a `ofertas`, y un `BEFORE DELETE` lógico.

#### `F-04` — Sin CSP, sin `X-Frame-Options`, sin HSTS

**Medido el 28/09:** [`vercel.json`](../vercel.json) solo define cabeceras de caché. El
pentest lo puso en cuarto lugar de su orden de corrección con la nota de que
`X-Frame-Options` y HSTS **no rompen nada**. Sigue sin aplicarse.

### 3.2 El resto, por tema

| Id | Qué | Estado medido |
|---|---|---|
| `Q-01` 🔴 | `perfiles` no tenía guard de INSERT: la política solo exige `auth.uid() = user_id`, así que una cuenta sin perfil podía crearse el suyo como `superadmin`, activa, verificada o acreditada (5ª auditoría, 29/09) | **Cerrado el 29/09.** `20260929130000_perfiles_guard_de_alta.sql`: `trg_guard_perfil_insert` protege al nacer las columnas de `guard_perfil_self_update`. Pruebas 18:25 UTC, producción 19:08 UTC; el bloque (12 altas como `authenticated`, 1 como `service_role`, y los supuestos del catálogo) pasó en las dos. Sin réplica previa por decisión del usuario: se compararon solo sus dependencias (idénticas, sello 29/09). Registro real probado en `dev`. Alta desde Usuarios (`gestionar-usuario`, clave de servicio) probada en `dev` el 29/09: cliente y admin creados activos, entran directo. Lo único no comparable desde SQL: que el `gestionar-usuario` desplegado en producción sea el mismo código que el de pruebas |
| `Q-02` 🔴 | Flota: ningún guard de INSERT y `DEFAULT 'aprobada'` en `camiones`, `custodios` y `patios` — la aprobación la decide el navegador (5ª auditoría, 29/09) | **Cerrado el 29/09.** Pruebas 21:46 UTC, producción 23:48 UTC; el bloque (25 altas) pasó en las dos. `20260929140000_flota_nace_pendiente.sql`: guard BEFORE INSERT en las cinco tablas + `DEFAULT 'pendiente'`. Probada en banco local (25 altas) con dos sabotajes que la abortan. **Probada en `dev` el 29/09:** una empresa nueva da de alta camión y operador, nacen pendientes y el superadmin los aprueba |
| `Q-03` 🔴 | `calificaciones` admite INSERT directo con solo `cliente_id = auth.uid()`; con `reservacion_id` NULL el índice único parcial no frena nada: calificaciones falsas ilimitadas a cualquier empresa (29/09). Las 4 de producción son legítimas | **Cerrado el 29/09.** Pruebas 21:47 UTC, producción 23:48 UTC; el bloque pasó en las dos. `20260929150000_calificaciones_solo_por_rpc.sql`: `REVOKE INSERT` a `authenticated`; la política queda inerte y comentada, sin `DROP`. Probada en banco local con un sabotaje. **Probada en `dev` el 29/09:** un cliente califica por la web un servicio recién completado |
| `Q-04` 🔴 | `ofertas` INSERT sin control: nace `aceptada`, en ronda 2, sin caducar o sobre un pedido cerrado o en revisión (29/09) | **Cerrado el 29/09.** Pruebas 21:50 UTC, producción 23:48 UTC; el bloque (14 casos) pasó en las dos. `20260929160000_oferta_nace_enviada.sql`: guard BEFORE INSERT. Fuera a propósito: dueño del recurso ofertado, `permite_reoferta` (cerrado después como `Q-18`: desde el 30/09 también lo frena la base), `Q-12`, `Q-13`. Probada en banco local (14 casos) con dos sabotajes. **Probada en `dev` el 29/09:** oferta, contraoferta del cliente, aceptación de la empresa y cierre completo del servicio. La recontraoferta de la empresa falló, pero por `Q-14`, no por este guard |
| `Q-14` 🟡 | La empresa no puede volver a contraofertar tras la contraoferta del cliente: `pedidos.js:2530` calcula ronda 3 y `ofertas_ronda_check` admite 1 o 2. El botón existe desde el 17/08 y falla siempre, también en producción (medido en `dev` el 29/09 probando Q-04; es un UPDATE, no lo causa el guard de INSERT) | **Decidido (opción B, sin tope). Aplicada en pruebas el 29/09 23:19 UTC, en producción no.** `20260929191000_ofertas_rondas_sin_tope.sql`: CHECK `ronda >= 1`; `responder_oferta()` pasa de `ronda = 2` a `ronda + 1` sustituyendo solo esa cadena sobre su definición viva, y el bloque comprueba que no cambió nada más. En el navegador, `enviarContraoferta()` usa `ronda + 1`. Probada en banco local, idempotente, con dos sabotajes que la abortan. **Probada en `dev` el 29/09:** oferta, contraoferta del cliente, recontraoferta de la empresa y nueva contraoferta del cliente, sin error — pasa de 2 rondas |
| `Q-05` 🔴 | `guard_reservacion_insert()` dejaba a la empresa (`propietario_id = auth.uid()`) crear reservaciones «como quiera»: cualquier estado, precio y cliente — servicios y cobros inventados. El motivo de esa rama caducó el 09/09 (el acuerdo lo cierra `cerrar_acuerdo()`); medido el 30/09, ninguna vía legítima la usa: `cerrarAcuerdo()` de `js/pedidos.js` no se llama desde ningún sitio | **Cerrado el 30/09.** Pruebas 16:29 UTC, producción 17:22 UTC; el bloque (7 casos) pasó en las dos. `20260930120000_empresa_no_crea_reservaciones.sql`: la rama pasa de `return new` a un rechazo con `hint 'Q-05'`, sustituyendo solo ese bloque sobre la definición viva. Probada en banco local (7 casos: empresa, cierre con marca, cliente, superadmin), idempotente, con dos sabotajes que la abortan. La política `reservaciones_insert` no se toca. **Probada en `dev` el 30/09:** acepta la empresa una contraoferta y la reservación se crea y aparece a las dos partes |
| `Q-06` 🔴 | `ped_delete` deja al cliente borrar su pedido en **cualquier** estado —también `acordado` o `finalizado`—: las ofertas se van en cascada y la reservación queda sin pedido. La interfaz nunca lo ofrecía; la base sí | **Cerrado el 30/09 (las dos mitades).** Producción 20:32 UTC, en una transacción; los dos bloques pasaron allí igual que en pruebas. Primera mitad: `20260930130000_pedidos_no_se_borran.sql`: `REVOKE DELETE` sobre `pedidos` a `authenticated` (decisión del usuario, 30/09: **nadie borra pedidos, tampoco el superadmin**; se archivará con una función aparte). `ped_delete` queda inerte y comentada, sin `DROP`. Se retira el botón «🗑 Eliminar» del superadmin (código en `dev`; en producción el botón sigue visible y da error de permisos hasta la próxima fusión `dev` → `main`). Probada en banco local con dos sabotajes. **Probada en `dev` el 30/09:** el superadmin ya no ve «🗑 Eliminar» y el cliente sigue cancelando una solicitud `abierto`. **Segunda mitad (`expdocs_all`):** `20260930140000_expediente_documentos_solo_se_modifican.sql` retira INSERT y DELETE sobre `expediente_documentos` a `authenticated` — el guard solo vigilaba UPDATE, y cualquiera de las dos partes podía borrar un documento obligatorio o inventar renglones. Los renglones solo nacen en `abrir_expediente()`; la web y Android solo los modifican. `expdocs_all` se conserva (sigue gobernando SELECT y UPDATE). Probada en banco local con tres sabotajes. **Probada en `dev` el 30/09:** la empresa solicita la documentación (los renglones nacen por la función), el cliente sube, la empresa acepta y pide corrección, sin error |
| `Q-15` 🔴 | La rama del cliente en `guard_pedido_update` solo le prohíbe pasar a `rechazado` y a `acordado` (fuera del camino de `pendiente_acuerdo`). Todo lo demás lo deja: **autopublicarse** (`pendiente_revision` → `abierto`, sin la revisión del superadmin), marcar `finalizado`, o pasar a `cancelado` un pedido `acordado` saltándose la cancelación de la reservación que resuelve el superadmin. Leído en el guard vivo el 30/09, no ejecutado. No es `A2-C3`: aquel es la rama de la empresa | **Abierto por decisión del usuario (30/09):** la cancelación se queda como estaba. Se propuso cerrar las transiciones del cliente y registrar las cancelaciones con motivo; quedó para más adelante |
| `Q-16` 🟡 | «⚠ Pedir corrección» del expediente abría su nota **detrás** de la ventana del expediente y no se podía escribir: todas las `.modal-overlay` comparten `z-index: 200` y manda el orden del HTML, donde `modal-rechazar-nota` y `modal-confirm` van antes que `modal-expediente`. Presente también en producción. Encontrado en `dev` el 30/09 probando Q-06 | **Corregido y probado en `dev` el 30/09, sin promover:** los dos diálogos que se abren encima de otra ventana pasan a `z-index: 210` (`css/components.css?v=41`). Llega a producción con la próxima fusión `dev` → `main` |
| `Q-07` 🟡 | `propietario_id` es `NOT NULL` en las cinco tablas de flota desde `20260924140000`, pero sus FK siguen `ON DELETE SET NULL`: borrar la cuenta de una empresa con flota intenta vaciar el dueño y **el borrado entero falla** (ejecutado en banco local el 30/09: `23502` en `camiones`). No se pierde nada, pero el superadmin recibía un error crudo | **Decidido (usuario, 30/09): una empresa con flota no se borra, se suspende; las FK no se tocan.** `gestionar-usuario` cuenta la flota antes de borrar y responde `409` con cuántas unidades tiene y que la suspenda con 🚫. Compila con `deno check`; **Cerrado el 30/09:** desplegado en pruebas (v11) y en producción (v17, 20:46 UTC, con permiso explícito), mismo paquete en los dos (`a063a35e…`). **Probado en `dev` el 30/09:** eliminar una empresa con flota responde «Esta cuenta tiene flota registrada (4 camion(es), 4 custodio(s), 3 patio(s), 2 operador(es))…» y la cuenta sigue. Ojo: el CLI de este equipo está enlazado a producción — desplegar siempre con `--project-ref`. La rama de «orfandad por borrado de cuenta» de `guard_fleet_resource_update` quedó sin uso desde el 24/09; no se toca |
| `Q-17` 🟡 | Producción tiene una tercera Edge Function, **`smart-service`** (v5, desplegada el 30/07), que **no está en el repositorio ni en pruebas**. Código en producción sin versionar y sin copia en el entorno de pruebas (medido el 30/09 con `supabase functions list`) | **Abierto, sin investigar.** No se sabe qué hace ni quién la desplegó; preguntar al equipo antes de tocar nada |
| `Q-11` 🟡 | `consentimientos` tenía 0 filas en producción | **Explicado el 30/09.** No ha habido altas de cuenta en producción desde que existe el registro (28/07); los operadores de abril y junio son anteriores. Única excepción sin causa demostrable: `OP-A86E8DC0` (11/08) — el código ya estaba en `main`, el CHECK no lo rechaza y su dueño existe; quedan en pie que lo creara otra cuenta después borrada (el consentimiento se va en cascada con ella) o un fallo que solo iba a la consola. **No se le crea constancia a posteriori.** Medido en pruebas: los operadores y registros recientes sí la guardan. Arreglos: (1) el fallo deja de ser silencioso en el registro y en el alta de operador (`auth.js?v=25`, `operadores.js?v=19`, en `dev`); (2) bloqueo legal al borrar la cuenta — decisión del usuario del 30/09: `20260930160000_consentimientos_bloqueo_legal.sql`, un trigger copia cada consentimiento a `consentimientos_bloqueados` (RLS sin políticas, sin privilegios para la app) antes de la cascada; plazo por definir, al vencer se anonimiza. Probada en banco local, incluida la cascada real al borrar una cuenta. **Bloqueo legal en producción y en pruebas desde el 30/09** (pruebas 21:28 UTC, producción 21:36 UTC, con permiso explícito; el bloque pasó en las dos). Por decisión del usuario no se probó borrando una cuenta en `dev`: basta el bloque (borrado directo, ejercido en pruebas) y la cascada del banco local ⚠ **Regla para el futuro:** el trigger corre dentro del borrado de la cuenta; si se añade un `tipo` nuevo al CHECK de `consentimientos`, hay que añadirlo también al de `consentimientos_bloqueados`, o el borrado de las cuentas con ese tipo fallará |
| `Q-12` · `Q-13` 🟡 | Una empresa podía tener dos ofertas vivas en la misma solicitud (solo lo frenaba la interfaz), y los importes del flujo admitían 0 o negativos. 0 violaciones en el volcado de producción | **Cerrado el 30/09.** Pruebas 22:28 UTC, producción 22:59 UTC (con permiso explícito, junto con Q-18); el bloque pasó en las dos. `20260930173000_ofertas_unicas_e_importes_positivos.sql`: índice único parcial `uq_ofertas_viva_por_empresa` (mismos estados que la interfaz trata como «oferta activa») y CHECK `> 0` en `precio_oferta`, `contra_precio`, `precio_cliente` y `precio_acordado`. **`pagos.monto` fuera a propósito:** 0 filas, la diseña Salvador para Stripe. Probada en banco local (7 casos) con dos sabotajes. **Probada en `dev` el 30/09:** tras rechazar la oferta permitiendo reofertar, la misma empresa vuelve a ofertar en la misma solicitud |
| `Q-18` 🟡 | «No permitir que vuelva a ofertar» (`ofertas.permite_reoferta = false`, lo marca el cliente al rechazar y `cancelar_reservacion()` para quien cancela) solo lo cumplía la interfaz: la base aceptaba la oferta nueva | **Cerrado el 30/09.** Pruebas 22:49 UTC, producción 22:59 UTC (con permiso explícito, junto con Q-12/13); el bloque pasó en las dos. `20260930183000_ofertas_respetan_permite_reoferta.sql`: un bloque más en `guard_oferta_insert()` (hint `Q-18`), insertado sobre la definición viva y comparado antes/después. Probada en banco local (2 casos) con un sabotaje. **Probada en `dev` el 30/09:** reofertar tras un rechazo que lo permite sigue funcionando; sin permitirlo, la solicitud desaparece de sus disponibles. Se promoverá junto con Q-12/13 |
| `Q-09` 🟢 | El catálogo descargaba **todas** las calificaciones de todas las empresas visibles, con sus comentarios, solo para pintar cuántas hay y su promedio (regla 43) | **Vista en producción y en pruebas desde el 30/09** (producción 23:32 UTC, con permiso explícito; el catálogo que la usa llega a producción con la fusión `dev` → `main`): `20260930193000_calificaciones_resumen.sql`, vista `calificaciones_resumen` (empresa, total, promedio; `security_invoker`, solo lectura). El catálogo la lee desde `js/catalogo.js?v=26`, subido después de aplicarla (regla 41); en producción, la vista va primero y el código con la fusión. Probada en banco local con dos sabotajes. **Probada en `dev` el 30/09:** las tarjetas del catálogo muestran los mismos números. De paso, la ficha de empresa (`abrirPerfilEmpresaCat`) promediaba solo las 5 últimas calificaciones; ahora usa también la vista (`catalogo.js?v=27`) |
| `Q-10` 🟢 | El cliente se suscribía por Realtime a las cuatro tablas de flota, que desde H-10 no puede leer: nunca recibía un evento, pero el servidor evaluaba la RLS de cada cambio de flota para cada cliente conectado | **Corregido en `dev` (`main.js?v=22`), sin promover:** el cliente ya no se suscribe a flota; empresa y superadmin siguen igual. No cambia lo que el cliente ve. Probado en `dev` junto con `Q-19`, que apareció al probarlo. Llega a producción con la próxima fusión `dev` → `main` |
| `Q-19` 🔴 | **Realtime nunca refrescó la flota ni las reservaciones.** El canal `portgo-changes` mezclaba `pedidos` y `ofertas` —no publicadas desde el 28/08, decisión del hueco 14— con las cuatro tablas de flota y `reservaciones`; un canal con una tabla no publicada no entrega **ningún** evento aunque diga `SUBSCRIBED`. Medido en `dev` el 30/09 probando Q-10: el mismo filtro de camiones recibía en un canal solo y dejaba de recibir al sumarle `pedidos` y `ofertas`. Solo funcionaba la campana, que va en su propio canal. No lo causó Q-10 | **Corregido y probado en `dev` el 30/09 (`main.js?v=23`), sin promover:** `pedidos` y `ofertas` pasan a su propio canal; la lista de unidades de la empresa ya se refresca sola al aprobar el superadmin. Llega a producción con la fusión `dev` → `main`. **Regla:** nunca meter en un canal compartido una tabla que no esté publicada |
| `Q-20` 🔴 | **Siete migraciones llegaron a producción por fuera de los guiones, sin registro.** Entre la comparación del 30/09 (~23:30 UTC, producción aún sin Q-14) y el intento de Salvador del 01/10 (~17:00 UTC), alguien aplicó a producción las 6 de Carta Porte y Q-14 —que borra y recrea `ofertas_ronda_check` sin el sí de la Regla #1 para producción—. No fue `supabase db push` (`supabase_migrations.schema_migrations` acaba en el 10/06) ni `aplicar-migraciones.sh` (solo aplica dos archivos de agosto); **se aplicaron desde el SQL Editor del panel de Supabase** (confirmado el 01/10). Medido el 01/10: el esquema de producción coincide con pruebas salvo `datos_carta_porte()`, que en producción lleva un **comentario de 3 líneas que no está en el repositorio** (código idéntico) — ⚠ **falso, medido el 01/10:** el comentario («Sin filtrar por recurso_tipo a propósito…») **sí está en el repositorio**; la versión que no lo tiene es la de **pruebas**. La de producción es la del repositorio byte a byte salvo los fines de línea: se pegó con CRLF desde el SQL Editor (`md5(prosrc)` reproducido en banco local: `a7eca2a6…`); `vigencias_espejo()` sigue estricta | **Cerrado el 01/10, sin daño medible.** Salvador registró las 7 en el libro mayor el 01/10 tras verificar el esquema a mano. La diferencia del comentario se deja (es cosmética). **Regla adoptada (usuario, 01/10):** a producción solo se aplica con `aplicar-a-produccion.sh` — escrita en `CLAUDE.md`, Regla #2. Vía confirmada: SQL Editor; la regla existe para cerrar justo esa |
| `S-01` 🔴 | **Los documentos de los choferes se listaban y se borraban con cualquier cuenta.** Las tres políticas del bucket `operadores` solo miraban el bucket: `operadores_read` sin `TO` (alcanzaba a todo `authenticated`), `operadores_upload` y `operadores_delete` a cualquier `authenticated`. Medido en pruebas el 01/10 como cliente: 98 archivos de 4 empresas —fotos, licencias, examen toxicológico, examen médico, carta de antecedentes: datos sensibles—, descargables por su URL pública. Sin sesión no (`anon` sin privilegio sobre `storage.objects`, 403 medido). 6ª auditoría | **Cerrado el 01/10.** Pruebas el 01/10, probada en pantalla en `dev` (todas las pruebas como se esperaba) y **en producción el 01/10 23:30 UTC** (con permiso explícito, una transacción con las otras dos S; el bloque pasó allí). `20261001120000_storage_operadores_por_carpeta.sql`: las tres, solo sobre la carpeta propia (`foldername[1] = auth.uid()`) o como superadmin (da de alta choferes por una empresa). El bloque (solo lectura: en producción `storage.protect_delete` impide borrar por SQL) pasó en pruebas: 98 archivos, perfil sin archivos ve 0, el dueño sus 65, el superadmin todos. Probada en banco local con dos sabotajes y el bucket vacío. **Medido por API en pruebas:** el cliente lista 0, la empresa solo su carpeta, subir a carpeta ajena da RLS. **Paso 2, en tres etapas** (plan aprobado por el usuario el 05/10): **A)** la web abre siempre con URL firmada y guarda rutas — hecha en `dev` el 05/10 (`utils.js?v=10`: `rutaDocStorage`/`urlDocFirmada`/`attrsDoc`/`imgDoc`, un manejador de clics y un observador de imágenes; `operadores.js?v=21`, `admin.js?v=43`, `aprobaciones.js?v=50`); compatible con las URL viejas mientras el bucket siga público. **Probada en pantalla en `dev` el 05/10:** choferes existentes (URL) y nuevos (ruta), sus cinco documentos desde el panel del superadmin, «ver el actual» al editar y los documentos de empresa abren con `/object/sign/`. Android no sube ni abre estos documentos (`urlPublica` y `subirArchivoOperador` no tienen llamadas). **B)** convertir las URL guardadas en rutas: `20261005170000_documentos_url_publica_a_ruta.sql`, en contexto de superadmin (S-12 y el guard de `vigencias`), sin borrar nada y reversible; aborta ante URL codificadas o con parámetros. Probada en banco local (datos reales, una empresa acreditada con póliza como URL, un sabotaje). **Aplicada en pruebas el 05/10:** 5 choferes, 2 perfiles y 24 filas de `vigencias` convertidos; 0 rutas sin archivo en Storage. **Probada en pantalla en `dev` el 05/10** (choferes, panel del superadmin y documentos de empresa abren con `/object/sign/`). **En producción el 05/10** (con permiso explícito): 3 choferes y 12 filas de `vigencias` convertidos, ninguna póliza de empresa como URL; 0 rutas sin archivo. **C)** volver privados `operadores`, `documentos-empresa` y `custodios`: `20261005180000_buckets_de_documentos_privados.sql` (solo `public = false` en tres filas de `storage.buckets`; reversible). La comprobación aborta si queda un bucket público, si alguno no tiene política de lectura por carpeta (nadie podría firmar) o si queda una URL pública guardada. **Aplicada en pruebas el 05/10; medido por API** con un examen toxicológico real: la URL pública sin sesión da HTTP 400, el dueño firma y abre (200), un cliente ajeno no puede firmar (400). **Probada en pantalla en `dev` el 05/10** con los buckets ya cerrados: choferes, panel del superadmin y documentos de empresa abren igual. **En producción el 05/10 23:36 UTC.** ✅ **S-01 CERRADO POR COMPLETO**: nadie lista, sube ni borra fuera de su carpeta, y nadie abre un documento sin URL firmada del dueño o del superadmin. De paso, en A: `_uploadOpDoc` devolvía `null` si fallaba la subida y **borraba** la ruta guardada al editar un chofer (ahora conserva la anterior y avisa); `eliminarMiRecurso` pasaba URL a `storage.remove()`, que espera rutas (nunca borró nada); y el permiso del patio se enlazaba con su ruta del bucket privado `unidades` como si fuera URL (404) |
| `S-02` 🟠 | **La empresa acreditada no podía tocar su propio perfil.** `vigencias_espejo()` repetía en cada UPDATE de `perfiles` el `INSERT … ON CONFLICT DO UPDATE` de los seis documentos aunque no cambiara ninguno, y `guard_vigencia_update()` rechaza (H-02) todo UPDATE de una fila `vigente` de perfil. Guardar «Perfil de empresa», el interruptor de correos y «Enviar documentos para aprobación» fallaban con `VIGENCIA_ACREDITADA` para la empresa con documentos acreditados — la única que hay. Roto desde que el espejo se hizo estricto (`20260923120000`); `20260929140000` lo topó y lo atribuyó a la sesión sin JWT. 6ª auditoría | **Cerrado el 01/10.** Pruebas el 01/10, probada en pantalla en `dev` (todas las pruebas como se esperaba) y **en producción el 01/10 23:30 UTC** (con permiso explícito, una transacción con las otras dos S; el bloque pasó allí). `20261001130000_espejo_vigencias_no_reescribe_lo_igual.sql`: en un UPDATE el espejo se salta el documento cuyo archivo y fecha no cambiaron; el guard no se toca (regla 15). Bloque insertado sobre la definición viva y comparado antes/después (regla 3). El bloque (4 casos con una acreditación montada) pasó en pruebas; en banco local, dos sabotajes la abortan. **Medido por API en pruebas con la empresa acreditada:** cambia `notif_email` (200) y cambiar la ruta o la fecha de su seguro RC sigue rechazado (H-02 cerrado). Aviso de choque con `20260922130000_vigencias_espejo_tolerante`: falso positivo, ver `docs/PROMOCION-PENDIENTE.md` |
| `S-03` 🟠 | **La Carta Porte de referencia entregaba filas enteras a la contraparte.** `datos_carta_porte()` (`SECURITY DEFINER`, Carta Porte, 30/09) comprobaba bien quién llama y devolvía `to_jsonb()` de seis filas: 44 columnas de cada perfil (con `nota_rechazo_cuenta`, rutas de `fotos_verificacion` y pólizas) y 39 del chofer (`nss`, `tipo_sanguineo`, correo, teléfono, rutas de sus exámenes) para pintar 8 y 6. Es `H-01` por la puerta de una RPC (reglas 11 y 43). 6ª auditoría | **Cerrado el 01/10.** Pruebas el 01/10, probada en pantalla en `dev` (todas las pruebas como se esperaba) y **en producción el 01/10 23:30 UTC** (con permiso explícito, una transacción con las otras dos S; el bloque pasó allí). `20261001140000_carta_porte_solo_lo_que_imprime.sql`: cada `to_jsonb(fila)` pasa a `jsonb_build_object` con las columnas que lee `js/cartaporte.js` (grep completo; sin accesos indirectos). Sustituido sobre la definición viva —conserva el comentario que solo tiene producción, `Q-20`— y comparado contra el texto construido. El bloque verifica las claves exactas y que un ajeno siga en `No autorizado`; en banco local, dos sabotajes (sin cambio, una columna olvidada) la abortan. **Medido por API en pruebas:** empresa y cliente de una reservación reciben 6/17/8/8/3/6 claves. Documentada por primera vez en `FLUJO-OPERATIVO.md` §6 |
| `S-04` 🟡 | **El bucket `custodios` no tenía ninguna política: la licencia SEDENA del custodio armado nunca se guardaba.** Con RLS y sin política, toda subida se rechaza; `js/admin.js` (alta y edición) hacía `if (!upErr) …` sin avisar y el custodio se guardaba sin documento. Medido: 2 custodios «Armado» en producción, 0 con `doc_licencia_sedena`; bucket vacío en las dos bases. Mismo defecto que `20260930170000` corrigió para `documentos-empresa`. Custodios está apagado en la interfaz: no afecta a nadie hoy. 6ª auditoría | **Cerrado el 05/10.** Pruebas el 05/10 y **producción el 05/10 21:33 UTC** (el bloque pasó en las dos; el JS llega a producción con la próxima fusión `dev` → `main`). `20261005130000_storage_custodios_por_carpeta.sql`: crea `custodios_upload` y `custodios_read`, carpeta propia o superadmin (regla 44b); sin `DELETE`/`UPDATE`, que nadie usa. `js/admin.js?v=42` avisa y detiene el guardado si la subida falla (regla 24). El bloque prueba con el bucket vacío: altas como `authenticated` dentro de una subtransacción deshecha (solo metadatos, nunca archivos; no queda nada que borrar), 6 casos; en banco local reproduce el defecto sin las políticas y caza una lectura abierta. **Sin prueba en pantalla:** el formulario está oculto con CSS |
| `S-05` 🟡 | **Las pólizas y permisos SCT de las empresas se listaban con cualquier cuenta.** `docempresa_read` (`20260930170000`, que arregló la subida) era `FOR SELECT TO public` con solo `bucket_id`: cualquier cuenta con sesión listaba el bucket `documentos-empresa` entero. Medido en pruebas el 01/10 como cliente. En producción el bucket estaba vacío el 02/10: no se llegó a exponer nada. 6ª auditoría | **Cerrado el 02/10.** Pruebas el 02/10, probada en pantalla en `dev` (la empresa sube y el superadmin abre) y **en producción el 02/10 21:45 UTC** (con permiso explícito, Reglas #1 y #2; allí el bucket estaba vacío y el bloque comprobó solo el catálogo, como estaba previsto). `20261002120000_storage_documentos_empresa_por_carpeta.sql`: lectura solo de la carpeta propia o como superadmin; `docempresa_upload` ya estaba atada a la carpeta y no se toca. El bloque comprueba el catálogo siempre y, si hay archivos, cuenta como cada rol; en pruebas pasó con 2 archivos. En banco local, dos sabotajes la abortan, también con el bucket vacío (lo caza el catálogo). **Medido por API en pruebas:** el cliente lista 0 (antes 1), la empresa solo su carpeta |
| `S-06` 🟢 | **`vigencias_caducidad` seguía escribible por `service_role`.** `20260923130000` le quitó la escritura a `authenticated` y no al tercer rol, que la recibe por los privilegios por omisión; la vista es auto-actualizable. Era la única vista del esquema con escritura para algún rol, y es lo que la regla 10 nació para impedir (`R-07`). 6ª auditoría | **Cerrado el 02/10.** `20261002130000_vigencias_caducidad_solo_lectura.sql`: `REVOKE INSERT, UPDATE, DELETE, MAINTAIN` a `service_role`; la lectura se conserva. Nada la usaba con la clave de servicio (Edge Functions, Android, `pruebas/`). El bloque comprueba los privilegios de los tres roles y un `UPDATE … where false` real como `service_role` (rechazado con `42501`); un sabotaje sin el `REVOKE` lo aborta en banco local. Pruebas y **producción el 02/10 21:51 UTC** (con permiso explícito); sin prueba en pantalla: no cambia nada que la app use. `TRUNCATE` sobre las vistas no se tocó: PostgreSQL no permite vaciar una vista |
| `S-07` 🟢 | **`perfiles.cp` (Carta Porte, 29/09) repite a `perfiles.cp_fiscal`**, que llevaba marcada «SIN USO» desde `H-15`. Medido el 05/10: `cp_fiscal` 0 referencias (web, Android, Edge Functions, vistas, funciones) y 0 de 13 filas con valor; `cp` 9 referencias y 7 filas. El comentario de `cp_fiscal` decía «el dato vive en `solicitudes_cuenta`», falso desde el 29/09. 6ª auditoría | **Cerrado el 05/10, sin borrar** (decisión del usuario: igual que `H-15`, regla 9). `20261005140000_perfiles_cp_fiscal_superada_por_cp.sql`: solo comentarios — `cp_fiscal` «SUPERADA por `perfiles.cp`… vacía, no usar», y `cp` documenta su origen y uso. El bloque aborta si `cp_fiscal` tuviera valores (el comentario sería falso). Pruebas y producción el 05/10 21:55 UTC |
| `S-08` 🟡 | **`reservaciones.operador_id` y `ofertas.operador_id` sin clave foránea a `operadores`.** Nada impedía borrar un chofer referenciado; lo leen `cerrar_acuerdo`, `enviar_oferta`, `guard_operador_hazmat`, `guard_reservacion_update` y `datos_carta_porte`. Medido en banco local: con solo `SET NULL`, el dueño borraba al chofer de un viaje en curso y el servicio se quedaba sin chofer. De paso: `eliminarOperador()` (web) no miraba el error y anunciaba «eliminado» siempre. 6ª auditoría | **Cerrado el 05/10 en la base** (pruebas y **producción el 05/10 22:27 UTC**, con los dos casos ejercidos allí sobre choferes reales; `operadores.js?v=20` llega con la próxima fusión `dev` → `main`). Decisión del usuario: bloquear si hay viaje vivo, `SET NULL` en lo demás. `20261005150000_operador_id_con_fk_y_guard_de_borrado.sql`: dos FK `ON DELETE SET NULL` con sus índices parciales, y `guard_operador_delete` (`BEFORE DELETE`) que rechaza borrar al chofer de una reservación viva. Aborta si hubiera referencias huérfanas. `operadores.js?v=20` muestra el error. El bloque ejerce con choferes reales los dos casos (rechazo con viaje vivo; `SET NULL` y nombre conservado sin él); en banco local, sin el guard o sin las FK la migración aborta. En pruebas: los dos casos ejercidos. **Probada en pantalla en `dev` el 05/10:** borrar al chofer de un servicio activo muestra el aviso y no lo borra; uno sin servicios se borra; el servicio sigue avanzando |
| `S-09` 🟢 | **`camiones.configuracion_vehicular` aceptaba cualquier texto** (Carta Porte, 29/09): la clave SAT tiene catálogo (`config_vehicular_sat`) pero nada obligaba a usarlo; un valor inválido por la API acabaría impreso en la Carta Porte. 0 de 12 camiones con valor en el volcado. 6ª auditoría | **Cerrado el 05/10.** Pruebas y **producción el 05/10 22:48 UTC** (con permiso explícito; el bloque pasó allí). `20261005160000_camion_configuracion_vehicular_del_catalogo.sql`: trigger de validación (`guard_camion_config_vehicular`), no la FK compuesta de `vigencias`: medido que `revertirRecursoRechazado()` reenvía la fila completa del `snapshot_anterior` y una columna generada nueva rompería «Revertir». Solo valida si el valor cambia. Aborta si hubiera camiones con claves fuera del catálogo. 4 casos como el dueño de un camión real; en banco local, sin validar o validando siempre con clave activa, aborta. **Medido por API en pruebas:** clave inventada → HTTP 400 `S-09`; clave del catálogo → guarda. **Probada en pantalla en `dev` el 05/10:** la empresa guarda una configuración del desplegable sin error |
| `S-13` 🟡 | **El superadmin aprobaba ediciones sin ver qué cambió.** `_diffHtml()` (`js/aprobaciones.js`) descartaba en silencio todo campo editado sin etiqueta (`.filter(k => labels[k])`), y la lista de camión es anterior a Carta Porte: `configuracion_vehicular`, `numero_permiso_sct`, `operador`, `tipo_carga` y `estado` no salían. Encontrado por el usuario el 05/10 probando S-09 en `dev`: la tarjeta de aprobación no mostraba el cambio. Presente también en producción. 6ª auditoría | **Corregido en `dev` el 05/10, sin promover** (`aprobaciones.js?v=49`): etiquetas nuevas en camión, y un campo sin etiqueta se muestra con el nombre de su columna en vez de descartarse (solo se omite `emoji`, derivado del tipo). Vale para los cinco recursos: en choferes, custodios, patios y lavados aparecen campos que antes se ocultaban. Probado aislando la función y **en pantalla en `dev` el 05/10**: la tarjeta del superadmin muestra «Configuración vehicular (SAT)» con el valor anterior y el nuevo. **Regla:** una lista de etiquetas no puede ser un filtro; lo que no tiene etiqueta se muestra crudo, no se oculta |
| `S-10` 🟡 | **La base no se podía reconstruir desde el repositorio.** El plano `supabase/esquema/` (último commit 31/08) tenía 22 de 27 tablas: faltaban `vigencias`, `avisos_superadmin`, `consentimientos_bloqueados` y lo de septiembre. Y rehacer la base aplicando las migraciones desde cero tampoco sirve: varias abortan en una base sin datos («no hay ningún perfil para la prueba»), y 14 tablas centrales nacieron en el panel, no en una migración. 6ª auditoría | **Cerrado el 05/10.** Plano regenerado con `volcar-esquema.sh` (solo lectura de producción): 27 tablas, 8 vistas, 73 políticas, 51 triggers, 15 políticas de Storage, catálogos sin datos personales. **Reconstruido en banco local desde cero:** carga sin errores y coincide con producción en tablas, vistas, funciones (66), índices, FK, CHECK, políticas y triggers. **Regla:** el plano se regenera después de cada promoción a producción que cambie el esquema, y el camino para reconstruir la base es el plano, no reaplicar las migraciones |
| `S-11` 🟢 | **Dos FK de `vigencias` hacia `auth.users` sin índice** (`revisado_por`, `subido_por`, `ON DELETE SET NULL`): borrar una cuenta recorría `vigencias` entera por cada usuario, la misma ruta (con plazo ARCO) por la que `H-13` indexó otras ocho. La tabla nació después de `H-13`. El informe contaba una tercera, `(cat_clave, tipo_documento)` → `catalogos`: **al medirla se decidió no indexarla**, porque solo la recorre editar un valor del catálogo `vigencia_tipo` (raro, manual) y `vigencias` se escribe en cada guardado por el espejo. 6ª auditoría | **Cerrado el 02/10.** `20261002140000_vigencias_indices_de_fk.sql`: dos índices parciales `WHERE … IS NOT NULL`, como el precedente (hoy 0 de 60 filas con valor: nacen vacíos). El plan del `SET NULL` usa el índice (banco local); un sabotaje sin uno de los dos lo aborta. Pruebas y **producción el 02/10 21:57 UTC** (con permiso explícito). El aviso de zona con `20260922130000_vigencias_espejo_tolerante` es el falso positivo de `PROMOCION-PENDIENTE.md` |
| `S-12` 🟢 | **Una empresa sin acreditar se crea sola una fila `vigente` en `vigencias`.** `guard_perfil_self_update` protege las fechas de los tres documentos pero no sus rutas (`doc_permiso_sct`, `doc_seguro_rc`, `doc_seguro_carga`); al escribir una, el espejo inserta la fila como `vigente` y el guard de `vigencias` solo vigila UPDATE. Ejecutado en banco local el 01/10. Sin fecha, `empresas_publico` no pinta ningún distintivo (medido); sí aparece en `vigencias_caducidad`, que lee el panel del superadmin | **Cerrado el 05/10.** Pruebas el 05/10, probada en pantalla en `dev` (envío de documentos, aprobación del superadmin y registro de cuenta, sin errores) y **en producción el 05/10 17:48 UTC** (con permiso explícito; el bloque pasó allí). `20261005120000_rutas_de_documentos_acreditados_protegidas.sql`: las tres rutas se suman a las fechas en **los dos** guards — `guard_perfil_self_update` y también `guard_perfil_insert` (Q-01), que tenía el mismo hueco al alta. Solo las escribe `aprobarDocsEmpresa()`, como superadmin (inventario del 05/10); sin datos autodeclarados que limpiar. Inserción sobre las definiciones vivas; 6 casos (las altas con el método de Q-01: uid inventado, FK frente a P0001); contra los guards sin cambiar, la comprobación caza los casos 1, 2 y 5. **Medido por API en pruebas:** escribir `doc_seguro_rc` en el perfil propio da HTTP 400 «No autorizado» |
| `H-17` | 1 índice redundante (`idx_pedidos_fecha`) y 2 incoherentes con sus hermanos (`idx_lavados_pendientes`, `idx_operadores_pendientes`) | **Abierto.** Los tres siguen igual que el 14/09. El `DROP` se condicionó a leer `pg_stat_user_indexes`, que sigue sin leerse; alinear los dos no depende de ese dato |
| `H-18` (mitad) | Dinero con dos tipos: catálogo `numeric(14,2)`, flujo `numeric` sin escala | **Abierto, y estaba dado por cerrado.** Medido: `precio_cliente`, `precio_oferta`, `contra_precio`, `precio_acordado` y `pagos.monto` siguen sin escala. El `CHECK` de `aprobacion_cuenta` sí se puso |
| `H-14` | Grupo repetitivo `contenedor_1/_2` | **Acotado.** Hay `CHECK` de coherencia; la estructura sigue. Decidido no normalizar: añadiría un `JOIN` a la consulta más caliente para modelar un máximo de dos |
| `H-15` | 7 columnas sin uso ni datos (vocabulario de Carta Porte) + `reservaciones.telefono` | **Acotado.** Documentadas con `COMMENT`, **ningún `DROP`**. `telefono` sigue leída por la interfaz y nunca escrita |
| `A3-A5` | El `ALTER DEFAULT PRIVILEGES` de `supabase_admin` | **No aplicable.** Exige ser miembro de ese rol; el rol que aplica migraciones no lo es (`ERROR 42501`). Riesgo aceptado y **vigilado** por `supabase/sondas/exposicion-anon.sql`. Cerrarlo de verdad requiere soporte de Supabase |
| `R-20` | El libro mayor marca 5 migraciones «editadas tras aplicarse» y 3 no lo fueron: el hash anotado es del mismo archivo con CRLF | **Abierto a propósito.** Arreglarlo exige decidir qué identifica el libro (hash normalizado a LF, o el `blob` de git) e invalida las 26 líneas ya escritas. Es decisión del usuario |
| `A2-M6` · hueco 1 | Nada marca la unidad `ocupado` al llegar su fecha; el estado es derivado y se mantiene a mano | **Abierto.** No existe trigger sobre `reservaciones` que lo haga |
| `A2-M11` | Índices sin valor (`idx_pedidos_categoria_carga`, `idx_consentimientos_tipo`) y redundante (`idx_expedientes_reserva`) | **Abierto.** Los tres siguen. Es un `DROP`: Regla #1 |
| `A2-M13` | IDs de recurso de 32 bits generados en el cliente (~1,2 % de colisión a 10 000 unidades) | **Abierto.** Decidido en la 4ª no migrar las PK de texto a `uuid`: son legibles, se enseñan al usuario y arrastrarían las políticas de Storage |
| `A2-M14` | Falta el `UNIQUE` de `solicitudes_cuenta.user_id` que el código asume | **Abierto.** Los de `operadores` sí se añadieron |
| `A2-M10` · `A2-M5` | Las cinco tablas de flota son la misma entidad | **Abierto**, y ya no arrastra lo peor: la parte de «documento con vigencia» se cerró con `H-04` (tabla `vigencias`) |
| `A2-B1`,`B2`,`B5`,`B7`,`B10`,`B11` | Columnas muertas · `calificaciones.admin_id CASCADE` (blanqueo de reputación) · dos padres de identidad · tablas sin `ANALYZE` · uuid que parecen FK · columnas derivables | **Abiertos.** Todos 🟢; ninguno verificado de nuevo desde el 28/08 |
| `F-05` | Pedidos `abierto`/`en_negociacion` exponen correo y contacto del cliente a todas las empresas | **Abierto.** Minimización de datos |
| `F-06` · `A3-B2` | `Access-Control-Allow-Origin: '*'` en las dos Edge Functions, una con la clave de servicio | **Abierto**, medido el 28/09 en los dos `index.ts` |
| `F-07` | Contraseñas de 8 sin MFA, sin bloqueo de login, sin leaked-password protection | **Abierto por decisión.** La rotación de contraseñas queda **antes del lanzamiento**, no ahora — decisión tomada, no volver a proponerla |
| `A3-B3`,`B4` | El `catch` final devuelve `String(err)` al cliente · errores sin `Content-Type: application/json` | **Abiertos**, sin verificar de nuevo |
| huecos 7,8,10,11,12,13 | 5 de las 11 RPC sin usar · `aprobarCuenta()` mira un error de dos · operador sin fecha no editable · dos formularios de camión · el permiso hazmat de la unidad · el alta de flota del móvil apunta a RPC que producción no tiene | **Abiertos y documentados** en [FLUJO-OPERATIVO.md § Huecos conocidos](FLUJO-OPERATIVO.md) |
| hueco 14 | La lista de Solicitudes no se actualiza en vivo | **Decisión tomada**, no hueco por cerrar. `pedidos`/`ofertas` no están publicadas en Realtime; la campana cubre mejor el caso. Ver `H-16` |

### 3.3 Cerrados que conviene no dar por eternos

- **`A2-C1` · Realtime.** La publicación se corrigió: hoy lleva las seis correctas
  (`camiones`, `custodios`, `lavados`, `patios`, `notificaciones`, `reservaciones`), con
  `mensajes` y `calificaciones` fuera. **Pero el 84 % del CPU que aquella auditoría midió no
  se ha vuelto a medir nunca**, y no hay forma de saber desde un volcado si bajó. Es la
  medición pendiente más grande del proyecto (§6).
- **`H-16`.** Su aritmética («800 consultas por solicitud con 200 empresas») era falsa: esos
  eventos no llegan. Si algún día se publican `pedidos`/`ofertas`, el problema vuelve — y el
  impedimento que lo bloqueaba (las cinco escrituras del render) ya no está.
- **`A3-N1` · el rol de un usuario.** Se arregló con `cambiar_rol()`, concedida solo a
  `service_role`. Lo que enseñó sigue vigente: **el guard se dispara en toda actualización de
  `perfiles`, no solo en la propia**, y con la clave de servicio `auth.uid()` es NULL. No
  abrir el guard a `service_role` para resolver un caso así.

---

## 4. Las reglas

Cada una lleva entre paréntesis el hallazgo que la produjo. **Si una regla estorba, se
discute con su hallazgo delante, no de memoria.**

### 4.1 Migraciones y esquema

1. **Todo objeto nuevo nace abierto: se revoca en la misma migración.** En producción, cada
   tabla, vista y función creada por `postgres` en `public` recibe `ALL` para
   `authenticated` y `service_role` por privilegios por omisión, y las funciones también
   para `anon`. Lo único que lo cierra es acordarse. *(`H-01`, `H-21`, `R-07`, `R-17`,
   `A3-A5`)*
2. **Toda migración lleva un bloque de verificación que sabe fallar,** y falla si el
   objetivo no se cumplió. Dos veces ha sido ese bloque —no una revisión— lo que cazó el
   error: el `revoke` de `H-21` no retiraba nada porque PostgreSQL concede a `PUBLIC`, y
   `vigencias_caducidad` nació escribible. *(`H-21`, `H-04` etapa 4.7)*
3. **Una migración que reescribe una función se compara con `pg_get_functiondef` antes y
   después.** Una cabecera que dice «solo cambian tres cosas» no es evidencia. *(`R-11`: se
   perdió un `UPDATE` de cuatro líneas y el cierre del acuerdo estuvo roto 22 h en
   producción sin lanzar un error)*
4. **El estado de una función se lee de la base, nunca del `.sql` que la creó.** El archivo
   de `sincronizar_estados_pedidos()` tiene cuatro reglas; la función viva tiene cinco.
   *(`R-14`)*
5. **Dos objetos que expresan la misma regla se cambian en el mismo archivo.** Si no, uno
   deja de decir lo que dice el otro y el usuario recibe un mensaje que no corresponde a la
   regla que le frenó. Pares conocidos: `check_reservacion_disponibilidad()` ↔
   `reservaciones_sin_solape`; `TRACKING_POR_TIPO` (JS) ↔ `tracking_pasos()` (SQL).
   *(`H-06`, `A3-M1`)*
6. **El nombre de un trigger `BEFORE` es carga funcional:** disparan en orden alfabético, y
   cualquiera que toque `NEW` tiene que correr **después** de los `trg_guard_*`, que pueden
   rechazar o revertir. *(`H-19`)*
7. **Un cambio de modelo va por etapas con doble escritura, y la marcha atrás se escribe
   antes de necesitarla.** Así se hicieron las seis etapas de `vigencias` y el paso de
   `plantillas_pedido` a `jsonb`, y por eso ninguno necesitó ventana de rotura. *(`H-04`,
   `H-05`)*
8. **Para renombrar una columna sin ventana de rotura, primero se quita del cliente.** Si el
   navegador no la menciona —porque la rellena un `DEFAULT`, o porque se lee con una función
   que cae a la vieja— el orden de despliegue deja de importar. *(`H-22`, `H-05`)*
9. **Nada de `DROP` por iniciativa propia.** Columnas muertas se documentan con
   `COMMENT ON COLUMN`; índices sospechosos esperan estadísticas de uso. Y todo borrado pasa
   por la Regla #1. *(`H-15`, `H-17`, `A2-M11`)*

### 4.2 Permisos, RLS y vistas

10. **Una vista no tiene RLS detrás: solo `GRANT SELECT`, y la escritura se revoca a los
    tres roles.** `anon`, `authenticated` **y `service_role`** — el barrido original de
    `H-01` olvidó el tercero y la vista siguió escribible cuatro días más. Una vista
    declarada de solo lectura tiene que serlo para todos, o la declaración no significa
    nada. *(`H-01`, `R-07`)*
11. **RLS decide filas, no columnas.** Para restringir columnas, vista con las que la
    pantalla pinta de verdad + `GRANT SELECT`. Es lo que hacen `empresas_publico` y las
    cuatro `*_publico` de flota. *(`H-10`, `A2-A6`, `A2-A7`, `F-02`)*
12. **Toda política lleva `TO`.** Sin él alcanza también a `anon`. Las 73 de producción lo
    tienen; que siga así. *(`A3-M7`, `F-01`)*
13. **`SECURITY INVOKER` salvo que haga falta lo contrario,** y si hace falta `DEFINER`, la
    función reverifica al autor a mano porque se salta el RLS en `SELECT`/`UPDATE`. Pedir el
    privilegio que no se necesita es como se acumulan los `H-21`. *(`R-09`, RPC de negocio)*
14. **El autor de una fila no puede vivir en una columna que escribe el cliente.** El primer
    arreglo de `H-20` guardaba el autor en `meta->>'generado_por'`: habría permitido a una
    cuenta silenciar a otra durante una hora. Un contador de abuso necesita tabla propia,
    sin políticas y sin privilegios. *(`R-12`)*
15. **Los guard triggers son la capa de transiciones, y no se abren para resolver un caso
    particular.** Leen `auth.uid()`, así que siguen aplicando dentro de un `SECURITY
    DEFINER`; con la clave de servicio `auth.uid()` es NULL y el guard rechaza. La salida es
    una función acotada concedida solo a `service_role` con marca transaccional
    (`cambiar_rol()`, `portgo.sync`), no relajar el guard. *(`A3-N1`)*
16. **Nada de lógica de autorización solo en el cliente.** Las clases `role-*` del `<body>`
    son cosméticas; la frontera es el servidor. *(`F-09`)*

### 4.3 Consultas y lecturas

17. **Filtrar y paginar en el servidor. Nunca filtrar lo ya paginado:** un filtro aplicado
    en JavaScript sobre la página acumulada devuelve una lista vacía habiendo resultados más
    abajo, y el usuario concluye que no hay. Es un fallo de corrección, no de eficiencia.
    *(`H-11`)*
18. **Antes de enumerar columnas, medir.** De las tres consultas que `H-08` pedía arreglar,
    dos ya estaban hechas y la tercera no pagaba. Enumerar de más tiene su propio riesgo:
    olvidar una columna no da error, deja un hueco en la interfaz. *(`H-08`, `A2-A3`)*
19. **Los agregados se calculan en la base.** Traer el conjunto completo al navegador para
    sumarlo no tiene cota superior. *(`H-07`, `R-09`, `A2-A8`)*
20. **Un contador es una ida y vuelta, no diez.** *(`H-09`, `A2-A1`)*
21. **Un globo tiene que contar exactamente lo que la pantalla lista.** Antes de mover un
    contador a la base se compara su condición con la del panel. Un globo que cuenta otra
    cosa es peor que no tener globo. *(`R-05`, `R-09`)*
22. **Paginación por keyset con desempate por `id`. Cero `OFFSET`.** *(`A2-M2`)*
23. **`ilike '%x%'` no usa índice B-tree.** Si un buscador de texto se vuelve caliente, el
    remate es GIN con `pg_trgm` — y no antes de tener el dato que lo justifique. *(`H-11`)*

### 4.4 Código de cliente

24. **Comprobar que la escritura ocurrió.** Cuando RLS bloquea un `UPDATE`, afecta a **0
    filas y devuelve `error: null`**: la interfaz canta éxito y nada cambió. Para eso está
    `actualizarConfirmado()` en `js/utils.js`. Y lo mismo vale para una RPC: `R-11` devolvía
    `{resultado:'cerrado', reserva_id:null}` y la pantalla decía que todo fue bien.
    **Comprobar que la fila existe, no que la llamada no dio error.** *(`A3-A1`, `R-11`)*
25. **`esc()` para HTML, `escJs()` dentro de un `onclick`.** El navegador decodifica
    entidades antes de ejecutar el JS, así que `esc()` solo no basta ahí.
26. **Toda ventana modal que pueda fallar necesita salida.** En esta app **no hay cierre por
    `Esc` ni por clic en el fondo** —comprobado, no hay manejador—, así que si los botones
    reintentan la operación que falla, el usuario queda atrapado y tiene que recargar.
    *(`R-18`)*
27. **Un render no escribe.** Escribir al dibujar una lista abre dos agujeros a la vez: hay
    que conceder `UPDATE` sobre filas ajenas (que es `A2-C3`), y dos pestañas abiertas
    emiten los mismos `UPDATE` en carrera. *(`H-16`, `A2-C3`, `A2-A5`)*
28. **Lo inalcanzable se declara inalcanzable, no se arregla.** Hay código muerto conocido
    —el listado de camiones, el detalle de unidad, el modal de reserva directa, el estado
    `Pendiente` y `cerrarAcuerdo()` en `js/pedidos.js`— y está en los huecos 5 y 6 del flujo.
    Proponer un arreglo ahí hace perder el tiempo a quien lo lea. *(`A3-N2`, hueco 6)*

### 4.5 Estados y transiciones

29. **Los estados salen de los `CHECK`, las etiquetas del HTML.** Si no aparece en uno de los
    dos, no existe. *(Regla #4 de `CLAUDE.md`; pasó tres veces en septiembre)*
30. **La máquina de estados vive en `pg_cron` y solo ahí.** Consecuencia asumida: un estado
    rancio tarda hasta 15 minutos en cuadrar en la base. La normalización que el navegador
    conserva es **en memoria**, cosmética. *(hueco 4, `H-16`)*
31. **Quién puede hacer qué lo deciden los guards, no la intuición ni la interfaz.**

### 4.6 Pruebas y verificación

32. **Antes de escribir una prueba, decir qué fallo concreto la haría fallar.** Si no hay
    respuesta, no es una prueba. Hay tres casos medidos de verde sin evidencia: una aserción
    sobre `updated_at` que habría pasado con el trigger roto porque `now()` no cambia dentro
    de una transacción *(`R-13`)*; un contador de errores que solo sabía decir cero, y por
    eso el banco local se daba por limpio **sin la restricción que se iba a probar allí**
    *(`R-16`)*; y una RPC que devolvía éxito con la reservación sin crear *(`R-11`)*.
33. **Una migración se prueba desde el estado ANTERIOR a ella.** Sobre un banco sucio, el
    estado sobreviviente contesta por la migración: `pruebas/banco-local/rehacer-banco.sh`
    existe porque dos sabotajes deliberados pasaron en verde por eso.
34. **Los planes de prueba no llevan cifras absolutas, llevan invariantes.** Una base viva
    caduca los números y nadie escribe la fecha de caducidad. *(`R-19`)*
35. **Verificar qué build y qué proyecto cargó la página antes de leer una sola cifra.**
    `portgo-pruebas` es copia byte a byte de producción: **los datos no distinguen un
    entorno del otro ni un build del otro**. *(`R-10`)*
36. **No mandar a nadie a pulsar un botón sin haber abierto la pantalla.** Un `grep` prueba
    que una cadena está en el repositorio, no que el usuario pueda llegar a ella. *(`R-15`,
    tres veces)*
37. **Paridad verificada antes de sembrar y antes de probar, y el sello se cita con el
    resultado.** Si falló o no se pudo verificar, **se dice eso en vez del resultado**.
    *(Regla #3; el sello vigente es `identicas`, 19/19, 2026-09-28 23:34 UTC)*
38. **Lo que se prueba en pruebas demuestra que funciona en pruebas.** Es el requisito para
    *pedir* permiso de promoción, no la prueba de que producción se comportará igual.

### 4.7 Despliegue

39. **`?v=` por cada fichero cambiado, `CACHE` de `sw.js`, `commit` y `push`.** Sin las tres
    cosas el usuario prueba el fichero viejo.
40. **Confirmar que el despliegue aterrizó antes de pedir una prueba y antes de tratar lo que
    el usuario reporte como evidencia.** Un push no es un despliegue: Vercel serializa
    construcciones y una vez tardó 52 minutos. *(`R-10`)*
41. **Migraciones primero, código después.** El código desplegado puede depender de un
    permiso o una columna que tienen que existir ya.
42. **Los guiones de `supabase/` van en Git Bash, y el comando se entrega en una sola
    línea.** En PowerShell `bash` resolvería a WSL, y un `\` no es continuación: se traga
    cada línea como un comando aparte y no imprime nada útil.
43c. **A producción solo con `aplicar-a-produccion.sh`.** Ni SQL Editor, ni `psql` a mano, ni `execute_sql`, ni `supabase db push`: solo ese guion registra en el libro mayor, avisa de choques y exige la confirmación escrita. *(`Q-20`: siete migraciones llegaron sin registro)*
43d. **El plano `supabase/esquema/` se regenera tras cada promoción que cambie el esquema** (`volcar-esquema.sh`, solo lectura, con `PORTGO_DB_URL="$PORTGO_DB_URL_PROD"`), y se revisa antes de commitear: es lo único con lo que se puede reconstruir la base. Reaplicar las migraciones desde cero no funciona. *(`S-10`: el plano llevó un mes con 22 de 27 tablas)*
43b. **Dos personas trabajan a la vez: el libro mayor registra, no previene.** Si dos migraciones reescriben la misma función, gana la última que se aplica, sin error. `supabase/choques-migraciones.sh` avisa, antes de confirmar, de choques de objeto, de tabla y de número con lo pendiente de promover; lo llaman los dos guiones de aplicación. *(30/09: dos números repetidos en dos días)*

### 4.8 Datos personales

43. **No traer PII que la pantalla no pinta.** Datos fiscales, teléfonos y rutas de
    documentos han viajado al navegador tres veces por un `select('*')`. *(`F-02`, `F-05`,
    `A2-A13`, `H-10`)*
44. **Buckets privados solo por URL firmada.** `unidades`, `registros` y `documentos-viaje`
    guardan **rutas** en la base y se firman al mostrar. Nunca `getPublicUrl`.
44b. **Una política de Storage se ata a la carpeta del dueño, también la de lectura.** Un bucket público sirve sus URL sin pasar por RLS, así que la política `SELECT` no hace falta para abrir un archivo: solo decide quién puede **listar** el bucket entero. `bucket_id = 'x'` a secas, en `SELECT`, `INSERT` o `DELETE`, es dejarle a cualquier cuenta enumerar, subir a carpetas ajenas o borrar lo de otros. *(`S-01`: 98 documentos de choferes listables y borrables)*
45. **`portgo-pruebas` tiene las direcciones reales de los clientes.** Por eso la sonda de
    correo corre **primero**, antes de replicar: comprobar el bloqueo después de llenar
    pruebas con direcciones reales es comprobarlo demasiado tarde. *(Regla #3)*
46. **Hay obligación legal con plazo** (ARCO, LFPDPPP). El borrado de cuenta es la operación
    con menos margen para ir lenta o fallar. *(`A2-C4`, `js/privacidad.js`)*

---

## 5. Revisado y correcto: no se toca

Consolidado de las cuatro auditorías. Cada entrada costó averiguar por qué está así, y
«arreglarla» es una regresión.

**Seguridad e integridad**

- **RLS activo en las 24 tablas**, sin una excepción. **73 políticas en el volcado del 28/09,
  y las 73 con `TO`** — la 4ª auditoría contó 74 el 14/09; la diferencia no se ha rastreado y
  se deja dicha en vez de elegir un número.
- **Las funciones `SECURITY DEFINER` fijan `search_path`.** Todas. Es la defensa contra el
  secuestro por `search_path`.
- **Los guard triggers.** La mejor pieza del sistema en las cuatro auditorías: son la capa
  que RLS no puede dar y siguen aplicando dentro de un `DEFINER`.
- **`puede_notificar()`** — cinco ramas de relación, la más cara al final.
- **`reservaciones_sin_solape`**, el `EXCLUDE` con GiST: declarativo, sin condición de
  carrera.
- **`empresas_publico`** como patrón: separar la ficha pública del expediente en vez de
  cerrar de golpe. Con la lección de `H-01` aplicada — nunca `GRANT ALL` sobre una vista.
- **Sin XSS ni inyección.** Revisados los ~60 manejadores en línea: todos reciben
  identificadores generados por el sistema. El escape doble está bien entendido.
- **`sessionStorage` para la sesión, `localStorage` solo para el tema.**
- **Sin secretos en el repositorio.** La clave de servicio solo en secretos de Edge
  Function.

**Modelo**

- **La denormalización de nombres** (`cliente_nombre`, `cliente_email`, `admin_nombre`) es
  deliberada y correcta: las FK son `ON DELETE SET NULL` y los `CHECK` `*_presente` lo
  demuestran. Normalizarla dejaría sin nombre a registros que son legales.
- **`reservaciones_historico` es un archivo, no una copia viva.** Que le falten columnas es
  `A2-C2`; que exista separada, no.
- **La tabla ancha y dispersa de `pedidos`** es lo correcto: los cuatro servicios comparten
  cliente, ruta, fechas, precio, estado y flujo de ofertas. Cuatro tablas obligarían a un
  `UNION` en la consulta más caliente.
- **Sin `deleted_at` ni borrado lógico**, y está bien: las columnas `estado` ya llevan el
  ciclo de vida y el archivo tiene tabla propia.
- **`documentos_fiscales` y `pagos` vacías** son andamiaje de funcionalidad planificada, no
  restos.
- **Las PK de texto legibles** (`F-001`, `CUS-005`) se enseñan al usuario y arrastrarían las
  políticas de Storage. Decidido no migrarlas a `uuid`.

**Consultas**

- **Cero N+1.** Todas las listas resuelven sus relaciones con un `.in(...)` agrupado tras
  recoger los `id` de la página. Los únicos bucles con `await` son subidas y firmas de
  Storage, y van en `Promise.all`.
- **Keyset en las dos listas que crecen**, con los índices `(created_at DESC, id DESC)`
  puestos para eso.
- **`estadoCobro()` derivado y no almacenado:** no hay tarea diaria que pueda quedarse atrás
  y dar por al día una factura vencida. Y el índice
  `idx_reservaciones_cobro (pagado, fecha_vencimiento_pago) WHERE estado='Completada'`
  respalda exactamente la consulta del globo.
- **`timestamptz` para instantes, `date` para días.** Uniforme, sin un `timestamp` sin zona.
- **Los 21 índices parciales** calzan con filtros reales del código. Sus 0 escaneos son
  efecto del volumen, no del diseño.

**Operación**

- **El sistema de paridad de la Regla #3.** 19 dimensiones, sello con fecha y veredicto, y
  guiones que **se niegan a arrancar** si el sello falta, caduca o dice que divergen. Las
  tres veces que salió en rojo, señalaba algo real.
- **`FLUJO-OPERATIVO.md`.** Declara sus huecos conocidos en vez de esconderlos y dice de
  dónde sale cada afirmación.
- **Las pruebas de `pruebas/` pasan por RLS, guards y RPC igual que la app**, no por un
  atajo.
- **`arranque_app()`** es el patrón correcto: una RPC que devuelve todo el arranque en un
  `jsonb`.

---

## 6. Lo que nunca se ha medido

Esto no es una lista de pendientes menores: es el hueco de método que las cuatro auditorías
arrastran, y lo que mantiene abiertos varios hallazgos por falta de dato, no por falta de
trabajo.

1. **Realtime, desde el 2026-08-28.** Era el hallazgo dominante de la 2ª auditoría —84 % del
   CPU de la base, 680 007 llamadas al decodificador WAL— y **ninguna auditoría posterior ha
   podido volver a medirlo**. La publicación se corrigió; si eso bajó el consumo, nadie lo
   sabe. Es la medición pendiente más grande, y ninguna otra optimización se le acerca en
   tamaño.
2. **`EXPLAIN` / `EXPLAIN ANALYZE`,** desde la 2ª auditoría. La 3ª y la 4ª no pudieron.
3. **`pg_stat_statements`.** Está instalada (v1.11) y no se usa. Es lo que le faltó a la 4ª
   auditoría, y sin ella la quinta tendrá el mismo hueco. **Encenderla como práctica es una
   línea de configuración.**
4. **`pg_stat_user_indexes`.** Sin `idx_scan` no se puede decidir ningún `DROP INDEX`: es
   exactamente lo que mantiene `H-17` abierto.
5. **La concurrencia real.** La carrera de `A3-C2` no se reprodujo: exige dos aceptaciones
   simultáneas de verdad. Lo verificado es que el índice único existe y que la comprobación
   de estado rechaza el segundo intento. El índice es la garantía real, no la prueba.
6. **Cuántas sesiones concurrentes hay.** Sin ese dato no se puede justificar el umbral de
   reparto de Realtime, ni el particionado de `notificaciones`, ni el índice trigram.
7. ~~**`A2-C3` ejercitado con una sesión de empresa.**~~ **Medido el 01/10**: ejecutado en
   banco local y, tras el arreglo, por API en pruebas con la sesión de empresa. Ver §3.1.

A los volúmenes actuales —la tabla mayor ronda las 900 filas— **ninguna consulta de este
sistema puede ir lenta**, y PostgreSQL ignoraría la mitad de los índices que existen. Eso
significa dos cosas: ningún problema de rendimiento de este archivo es visible hoy, y el
momento de arreglarlos es ahora, cuando una migración toca decenas de filas y no millones.

---

## 7. Las lecciones de método

Las cuatro auditorías coinciden en esto más que en cualquier hallazgo concreto.

**Una auditoría estática dice dónde mirar; no dice qué hay.** De los 23 defectos `R`/`N`,
ninguno estaba en las listas. Ocho de los diez primeros aparecieron *ejecutando* los
arreglos. Y la 3ª auditoría lo escribió de sí misma: no detectó que cambiar el rol de un
usuario **no había funcionado nunca**, un fallo vivo en producción que una lectura del código
no podía ver porque el error se tragaba.

**Ejecutar tampoco basta si no se comprueba qué se está ejecutando.** `H-07` se dio por
probado tres veces sobre un despliegue que no lo contenía. Con dos bases idénticas, de dos
pantallas completas —trece cifras, dos gráficos, tres tablas— solo **una celda** distinguía el
código viejo del nuevo, y se notó por suerte.

**Un verde no es evidencia si la prueba no podía fallar.** Tres casos medidos, en `R-13`,
`R-16` y `R-11`. El patrón es siempre el mismo: se comprueba algo *parecido* a lo que se
quería comprobar.

**No entregar una explicación sin medirla.** Ante un síntoma se propusieron tres causas
plausibles seguidas, las tres afirmadas como hechos, las tres falsas; cada una mandó al
usuario a hacer trabajo que no llevaba a ninguna parte, y la causa real estaba a una petición
HTTP de distancia desde el primer momento.

**Lo que no queda escrito se pierde, y lo escrito se queda atrás en silencio.** `CLAUDE.md`
—el archivo que va siempre en contexto— ha afirmado cosas falsas al menos cinco veces:
que ninguna RPC se usaba, que tres tablas se repintaban por Realtime, que ambas partes tenían
que subir evidencia, que el render seguía escribiendo, y que tres ficheros faltaban del
`SHELL` del service worker. **Un documento maestro equivocado es peor que ninguno**, porque se
cree.

**Lo más caro lo encontró el usuario.** `R-10`, `R-11` y `R-18`, probando a mano, con la
pantalla delante. En dos de los tres, una frase suya descartó de golpe la explicación que yo
defendía — «este mensaje no lo vi en ningún momento» convirtió un fallo supuesto en un no-op
demostrado. No es suerte: es el único punto del proceso donde alguien mira el sistema entero
sin saber ya lo que debería pasar.

---

## 8. Índice de hallazgos y equivalencias

### 8.1 El mismo defecto, numerado cuatro veces

Media docena de problemas los encontró cada auditoría por su cuenta. Saber que son el mismo
evita contarlos de más y evita «descubrirlos» una quinta vez.

| Defecto | 1ª (pentest) | 2ª (BD) | 3ª (web) | 4ª (BD) | Estado |
|---|---|---|---|---|---|
| `select('*')` de más | — | `A3` (67) | `M6` (65) | `H-08` (65) | Cerrado al medirlo · 25/09 |
| `perfiles` entero legible (PII fiscal) | `F-02` | `A6`, `A10` | — | — | Cerrado con `empresas_publico` — que a su vez creó `H-01` |
| El catálogo entrega la fila entera de flota | `F-08` | `A7` | — | `H-10` | Cerrado · 18/09 |
| «Documento con vigencia» repetido en 5 tablas | — | `M5` (41 col.) | — | `H-04` | Cerrado · 24/09 |
| Agregados calculados en el navegador | — | `A8` | — | `H-07`, `R-09` | Cerrado · 18 y 28/09 |
| Contador del superadmin con 10 consultas | — | `A1` | — | `H-09` | Cerrado · 17/09 |
| FK sin índice de apoyo | — | `M4` (14) | `M5` (14) | `H-13` (8) | 8 índices creados; los otros, condicionados a que se poblaran |
| Cron sin índice | — | `A4` | — | `H-12` | Cerrado · 18/09 |
| Sin `updated_at` | — | `A10` | — | `H-19` | Cerrado · 28/09 |
| `TRUNCATE`/`EXECUTE` de más a `anon`/`authenticated` | — | `B6` | `A6`, `B5` | `H-21` | Cerrado · 11 y 18/09 |
| `plantillas_pedido` duplica `pedidos` | — | `A9` | — | `H-05` | Cerrado · 17/09 |
| Convención de fechas `_at`/`_en` | — | `B3` | — | `H-22` | Cerrado · 28/09 |
| Dinero con dos tipos | — | `M12` | — | `H-18` | **Abierto**, dado por cerrado por error |
| Referencias polimórficas sin FK | — | `C5` | — | `H-06` | Cerrado a medias — ver §3.1 |
| La máquina de estados en el render | — | `C3`, `A5` | — | `H-16` | Cerrado · 25/09 |
| Realtime mal configurado | — | `C1` | — | `H-16` | Publicación corregida; **el coste, sin volver a medir** |

### 8.2 Dónde leer el detalle de cada id

| Prefijo | Auditoría | Archivo |
|---|---|---|
| `F-01`…`F-09` | 1ª · pentest, 24/08 | [`security-findings.md`](../security-findings.md) |
| `C1`…`C5`, `A1`…`A13`, `M1`…`M15`, `B1`…`B11` | 2ª · BD, 28/08 | [`auditoria-2.md`](../auditoria-2.md) §12 tiene la matriz |
| `C1`,`C2`,`A1`…`A6`,`M1`…`M8`,`B1`…`B6`, `N1`…`N3` | 3ª · web, 11/09 | [`auditoria-3.md`](../auditoria-3.md) §0 tiene el estado |
| `H-01`…`H-22`, `R-01`…`R-20` | 4ª · BD, 14/09 | Artifact: `https://claude.ai/artifact/ECNDyAMoTyavND4qjmEoRJ` |
| huecos 1…14 | Verificados, con decisión tomada | [`FLUJO-OPERATIVO.md`](FLUJO-OPERATIVO.md) § Huecos conocidos |
| Encargo de 25 apartados | Plantilla para la 5ª | [`Auditoriabd.md`](../Auditoriabd.md) |

**Cuidado con los prefijos repetidos.** La 2ª y la 3ª usan las mismas letras para hallazgos
distintos: `C2` es «el archivado pierde columnas» en la 2ª y «dos reservaciones para un mismo
pedido» en la 3ª. En este archivo van siempre con la auditoría delante (`A2-C2`, `A3-C2`).

### 8.3 Los planes de prueba, y qué cerró cada uno

Los guiones de `pruebas/` no son documentación de apoyo: son la prueba de que un hallazgo se
cerró de verdad. Se conservan con su resultado anotado.

| Plan | Cubre | Resultado |
|---|---|---|
| [`PLAN-PRUEBAS-ETAPA4.md`](../pruebas/PLAN-PRUEBAS-ETAPA4.md) · [`-B`](../pruebas/PLAN-PRUEBAS-ETAPA4-B.md) | `H-04` etapa 4: cinco pantallas que pasaron a leer de `vigencias` | Pasadas |
| [`PLAN-PRUEBAS-ESPEJO.md`](../pruebas/PLAN-PRUEBAS-ESPEJO.md) | `H-04` etapa 3: la doble escritura y el espejo | Pasado |
| [`PLAN-PRUEBAS-TRES-DECISIONES.md`](../pruebas/PLAN-PRUEBAS-TRES-DECISIONES.md) | Hazmat frena el trato · todo papel con fecha · todo recurso con dueño | Pasado |
| [`PLAN-PRUEBAS-COLA-DEV.md`](../pruebas/PLAN-PRUEBAS-COLA-DEV.md) | Los seis cambios de `dev`: `H-11`, `H-06`, `H-19`, `H-22`, `R-09`, el render sin escrituras | Pasado, y destapó `R-18` |
| [`PLAN-PRUEBAS-PASO2.md`](../pruebas/PLAN-PRUEBAS-PASO2.md) | La corrección de `R-11` y, de paso, `H-06` —que no se podía probar antes porque el cierre abortaba— | Pasado |
| [`PLAN-PRUEBAS-APROBAR-ACUERDO.md`](../pruebas/PLAN-PRUEBAS-APROBAR-ACUERDO.md) | La aprobación del superadmin pasando por la RPC en una transacción | Pasado |
| [`pruebas/LEEME.md`](../pruebas/LEEME.md) | Las ocho sondas automatizadas, los candados y cómo se monta el ambiente | — |

**Tres cosas que estos planes enseñaron y valen más que su resultado:**

1. **Casi ninguna auditoría se cierra midiendo.** De los seis cambios del plan de la cola,
   **tres no tenían nada nuevo que enseñar en pantalla**: su prueba era que todo siguiera
   igual. Decirlo por adelantado evita ir a buscar un botón nuevo que no existe.
2. **Lo que ninguna medición alcanza es teclear y pulsar.** La validación de formularios, la
   salida de un modal y que una variable esté en alcance no dan error de compilación y solo
   aparecen al abrir la pantalla.
3. **Un plan se escribe contra lo que hay hoy en la base, y eso caduca.** Por eso ahora
   llevan invariantes en vez de cifras.
