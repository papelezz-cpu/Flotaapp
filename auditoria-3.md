# Tercera auditoría técnica — PortGo

**Fecha:** 2026-09-11
**Alcance:** la **plataforma web** — base de datos, código cliente (`js/`, 13 258 líneas), `app.html`, `sw.js`, Edge Functions y coherencia con el flujo de negocio.
**Método:** auditoría fresca e independiente. No se partió de la lista de la 2ª auditoría ni se usó como guion; los hallazgos de abajo salieron de leer el esquema y el código de nuevo. Al final se contrastan con ella.
**Documento de apoyo:** [docs/FLUJO-OPERATIVO.md](docs/FLUJO-OPERATIVO.md), usado como declaración de lo que el sistema *debe* hacer, para contrastarlo con lo que hace.

## Fuera de alcance, por decisión

**El cliente Android no se audita ni se puntúa.** La plataforma web sale primero; las aplicaciones móviles se construyen después, cuando la web funcione. Auditar hoy un cliente que nadie usa, y penalizar la nota por sus diferencias con la web, mide un problema que todavía no existe.

Esto se deja escrito para que una lectura futura sepa que **fue una decisión de alcance y no un descuido**. Cuando el móvil entre en producción, la coherencia entre los dos clientes vuelve a ser materia auditable — y conviene que lo sea antes de publicarlo, no después.

Lo que **sí** se audita aunque tenga origen en aquel trabajo: lo que está vivo en la base de datos de producción hoy y es alcanzable desde la web. Ver **M8**.

## Fuente de los datos, y qué no cubre

Todo lo estructural está leído de **`supabase/espejo/`, el volcado de producción del 2026-09-08 a las 16:08**, con sello de paridad `identicas`, 0 diferencias, 0 dimensiones no verificables, en sus 18 dimensiones. Es una fuente sólida para esquema, RLS, triggers, funciones, permisos y datos.

**Lo que esa fuente no puede dar, y por tanto aquí no se afirma:**

- **Nada medido en tiempo de ejecución.** Sin `pg_stat_statements`, sin `EXPLAIN ANALYZE`, sin conteos de escaneos. La 2ª auditoría midió contra la base viva y descubrió que Realtime se llevaba el 84 % del CPU; **esta auditoría no puede confirmar ni desmentir que eso siga así.** Cualquier afirmación de rendimiento de abajo es estructural —la forma de la consulta— no medida.
- **Los tres días posteriores al volcado.** Las migraciones `20260909120000` y `20260910120000` son posteriores y se leyeron del repositorio, no de la base. No consta que estén aplicadas en producción.
- **El estado real de las migraciones del propio 8-sep.** Ver **M4**: los índices de `20260908120000` no están en el volcado, y desde el repositorio no hay forma de saber si es porque se aplicaron después o porque no se aplicaron.

---

# 0. Estado de resolución — 2026-09-11, misma tarde

Los diez hallazgos se corrigieron y se aplicaron a `portgo-pruebas` el mismo día
de la auditoría. **Nada de esto ha llegado a producción**, y nada se ha probado
a mano todavía.

| # | Hallazgo | Cómo se cerró | Dónde está |
|---|---|---|---|
| C1 | Relay de correo | Destinatarios separados por procedencia; los que vienen en la petición pasan por `puede_notificar()`, llamada con la identidad de quien llama | Función desplegada en pruebas |
| C2 | Dos reservaciones | `FOR UPDATE` sobre el pedido en las dos funciones + índice único parcial | Migración aplicada |
| A1 | Escrituras mudas | `actualizarConfirmado()` en las tres transiciones que dejan estado colgando (adopción 7 → 14) | En `dev` |
| A2 | Precacheo inútil | `ignoreSearch` en el respaldo + los tres ficheros que faltaban en `SHELL` | En `dev` |
| A3 | CDN sin fijar | Las tres etiquetas con `integrity`; Supabase fijado a 2.116.0 | En `dev` |
| A4 | Éxito falso | Resultado comprobado en las tres acciones, `rol` validado, último superadmin protegido | Función desplegada en pruebas |
| A5 | Privilegio por defecto | **No se puede aplicar**: exige ser miembro de `supabase_admin`, y ni el rol de migraciones ni el SQL Editor lo son (`ERROR 42501`, comprobado). Se sustituye por detección: `supabase/sondas/exposicion-anon.sql` | Sonda en `dev` |
| A6 | TRUNCATE | Retirado de las 25 relaciones, preguntando al catálogo en vez de enumerar | Migración aplicada |
| M7 | Políticas sin `TO` | `ALTER POLICY … TO authenticated` ×33 | Migración aplicada |
| M8 | RPC del flujo viejo | Su rama `aceptar` delega en `aceptar_y_cerrar_acuerdo` | Migración aplicada |
| M4 | Sin libro mayor | `aplicadas.tsv` + `estado-migraciones.sh`, escritos por los guiones que ya aplican | En `dev` |

**La nota no se mueve.** Sigue siendo 61/100 porque mide lo que la auditoría
encontró, y lo corregido vive en pruebas, sin verificación manual y sin llegar a
producción. Moverla ahora sería afirmar como hecho lo que todavía es una
expectativa — que es justo lo que esta auditoría reprocha en otros sitios.

## Lo que apareció al arreglar, y la auditoría no había visto

Tres cosas que solo salieron al tocar el código:

1. **A3 estaba peor de lo documentado.** La ruta sin fijar servía en ese momento
   **2.116.0**, mientras las Edge Functions fijan 2.112.3 con un comentario
   explicando por qué hay que fijarlas. El navegador llevaba tiempo corriendo
   una versión que nadie verificó. Se fijó a 2.116.0 —lo que ya corría— y no a
   2.112.3: congelar lo que hay, sin cambiar de versión de paso.

2. **M8 tapaba algo más grave de lo que decía el hallazgo.** Al delegar, esas
   dos RPC heredan comprobaciones que no tenían. La que importa: **por esa vía,
   una empresa con el permiso SCT o los seguros vencidos cerraba el trato sin
   que nadie lo mirara**, porque el desvío `DOCUMENTOS_VENCIDOS` solo existe en
   `aceptar_y_cerrar_acuerdo`. Eso es un agujero de negocio, no de coherencia
   entre clientes, y la auditoría no lo vio.

3. **El arreglo de C1, tal como se escribió primero, rompía un caso legítimo.**
   El campo de correo al reservar viene relleno con el de la cuenta pero es
   editable, y una empresa que usa su buzón de operaciones se habría quedado sin
   confirmación, en silencio. Se corrigió apoyando la regla en la fila: la
   dirección pasa si figura como contacto de una reserva de la que quien llama
   es parte, y el propio RLS decide ese «es parte».

## Lo que sigue abierto

- **A5 no se puede cerrar por la vía prevista.** Cambiar los privilegios por
  defecto de `supabase_admin` exige ser miembro de ese rol, y en Supabase ni el
  rol que aplica migraciones ni el SQL Editor lo son. Queda como riesgo
  aceptado y **vigilado**: `supabase/sondas/exposicion-anon.sql` comprueba lo
  que A5 pretendía evitar —una tabla legible por `anon`— y además el fallo más
  probable, que A5 no cubría: que alguien cree una tabla y olvide activarle RLS.
  Cerrarlo de verdad requiere soporte de Supabase.
- **Las pruebas manuales**, que no se han hecho.
- **Medir Realtime**, que sigue siendo la partida más grande y necesita la base
  viva. El hallazgo dominante de la 2ª auditoría continúa sin confirmar ni
  desmentir.
- **La réplica de producción**, que no llegó a correr: el sello de paridad sigue
  siendo el del 8 de septiembre y pruebas ya lleva cuatro migraciones que
  producción no tiene.

---

# 1. Calificación

| Apartado | Nota | En una línea |
|---|---:|---|
| **Seguridad** | **58 / 100** | RLS completa y guards serios en la base; el correo sale por un canal sin ningún control de relación. |
| **Integridad y concurrencia** | **57 / 100** | Los guards son excelentes fila a fila; el cierre del acuerdo no se protege contra dos transacciones a la vez. |
| **Modelo de datos** | **60 / 100** | El dominio está bien capturado. Las referencias polimórficas de texto y las cinco tablas de flota idénticas siguen ahí. |
| **Rendimiento y escalabilidad** | **62 / 100** | Cursor en las dos listas que crecen y la máquina de estados ya en cron. Enfrente, 65 `select('*')` y 127 lecturas sin cota. |
| **Operación y despliegue** | **60 / 100** | El sistema de paridad es ejemplar. El precacheo del Service Worker no sirve, y no hay registro de qué migración corre dónde. |
| **Documentación** | **82 / 100** | `FLUJO-OPERATIVO.md` es de las mejores piezas del proyecto. `CLAUDE.md` afirma algo que el código desmiente. |

## **Promedio ponderado: 61 / 100**

Ponderación: seguridad 23 %, integridad 23 %, modelo 17 %, rendimiento 14 %, operación 14 %, documentación 9 %.

> **Los dos puntos que suben respecto al primer borrador de esta auditoría no son una mejora del sistema: son una categoría que salió del alcance.** Con el cliente Android dentro, la nota era 59. Nada se ha arreglado entre una cifra y otra. Conviene no leer el 61 como progreso.

**Frente al 56 de la 2ª auditoría, la comparación tampoco es limpia**, porque aquella midió la base viva y esta no puede. Lo que sí se puede decir con la evidencia disponible: entre el 28 de agosto y hoy se cerró la exposición de `perfiles`, se bajó la máquina de estados a `pg_cron`, se adoptaron seis RPC transaccionales, se construyó un sistema de paridad de 18 dimensiones y se escribió el documento de flujo. Ese trabajo es real y se nota al leer el código.

La nota sigue en la franja baja porque esta auditoría miró donde la anterior no había mirado —el canal de correo y la concurrencia de las RPC nuevas— y encontró allí dos problemas serios. **No es que el sistema haya empeorado: es que la parte que faltaba por auditar era la que peor estaba.**

---

# 2. Los dos hallazgos críticos

## 🔴 C1 — El correo de PortGo es un relay abierto para cualquier usuario con cuenta

**Dónde:** `supabase/functions/enviar-notificacion/index.ts`, líneas 184-190 y 477-497.

La función exige una sesión válida y —bien hecho— cierra los envíos masivos: `nueva_solicitud` y `solicitudes_lote` comprueban que quien llama sea superadmin, con un comentario que explica exactamente por qué. **Ese control no existe para ningún otro tipo.**

La resolución de destinatarios es una cadena de `if/else` sobre campos que vienen del cuerpo de la petición, sin una sola comprobación de que quien llama tenga relación con el destinatario:

```ts
} else if (tipo === 'resolucion') {
  ids = (Array.isArray(payload.destinoIds) ? payload.destinoIds : []) ...
} else if (payload.clienteEmail) {
  directos = [payload.clienteEmail as string];
```

Y la plantilla `resolucion` —la más usada, 9 sitios del código la disparan— pone texto del cuerpo de la petición en el asunto y en el cuerpo del correo:

```ts
resolucion: (p) => tpl(
  `${String(p.titulo ?? 'Actualización').slice(0, 45)} - PortGo`,
  `<h2 …>${esc(p.titulo)}</h2><p>${esc(p.mensaje)}</p> …`
```

**Consecuencia.** Cualquiera que se registre en PortGo —el alta es autoservicio— puede hacer que la plataforma envíe:

- un correo **a cualquier usuario registrado** cuyo id conozca, con asunto y cuerpo que él escribe (`tipo:'resolucion'` + `destinoIds`);
- un correo **a cualquier dirección de internet**, con texto propio en el campo `nota` (`tipo:'reserva_rechazada'` + `clienteEmail`).

Sale del servidor SMTP de PortGo, con su dominio y su SPF/DKIM en regla. Es phishing con sello de autenticidad, y el blanco natural son los propios usuarios de la plataforma, a quienes el remitente ya les resulta familiar.

**Por qué esto es una contradicción interna, no solo un fallo.** La base de datos sí resuelve este problema, y con cuidado. `puede_notificar()` es una función de cinco ramas que comprueba la relación antes de dejar insertar una fila en `notificaciones`: a ti mismo, a un superadmin, siendo superadmin, o siendo las dos partes de una misma reservación o de una misma negociación. El documento de flujo lo enuncia como regla: *«Quién puede avisar a quién lo decide el RLS de `notificaciones`, y es restringido por relación»*.

**La campana está protegida por relación; el correo, que es el canal de más confianza porque sale del dominio, no tiene ningún control.** Se protegió el canal barato y se dejó abierto el caro.

**Corrección.** La misma regla que ya existe: resolver el destinatario en el servidor a partir de la entidad, no aceptarlo del cliente. La función ya tiene la clave de servicio, así que puede leer la reservación o la oferta y deducir a quién le toca. Mientras tanto, `select public.puede_notificar(<destino>)` ejecutado con el JWT de quien llama corta el caso entero con una línea.

---

## 🔴 C2 — Dos reservaciones para un mismo pedido: el cierre del acuerdo no se protege contra concurrencia

**Dónde:** `supabase/migrations/20260903120000_rpc_aceptar_y_cerrar_acuerdo.sql`.

`aceptar_y_cerrar_acuerdo` lee las dos filas que gobiernan la decisión sin bloquearlas:

```sql
SELECT * INTO v_oferta FROM public.ofertas WHERE id = p_oferta_id;
SELECT * INTO v_pedido FROM public.pedidos WHERE id = v_oferta.pedido_id;
...
IF v_pedido.estado NOT IN ('abierto', 'en_negociacion') THEN
  RAISE EXCEPTION 'Esta solicitud ya no está en negociación.';
END IF;
```

Hay **dos vías legítimas y simultáneas** de llegar aquí sobre el mismo pedido, y el propio parámetro `p_via` las nombra:

- el **cliente** acepta la oferta A de la empresa X (`cliente_acepta_oferta`);
- la **empresa Y** acepta la contraoferta que el cliente le puso sobre su oferta B (`empresa_acepta_contra`).

Son dos personas distintas, en dos sesiones distintas, ambas haciendo algo que el sistema les permite. En `READ COMMITTED`, las dos transacciones leen el pedido en `en_negociacion`, las dos pasan la comprobación, y las dos siguen adelante hasta `cerrar_acuerdo`, que inserta una reservación.

**Nada lo detiene aguas abajo:**

- **No hay UNIQUE sobre `reservaciones.pedido_id`.** Verificado: las únicas restricciones de unicidad del esquema son `expedientes(reserva_id, etapa)` y `uq_calificaciones_reservacion`.
- **`reservaciones_sin_solape` no cubre este caso.** Es un `EXCLUDE USING gist (unidad WITH =, daterange(…) WITH &&)`: protege contra reservar *la misma unidad* dos veces. Aquí son dos unidades distintas, de dos empresas distintas.

**Resultado:** un pedido en `acordado` con dos reservaciones `Activa`, dos empresas que creen tener el trabajo, dos unidades comprometidas y un cliente que pagará una. Y la segunda transacción marca `rechazada` la oferta de la primera, así que la reservación viva de la empresa X queda colgando de una oferta rechazada.

**Corrección, dos líneas:**

1. `SELECT * INTO v_pedido FROM public.pedidos WHERE id = v_oferta.pedido_id FOR UPDATE;` — serializa las dos transacciones sobre la fila del pedido, y la segunda encuentra el estado ya en `acordado` y sale por el `RAISE EXCEPTION` que ya está escrito.
2. Una red de seguridad declarativa, porque el bloqueo protege este camino y no los futuros:
   ```sql
   create unique index uq_reservaciones_pedido_vivo
     on public.reservaciones (pedido_id)
     where estado not in ('Cancelada', 'Rechazada');
   ```
   El índice **parcial** es imprescindible: cancelar una reserva reabre el pedido y una segunda empresa puede ganarlo después, así que un UNIQUE a secas rompería el flujo de cancelar-reabrir que el documento describe en §9.

> **Antes de crear ese índice hay que comprobar si ya existe alguna fila duplicada.** Si la carrera ya ocurrió alguna vez, el índice fallará al crearse — y esa sería la confirmación de que el problema no es teórico.

---

# 3. Hallazgos altos

### 🟠 A1 — Veinticinco escrituras sin comprobar el resultado, y el remedio propio del proyecto usado en el 8 % de los casos

`CLAUDE.md` lo escribe como norma: *«Always surface RLS errors: check `error` from every mutating call»*, y el proyecto tiene `actualizarConfirmado()` en `js/utils.js:123` precisamente porque **un UPDATE bloqueado por RLS afecta 0 filas y devuelve `error: null`** — comprobar el error no basta.

Medido:

- **87** llamadas a `.update(` en `js/`.
- **7** usos de `actualizarConfirmado()`, en 2 archivos (`admin.js`, `aprobaciones.js`). **Adopción: 8 %.**
- **25+** escrituras cuyo resultado no se desestructura siquiera.

Las que más duelen, porque dejan estado inconsistente en silencio:

| Sitio | Qué hace | Qué queda si falla |
|---|---|---|
| `js/aprobaciones.js:1146` y `:1231` | `update({estado:'disponible'})` sobre el recurso | La unidad queda `ocupado` para siempre; el catálogo la esconde |
| `js/aprobaciones.js:1142` | `update({estado:'finalizado'})` sobre el pedido | El superadmin ve éxito; el pedido no avanza |
| `js/pedidos.js:2368` | `update({estado:'ocupado'})` | Unidad libre en pantalla, comprometida de verdad |

Es el mismo fallo mudo que la migración `20260728120000` existe para reparar.

### 🟠 A2 — El precacheo del Service Worker no se usa nunca, y sin red la app no arranca en la primera visita

`sw.js` precarga en la instalación una lista `SHELL` de 33 rutas **sin parámetro de versión**:

```js
const SHELL = [ …, '/js/pedidos.js', '/js/reservaciones.js', … ];
```

`app.html` pide esos mismos ficheros **con** el parámetro que la lista de despliegue obliga a bombear:

```html
<script src="js/pedidos.js?v=72"></script>
```

Y el respaldo sin red es `caches.match(e.request)`, **sin `ignoreSearch`**. La Cache API compara la URL completa, la query incluida, así que `/js/pedidos.js` nunca responde a `/js/pedidos.js?v=72`.

Dos consecuencias:

1. **Las 33 descargas de cada instalación son trabajo tirado:** ocupan el caché y no se sirven jamás.
2. **Sin conexión, un visitante nuevo no ve la aplicación.** Solo funciona offline quien ya la haya cargado online al menos una vez, porque entonces la estrategia network-first sí guardó las URL con su `?v=`.

Arreglo: una línea, `caches.match(e.request, { ignoreSearch: true })` en el respaldo — o quitar `SHELL`, que con network-first aporta poco. De paso, faltan en la lista `js/detalle.js`, `js/notificaciones.js` y `css/detalle.css`.

### 🟠 A3 — Tres dependencias de terceros sin verificación de integridad; una sin fijar

```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
<link   href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
```

Ninguna lleva `integrity=`. Y `@supabase/supabase-js@2` **no está fijada**: resuelve a la última 2.x en cada carga. Una versión con un fallo, o un paquete comprometido, entra en producción sin que nadie toque el repositorio.

El contraste está en la propia casa: las dos Edge Functions fijan la versión exacta, con un comentario que explica por qué. **El mismo cuidado que se puso en el servidor falta en el navegador**, que es donde se teclean las contraseñas.

### 🟠 A4 — `gestionar-usuario` informa éxito de operaciones que fallaron

En `supabase/functions/gestionar-usuario/index.ts`, las tres acciones privilegiadas ignoran el resultado de su escritura:

```ts
await sbAdmin.from('perfiles').insert({ user_id: newUser.user.id, nombre, rol })
return new Response(JSON.stringify({ ok: true }), …)
```

- **`crear`:** el usuario de auth ya existe. Si el `insert` en `perfiles` falla —por ejemplo porque `rol` no pasa `perfiles_rol_check`, que la función no valida— queda **una cuenta sin perfil** y la respuesta dice `ok: true`. Es exactamente lo que el flujo advierte: *«Si el perfil no se crea, la cuenta queda inutilizable»*. El superadmin no se entera.
- **`editar`:** mismo patrón con el `update`.
- **`eliminar`:** `deleteUser` sin comprobar. Y la 2ª auditoría documentó que hay cuentas cuyo borrado falla por restricciones `CHECK`. El superadmin ve «ok», el usuario sigue ahí, y si la petición venía de un derecho ARCO de cancelación, se da por atendida sin haberse atendido.

Además: **nada impide que el superadmin borre al último superadmin** o se cambie el rol a sí mismo. Sin superadmin no se aprueban cuentas, ni recursos, ni solicitudes: la plataforma se para y no hay camino de vuelta desde la aplicación.

Y **no queda rastro**. Una función que crea, edita y borra cuentas con la clave de servicio no escribe ningún registro de quién hizo qué ni cuándo.

### 🟠 A5 — El privilegio por defecto que reabre lo que la migración del 27-ago cerró

`20260827160000_anon_sin_privilegios_de_tabla.sql` retiró los permisos de `anon`, y lo hizo bien: hoy solo le queda `SELECT` sobre `app_config`. Pero eso es una **fotografía**, y debajo sigue viva la regla que reparte permisos a las tablas futuras:

```sql
ALTER DEFAULT PRIVILEGES FOR ROLE postgres       IN SCHEMA public GRANT ALL ON TABLES TO postgres, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO postgres, anon, authenticated, service_role;
```

**La línea de `postgres` ya no incluye `anon`. La de `supabase_admin` sí.** El arreglo se aplicó a un rol y no al otro.

Cualquier tabla que cree `supabase_admin` en `public` nace con **ALL para `anon`**. Con RLS activada y sin políticas no se lee nada; pero una tabla nueva a la que se olviden de activarle RLS queda abierta a internet sin que nadie haya escrito un `GRANT`. Es la clase de fallo que no aparece revisando el diff de la migración, porque no está en la migración.

### 🟠 A6 — `authenticated` puede hacer TRUNCATE sobre las 24 tablas

El volcado da `GRANT ALL ON TABLE public.<tabla> TO authenticated` para las 24. `ALL` incluye `TRUNCATE`, `REFERENCES` y `TRIGGER`, y **`TRUNCATE` ignora RLS por completo**.

No es explotable a través de PostgREST, que no expone esa sentencia — por eso es 🟠 y no 🔴. Pero es un permiso que nadie necesita: la aplicación jamás trunca nada. El coste de quitarlo es un `REVOKE`; el coste de dejarlo es que la seguridad de 24 tablas dependa de que ninguna vía futura ejecute SQL como `authenticated`.

---

# 4. Hallazgos medios

### 🟡 M1 — Los pasos del seguimiento tienen dos fuentes, y una de ellas es editable

`CLAUDE.md` y el flujo dicen que `TRACKING_POR_TIPO` (JS) y `tracking_pasos()` (SQL) están duplicados y que *«cambiar uno obliga a cambiar el otro»*. **Ya no es simétrico.** La función SQL dejó de tener los pasos escritos como fuente principal:

```sql
SELECT array_agg(valor ORDER BY orden) INTO v_pasos
  FROM public.catalogos WHERE clave = v_clave AND activo;
IF v_pasos IS NOT NULL AND array_length(v_pasos, 1) >= 2 THEN
  RETURN v_pasos;        -- ← la base manda
END IF;
RETURN CASE p_recurso_tipo … END;   -- ← respaldo escrito a mano
```

El motor lee **datos** (`catalogos`, filas `tracking_camion`, `tracking_custodio`, `tracking_patio`, `tracking_lavado`); la interfaz lee **código**. Editar esas filas —cosa que las políticas `catalogos_write` permiten al superadmin— desincroniza motor e interfaz **sin tocar el repositorio y sin aviso**.

El daño es concreto: `registrar_evidencias` exige estar en el último paso *según SQL*, mientras la pantalla dibuja los pasos *según JS*. La empresa llega a lo que ve como el final y el sistema le niega subir la evidencia.

Atenuante: no hay pantalla que edite `catalogos` (ver M2), así que hoy solo se llega desde el panel de Supabase.

### 🟡 M2 — `CLAUDE.md` afirma sobre `catalogos` algo que el código desmiente

> *«`catalogos` — dropdown values served from the DB instead of hardcoded in JS. Editing a catalog no longer requires a deploy.»*

Verificado: **`grep -rn "'catalogos'" js/` devuelve 0.** Ni un archivo de la plataforma web lee esa tabla. Los desplegables siguen escritos a mano —`prefijos` en `js/admin.js:905`, `TRACKING_POR_TIPO` en `js/tracking.js`— y editar el catálogo no cambia nada en la web.

La tabla no es peso muerto: la lee `tracking_pasos()` desde SQL (M1), y está prevista para los clientes móviles. **Pero la frase describe una capacidad que la web no tiene**, y alguien que la crea editará el catálogo esperando ver el cambio en pantalla.

Regla #4 dice que cuando el documento y el código se contradicen, gana el código y se corrige el documento. Esta línea lleva contradiciéndolo desde antes de la 2ª auditoría, que ya lo señaló como M1.

### 🟡 M3 — El desvío por documentos vencidos se reconoce por el texto del mensaje de error

```ts
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'DOCUMENTOS_VENCIDOS%' THEN
    v_docs_venc := true;
```

El desvío a `pendiente_acuerdo` —una rama central del negocio— depende de que `guard_oferta_update` siga empezando su mensaje con esa palabra. Cambiar la redacción del aviso, traducirlo o anteponerle un prefijo convierte el desvío controlado en un error crudo propagado al usuario.

Lo correcto es un `SQLSTATE` propio: `RAISE EXCEPTION … USING ERRCODE = 'P0002'` y `WHEN SQLSTATE 'P0002' THEN`. El contrato pasa a ser un código, no una frase.

### 🟡 M4 — No hay forma de saber qué migración está aplicada en qué proyecto

`supabase/migrations/` tiene **60 archivos**. En el repositorio no hay ningún registro de cuáles corren en producción y cuáles en `portgo-pruebas`.

El sistema de paridad —que es excelente— responde a *«¿son iguales las dos bases?»*, que no es la misma pregunta que *«¿está aplicado el archivo N?»*. Dos bases pueden ser idénticas y estar las dos sin una migración.

**Esta auditoría se topó con ello.** Los índices de `20260908120000_restricciones_e_indices_pendientes.sql` (`idx_pagos_reservacion`, `idx_mensajes_de_user`, `idx_reservaciones_pagado_por`…) **no están en el volcado de producción del 8-sep a las 16:08**, aunque el archivo se commiteó ese día a las 14:00. Puede ser que se aplicaran después del volcado, o que no se hayan aplicado. **Desde el repositorio no se puede saber, y por eso M5 queda sin veredicto.**

Un archivo `supabase/aplicadas.tsv` con `migración · proyecto · fecha`, escrito por los guiones que ya existen, cierra el hueco.

### 🟡 M5 — Catorce claves foráneas sin índice de apoyo *(en el volcado; ver M4)*

Cruzando las 37 FK contra los 43 índices del volcado, 14 no tienen índice que empiece por su columna:

`calificaciones.cliente_id` · `documentos_fiscales.cancelado_por` · `documentos_fiscales.emitido_por` · `documentos_fiscales.reservacion_id` · `expedientes.incidente_reportado_por` · `mensajes.de_user_id` · `pagos.registrado_por` · `pagos.reservacion_id` · `pedidos.oferta_pendiente_id` · `reservaciones.cancelacion_resuelta_por` · `reservaciones.cancelacion_solicitada_por` · `reservaciones.pagado_por` · `reservaciones_historico.archivado_por` · `solicitudes_arco.atendida_por`

Sin índice, borrar la fila padre obliga a un escaneo completo del hijo para verificar la FK. Seis de estas son justo las que `20260908120000` dice crear.

De estas, **`pedidos.oferta_pendiente_id` es la única que importa hoy**: la recorre el flujo del acuerdo, no solo el borrado.

### 🟡 M6 — 65 `select('*')`, y el RFC de cada empresa a la vista de cualquier usuario

- **65** `select('*')` sobre **127** lecturas totales. Sobre tablas de 48 y 63 columnas, con documentos, notas internas de rechazo y `snapshot_anterior` dentro.
- **127 lecturas y muy pocas cotas.** Las listas que crecen —pedidos, reservaciones— sí pasaron a cursor, y eso está bien hecho; el resto no tiene techo.
- **`empresas_publico` entrega `rfc` y `telefono`** de cada transportista a cualquier usuario autenticado, y `js/catalogo.js:22` los pide por nombre.

Lo último es deliberado y está razonado en la migración: la vista replica *exactamente* lo que las pantallas ya mostraban, y el arreglo consistió en separar la ficha pública del expediente completo, no en cerrar de golpe. Fue la decisión correcta.

Pero conviene separar dos cosas que la migración junta: que la vista **no empeoró** lo que había es cierto; que el RFC **deba** estar ahí es una pregunta que no se hizo. Es un dato fiscal bajo la LFPDPPP, y un cliente que elige transportista no lo necesita para decidir. Ver §6.

### 🟡 M7 — Unas treinta políticas sin cláusula `TO`, que por tanto alcanzan a `anon`

De las 74 políticas, alrededor de 30 se declaran sin `TO authenticated`, así que aplican a **todos** los roles: `ped_update`, `ped_insert_own`, `ped_delete`, las cuatro de `reservaciones`, `of_insert`, `of_update`, las de `mensajes`, las de flota, las de `pagos` y `documentos_fiscales`…

Hoy no es explotable: `anon` no tiene privilegios de tabla desde `20260827160000`. **Pero eso deja la seguridad apoyada en una sola capa donde el diseño quiso tener dos**, y A5 describe con qué facilidad esa capa puede reabrirse sin que nadie lo note. Las políticas nuevas sí llevan el `TO`; son las antiguas las que quedaron a medias.

### 🟡 M8 — Las RPC del flujo anterior al 9 de septiembre siguen vivas y concedidas a `authenticated`

La decisión del **2026-09-09** dice que cuando las dos partes aceptan, la reserva se crea sin superadmin. La web lo implementa con `aceptar_y_cerrar_acuerdo`.

**Pero las funciones del flujo viejo no se retiraron.** Verificado en el volcado de producción:

```sql
GRANT ALL ON FUNCTION public.responder_oferta(uuid, text, numeric, text)  TO authenticated;
GRANT ALL ON FUNCTION public.responder_contraoferta(uuid, text)           TO authenticated;
```

Y su cuerpo, al aceptar, hace lo que hacía antes:

```sql
UPDATE public.ofertas SET estado = 'aceptada' WHERE id = p_oferta_id;
-- luego crea la reservación (cerrarAcuerdo), no este flujo.
UPDATE public.pedidos
   SET estado = 'pendiente_acuerdo', oferta_pendiente_id = p_oferta_id
 WHERE id = v_pedido.id;
```

Deja el pedido en `pendiente_acuerdo` **sin crear reservación**.

**Por qué importa aunque la interfaz web no las llame.** Son endpoints de PostgREST concedidos a cualquier sesión válida: no hace falta la interfaz para invocarlas. Y el estado que producen es indistinguible del legítimo: `pendiente_acuerdo` tiene, según el flujo, un único significado —*la empresa tiene documentos vencidos*—, así que una fila llegada por esta vía aparece en la cola del superadmin marcada como bloqueada, con todos los documentos en regla y sin nada que explique por qué está ahí.

No es un agujero de seguridad: quien las llama solo puede aceptar ofertas que ya podía aceptar. Es **una segunda máquina de estados viva en producción, que contradice la regla de negocio vigente**.

Dos salidas, y la elección depende de cuándo lleguen los clientes móviles:

- **Si el móvil va a usarlas**, hay que actualizar su cuerpo para que cierren el acuerdo como la web, no retirarlas.
- **Si no**, `REVOKE EXECUTE … FROM authenticated` las deja inertes sin borrarlas, que es reversible con una línea.

Lo que no conviene es dejarlas como están: una regla de negocio con dos implementaciones vivas y divergentes es exactamente el problema que la migración del 9-sep vino a resolver.

---

# 5. Hallazgos bajos

| # | Hallazgo | Dónde |
|---|---|---|
| B1 | `SHELL` sin `js/detalle.js`, `js/notificaciones.js` ni `css/detalle.css` | `sw.js` |
| B2 | `Access-Control-Allow-Origin: '*'` en las dos Edge Functions, una de ellas con la clave de servicio | ambas `index.ts` |
| B3 | El `catch` final devuelve `String(err)` al cliente: filtra detalle interno | ambas `index.ts` |
| B4 | Respuestas de error sin `Content-Type: application/json` | `gestionar-usuario` |
| B5 | `GRANT ALL … TO anon` sobre 11 funciones trigger (`guard_*`, `limitar_plantillas`, `sync_datos_pago`), que ningún cliente puede invocar con sentido | volcado |
| B6 | Dos secuencias (`custodios_seq`, `patios_seq`) con `ALL` para `anon` | volcado |

---

# 6. Lo que está bien, y no debe tocarse

Dejarlo escrito importa tanto como la lista de arriba, para que nadie lo «arregle»:

- **RLS en 24 de 24 tablas**, sin una sola excepción.
- **Las 39 funciones `SECURITY DEFINER` fijan `search_path`.** Las 39. Es la defensa contra el secuestro por `search_path`, y no falta ninguna.
- **Los guard triggers.** Siguen siendo la mejor pieza del sistema: son la capa que RLS no puede dar, leen `auth.uid()` y por tanto siguen aplicando dentro de las `SECURITY DEFINER`.
- **`puede_notificar()`** — cinco ramas de relación, la más cara al final, con el comentario que lo explica. Es el modelo que le falta al correo (C1).
- **El sistema de paridad de la Regla #3.** 18 dimensiones, sello con fecha y veredicto, y guiones de prueba que **se niegan a arrancar** si el sello falta, caduca o dice que divergen. Esta auditoría se apoyó en él para dar por buena su fuente de datos. Es infraestructura de calidad superior a la de muchos equipos grandes.
- **`empresas_publico`.** Separar la ficha pública del expediente en vez de cerrar de golpe, con la migración explicando qué se descartó (`GRANT` por columna, `security_invoker`) y por qué, y dejando el `DROP` destructivo comentado para una migración posterior. Así se hace.
- **`reservaciones_sin_solape`**, el `EXCLUDE` con GiST: declarativo, sin condición de carrera. Que no cubra C2 no es un defecto suyo; cubre exactamente lo que dice cubrir.
- **`estadoCobro()` derivado y no almacenado**: no hay tarea diaria que pueda quedarse atrás.
- **El uso de Storage.** `getPublicUrl` aparece 6 veces y las 6 son sobre buckets públicos (`documentos-empresa`, `custodios`, `operadores`). Ni una sobre `unidades` o `registros`. La convención se respeta al 100 %.
- **`localStorage` solo para el tema.** La sesión sigue en `sessionStorage`, como está decidido.
- **Ni XSS ni inyección encontrados.** Se revisaron los 60 manejadores en línea que interpolan datos: todos reciben identificadores generados por el sistema (`crypto.randomUUID()` en `js/admin.js:919`, o UUID de la base), nunca texto de usuario. El escape doble `esc()`/`escJs()` está bien entendido.
- **`FLUJO-OPERATIVO.md`.** Declara sus siete huecos conocidos en vez de esconderlos, dice de dónde sale cada afirmación y advierte de que si el código lo contradice, gana el código. Un documento que enumera sus propias lagunas es más fiable que uno que no tiene ninguna.

---

# 7. Contraste con la 2ª auditoría

Esta auditoría no usó aquella lista como guion, pero cerrarla es parte del encargo. Leído sobre el código de hoy:

**Cerrados y verificados:** C3 (la política de pedidos se cerró), C4 (`20260827190000` desbloquea el borrado), A5 (la máquina de estados bajó a `pg_cron` el 8-sep), A6 (`perfiles` cerrada, sustituida por `empresas_publico`), A11 y A12 (render fuera del bucle, `.in()` en lote), B8 (la campana ya cuenta bien), M2 (reservaciones por cursor), M9 (el trigger redundante se retiró).

**Cerrados a medias:** A2 — la web pasó de 0 a 6 RPC transaccionales, pero quedan cinco caminos orquestados desde el navegador, el camino que sí se movió creó C2, y las funciones que sustituyó siguen vivas (M8). M14 — se añadieron los únicos de `operadores`, falta el de `solicitudes_cuenta.user_id`. B6 — sigue el `GRANT ALL` con TRUNCATE (aquí A6).

**Siguen abiertos, y esta auditoría los reencontró sin buscarlos:** A3 (65 `select('*')`, antes 67), M1 (`catalogos` sin uso en la web → M2 de aquí), M4 (FK sin índice → M5), M5 (las 41 columnas de documento repetidas en 5 tablas), M10 (las cinco tablas de flota).

**Lo que no se pudo volver a comprobar:** todo lo medido en ejecución. **C1 de aquella auditoría —Realtime consumiendo el 84 % del CPU— era su hallazgo dominante, y con el volcado no hay forma de saber si las migraciones de publicación declarativa lo resolvieron.** Es lo primero que habría que medir contra la base viva.

---

# 8. Plan, por orden de lo que duele

**Ahora — se puede hacer hoy, sin esperar a nada:**

1. **C1**, cerrar el relay de correo. Resolver destinatarios en el servidor, o interponer `puede_notificar()`. Es el único hallazgo explotable desde fuera hoy, por cualquiera que se registre.
2. **C2**, `FOR UPDATE` sobre el pedido. Dos palabras. Antes, contar si ya hay pedidos con más de una reservación viva.
3. **A4**, comprobar el resultado de las tres escrituras de `gestionar-usuario` y proteger al último superadmin.

**Después — necesita decisión o verificación previa:**

4. **A5 + A6 + M7**, las tres de permisos, en una sola migración: el `ALTER DEFAULT PRIVILEGES` de `supabase_admin`, el `REVOKE TRUNCATE` y el `TO authenticated` que falta.
5. **A2 + A3**, `ignoreSearch` en el respaldo del Service Worker, fijar la versión del SDK de Supabase y añadir `integrity` a las tres etiquetas CDN.
6. **A1**, extender `actualizarConfirmado()` a las transiciones que importan, empezando por la liberación del recurso.
7. **M8**, decidir qué se hace con `responder_oferta` y `responder_contraoferta`. La decisión puede esperar al arranque del trabajo móvil; **dejarlas concedidas mientras tanto es la opción que no conviene**, porque el estado que producen es indistinguible del legítimo.

**Cuando haya acceso a la base viva:**

8. **Medir Realtime.** Es la única forma de saber si el hallazgo dominante de la 2ª auditoría sigue vigente, y ninguna otra optimización se le acerca en tamaño.
9. **M4**, el libro mayor de migraciones — y de paso resolver M5.

---

# 9. Preguntas

Tres cosas que no se pueden decidir desde el código:

1. **¿El RFC de la empresa tiene que verse en el catálogo?** `empresas_publico` lo entrega a cualquier usuario con sesión. Es dato fiscal, y un cliente que elige transportista no lo necesita para decidir. Quitarlo de la vista es una línea; saber si alguna pantalla lo usa de verdad es cosa del negocio.

2. **¿`mensajes` se queda o se va?** La web no la usa y su RPC `enviar_mensaje` no la llama nadie; el contrato móvil la contempla. Mantenerla cuesta políticas, índices y superficie de auditoría. Dado que el móvil queda para después, la pregunta práctica es si conviene **dejarla inerte ahora** —revocando sus permisos, sin borrar nada— y decidir cuando llegue ese trabajo.

3. **¿Se aplicaron a producción los índices de `20260908120000`?** No están en el volcado de las 16:08 de ese día, con el archivo commiteado a las 14:00. Es lo que deja M5 sin veredicto, y es el ejemplo que justifica M4.

---

*Auditoría realizada el 2026-09-11 sobre el volcado de producción del 2026-09-08 (sello de paridad `identicas`, 18/18 dimensiones) y el código de la rama `dev` en el commit `4c21367`. Alcance: plataforma web; el cliente Android queda fuera por decisión de producto. No se ejecutó ninguna escritura contra ninguna de las dos bases.*
