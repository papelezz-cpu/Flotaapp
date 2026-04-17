# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**PortGo** is a PWA logistics platform for port transport services. Clients post transport requests, vendors (admins) bid on them, and superadmins manage the entire system. It is fully client-side with Supabase as the backend (PostgreSQL + Auth + Realtime).

## Development

There is no build system, no package manager, and no test suite. All dependencies are loaded via CDN in `index.html`. To develop:

- Open `index.html` directly in a browser, or serve it with any static file server (e.g. `npx serve .` or VS Code Live Server).
- The app connects to a live Supabase project on load — credentials are in `js/config.js`.
- Supabase CLI is available for schema migrations, edge function deploys, and SQL execution (configured in `.claude/settings.local.json`).

## Architecture

### Entry Points
- `index.html` — production entry, loads all JS/CSS, registers the service worker.
- `flota-app.html` — alternate shell (same structure).
- `sw.js` — service worker: cache-first for local assets, network-first for Supabase API calls.

### JS Module Responsibilities

| File | Role |
|---|---|
| `js/config.js` | Initializes Supabase client; exports `supabase`, `EDGE_URL` |
| `js/auth.js` | Login/signup/logout; populates `currentUser = {id, email, nombre, rol}` |
| `js/main.js` | App bootstrap: calls `checkExistingSession()`, sets up Supabase realtime subscriptions, registers SW |
| `js/views.js` | Manual SPA router — `showView(v, btn)` toggles DOM sections by ID |
| `js/utils.js` | `esc()` for XSS-safe HTML, `fmtFecha()`, `formatPrecio()`, skeleton loaders |
| `js/pedidos.js` | Order/request lifecycle — create, bid, accept, complete |
| `js/detalle.js` | Order detail modal with status transitions |
| `js/reservaciones.js` | Reservation booking view |
| `js/camiones.js` | Truck catalog with filters |
| `js/catalogo.js` | Service catalog |
| `js/admin.js` | Admin dashboard — manage trucks, custodians, patios |
| `js/usuarios.js` | Superadmin user management (calls Edge Function) |
| `js/chat.js` | Real-time messaging per order |
| `js/notificaciones.js` | Notification panel |
| `js/tracking.js` | Shipment tracking |
| `js/modal.js` | Generic modal open/close helpers |
| `js/theme.js` | Dark/light theme toggle |

### State Management
There is no state library. State is module-level globals (`currentUser`, `pedidoDetalle`, `ofertaDetalleId`, etc.) and live Supabase queries. Realtime subscriptions in `main.js` watch key tables and call module render functions when data changes.

### Auth & Roles
`currentUser.rol` drives UI visibility via CSS classes applied by `applyUserUI()`:
- `cliente` — can create and track requests
- `admin` — vendor role; can bid and manage fleet
- `superadmin` — full access including user management

Auth uses `sessionStorage` (not `localStorage`), so sessions do not persist across tabs or browser restarts.

### CSS Architecture
Six CSS files loaded in order: `base.css` → `layout.css` → `components.css` → `login.css` → `detalle.css` → `theme.css`. Role-based visibility is handled with CSS selectors (`.admin-only`, `.superadmin-only`) toggled by JS class manipulation on `<body>`.

### Supabase Edge Function
`gestionar-usuario` (URL in `config.js`) handles privileged user operations that bypass RLS (e.g. admin-created accounts). Called from `js/usuarios.js`.

## Key Conventions

- Always use `esc()` from `utils.js` when interpolating user data into HTML template literals.
- New views follow the pattern: add a `<section id="view-X">` in HTML, add a case in `views.js`, and create a `js/X.js` module with a `renderX()` function.
- Supabase queries use the JS SDK (`supabase.from(...).select(...)`) — not raw SQL in the client.
