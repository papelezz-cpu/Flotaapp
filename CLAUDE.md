# CLAUDE.md

This file provides guidance to Claude Code when working with the **PortGo** codebase.

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
├── css/                    # base → layout → components → login → detalle → theme (load order matters)
├── js/                     # Classic scripts, global scope, order defined in app.html
└── supabase/functions/
    ├── gestionar-usuario/  # Privileged user CRUD (superadmin only, service role key)
    └── enviar-notificacion/ # Email notifications
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
| `js/chat.js` | Per-pedido/per-reserva realtime chat (`mensajes` table, `participantes` array) |
| `js/notificaciones.js` | Notification bell panel |
| `js/tracking.js` | Shipment tracking state machine |
| `js/detalle.js` | Order detail modal |
| `js/modal.js` | Direct reservation booking modal |
| `js/reportes.js` | Superadmin KPI reports |
| `js/vigencias.js` | Document expiry monitoring |
| `js/theme.js` | Dark/light toggle (persists in `localStorage` — theme only, never auth) |

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
| `registros` | ❌ private | Same path rule; signed URLs only |
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
- **New view:** add `<section id="view-X" class="view">` in `app.html` → case in `showView()` → `js/X.js` with `renderX()` → `<script>` tag with `?v=1` → add to `sw.js` SHELL list → role-gate with CSS classes.
- **No npm packages** — CDN `<script>` tags only if truly needed.

---

## Database Schema

All tables in `public` with RLS enabled.

### `perfiles` — one row per auth user. PK `user_id`
`nombre`, `rol`, `aprobacion_cuenta`, `nota_rechazo_cuenta`, `verificado`, fiscal data (`rfc`, `razon_social`, `regimen_fiscal`, `tipo_persona`), company docs + expiry dates (`doc_permiso_sct`, `doc_seguro_rc`, `doc_seguro_carga` + `*_pendiente` variants for the edit-approval flow), `telefono`, `descripcion`.

### `pedidos` — client transport requests. PK `id` (uuid)
`cliente_id/_nombre/_email` (denormalized), `tipo_camion`, `tipo_carga`, `origen`, `destino`, `fecha_ini/_fin`, `precio_cliente`, `oferta_pendiente_id`, `rechazo_nota`, special-requirement bools.
**`estado` flow:** `pendiente_revision` → (SA approves) → `abierto` → `en_negociacion` → (client accepts, SA reviews) → `pendiente_acuerdo` → `acordado`. Also `cancelado`, `rechazado`. Cancelling a reservation returns the pedido to `abierto` and invalidates its ofertas.

### `ofertas` — company bids. PK `id` (uuid)
`pedido_id`, `admin_id/_nombre`, `precio_oferta`, `contra_precio` (client counter), `ronda` (1|2), `camion_id`, `estado` (`enviada` | `contra_oferta` | `aceptada` | `rechazada`), `expira_en` (now + 2 days). The offered truck's `tipo` must match `pedidos.tipo_camion` (validated in `openHacerOferta` + `_enviarOfertaCore`).

### `reservaciones` — active bookings. PK `id` (uuid)
`pedido_id` (links back for cancel-reopen), `propietario_id`, `cliente_user_id`, `cliente/_email`, `unidad`, `recurso_tipo` (`camion`|`custodio`|`patio`|`lavado`), `fecha_ini/_fin`, `precio_acordado`, `tracking_estado` (`Confirmado`→`En camino`→`En puerto`→`Cargando`→`En tránsito`→`Entregado`), `estado` (`Pendiente`|`Activa`|`Completada`|`Cancelada`), `completado_en`, `evidencias` (array of storage **paths**), `pagado`, `calificado`.
`reservaciones_historico`: archived rows + `archivado_at/_por`.

### `mensajes` — chat. PK `id` (uuid)
`de_user_id/_nombre`, `texto`, `pedido_id` | `reserva_id` (one set), `participantes uuid[]` (RLS checks membership), `leido`.

### `notificaciones` — PK `id` (uuid)
`user_id` (recipient), `tipo`, `titulo`, `mensaje`, `leido`, `meta jsonb`. INSERT restricted by relationship (see RLS section).

### Fleet tables — `camiones`, `custodios`, `patios`, `lavados` (PK text) and `operadores`
Shared pattern: `propietario_id`, `estado` (`disponible`|`ocupado`|`no_disponible`), `aprobacion` (`pendiente`|`aprobada`|`rechazada`), plus `rechazo_nota`, `rechazo_campos`, `es_edicion`, `campos_editados`, `snapshot_anterior` for the edit-approval workflow. Per-table extras: camiones (`tipo`, `placas`, `precio_dia`, `caat`…), custodios (`certificaciones[]`…), patios (`area_m2`…), lavados (`tipos_lavado[]`…), operadores (`curp`, `num_licencia`, fotos…).

### Other tables
- `calificaciones`: `reservacion_id`, `admin_id`, `cliente_id`, `rating` 1–5, `comentario`.
- `solicitudes_cuenta`: signup requests with fiscal data + document paths, `estado` (`pendiente`|`aprobada`|`rechazada`), `nota_rechazo`. Rejected users can re-apply with the same account.
- `pagos`, `documentos_fiscales`: payment/invoice records tied to reservaciones.

### DB functions & triggers
`is_superadmin()` (RLS helper) · `notificar_nueva_oferta`, `notificar_respuesta_oferta`, `fn_notificar_nuevo_mensaje`, `notificar_nueva_reserva`, `notificar_cambio_reserva` (notification triggers) · `expire_stale_offers`, `check_reservacion_disponibilidad`. All `SECURITY DEFINER` with pinned `search_path`, not callable via REST.

---

## Edge Functions

- **`gestionar-usuario`** — superadmin-only user CRUD (`crear`/`editar`/`eliminar`/`listar`). Verifies the caller's JWT server-side and requires `rol = 'superadmin'`. Uses service role key from secrets. Called from `js/usuarios.js` with `FN_URL`.
- **`enviar-notificacion`** — transactional emails (reservas, acuerdos). Called fire-and-forget with `FN_NOTIFICACION`.

Deploy with `mcp__supabase__deploy_edge_function` (or `supabase functions deploy`). Keep the local copy in `supabase/functions/` in sync with what you deploy.

---

## PWA / Service Worker

- `sw.js`: **network-first** for JS/CSS/HTML (falls back to cache offline), **stale-while-revalidate** for Supabase REST GETs, network-only for auth/realtime/Edge Functions, cache-first for images.
- New static assets → add to the `SHELL` list in `sw.js`.
- Bumping `CACHE` (`portgo-vXX`) purges all old caches on activate — required on every deploy.

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
