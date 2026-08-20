# PortGo — Contrato de datos para las apps móviles nativas

**Fase 1 — Análisis.** Documento intermedio previo a escribir código de app.
Fecha: 2026-08-10 · Base analizada: `main` @ 79d7f0a

---

## ⚠️ Actualización 2026-08-20 — el chat ya no es parte del contrato

Todo lo que este documento dice sobre el **chat** quedó obsoleto. La web lo dio de baja
en `6b8beee` y la app Android lo quitó después. Ningún cliente lo usa ya.

Lo sustituyen **avisos fijos**, sin texto libre en ninguna dirección, que escriben en
`notificaciones` y disparan el correo (`enviar-notificacion`, tipo `resolucion`):

| Aviso | De → a | `tipo` de la notificación |
|---|---|---|
| Solicitar documentos de carga | empresa → cliente | `documentos_carga_solicitados` |
| Confirmar lugar y hora | empresa → cliente | `confirmar_lugar_hora` |
| Avisar retraso | empresa → cliente | `aviso_retraso` |
| Actualizar lugar/hora | cliente → empresa + superadmins | `cambio_reportado` |
| Reportar problema (carga ❘ urgente) | cliente → empresa + superadmins | `cambio_reportado` |

"Actualizar lugar/hora" además **escribe** `pedidos.detalles_lugar` / `detalles_hora`: esa
es la diferencia de fondo con el chat, donde lo pactado no cambiaba ningún dato y no había
forma de reconstruirlo después.

La tabla `mensajes`, sus políticas RLS y la RPC `enviar_mensaje` **siguen en la base de
datos**, sin uso desde ningún cliente. No se han borrado.

Pendiente: los cinco avisos están implementados en el cliente (web y Android por separado),
no en una RPC. El conjunto de destinatarios —la empresa **y todos** los superadmins— es
regla de negocio y debería bajar a Postgres, igual que `enviar_oferta`.

---

## 0. Corrección de premisa: no hay Next.js

El encargo asume un backend Next.js con API routes. **No existe.** Verificado:

| Se buscó | Resultado |
|---|---|
| `package.json` | no existe |
| `next.config.*` | no existe |
| `app/`, `pages/`, `api/` | no existen |
| Route handlers / server actions | ninguno |
| `sb.rpc(...)` en todo `js/` | **0 ocurrencias** |

PortGo es un **sitio estático** (HTML + JS clásico en scope global, sin build) servido por
Vercel, que habla **directamente contra Supabase** desde el navegador con la anon key.
Todo lo que existe del lado del servidor es:

1. **PostgREST** (la API REST autogenerada de Supabase sobre las tablas)
2. **GoTrue** (auth email/password)
3. **Realtime** (postgres_changes)
4. **Storage** (6 buckets)
5. **2 Edge Functions** (`gestionar-usuario`, `enviar-notificacion`)
6. **RLS + triggers `BEFORE UPDATE`** — la única frontera de seguridad real

**Consecuencia para el móvil:** no hay una capa de API que consumir. El contrato *es*
PostgREST + GoTrue + Realtime + Storage. Las apps nativas usan `supabase-swift` /
`supabase-kt` contra el mismo proyecto (`xnyqsewaluezkkrlyhxg.supabase.co`), con la misma
anon key, y quedan sujetas exactamente a las mismas RLS que el navegador.

---

## 1. Autenticación

### 1.1 Cómo funciona hoy

- **Único método:** `signInWithPassword({ email, password })`. No hay OAuth, ni magic link,
  ni teléfono/OTP. No hay MFA.
- **Sesión web:** `sessionStorage` (deliberado — cerrar el navegador cierra sesión).
  `persistSession: true` dentro de esa storage. Ver `js/config.js:7`.
- **Perfil:** tras el login se lee `perfiles` por `user_id` para obtener
  `nombre`, `rol`, `aprobacion_cuenta`, `nota_rechazo_cuenta`, `metodo_verificacion`.
  El objeto global `currentUser = {id, email, nombre, rol, metodoVerificacion}`.
- **Roles:** `cliente` | `admin` (empresa/proveedor) | `superadmin`.
- **Gate de cuenta (client-side):** si `aprobacion_cuenta` ∈ {`pendiente`, `rechazada`,
  `suspendida`} → `signOut()` inmediato y mensaje. Fallback: si no hay fila en `perfiles`,
  se consulta `solicitudes_cuenta.estado`. Ver `js/auth.js:47-180`.
- **Password mínimo:** 8 caracteres (validado solo en cliente).
- **Reset:** `resetPasswordForEmail(email, { redirectTo: origin + pathname })` →
  el correo devuelve al sitio con `#type=recovery`, y `checkExistingSession()` abre el
  modal de cambio de contraseña.
- **No hay dependencias de servidor:** ni cookies, ni middleware, ni sesión de servidor.
  Todo es el JWT de GoTrue en el header `Authorization: Bearer`.

### 1.2 Qué se traduce directo a móvil

| Web | iOS (supabase-swift) | Android (supabase-kt) |
|---|---|---|
| `signInWithPassword` | `auth.signIn(email:password:)` | `auth.signInWith(Email)` |
| `sessionStorage` | `Keychain` (`kSecAttrAccessibleAfterFirstUnlock`) | `EncryptedSharedPreferences` (Keystore) |
| refresh automático | `autoRefreshToken` del SDK | `alwaysAutoRefresh` del SDK |
| lectura de `perfiles` | idéntica (PostgREST) | idéntica |

**Decisión pendiente (tuya):** en web la sesión muere al cerrar el navegador. En móvil,
guardar en Keychain/Keystore significa **sesión persistente entre aperturas de la app**.
Es lo que espera un usuario de app nativa, pero es un cambio de postura respecto a la web.
Alternativa: persistir el refresh token y exigir biometría (Face ID / BiometricPrompt) al
reabrir. Recomiendo esta segunda.

### 1.3 Lo que NO se traduce

- **Reset de contraseña** (§G6): `redirectTo` apunta a la URL web. En móvil hay que
  registrar un deep link (`portgo://reset`) en Supabase → Auth → URL Configuration, o usar
  `verifyOtp(type: .recovery)` con el código de 6 dígitos. Ambas requieren tocar la
  configuración de Supabase.
- **Registro** (§G7): `doRegistro()` son ~280 líneas: valida ~25 campos fiscales, sube
  entre 4 y 8 documentos al bucket `registros`, hace `signUp`, `upsert` en `perfiles`,
  `insert` en `solicitudes_cuenta` y `consentimientos`, notifica a superadmins y hace
  `signOut`. Además depende de que `signUp` devuelva sesión (si la confirmación de correo
  está activa, no la devuelve y el flujo se corta pidiendo confirmar el correo).
  **Recomendación: fuera del MVP móvil.** La app abre el registro web en un navegador
  del sistema (SFSafariViewController / Custom Tab).

---

## 2. Dónde vive realmente la lógica de negocio

Esta es la conclusión más importante del análisis.

### 2.1 Sí está en el servidor (confiable, se hereda gratis)

Triggers `SECURITY DEFINER` con `search_path` fijo, que sí protegen desde cualquier cliente:

| Trigger | Tabla | Qué garantiza |
|---|---|---|
| `guard_perfil_self_update` | `perfiles` | nadie se auto-asciende a superadmin ni se auto-aprueba la cuenta |
| `guard_pedido_update` | `pedidos` | `acordado`/`rechazado` solo por superadmin; el admin solo toca pedidos en negociación (+ excepción para reabrir al cancelar) |
| `guard_oferta_update` | `ofertas` | `aceptada` solo por el cliente del pedido (desde `enviada`) o por el admin al responder una `contra_oferta` |
| `guard_fleet_resource_update` | `camiones`/`custodios`/`patios`/`lavados`/`operadores` | nadie auto-aprueba su recurso ni transfiere propiedad |
| `guard_reservacion_update` | `reservaciones` | el cliente no toca tracking/pago/evidencias/precio; solo puede *solicitar* cancelación |
| `guard_expediente_documento` | `expediente_documentos` | solo el cliente sube archivo, solo el transportista dictamina |
| `sync_datos_pago` | `reservaciones` | coherencia de `pagado`/`pagado_en`/`pago_*` |
| `limitar_plantillas` | `plantillas_pedido` | máximo 12 por cliente |
| `check_reservacion_disponibilidad` | `reservaciones` | choque de fechas → excepción `RECURSO_NO_DISPONIBLE` |
| `notificar_*`, `fn_notificar_nuevo_mensaje` | varias | notificaciones automáticas de oferta/respuesta/mensaje/reserva |

### 2.2 NO está en el servidor (el problema)

**Cero `sb.rpc()` en todo el código.** Cada transacción de negocio multi-paso está
orquestada por el navegador, sin atomicidad. Las críticas:

**`cerrarAcuerdo(oferta, pedido)`** — `js/pedidos.js:2090` — 6 escrituras encadenadas:
```
SELECT otras ofertas activas
UPDATE ofertas   → 'rechazada'  (las demás)
INSERT notificaciones (una por admin descartado)
UPDATE pedidos   → 'acordado'
INSERT reservaciones (deriva recurso_tipo del string tipo_camion)
UPDATE camiones/custodios/patios/lavados → 'ocupado'  (si fecha_ini <= hoy)
```

**`cancelarReserva(reservaId, unidad)`** — `js/reservaciones.js:453` — 7 escrituras:
```
UPDATE reservaciones → 'Cancelada'
UPDATE {recurso}     → 'disponible'
UPDATE pedidos       → 'abierto', oferta_pendiente_id = null
UPDATE ofertas       → 'rechazada', permite_reoferta=false  (la aceptada)
UPDATE ofertas       → 'rechazada'                          (enviada/contra_oferta)
INSERT notificaciones (cliente)
INSERT notificaciones (todos los superadmins)
```

Mismo patrón en `aceptarReserva`, `rechazarReserva`, `_enviarOfertaCore`, `crearPedido`,
`subirEvidencias`, `avanzarTracking`, `enviarCalificacion`, `confirmarSolicitudCancelacion`
y todo `aprobaciones.js`.

**Máquina de estados "perezosa" dentro del render** — `js/pedidos.js:239-292`.
Al listar solicitudes, el cliente *escribe*:
- ofertas con `expira_en` vencido → `rechazada`
- pedido `en_negociacion` con todas las ofertas rechazadas → `abierto`
- pedido `en_negociacion` con una oferta `aceptada` → `pendiente_acuerdo`
- pedido `acordado` con `fecha_fin` pasada → `expirado`

Es decir: **si nadie abre la lista en la web, los estados no avanzan.** Una app móvil que
solo lea, no los avanza; una que los replique, duplica la regla en tres lenguajes.

**Notificaciones in-app las inserta el cliente**: 41 call sites de
`sb.from('notificaciones').insert(...)`. Solo algunos tipos los genera un trigger. Si la
app móvil no inserta, **la contraparte no se entera**.

**Correos**: `_notificarEmail()` / `_enviarEmail()` hacen `fetch` fire-and-forget a la Edge
Function con el JWT del usuario. Móvil debe replicar el mismo payload por tipo de plantilla.

**Reglas de negocio solo en cliente**, sin equivalente en servidor:
- recomendación de unidad (`_recomendarCamion`, ~60 líneas de reglas peso/tarimas/categoría)
- validación de que el camión ofertado es del tipo del pedido (`_enviarOfertaCore`)
- gate de qué empresa puede ofertar (`_categoriaTipo` + `_adminCamionTipos`)
- **filtro anti-desintermediación del chat** (`_contieneTelefono`, `js/chat.js:149`) —
  bloquea compartir teléfonos. Una app nativa que no lo implemente lo salta.
- plazo de 5 días para subir evidencias, máximo 5 archivos
- `recurso_tipo` derivado por prefijo del string `tipo_camion`

### 2.3 El conflicto con tu restricción

Pediste: *"No repliques lógica de negocio del backend: las apps son clientes"*.
El problema es que **esa lógica no está en el backend**. Solo hay dos caminos:

- **(A) Duplicarla** en Swift y Kotlin → 3 copias de `cerrarAcuerdo`, `cancelarReserva`,
  la máquina de estados perezosa y las 41 inserciones de notificación. Divergen en semanas.
  Es exactamente lo que pediste evitar.
- **(B) Bajarla a Postgres** como funciones RPC `SECURITY DEFINER` (o Edge Functions),
  y que **los tres clientes** — web incluida — las llamen. Una sola fuente de verdad,
  atómica, y la web queda mejor de lo que está.

**Recomiendo (B), acotado a los flujos del MVP.** Es un cambio de backend, así que —
según tu propia restricción — lo señalo antes de tocar nada y espero tu visto bueno.

RPCs mínimas propuestas (nombres tentativos):

| RPC | Reemplaza | Quién la llama |
|---|---|---|
| `crear_pedido(payload jsonb)` | `crearPedido` + notif superadmins | cliente |
| `enviar_oferta(pedido_id, camion_id, operador_id, precio, mensaje)` | `_enviarOfertaCore` + `pedidos→en_negociacion` | empresa |
| `responder_oferta(oferta_id, accion, contra_precio)` | `responderOferta` / `enviarContraoferta` | cliente |
| `aceptar_oferta(oferta_id)` | acepta + `pedidos→pendiente_acuerdo` | cliente |
| `cancelar_reservacion(reserva_id, motivo)` | `cancelarReserva` completa | empresa |
| `solicitar_cierre(reserva_id, paths[], actor)` | `subirEvidencias` (parte transaccional) | ambos |
| `avanzar_tracking(reserva_id)` | `avanzarTracking` + notif | empresa |
| `sincronizar_estados_pedidos()` | la máquina perezosa del render | cron / cualquiera |

Sin (B), el alcance realista del MVP móvil se reduce a **consulta + chat + tracking de
lectura + notificaciones**, sin acciones que muevan estados.

---

## 3. Contrato de datos

Todo vía PostgREST. Base: `https://xnyqsewaluezkkrlyhxg.supabase.co/rest/v1`.
Headers: `apikey: <anon>`, `Authorization: Bearer <access_token>`.
Los SDKs oficiales lo envuelven; no se arma HTTP a mano.

### 3.1 Matriz tabla × operación × rol

Leyenda: **C**=cliente, **E**=empresa(`admin`), **S**=superadmin. (r)=lectura, (w)=escritura.

| Tabla | C | E | S | Notas de RLS / triggers |
|---|---|---|---|---|
| `perfiles` | r + w propio | r + w propio | rw todo | No legible por `anon`. Trigger bloquea `rol`, `aprobacion_cuenta`, `verificado`, `metodo_verificacion` |
| `pedidos` | rw propios | r abiertos/en_negociación + donde ofertó; w limitado | rw todo | `ped_select` filtra por estado/participación; `guard_pedido_update` limita transiciones |
| `ofertas` | r de sus pedidos, w (aceptar/contraofertar) | rw propias | rw todo | `guard_oferta_update` controla `→aceptada` |
| `reservaciones` | r propias (`cliente_email`/`cliente_user_id`), w limitada | rw donde es `propietario_id` | rw todo | `guard_reservacion_update`; `check_reservacion_disponibilidad` en INSERT |
| `reservaciones_historico` | — | — | rw | archivado |
| `mensajes` | rw si está en `participantes` | idem | r todo (supervisión) | `msg_select_superadmin` |
| `notificaciones` | r propias, w `leido` | idem | idem | INSERT restringido por relación |
| `camiones` `custodios` `patios` `lavados` | r aprobados | rw propios | rw todo | `guard_fleet_resource_update` |
| `operadores` | — | rw propios | rw todo | idem |
| `calificaciones` | w (califica) + r | r propias | rw | 1–5 + comentario |
| `solicitudes_cuenta` | r propia | r propia | rw | flujo de alta |
| `plantillas_pedido` | rw propias | — | — | máx. 12 (trigger) |
| `expedientes` | rw si participa en la reservación | idem | rw | |
| `expediente_documentos` | sube archivo | dictamina | rw | `guard_expediente_documento` |
| `documentos_catalogo` | r | r | rw | catálogo editable |
| `consentimientos` | insert + r propios | idem | r todo | sin UPDATE/DELETE para nadie |
| `solicitudes_arco` | insert + r propias | idem | rw | solo SA resuelve |
| `pagos`, `documentos_fiscales` | — | — | rw | fuera de MVP |

### 3.2 Shapes clave

**`pedidos`** (~60 columnas). Núcleo que el móvil necesita leer/escribir:
```
id uuid · cliente_id uuid · cliente_nombre text · cliente_email text
estado text  -- pendiente_revision|abierto|en_negociacion|pendiente_acuerdo
             --  |acordado|finalizado|expirado|cancelado|rechazado
tipo_camion text · tipo_camion_sugerido text · categoria_carga text
origen text · destino text · origen_lat/lng numeric · destino_lat/lng numeric
fecha_arribo_puerto date · fecha_ini date · fecha_fin date
precio_cliente numeric · plazo_pago text · descripcion text
peso_carga numeric · num_tarimas smallint · volumen_m3 numeric
refrigerado bool · temp_min/temp_max numeric
num_contenedores smallint · contenedor_1_tipo/peso · contenedor_2_tipo/peso
largo_m/ancho_m/alto_m numeric · hazmat_clase/hazmat_un text
carga_peligrosa/temp_controlada/requiere_seguro/requiere_factura/entra_a_puerto bool
oferta_pendiente_id uuid · rechazo_nota text · created_at timestamptz
```

**`ofertas`**
```
id uuid · pedido_id uuid · admin_id uuid · admin_nombre text
camion_id text · operador_id text · operador_nombre text
precio_oferta numeric · contra_precio numeric · ronda int(1|2)
estado text -- enviada|contra_oferta|aceptada|rechazada
permite_reoferta bool · expira_en timestamptz · mensaje text · created_at
```

**`reservaciones`**
```
id uuid · pedido_id uuid · propietario_id uuid · cliente_user_id uuid
cliente text · cliente_email text · unidad text · recurso_tipo text(camion|custodio|patio|lavado)
fecha_ini/fecha_fin date · precio_acordado numeric · plazo_pago text
estado text -- Pendiente|Activa|PorAprobar|CancelacionSolicitada|Completada|Cancelada|Rechazada
tracking_estado text  -- depende de recurso_tipo, ver §3.4
evidencias text[] (empresa) · evidencias_cliente text[]  -- PATHS, no URLs
finalizacion_solicitada_por/nota/aprobada_por/aprobada_en
cancelacion_solicitada_en/por/motivo/detalle/tracking_estado/resuelta_en/por/nota_resolucion
pagado bool · pagado_en · pagado_por · pago_metodo · pago_referencia
fecha_vencimiento_pago date · completado_en · calificado bool
```

**`mensajes`**
```
id uuid · de_user_id uuid · de_nombre text · texto text
pedido_id uuid | reserva_id uuid  (uno de los dos)
participantes uuid[]  -- RLS verifica pertenencia; filtrar con .contains()
leido bool · created_at
```

**`notificaciones`**: `id, user_id, tipo, titulo, mensaje, leido, meta jsonb, created_at`.
Tipos vistos: `nueva_oferta`, `respuesta_oferta`, `respuesta_contra_oferta`,
`oferta_no_seleccionada`, `nuevo_mensaje` (con `meta.ctx_tipo`/`ctx_id`/`de_user_id`),
`reserva_aceptada`, `reserva_cancelada`, `tracking_actualizado`, `acuerdo_aprobado`,
`acuerdo_rechazado`, `revision_solicitud`, `revision_acuerdo`, `revision_finalizacion`,
`nueva_cuenta_pendiente`, `nueva_unidad_pendiente`, `nuevo_recurso_pendiente`,
`recurso_aprobado`, `recurso_rechazado`, `solicitud_rechazada`, `pedido_cancelado`,
`negociacion_cerrada`, `finalizacion_solicitada`, `finalizacion_rechazada`,
`servicio_completado`, `reserva_pendiente`.

### 3.3 Paginación y orden

| Vista | Consulta |
|---|---|
| Solicitudes | `.order('created_at', desc).range(offset, offset+N-1)` — único endpoint paginado |
| Ofertas | `.in('pedido_id', [ids])` — sin límite, ligado a la página de pedidos |
| Reservaciones | `.order('created_at', desc)` — **sin paginar** |
| Notificaciones | `.order('created_at', desc).limit(20)` |
| Chat | `.eq(reserva_id|pedido_id).contains('participantes', [...]).order('created_at', asc)` — sin límite |

Para móvil: paginar reservaciones y chat (keyset por `created_at`). Es cambio de cliente,
no de backend.

### 3.4 Máquinas de estado

**`pedidos.estado`**
```
pendiente_revision ──(SA aprueba)──> abierto ──(1ª oferta)──> en_negociacion
   │                                    ▲                          │
   │(SA rechaza)                        │(todas rechazadas)        │(cliente acepta)
   ▼                                    └──────────────────────────┤
rechazado                                                          ▼
                                                          pendiente_acuerdo
                                                                   │(SA aprueba)
                                    abierto <──(cancelar reserva)──┤
                                                                   ▼
                                                              acordado
                                                          ┌────────┴────────┐
                                                   finalizado           expirado
```
`cancelado` es alcanzable desde casi cualquier punto por el cliente o el SA.

**`reservaciones.estado`**
```
Activa ──(cualquiera sube evidencia y solicita cierre)──> PorAprobar ──(SA)──> Completada
  │                                                            └──(SA rechaza)──> Activa
  ├──(cliente solicita)──> CancelacionSolicitada ──(SA)──> Cancelada | Activa
  └──(empresa cancela)──> Cancelada
```
`Pendiente` y `Rechazada` pertenecen al flujo de reserva directa (`js/modal.js`), no al de
pedido→oferta→acuerdo.

**`tracking_estado`** — 5 pasos, distintos por `recurso_tipo` (`js/tracking.js:3-32`):
- camion: `Confirmado → En camino → En carga → En tránsito → Entregado`
- custodio: `Confirmado → Asignado → En ruta → En servicio → Finalizado`
- patio: `Confirmado → Listo → Recibido → En almacenaje → Liberado`
- lavado: `Confirmado → Recibido → En lavado → Control → Listo`

> Nota: `CLAUDE.md` documenta la secuencia de camión como
> `Confirmado→En camino→En puerto→Cargando→En tránsito→Entregado` (6 pasos). El código
> vigente tiene 5 y usa `En carga`. Manda el código.

### 3.5 Storage

| Bucket | Público | Regla de path | Acceso |
|---|---|---|---|
| `unidades` | ❌ | 1er segmento = `auth.uid()` | `createSignedUrl(path, 3600)` |
| `registros` | ❌ | `{userId}/{doc}.{ext}` | signed URL |
| `documentos-viaje` | ❌ | `{expediente_id}/{archivo}` | signed URL; RLS por `participa_en_expediente()` |
| `operadores` | ✅ | libre | `getPublicUrl` |
| `custodios` | ✅ | libre | `getPublicUrl` |
| `documentos-empresa` | ✅ | libre | `getPublicUrl` |

Evidencias de servicio: `{userId}/evidencias/{reservaId}/{timestamp}_{rand}.{ext}` en
`unidades`. **En la BD se guardan paths, nunca URLs** — se firman al mostrar. Hay entradas
heredadas que sí son URLs completas (`startsWith('http')`); el móvil debe contemplar ambas.
Límites del cliente web: 10 MB por archivo, tipos `image/jpeg|png|webp` y `application/pdf`.

### 3.6 Realtime

Canales que arma la web (`js/main.js:27-91`):

| Canal | Filtro | Uso |
|---|---|---|
| `notif-{userId}` | `notificaciones` INSERT, `user_id=eq.{uid}` | campana |
| `portgo-changes` | `*` sobre `camiones`, `custodios`, `patios`, `lavados`, `reservaciones`, `pedidos`, `ofertas`; INSERT sobre `mensajes`, `notificaciones` | re-render de la vista activa |
| `chat-res-{id}` / `chat-ped-{id}-{parts}` | `mensajes` INSERT filtrado | chat abierto |

Para móvil: **no replicar `portgo-changes` tal cual** — suscribirse a 7 tablas completas
consume batería y datos. Suscribir solo `notif-{userId}` y el canal del chat abierto;
el resto, refresco al entrar a la pantalla + pull-to-refresh.

### 3.7 Edge Functions

**`gestionar-usuario`** — `POST {FN_URL}` · `Authorization: Bearer <jwt>`
```jsonc
// request
{ "accion": "crear"|"editar"|"eliminar"|"listar",
  "nombre": "…", "email": "…", "password": "…", "rol": "…", "user_id": "uuid" }
// response
{ "ok": true }                    // crear/editar/eliminar
{ "lista": [ { user_id, nombre, rol, aprobacion_cuenta, created_at, email } ] }
// errores: 401 {"error":"No autenticado"|"Token inválido"}
//          403 {"error":"Acceso denegado"}   ← el caller no es superadmin
//          400 {"error":"<mensaje>"} · 500 {"error":"<string>"}
```
Solo superadmin. **Fuera del MVP móvil.**

**`enviar-notificacion`** — `POST {FN_NOTIFICACION}` · `Bearer <jwt>` · fire-and-forget
```jsonc
{ "tipo": "nueva_solicitud"|"solicitudes_lote"|"revision_solicitud"|"resolucion"
        |"acuerdo"|"nueva_reserva"|"solicitud_recibida"|"reserva_aceptada"
        |"reserva_rechazada"|"nueva_oferta"|"acuerdo_aprobado",
  /* campos según plantilla */ }
// response: { "ok": true, "sent": <n> } | { "ok": true, "skipped": true }
// 401 sin sesión válida · 403 si un no-superadmin pide un blast masivo
```
Requiere sesión válida. `nueva_solicitud` y `solicitudes_lote` exigen superadmin.
Respeta `perfiles.notif_email` para los tipos silenciables.

### 3.8 Errores

PostgREST devuelve `{ code, message, details, hint }`. Los que importan:

| Situación | Forma |
|---|---|
| RLS bloquea SELECT | **200 con array vacío** (no es error) — la causa nº1 de "no aparece nada" |
| RLS bloquea INSERT/UPDATE | `42501` — *new row violates row-level security policy* |
| Guard trigger | `P0001` + `message` en español, apto para mostrar al usuario |
| Choque de fechas | `P0001` con `RECURSO_NO_DISPONIBLE` — sentinela, requiere mensaje propio |
| CHECK constraint | `23514` |
| FK | `23503` |

**Regla del proyecto que el móvil debe honrar:** revisar `error` en *toda* llamada mutante y
mostrarlo. Los fallos silenciosos de RLS son el bug más caro de este código.

---

## 4. Qué va por SDK directo y qué necesitaría otra vía

| Operación | Vía | Comentario |
|---|---|---|
| Login / logout / refresh | SDK GoTrue | directo |
| Leer pedidos/ofertas/reservaciones/chat/notificaciones | SDK PostgREST | directo, RLS cubre |
| Marcar notificación leída, enviar mensaje | SDK PostgREST | directo |
| Subir evidencias / documentos de expediente | SDK Storage | directo |
| Avanzar tracking | SDK, **+ INSERT de notificación** | hoy son 2 escrituras del cliente |
| Enviar oferta | SDK ×2 + email | candidato a RPC |
| Aceptar oferta / contraofertar | SDK ×2–3 + notif | candidato a RPC |
| Cancelar reservación | SDK ×7 | **debe ser RPC** |
| Cerrar acuerdo (SA) | SDK ×6 | fuera del MVP |
| Reset de contraseña | GoTrue + deep link | requiere config en Supabase |
| Registro de cuenta | web | fuera del MVP |
| Gestión de usuarios | Edge Function | fuera del MVP |
| Push notifications | **no existe** | ver G9 |

---

## 5. Gaps y riesgos

Ordenados por lo que bloquea.

### 🔴 G1 — No existe el backend Next.js que asume el encargo
Ya desarrollado en §0. Cambia la naturaleza del trabajo: no es "consumir una API", es
"ser un segundo cliente de Supabase con las mismas RLS".

### 🔴 G2 — La lógica de negocio vive en el navegador, no en el backend
§2.3. **Bloquea la instrucción "no repliques lógica de negocio".** Requiere tu decisión
entre duplicar (A) o bajar a RPCs (B, recomendada, implica tocar backend).

### 🔴 G3 — El esquema base y las políticas RLS base NO están en el repo
`supabase/migrations/` tiene 16 migraciones **incrementales**. No hay línea base: los
`CREATE TABLE` de `pedidos`, `ofertas`, `reservaciones`, `perfiles`, `camiones`… y la
mayoría de las políticas (`ped_select` es la excepción) se crearon en el dashboard.
Este documento reconstruye el contrato desde el código cliente + migraciones, y **hay partes
que no puedo verificar sin acceso a la base** (tipos exactos, nullability, defaults, la
lista completa de políticas). En esta sesión no hay herramientas MCP de Supabase.
**Acción previa a la Fase 2:** correr `supabase db pull` (o `db dump --schema public`) y
commitear la línea base. Sin eso, los modelos de Swift/Kotlin se escriben adivinando
nullability, que es exactamente donde ambos lenguajes fallan en runtime.

### 🟠 G4 — `aprobacion_cuenta` parece no estar aplicado en RLS
El bloqueo de cuentas `pendiente`/`rechazada`/`suspendida` es **solo client-side**
(`js/auth.js:63-78`, `132-146`). Ninguna migración referencia `aprobacion_cuenta` dentro
de una política. Si las políticas base tampoco lo hacen, **un usuario suspendido conserva un
JWT válido y acceso completo por API** — hoy basta con `curl`; con apps nativas publicadas,
la superficie crece. No puedo confirmarlo sin leer las políticas base (G3).
**Acción:** verificar y, si aplica, añadir la condición a las políticas o a `is_superadmin()`-style helper.

### 🟠 G5 — Regresión en `guard_reservacion_update`
La migración `20260729140000_cancelacion_solicitada_cliente.sql` hace
`CREATE OR REPLACE` de la función y **pierde las protecciones que había añadido**
`20260729090000_finalizacion_reserva_aprobada.sql` para la rama del propietario:
ya no se bloquea `estado → 'Completada'` ni la escritura sobre `evidencias_cliente`.
Es decir, hoy la empresa puede **cerrar el servicio saltándose la aprobación del superadmin**
y sobrescribir la evidencia del cliente, por API directa. En la web el botón no existe;
en una app nativa (o con `curl`) sí. Verificar contra producción y corregir antes de publicar
apps que amplíen el acceso.

### 🟠 G6 — Deep link para reset de contraseña
`redirectTo` apunta a la URL web. Para móvil hay que registrar el esquema
(`portgo://…`) en Supabase → Auth → URL Configuration, o migrar a `verifyOtp`.
**Es un cambio de configuración del backend** → lo señalo, no lo hago sin tu OK.

### 🟡 G7 — Registro fuera del MVP
§1.3. Recomiendo abrir el registro web en navegador del sistema.

### 🟡 G8 — No hay push notifications
Hoy: Realtime + campana in-app + correo SMTP (Gmail) desde la Edge Function. Un usuario de
app nativa espera APNs/FCM. Supabase no manda push por sí solo: haría falta tabla de
device tokens + Edge Function con credenciales de APNs/FCM. **Decisión de alcance.**
Mitigación MVP: Realtime con la app en foreground + badge al reabrir.

### 🟡 G9 — Máquina de estados perezosa
§2.2. Si el móvil no la replica, ve estados obsoletos; si la replica, la duplica.
La RPC `sincronizar_estados_pedidos()` + un cron de Supabase lo resuelve de raíz.

### 🟡 G10 — Notificaciones in-app las inserta el cliente
Si la app móvil ejecuta una acción sin insertar la notificación correspondiente,
la contraparte no se entera. Se resuelve solo si se adopta (B).

### 🟡 G11 — Reglas de negocio que se saltan si no se implementan
Filtro anti-teléfono del chat, validación tipo de camión vs. pedido, gate de quién puede
ofertar, plazo de 5 días / máx. 5 evidencias. Ninguna tiene respaldo en servidor.

### 🟢 G12 — Fechas y zona horaria
`fecha_ini`/`fecha_fin`/`fecha_arribo_puerto` son `date`, y el cliente los compara como
strings `YYYY-MM-DD` contra `today()`.

Corrección respecto a la primera versión de este documento: `today()` en `js/utils.js:23`
hace `new Date().toISOString().split('T')[0]`, o sea **UTC, no hora local**. Entre las
18:00 y la medianoche de México la web ya cree que es el día siguiente, y por eso marca
una unidad como ocupada unas horas antes de tiempo.

La app Android usa la fecha local de `America/Mexico_City` (`Fmt.hoy()`), que es la
correcta para un campo `date` que el usuario elige en un calendario. Queda como
divergencia deliberada y documentada; lo que conviene es corregir el lado web para que
ambos coincidan.

### 🟢 G13 — Realtime costoso en móvil
§3.6. Mitigado con suscripciones acotadas.

### 🟢 G14 — Consulta de reservaciones del cliente por `cliente_email`
`renderReserv()` filtra por `cliente_email` (no por `cliente_user_id`) en la rama cliente.
Si el usuario cambia de correo, pierde de vista sus reservaciones. El móvil debería filtrar
por `cliente_user_id` — pero conviene alinear ambos clientes y revisar que la RLS lo permita.

### 🟢 G15 — Sin toolchain móvil en esta máquina
No hay JDK, Gradle, Android SDK ni Swift instalados (Windows 10). Puedo escribir el código
completo de ambas apps, pero **no puedo compilarlo ni ejecutarlo aquí**. Android es
verificable en esta máquina instalando Android Studio; **iOS requiere macOS + Xcode
obligatoriamente**, así que ese código se entregará sin ejecución previa.

---

## 6. Alcance propuesto del MVP

**Roles en la app:** `cliente` y `admin` (empresa). **`superadmin` fuera** — su panel
(aprobaciones, reportes, gestión de usuarios, vigencias) es una consola de escritorio con
tablas densas; portarla a móvil no aporta y multiplica el trabajo por tres.

| Pantalla | Cliente | Empresa |
|---|---|---|
| Login (+ biometría) | ✓ | ✓ |
| Home / resumen | ✓ | ✓ |
| Solicitudes: lista + detalle | propias | disponibles + donde ofertó |
| Crear solicitud | ✓ (formulario por categoría de carga) | — |
| Ofertas: ver / aceptar / contraofertar | ✓ | enviar / responder contraoferta |
| Reservaciones: lista + detalle | lectura | operar |
| Tracking | ver | avanzar |
| Evidencias (subir/ver con signed URL) | ✓ | ✓ |
| Expedientes documentales | subir | dictaminar |
| Chat por reserva/solicitud (realtime) | ✓ | ✓ |
| Notificaciones (campana) | ✓ | ✓ |
| Flota (camiones/operadores) | — | ✓ |
| Perfil + preferencia de correo | ✓ | ✓ |
| Registro | link a web | link a web |

---

## 7. Recomendación de plataforma inicial

**Android (Kotlin + Jetpack Compose) primero.** Razones, todas salidas del análisis:

1. **Verificabilidad (G15).** Esta máquina es Windows. Android se puede compilar y correr
   aquí instalando Android Studio; iOS es imposible sin macOS. Empezar por lo que se puede
   probar contra el Supabase real reduce el riesgo de entregar código no ejecutado.
2. **Perfil de usuario.** El lado empresa —despachadores, dueños de flota, operadores en
   patio y puerto— es abrumadoramente Android en México. Es también el rol con más
   interacción diaria (ofertar, tracking, evidencias).
3. **`supabase-kt` cubre más superficie.** Auth + PostgREST + Realtime + Storage con
   `kotlinx.serialization`, y Realtime en Kotlin es más maduro que en `supabase-swift`.
4. **La app iOS se beneficia del segundo turno.** El contrato de datos y los modelos ya
   estarán validados contra la base real; Swift se vuelve una traducción de algo probado en
   lugar de un segundo descubrimiento.

Arquitectura para ambas: MVVM + capa `Repository` que aísla el SDK de Supabase, modelos
compartidos generados desde el esquema (una vez resuelto G3), y estado de UI unidireccional
(`StateFlow` / `@Observable`). Material 3 en Android, HIG en iOS.

---

## 8. Decisiones tomadas (Fase 1 cerrada)

| Punto | Decisión |
|---|---|
| **G2 — lógica de negocio** | **Opción B**: baja a RPCs de Postgres. Migración `20260810120000_rpc_transacciones.sql` |
| **G3 — esquema base** | El usuario corre `supabase db pull`. Mientras tanto, modelos con nullability conservadora |
| **G4 — `aprobacion_cuenta` sin RLS** | **Fuera de alcance por ahora.** La app replica el gate en el cliente, igual que la web |
| **G5 — regresión de `guard_reservacion_update`** | **Fuera de alcance por ahora.** Queda documentado |
| **G6 — deep link** | Autorizado en el diseño: la app usa `portgo://auth`. Falta darlo de alta en Supabase Auth |
| **Alcance de roles** | Cliente + empresa. Superadmin fuera (la app lo manda a la web) |
| **Sesión** | Persistente en Keystore + desbloqueo biométrico al reabrir |
| **G8 — push** | **Fuera del MVP.** Realtime en primer plano + campana |
| **G9 — máquina de estados perezosa** | Migración `20260810130000_..._OPCIONAL.sql`, **opcional**: requiere una excepción en `guard_pedido_update` |
| **Plataforma inicial** | Android (ver §7). iOS entra después, sobre el contrato ya validado |

### RPCs creadas

`enviar_oferta` · `responder_oferta` · `responder_contraoferta` · `cancelar_reservacion` ·
`solicitar_cancelacion` · `registrar_evidencias` · `avanzar_tracking` · `abrir_expediente` ·
`calificar_servicio` · `enviar_mensaje` · `recomendar_unidad`
(+ `sincronizar_estados_pedidos` en la migración opcional).

Publicar una solicitud queda como INSERT directo a propósito: es una sola escritura que
RLS ya cubre, y envolverla obligaría a versionar las ~60 columnas de `pedidos` dentro de
una función de Postgres cada vez que la web agrega un campo.

### Pendiente de aplicar en el backend

1. Aplicar `20260810120000_rpc_transacciones.sql` — **sin esto la app lee pero no opera**.
2. Agregar `portgo://auth` a Supabase → Authentication → URL Configuration → Redirect URLs.
3. Decidir sobre `20260810130000_..._OPCIONAL.sql` (lee su encabezado).
4. Correr `supabase db pull` y commitear la línea base del esquema.

> La web **no** se migró a las RPCs en este paso, a propósito: cambiar los flujos de
> producción mientras se construye la app arriesga dos cosas a la vez. Es el siguiente
> trabajo natural, y deja una sola fuente de verdad para los tres clientes.
