# CLAUDE.md

This file provides guidance to Claude Code when working with the **PortGo** codebase.

---

## 🛑 RULE #1 — ASK BEFORE DELETING ANYTHING

**This rule overrides every permission setting, with no exception.** Even with `bypassPermissions` / auto-accept enabled, **never delete anything without asking the user first and getting an explicit yes.** A permission mode that suppresses prompts does **not** grant deletion authority: it removes the tool's confirmation, not this project's requirement.

Before any deletion, stop and state these three things:

1. **WHAT** — the exact target: full paths, file names, table and row identifiers, branch names, how many items. Never a vague summary like "some old files".
2. **WHAT IT IS FOR** — what that thing does or holds, and what depends on it. If you don't know, **find out before asking**, not after deleting.
3. **WHY** — the concrete reason it should be deleted, and what breaks or is lost if the deletion is wrong.

Then **wait for an explicit yes**. Silence, an unrelated reply, or a general "adelante" about another topic is not authorization.

This covers every form of deletion, including:

- Files and directories (`Remove-Item`, `rm`, `git clean`)
- Git history and refs — `git reset --hard`, force-push, deleting branches or tags, `git stash drop`
- Database — `DROP` / `TRUNCATE` / `DELETE`, dropping columns, policies, functions or triggers. **There is no staging: every deletion hits production immediately.**
- Supabase Storage objects, in any bucket
- Auth users — `auth.admin.deleteUser`, the `eliminar` action of `gestionar-usuario`
- Edge Functions and migrations
- Overwriting an existing file with `Write` when doing so destroys content

**Authorization is per-deletion and never carries over.** Approval to delete one thing does not extend to the next, however similar it looks.

When in doubt, do not delete — ask.

---

## Project Overview

**PortGo** is a PWA logistics platform for port transport services built as a fully client-side app with Supabase as the backend (PostgreSQL + Auth + Realtime + Storage).

**Business flow:** Client posts a transport request (`pedido`) → superadmin reviews and publishes it → companies (`admin`) bid (`ofertas`) → client accepts a bid → superadmin approves the agreement → a `reservación` is created and tracked to completion → client rates the service.

**Stack:** Vanilla JS (plain `<script>` tags, global scope, loaded in order), plain CSS, Supabase JS SDK v2 from CDN, no build tooling, no package manager, no tests.

---

## ⚡ Deployment Checklist — DO THIS EVERY TIME

The app is served from **Vercel** at **`https://portgo-six.vercel.app`** (repo `papelezz-cpu/Flotaapp`, root served as a static site — no build step). The app is `/app.html`; the landing is `/`. **`git push` to `main` auto-deploys** (usually live within ~30s). After ANY change:

1. **Bump the `?v=` param in `app.html`** for every JS/CSS file you changed (e.g. `js/pedidos.js?v=36` → `?v=37`). `app.html` is the application; `index.html` is the static marketing landing. If you skip this, browsers serve the old cached file and the user reports "it's not fixed".
2. **Bump the cache version in `sw.js`**: `const CACHE = 'portgo-vXX'` → `vXX+1`. On Vercel the Service Worker actually registers (the site is at the domain root), so the cache bump genuinely matters now — unlike on the old GitHub Pages subpath where `/sw.js` 404'd.
3. **Commit AND `git push`** — Vercel deploys on push to `main`; a local commit alone deploys nothing.
4. Schema changes: `mcp__supabase__apply_migration` (or run the SQL in the Supabase dashboard). Edge Functions: `mcp__supabase__deploy_edge_function`. Both hit **production immediately** — there is no staging.
5. Tell the user to hard-refresh (**Ctrl+Shift+R**) if they're testing right away.

`vercel.json` sets the static config: `cleanUrls:false` (keeps the `.html` URLs), no-cache for `sw.js`, revalidate for HTML/manifest.

> ⚠️ **Auth redirect URLs:** the Vercel domain must be in Supabase → Authentication → URL Configuration (Site URL + Redirect URLs), or password-reset links won't redirect. Add any new domain (e.g. a custom domain) there too.

To run locally: `npx serve .` (connects to the live Supabase project; credentials in `js/config.js`).

> ⚠️ Never commit secrets. `js/config.js` contains the anon key (safe to expose). The service role key lives only in Edge Function secrets, never in client code.

---

## File Structure

```
/
├── index.html              # Static marketing landing (self-contained: inline CSS, Lucide CDN). CTAs → app.html
├── app.html                # The application — all views, modals, script/link tags (formerly index.html)
├── sw.js                   # Service worker (bump CACHE version on every deploy)
├── privacidad.html         # Aviso de privacidad (static)
├── terminos.html           # Términos y condiciones (static)
├── css/                    # base → layout → components → login → detalle → theme (load order matters)
├── js/                     # Classic scripts, global scope, order defined in app.html (30 files)
├── docs/CONTRATO-MOVIL.md  # Backend contract for the native iOS/Android clients
├── android/                # Native Android client (separate from the PWA)
└── supabase/
    ├── functions/
    │   ├── gestionar-usuario/   # Privileged user CRUD (superadmin only, service role key)
    │   └── enviar-notificacion/ # Email notifications
    ├── migrations/         # 25 SQL migrations — the source of truth for schema, RLS,
    │                       #   guard triggers and the business RPCs
    └── aplicar-migraciones.sh   # Applies migrations via psql against PRODUCTION (asks for
                            #   the password interactively; there is no staging)
```

### JS Module Responsibilities

| File | Role |
|---|---|
| `js/config.js` | Creates Supabase client → exports globals `sb`, `FN_URL`, `FN_NOTIFICACION`, `SOPORTE_EMAIL` |
| `js/utils.js` | `esc()` HTML escape, `escJs()` for onclick strings, `fmtFecha()`, `formatPrecio()`, `showConfirm()`, skeletons, geo-autocomplete |
| `js/auth.js` | Login / registro (cliente & empresa with document upload) / logout / password reset; sets `currentUser = {id, email, nombre, rol}` |
| `js/main.js` | Bootstrap: session check, realtime subscriptions, `showToast()`, SW registration |
| `js/views.js` | Manual SPA router — `showView(viewId, btn)` toggles `<section id="view-*">` |
| `js/pedidos.js` | Order lifecycle: create, list, bid (`openHacerOferta`), counter-offers, accept, `cerrarAcuerdo` |
| `js/aprobaciones.js` | Superadmin approval panel: accounts, resources, pedidos, agreements, company docs |
| `js/reservaciones.js` | Reservations table, cancel/complete, evidencias (signed URLs), ratings |
| `js/admin.js` | Company dashboard: fleet CRUD, company documents |
| `js/usuarios.js` | Superadmin user management (calls `gestionar-usuario` Edge Function via `FN_URL`) |
| `js/operadores.js` | Driver registration with approval workflow |
| `js/camiones.js` / `js/recursos.js` / `js/catalogo.js` | Truck/resource catalogs with filters |
| `js/chat.js` | Per-pedido/per-reserva realtime chat (`mensajes` table, `participantes` array). `_contieneTelefono()` blocks phone numbers (anti-disintermediation) — **client-side only**, the server-side equivalent lives in the `enviar_mensaje` RPC |
| `js/notificaciones.js` | Notification bell panel |
| `js/tracking.js` | Shipment tracking state machine. `TRACKING_POR_TIPO` holds a **different 5-step sequence per `recurso_tipo`** — mirrored by `tracking_pasos()` in SQL; change one, change both |
| `js/detalle.js` | Order detail modal |
| `js/modal.js` | Direct reservation booking modal |
| `js/reportes.js` | Superadmin KPI reports |
| `js/vigencias.js` | Document expiry monitoring |
| `js/theme.js` | Dark/light toggle (persists in `localStorage` — theme only, never auth) |
| `js/cobros.js` | Credit-terms billing. `PLAZO_PAGO_DIAS` maps "30 días" → 30. Payment status is **derived, never stored**: `estadoCobro(r)` computes it from `pagado` + `fecha_vencimiento_pago` so no daily job is needed. Registers/reverts payments, overdue badge on home |
| `js/expedientes.js` | Trip document files for two blocking moments: `ingreso_puerto` (pedimento, carta de liberación, BL) and `entrega_vacios` (container return — demurrage accrues daily past `fecha_limite_vacios`). Checklist copied from `documentos_catalogo` at creation, never referenced, so editing the catalog can't rewrite past files. Client uploads, carrier approves/rejects per document |
| `js/mapa.js` | Leaflet + OpenStreetMap picker for exact origin/destination coordinates (no API key needed). `_mapaPuntos` holds `{origen, destino}` and is read when publishing a pedido. Complements the free-text address — it does not replace it |
| `js/plantillas.js` | Client's saved frequent requests (`plantillas_pedido`). `PLANTILLA_CAMPOS` maps form field IDs → columns → type. **Dates are deliberately never saved.** Ordered by `veces_usada`, capped by a DB trigger |
| `js/preferencias.js` | Per-user email toggle (`perfiles.notif_email`). `PREF_CORREOS` spells out per role which emails go silent and which always arrive — transactional mail and the in-app bell are never silenced (see `TIPOS_SILENCIABLES` in the `enviar-notificacion` Edge Function) |
| `js/privacidad.js` | ARCO rights (Mexican data-protection law): Acceso, Rectificación, Cancelación, Oposición. Holder submits and tracks their own; superadmin resolves. Also renders the user's `consentimientos` history |
| `js/verificacion.js` | Superadmin marks a user as verified from 1–5 in-person photos stored in the private `registros` bucket (signed URLs) |

### State

No state library. Globals refreshed via Supabase queries: `currentUser` (auth.js), `_pedidosAccum` (pedidos.js), per-module caches. Realtime subscriptions in `main.js` re-render the active view when `pedidos`, `ofertas`, `mensajes`, `notificaciones`, fleet tables change.

### Auth & Roles

- Sessions use **`sessionStorage`** (intentional: closing the browser logs out). Never switch to `localStorage`.
- `currentUser.rol` ∈ `cliente` | `admin` (= empresa/proveedor) | `superadmin`.
- `applyUserUI()` puts **`role-admin`** / **`role-superadmin`** / **`logged-in`** classes on `<body>` (note: `role-`, not `rol-`).
- CSS gates visibility: `.admin-only`, `.superadmin-only`, `.admin-hidden`. Never gate roles with inline `display:none`.
- New accounts go through `solicitudes_cuenta` review; `perfiles.aprobacion_cuenta` ∈ `null` (active) | `pendiente` | `rechazada` | `suspendida`.
- Passwords: minimum **8** characters (validated client-side in registro, reset, and user management).

---

## Security Conventions

### Escaping — two different helpers
```js
// HTML body/attribute context:
el.innerHTML = `<p>${esc(pedido.descripcion)}</p>`;

// Inside a JS string in an inline handler — esc() alone is NOT enough
// (the browser decodes entities before the JS runs):
`<button onclick="abrirX('${u.id}','${escJs(u.nombre)}')">`
```
Any user-controlled value interpolated into `onclick="...'${...}'..."` MUST use `escJs()`.

### Storage buckets
| Bucket | Public | Path rule / access |
|---|---|---|
| `unidades` | ❌ private | First path segment must be `auth.uid()`. Read with `createSignedUrl(path, 3600)` — **never `getPublicUrl`** |
| `registros` | ❌ private | Same path rule; signed URLs only. Also holds `perfiles.fotos_verificacion` |
| `documentos-viaje` | ❌ private | Trip file documents (`expediente_documentos.archivo_path`); signed URLs only |
| `operadores` | ✅ public | `getPublicUrl` OK |
| `custodios` | ✅ public | `getPublicUrl` OK |
| `documentos-empresa` | ✅ public | `getPublicUrl` OK |

Store **paths** in the DB for private buckets and sign at display time (see `abrirEvidencias` in `reservaciones.js`).

### RLS (the real security boundary — client checks are cosmetic)
- Every table has RLS. If a query unexpectedly returns empty or an insert/update silently fails, **check RLS first**, then code.
- `is_superadmin()` is a `SECURITY DEFINER` helper used in policies; executable by `authenticated` only.
- `notificaciones` INSERT is relationship-restricted: you can only notify yourself, superadmins, or the counterparty of your reservación/oferta. New notification flows must fit one of those, or use a DB trigger.
- `reservaciones` INSERT requires the creator to be the cliente, the propietario, or superadmin.
- `perfiles` is NOT readable by `anon` (fiscal data). Authenticated users can read all rows (for display names).
- Always surface RLS errors: check `error` from every mutating call and `showToast(...)` it — silent failures cost hours of debugging.

---

## Key Conventions

- **Supabase access:** always through the SDK global `sb` (`const { data, error } = await sb.from(...)`), never raw SQL in the client.
- **Errors:** check `error`, `console.error` + `showToast(msg, 'error')`. Never `alert()`.
- **Formatting:** `fmtFecha(row.created_at)` → "12/05/2025", `formatPrecio(n)` → "$1,250 MXN/día". Never inline.
- **Confirmations:** `showConfirm(msg, cb, { danger, confirmLabel })` — never `window.confirm`.
- **Scripts are NOT ES modules.** Everything is global scope; load order in `app.html` matters (utils → config → auth → … → main last). New functions are global — avoid name collisions.
- **New view:** add `<section id="view-X" class="view">` in `app.html` → an `if (v === 'X') renderX();` line in `showView()` (it's a chain of `if`s, not a `switch`) → `js/X.js` with `renderX()` → `<script>` tag with `?v=1` → add to `sw.js` SHELL list → role-gate with CSS classes.
- **Confirming a write actually happened:** `actualizarConfirmado(tabla, filtro, payload, etiqueta)` in `js/utils.js`. Checking `error` alone is not enough — when RLS blocks an UPDATE it affects **0 rows and returns `error: null`**, so the UI cheerfully reports success while nothing changed. This helper `.select()`s the result and returns `true` only if a row really changed. Use it for any state transition that matters.
- **No npm packages** — CDN `<script>` tags only if truly needed.

---

## Database Schema

All tables in `public` with RLS enabled.

### `perfiles` — one row per auth user. PK `user_id`
`nombre`, `rol`, `aprobacion_cuenta`, `nota_rechazo_cuenta`, `verificado`, fiscal data (`rfc`, `razon_social`, `regimen_fiscal`, `tipo_persona`), company docs + expiry dates (`doc_permiso_sct`, `doc_seguro_rc`, `doc_seguro_carga` + `*_pendiente` variants for the edit-approval flow), `telefono`, `descripcion`.

### `pedidos` — client transport requests. PK `id` (uuid)
`cliente_id/_nombre/_email` (denormalized), `tipo_camion`, `tipo_carga`, `origen`, `destino`, `fecha_ini/_fin`, `precio_cliente`, `oferta_pendiente_id`, `rechazo_nota`, special-requirement bools.
Cargo-driven fields (the request is built from the load, not from the truck): `categoria_carga`, `peso_carga`, `num_tarimas`, `num_bultos`, `contenedor_N_tipo/_peso`, `num_contenedores`, `largo/ancho/alto_m`, `hazmat_clase/_un`, `temp_min/_max`, `origen/destino_lat/_lng` (map pin), `plazo_pago`, `detalles_*` (lugar, hora, contacto — captured when the client accepts an offer).
**`estado` flow:** `pendiente_revision` → (SA approves) → `abierto` → `en_negociacion` → (client accepts, SA reviews) → `pendiente_acuerdo` → `acordado` → `finalizado` (service closed and approved). Also `cancelado`, `rechazado`, and `expirado` (was `acordado` and `fecha_fin` passed without completion). Cancelling a reservation returns the pedido to `abierto` and invalidates its ofertas.

> ⚠️ **The state machine advances as a side effect of rendering the list** — `renderPedidos()` in [js/pedidos.js:239-292](js/pedidos.js) expires stale offers, reopens pedidos with no live offers, and marks past-due agreements `expirado`. If nobody opens "Solicitudes" in the web app, none of that happens. The optional migration `20260810130000_sincronizar_estados_OPCIONAL.sql` moves it to pg_cron; it is **not applied** by default.

### `ofertas` — company bids. PK `id` (uuid)
`pedido_id`, `admin_id/_nombre`, `precio_oferta`, `contra_precio` (client counter), `ronda` (1|2), `camion_id`, `estado` (`enviada` | `contra_oferta` | `aceptada` | `rechazada`), `expira_en` (now + 2 days). The offered truck's `tipo` must match `pedidos.tipo_camion` (validated in `openHacerOferta` + `_enviarOfertaCore`).

### `reservaciones` — active bookings. PK `id` (uuid)
`pedido_id` (links back for cancel-reopen), `propietario_id`, `cliente_user_id`, `cliente/_email`, `unidad`, `recurso_tipo` (`camion`|`custodio`|`patio`|`lavado`), `fecha_ini/_fin`, `precio_acordado`, `completado_en`, `calificado`.
**`estado`:** `Pendiente` | `Activa` | `PorAprobar` (closure requested, waiting on SA) | `CancelacionSolicitada` (client asked to cancel, SA resolves) | `Completada` | `Cancelada`.
**`tracking_estado`:** five steps, **different per `recurso_tipo`** — camión `Confirmado→En camino→En carga→En tránsito→Entregado`; custodio `Confirmado→Asignado→En ruta→En servicio→Finalizado`; patio `Confirmado→Listo→Recibido→En almacenaje→Liberado`; lavado `Confirmado→Recibido→En lavado→Control→Listo`. Defined in `TRACKING_POR_TIPO` (js/tracking.js) and duplicated in the SQL function `tracking_pasos()`.
**Closure evidence:** each side has its own column — `evidencias` (company) and `evidencias_cliente` (client), both arrays of storage **paths**; plus `finalizacion_solicitada_por`. Both sides must upload before the SA can approve.
**Billing:** `pagado`, `pagado_en/_por`, `pago_metodo`, `pago_referencia`, `plazo_pago` (snapshot of the agreed term), `fecha_vencimiento_pago`. The `trg_sync_datos_pago` trigger clears the payment fields when `pagado` goes back to false.
**Cancellation:** `cancelacion_motivo`, `cancelacion_detalle`, `cancelacion_solicitada_en/_por`, `cancelacion_tracking_estado` (freezes how far the trip had gone).
`reservaciones_historico`: archived rows + `archivado_at/_por`.

### `mensajes` — chat. PK `id` (uuid)
`de_user_id/_nombre`, `texto`, `pedido_id` | `reserva_id` (one set), `participantes uuid[]` (RLS checks membership), `leido`.

### `notificaciones` — PK `id` (uuid)
`user_id` (recipient), `tipo`, `titulo`, `mensaje`, `leido`, `meta jsonb`. INSERT restricted by relationship (see RLS section).

### Fleet tables — `camiones`, `custodios`, `patios`, `lavados` (PK text) and `operadores`
Shared pattern: `propietario_id`, `estado` (`disponible`|`ocupado`|`no_disponible`), `aprobacion` (`pendiente`|`aprobada`|`rechazada`), plus `rechazo_nota`, `rechazo_campos`, `es_edicion`, `campos_editados`, `snapshot_anterior` for the edit-approval workflow. Per-table extras: camiones (`tipo`, `placas`, `precio_dia`, `caat`…), custodios (`certificaciones[]`…), patios (`area_m2`…), lavados (`tipos_lavado[]`…), operadores (`curp`, `num_licencia`, fotos…).

### Trip document files (`js/expedientes.js`)
- `expedientes`: one per `(reserva_id, etapa)` — UNIQUE. `etapa` ∈ `ingreso_puerto` | `entrega_vacios`; `estado` ∈ `solicitado` | `en_revision` | `completo`; `solicitado_por/_en`, `nota`. For `entrega_vacios` only: `deposito_vacios`, `fecha_limite_vacios` (**demurrage accrues per day past this date** — that's where the money is).
- `expediente_documentos`: the checklist items. `nombre`, `descripcion`, `obligatorio`, `orden`, `estado`, `archivo_path` (private bucket). Rows are **copied** from `documentos_catalogo` at creation, never referenced, so editing the catalog can't rewrite what an old file asked for. `trg_guard_expediente_documento` stops each side from doing the other's job.
- `documentos_catalogo`: the editable master checklist per `etapa` (`activo`, `orden`).

### Privacy & consent (`js/privacidad.js`)
- `consentimientos`: `user_id`, `tipo` (`aviso_privacidad` | `terminos` | `datos_sensibles_operador`), `version`, `aceptado_en`, `contexto`, `referencia`. Written at registro and at alta de operador.
- `solicitudes_arco`: ARCO rights requests. `tipo` (`acceso`|`rectificacion`|`cancelacion`|`oposicion`), `descripcion`, `estado` (`pendiente`|`en_proceso`|`atendida`|`rechazada`), `respuesta`, `atendida_por/_en`. Legal deadlines apply to responses.

### Other tables
- `calificaciones`: `reservacion_id`, `admin_id`, `cliente_id`, `rating` 1–5, `comentario`.
- `solicitudes_cuenta`: signup requests with fiscal data + document paths, `estado` (`pendiente`|`aprobada`|`rechazada`), `nota_rechazo`. Rejected users can re-apply with the same account.
- `plantillas_pedido`: the client's saved frequent requests. Full copy of the pedido's cargo/route/commercial fields **minus the dates**, plus `veces_usada` / `ultima_vez_usada` for ordering. `trg_limitar_plantillas` caps how many a client may keep.
- `catalogos` (PK `clave, valor`): dropdown values served from the DB instead of hardcoded in JS — `etiqueta`, `ayuda`, `orden`, `activo`, `meta jsonb`. Editing a catalog no longer requires a deploy.
- `app_config` (PK `clave`, `valor jsonb`): runtime settings.
- `pagos`, `documentos_fiscales`: payment/invoice records tied to reservaciones.

### DB functions & triggers
**Notification triggers:** `notificar_nueva_oferta`, `notificar_respuesta_oferta`, `fn_notificar_nuevo_mensaje`, `notificar_nueva_reserva`, `notificar_cambio_reserva`.
**Helpers:** `is_superadmin()` (RLS), `mi_nombre()`, `tracking_pasos()`, `tabla_recurso()`, `es_servicio_camion()`, `recurso_tipo_de_servicio()`, `expire_stale_offers`, `check_reservacion_disponibilidad` (raises `RECURSO_NO_DISPONIBLE` / `P0001` on overlapping bookings).
**Guard triggers — the transition police.** Beyond RLS (which decides *whether* you may write a row), these decide *which state changes are legal for you*: `trg_guard_perfil_self_update`, `trg_guard_reservacion_update`, `trg_guard_pedido_update`, `trg_guard_oferta_update`, `trg_guard_expediente_documento`, and one per fleet table (`camiones`, `custodios`, `patios`, `lavados`, `operadores`). They read `auth.uid()`, so **they still apply inside `SECURITY DEFINER` functions** — a bad transition rolls back the whole transaction.

All `SECURITY DEFINER` with pinned `search_path`, not callable via REST.

### Business RPCs — atomic, and currently **unused by the web client**

`supabase/migrations/20260810120000_rpc_transacciones.sql` defines 11 functions that push the multi-step flows into single Postgres transactions: `enviar_oferta`, `responder_oferta`, `responder_contraoferta`, `cancelar_reservacion`, `solicitar_cancelacion`, `registrar_evidencias`, `avanzar_tracking`, `abrir_expediente`, `calificar_servicio`, `enviar_mensaje`, `recomendar_unidad`. Each re-verifies the caller (`SECURITY DEFINER` skips RLS on SELECT/UPDATE, so authorship is checked by hand) and the guard triggers still apply.

**`grep -rn "sb.rpc(" js/` returns nothing — the browser still orchestrates every one of these step by step, without atomicity.** `cancelarReserva()` (js/reservaciones.js) is 7 chained writes; if the tab closes halfway the unit stays `ocupado` and the pedido hangs — migration `20260728120000` exists because that already happened once.

When fixing anything in these flows, prefer moving the call to the RPC over patching the client sequence. The native iOS/Android clients are expected to use the RPCs (see `docs/CONTRATO-MOVIL.md`), so logic left in JS will diverge across the three clients.

Note this also means the **anti-disintermediation phone-number block is browser-only** today: `enviar_mensaje` enforces it server-side, `js/chat.js` does not stop a direct REST call.

---

## Edge Functions

- **`gestionar-usuario`** — superadmin-only user CRUD (`crear`/`editar`/`eliminar`/`listar`). Verifies the caller's JWT server-side and requires `rol = 'superadmin'`. Uses service role key from secrets. Called from `js/usuarios.js` with `FN_URL`.
- **`enviar-notificacion`** — transactional emails (reservas, acuerdos). Called fire-and-forget with `FN_NOTIFICACION`.

Deploy with `mcp__supabase__deploy_edge_function` (or `supabase functions deploy`). Keep the local copy in `supabase/functions/` in sync with what you deploy.

---

## PWA / Service Worker

- `sw.js`: **network-first** for JS/CSS/HTML and for Supabase REST GETs (falls back to cache only when actually offline — a prior stale-while-revalidate strategy for REST GETs always served last-known data first, so the app looked "one step behind" until a second refresh; don't reintroduce it), network-only for auth/realtime/Edge Functions, cache-first for images.
- New static assets → add to the `SHELL` list in `sw.js`. ⚠️ `js/detalle.js`, `js/notificaciones.js` and `css/detalle.css` are currently **missing** from `SHELL` — they load fine online (network-first) but are absent from the offline shell.
- Bumping `CACHE` (`portgo-vXX`) purges all old caches on activate — required on every deploy.
- `app.html` also loads **Leaflet 1.9.4 from unpkg** (CSS + JS) for the map picker — the only runtime CDN dependency besides the Supabase SDK. It is not in `SHELL`, so the map needs connectivity; `abrirMapa()` degrades with a toast when `L` is undefined.

---

## What to Avoid

- **Don't use `localStorage` for auth** — `sessionStorage` is intentional (theme preference is the only `localStorage` use).
- **Don't add `type="module"` to script tags** — the codebase is classic globals; modules would break cross-file calls.
- **Don't use `getPublicUrl` on `unidades`/`registros`** — private buckets, signed URLs only.
- **Don't interpolate user data into `onclick` with plain `esc()`** — use `escJs()`.
- **Don't gate roles with inline styles** — use the `<body>` class system.
- **Don't use `alert()`/`confirm()`** — `showToast()` / `showConfirm()`.
- **Don't ship without bumping `?v=` + sw.js cache + pushing** — see the deployment checklist.
- **Don't put the service role key anywhere near client code.**
- **Don't delete anything without explicit authorization** — even under `bypassPermissions`. See [Rule #1](#-rule-1--ask-before-deleting-anything) at the top of this file.
