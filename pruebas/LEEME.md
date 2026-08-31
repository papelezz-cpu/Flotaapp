# Ambiente de pruebas y pruebas automatizadas

Sin npm y sin build: usan el `fetch` nativo de Node y hablan el mismo protocolo
que el SDK del navegador (GoTrue + PostgREST). Eso significa que **pasan por RLS,
por los guard triggers y por las RPC igual que la app**, no por un atajo.

## Dónde van las credenciales

En **`pruebas/credenciales.local.json`**. Está en `.gitignore`, así que git no lo
ve ni lo sube nunca. No hace falta `.env`.

```json
{
  "pruebas":    { "url": "https://….supabase.co", "anon": "…", "service_role": "…",
                  "clave_siembra": "…" },
  "produccion": { "service_role": "…" },
  "superadmin": { "email": "…", "password": "…" },
  "empresa":    { "email": "…", "password": "…" },
  "cliente":    { "email": "…", "password": "…" }
}
```

⚠ **`clave_siembra` no puede volver al repositorio.** Es la contraseña de las
cuentas que crea `02-sembrar.mjs`, una de ellas superadmin. Estuvo en
`lib/cuentas.mjs` en claro mientras pruebas tenía datos inventados; desde que
pruebas es copia fiel de producción, esa contraseña abre una sesión superadmin
sobre datos reales de clientes, y este repositorio es público.

- El bloque `pruebas` es el proyecto **portgo-pruebas** (Supabase → Settings → API).
  La `service_role` solo vive aquí: nunca en código del cliente.
- `superadmin` / `empresa` / `cliente` son las cuentas **de producción**, y solo las
  usa el diagnóstico de lectura.
- `credenciales.ejemplo.json` es la plantilla vacía; esa sí se sube al repo.

El URL y la anon key de producción no se escriben aquí: se leen de `js/config.js`
para que haya una sola fuente de verdad.

## Montar el ambiente de pruebas (una vez)

```bash
# 1. Sacar el plano de producción (SOLO LEE, no toca nada)
bash supabase/volcar-esquema.sh

# 2. Crear el proyecto en Supabase → New project → portgo-pruebas
#    y aplicarle ese plano
bash supabase/preparar-pruebas.sh

# 3. Llenar el bloque "pruebas" en credenciales.local.json
#    y AMBIENTES.pruebas en js/config.js

# 4. Sembrar usuarios, empresas y flota
node pruebas/02-sembrar.mjs
```

Por qué hace falta el paso 1: `supabase/migrations/` solo tiene el `CREATE TABLE`
de 8 tablas. Las 14 centrales se crearon a mano en el panel y no están en ningún
archivo, así que las migraciones por sí solas **no pueden reconstruir la base**.

## Antes de CADA siembra y de CADA prueba: replicar producción

No es un paso opcional ni una puesta a punto de una sola vez. Una prueba que
corre sobre una base que no es copia de producción no dice nada sobre
producción, y ese es todo el propósito de correrla.

```bash
PORTGO_DB_URL_PROD="postgresql://…xnyqsewaluezkkrlyhxg…" \
PORTGO_DB_URL_PRUEBAS="postgresql://…xskgnudiznryhgagxadu…" \
bash supabase/replicar-produccion-a-pruebas.sh   # producción SOLO se lee

node pruebas/04-copiar-archivos.mjs              # los bytes del Storage
node pruebas/05-sonda-correo.mjs                 # el correo sigue bloqueado
```

La réplica termina verificando 18 dimensiones (estructura, permisos, RLS,
triggers, Realtime, pg_cron, buckets, usuarios de auth, conteo y **hash de contenido de
cada tabla**) y deja el veredicto en `supabase/espejo/paridad.json`.
`02-sembrar.mjs`, `03-flujo-completo.mjs` y `01-diagnostico.mjs --pruebas` leen
ese sello y **se niegan a arrancar** si falta, si tiene más de 6 horas o si dice
que las bases divergen.

Para solo comprobar, sin tocar nada: `bash supabase/verificar-paridad.sh --detalle`.

### La única diferencia permitida

De pruebas no sale ni un correo. Importa más ahora que pruebas tiene las
direcciones reales de los clientes de producción: el bloqueo vive en el código
de `enviar-notificacion` (`CORREO_SALIDA=bloqueada`), es idéntico en los dos
proyectos y se comprueba con `05-sonda-correo.mjs`.

Los correos del propio Supabase Auth no pasan por esa función, así que la sonda
compara además `/auth/v1/settings` de los dos proyectos y falla si difieren. El
que importa es `mailer_autoconfirm`: producción lo tiene en `true` (confirmación
por correo **apagada**), y pruebas debe estar igual — el interruptor está en
Authentication → Sign In / Providers → Email → "Confirm email". No se ve desde
SQL, por eso `verificar-paridad.sh` no lo mide y la sonda sí.

## Las pruebas

| Archivo | Qué hace | Escribe |
|---|---|---|
| `01-diagnostico.mjs` | Entra con las dos cuentas, revisa qué ve cada rol, compara el código con la base y busca datos incoherentes | **No.** Solo lectura |
| `02-sembrar.mjs` | Crea las cuentas y la flota del ambiente de pruebas. Idempotente | Sí, solo en pruebas |
| `03-flujo-completo.mjs` | El ciclo entero: publicar, ofertar, contraofertar, acordar, seguir, cerrar, cobrar, calificar. Más 15 pruebas de lo que **no** debería poderse | Sí, solo en pruebas |
| `04-copiar-archivos.mjs` | Baja los archivos de Storage de producción y los sube a pruebas. Sin esto, cada documento y cada evidencia da 404 | Sí, solo en pruebas |
| `05-sonda-correo.mjs` | Pregunta a la Edge Function si la salida de correo está bloqueada. No provoca ningún envío | **No.** Solo pregunta |

```bash
node pruebas/01-diagnostico.mjs             # contra producción (solo lee)
node pruebas/01-diagnostico.mjs --pruebas   # contra el ambiente de pruebas
node pruebas/03-flujo-completo.mjs
```

Cada corrida imprime en consola y deja el reporte en `pruebas/salida/` (ignorada
por git).

## Los candados

No hay ambiente de pruebas por accidente, así que todo lo que escribe está
atrancado por partida doble:

- `exigirParidad()` (en `lib/paridad.mjs`) aborta si producción y pruebas no son
  la misma base hoy. Es el candado que impide que una prueba verde signifique
  algo que no es.
- `replicar-produccion-a-pruebas.sh` se niega a correr si el ORIGEN no es
  producción o si el DESTINO sí lo es, y pide escribir `REEMPLAZAR PRUEBAS`
  antes de borrar nada (Regla #1).
- `leerAmbientePruebas()` aborta si la URL contiene el ref de producción.
- `preparar-pruebas.sh` se niega a correr si le pegas la cadena de producción.
- `js/config.js` solo usa el proyecto de pruebas en los dominios de
  `HOSTS_PRUEBAS`; cualquier otro dominio entra a producción. Y si el ambiente
  de pruebas está a medio configurar, la app se detiene con un mensaje en vez de
  caer en producción sin avisar.
- `localhost` ya apunta a pruebas: abrir la app con `npx serve .` dejó de tocar
  datos reales.
