# CLAUDE.md

This file provides guidance to Claude Code when working with the **PortGo** codebase.

---

## Project Overview

**PortGo** is a PWA logistics platform for port transport services built as a fully client-side app with Supabase as the backend (PostgreSQL + Auth + Realtime).

**Business flow:** Clients post transport requests → Admins (vendors) bid on them → Client accepts a bid → Shipment is tracked to completion. Superadmins manage the full system (users, fleet, patios).

**Stack:** Vanilla JS (ES modules via `<script type="module">`), plain CSS, Supabase JS SDK v2, no build tooling.

---

## Development Setup

No build system, no package manager, no test suite. All dependencies load from CDN in `index.html`.

```bash
# Quickest way to run locally
npx serve .

# Or just open index.html directly in a browser
```

- The app connects to the **live Supabase project** on load — credentials are in `js/config.js`.
- Supabase CLI is configured in `.claude/settings.local.json` for migrations, edge function deploys, and direct SQL execution.
- There is no staging environment — changes to schema or Edge Functions affect production immediately.

> ⚠️ Never commit secrets. `js/config.js` contains the Supabase anon key (safe to expose) and the project URL. The service role key lives only in Edge Functions, never in client code.

---

## File Structure

```
/
├── index.html              # Production entry point
├── flota-app.html          # Alternate shell (same structure, fleet-focused)
├── sw.js                   # Service worker
├── css/
│   ├── base.css
│   ├── layout.css
│   ├── components.css
│   ├── login.css
│   ├── detalle.css
│   └── theme.css
├── js/
│   ├── config.js
│   ├── auth.js
│   ├── main.js
│   ├── views.js
│   ├── utils.js
│   ├── pedidos.js
│   ├── detalle.js
│   ├── reservaciones.js
│   ├── camiones.js
│   ├── catalogo.js
│   ├── admin.js
│   ├── usuarios.js
│   ├── chat.js
│   ├── notificaciones.js
│   ├── tracking.js
│   ├── modal.js
│   └── theme.js
└── supabase/
    └── functions/
        └── gestionar-usuario/
```

---

## Architecture

### Entry Points

- `index.html` — loads all JS/CSS in order, registers the service worker, defines all `<section id="view-*">` DOM sections.
- `flota-app.html` — alternate shell with same structure, focused on fleet management.
- `sw.js` — cache-first strategy for local assets; network-first for Supabase API calls.

### JS Module Responsibilities

| File | Role |
|---|---|
| `js/config.js` | Initializes Supabase client; exports `supabase` and `EDGE_URL` |
| `js/auth.js` | Login / signup / logout; populates `currentUser = { id, email, nombre, rol }` |
| `js/main.js` | App bootstrap: `checkExistingSession()`, Supabase realtime subscriptions, SW registration |
| `js/views.js` | Manual SPA router — `showView(viewId, btn)` toggles `<section>` visibility by ID |
| `js/utils.js` | `esc()` XSS sanitizer, `fmtFecha()`, `formatPrecio()`, skeleton loader helpers |
| `js/pedidos.js` | Full order lifecycle — create, list, bid, accept, complete |
| `js/detalle.js` | Order detail modal with status transition controls |
| `js/reservaciones.js` | Reservation booking view (distinct from on-demand orders) |
| `js/camiones.js` | Truck catalog with filters |
| `js/catalogo.js` | Service/rate catalog |
| `js/admin.js` | Admin dashboard — manage trucks, custodians, patios |
| `js/usuarios.js` | Superadmin user management (calls `gestionar-usuario` Edge Function) |
| `js/chat.js` | Real-time per-order messaging via Supabase Realtime |
| `js/notificaciones.js` | Notification panel |
| `js/tracking.js` | Shipment tracking view |
| `js/modal.js` | Generic modal open/close helpers |
| `js/theme.js` | Dark/light theme toggle; persists preference to `localStorage` |

### State Management

No state library. State lives in module-level globals and is refreshed via Supabase queries:

```js
// Key globals (defined in their respective modules)
currentUser        // auth.js   — logged-in user object
pedidoDetalle      // detalle.js — currently open order
ofertaDetalleId    // detalle.js — currently focused bid
```

Realtime subscriptions in `main.js` watch key tables (`pedidos`, `ofertas`, `mensajes`, `notificaciones`) and call the relevant module's render function when rows change.

### Auth & Roles

`currentUser.rol` drives all UI visibility. Set by `applyUserUI()` in `auth.js` which adds/removes CSS classes on `<body>`:

| Role | Capabilities |
|---|---|
| `cliente` | Create requests, track shipments, chat |
| `admin` | Bid on requests, manage own fleet (trucks, custodians, patios) |
| `superadmin` | Full access — all of the above + user management |

> Auth uses `sessionStorage` (not `localStorage`). Sessions **do not persist** across tabs or browser restarts. This is intentional for security in shared-device port environments.

### CSS Architecture

Six files loaded in strict order — later files override earlier ones:

```
base.css → layout.css → components.css → login.css → detalle.css → theme.css
```

Role-based visibility uses CSS class selectors on `<body>`:
- `.admin-only` — visible only when `<body>` has class `rol-admin` or `rol-superadmin`
- `.superadmin-only` — visible only when `<body>` has class `rol-superadmin`

Do not use `display:none` inline for role gating — always rely on these CSS classes.

### Supabase Edge Function

`gestionar-usuario` handles privileged user operations that must bypass Row Level Security (RLS):
- Creating accounts on behalf of clients (admin-initiated onboarding)
- Updating roles
- Deleting users from `auth.users`

Called exclusively from `js/usuarios.js`. The function URL is exported from `js/config.js` as `EDGE_URL`.

---

## Key Conventions

### Security — always sanitize user output
```js
// ✅ Correct — always use esc() for user-generated content in template literals
container.innerHTML = `<p>${esc(pedido.descripcion)}</p>`;

// ❌ Wrong — XSS risk
container.innerHTML = `<p>${pedido.descripcion}</p>`;
```

### Adding a new view
1. Add `<section id="view-X" class="view">` in `index.html`.
2. Add a `case 'X':` in `views.js` inside `showView()`.
3. Create `js/X.js` with an exported `renderX()` function.
4. Import and call `renderX()` from the appropriate trigger (nav click, role gate, etc.).
5. Add role-gating CSS classes if needed (`.admin-only`, `.superadmin-only`).

### Supabase queries — always use the JS SDK
```js
// ✅ Correct
const { data, error } = await supabase
  .from('pedidos')
  .select('*, ofertas(*)')
  .eq('estado', 'activo');

// ❌ Never use raw SQL in client code
```

### Error handling pattern
```js
const { data, error } = await supabase.from('pedidos').select('*');
if (error) {
  console.error('pedidos fetch:', error.message);
  // Show user-facing feedback — use toast or modal, not alert()
  return;
}
```

### Date and price formatting
Always use the helpers from `utils.js` — never format inline:
```js
fmtFecha(row.created_at)   // → "12 may 2025"
formatPrecio(row.monto)    // → "$1,250.00"
```

---

## Supabase / Database Notes

- All client queries go through RLS policies. If a query returns empty unexpectedly, check RLS before assuming a code bug.
- The `gestionar-usuario` Edge Function uses the **service role key** (set as a Supabase secret) to bypass RLS — never pass the service role key to the client.
- Run migrations with the Supabase CLI: `supabase db push` or `supabase migration new <name>`.
- To inspect live data during debugging: `supabase db studio` or the Supabase dashboard Table Editor.

---

## PWA / Service Worker

- `sw.js` uses a **cache-first** strategy for static assets (JS, CSS, fonts, images).
- Supabase REST/Realtime calls always go **network-first** — never cache auth or data responses.
- When adding new static assets, add them to the SW cache list in `sw.js`.
- The SW is registered in `main.js` on app init.

---

## What to Avoid

- **Don't use `localStorage` for auth state** — the app intentionally uses `sessionStorage`.
- **Don't add `<script>` tags without `type="module"`** — all JS uses ES module scope.
- **Don't inline role-visibility logic with `display:none`** — use the CSS class system.
- **Don't call the Supabase service role key from client code** — Edge Functions only.
- **Don't use `alert()`** — use the existing modal or toast helpers.
- **Don't add npm packages** — there is no bundler; add CDN links to `index.html` if a new library is truly needed.
