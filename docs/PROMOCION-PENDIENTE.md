# Promoción pendiente `dev` → producción

**Estado medido el 2026-09-30** contra el libro mayor (`supabase/aplicadas.tsv`), la
comparación de paridad y `git diff origin/main origin/dev`. Si lees esto más tarde,
vuelve a medirlo antes de seguir: este documento caduca en cuanto alguien aplique algo.

Lo que falta en producción son **7 migraciones** (6 de Carta Porte y 1 de la quinta
auditoría) y **el código de `dev`** (Carta Porte, más siete arreglos de la auditoría).
El orden importa: **primero las migraciones, después el código** (regla 41 de
`docs/AUDITORIA.md`), porque el código nuevo lee columnas y funciones que tienen que
existir ya.

> ⚠ **Esto es una promoción a producción (Regla #2 de `CLAUDE.md`).** Necesita la
> autorización explícita del responsable, para esta tanda concreta. Y la migración
> de Q-14 **borra y recrea** una restricción: necesita además un sí expreso para ese
> borrado (Regla #1). Nada de lo que sigue se hace «porque ya pasó en pruebas».

---

## Paso 1 · Comparación de paridad, justo antes

Para no pegar las cadenas en cada paso, empieza la ventana de Git Bash con
`source supabase/sesion-conexiones.sh`: las pide una vez, las comprueba y las deja
solo en esa ventana.

En Git Bash (MINGW64), una sola línea:

```
bash supabase/verificar-paridad.sh --rapido --detalle
```

Lo esperado, y nada más:

- **Solo en pruebas:** las columnas de Carta Porte (`camiones`: 2, `pedidos`: 9,
  `perfiles`: 5), la función `datos_carta_porte()`, la versión nueva de
  `guard_expediente_update()` y de `responder_oferta()`, y el CHECK
  `ofertas_ronda_check` como `ronda >= 1`.
- **Solo en producción:** las versiones anteriores de esas mismas tres cosas.

Cualquier otra línea «solo en produccion» es un cambio que nadie ha registrado:
**para y averigua qué es antes de aplicar nada.**

## Paso 2 · Las migraciones, en una sola transacción

En Git Bash, **una sola línea** (en PowerShell no funciona):

```
bash supabase/aplicar-a-produccion.sh supabase/migrations/20260929120000_guard_expediente_deja_pasar_a_revision.sql supabase/migrations/20260929140000_domicilio_fiscal_en_perfiles.sql supabase/migrations/20260929170000_camion_config_vehicular_y_permiso_sct_unidad.sql supabase/migrations/20260929180000_pedidos_domicilio_estructurado.sql supabase/migrations/20260929190000_pedidos_clave_prod_serv_sat.sql supabase/migrations/20260929191000_ofertas_rondas_sin_tope.sql supabase/migrations/20260930120000_rpc_datos_carta_porte.sql
```

| # | Migración | Autor | Qué hace |
|---|---|---|---|
| 1 | `20260929120000_guard_expediente_deja_pasar_a_revision` | alecorona | Arregla el guard de expedientes |
| 2 | `20260929140000_domicilio_fiscal_en_perfiles` | alecorona | 5 columnas de domicilio fiscal en `perfiles` |
| 3 | `20260929170000_camion_config_vehicular_y_permiso_sct_unidad` | alecorona | 2 columnas en `camiones` |
| 4 | `20260929180000_pedidos_domicilio_estructurado` | alecorona | 8 columnas de domicilio en `pedidos` |
| 5 | `20260929190000_pedidos_clave_prod_serv_sat` | alecorona | `pedidos.clave_prod_serv_sat` |
| 6 | `20260929191000_ofertas_rondas_sin_tope` | omarsilv | **Q-14.** ⚠ Borra y recrea `ofertas_ronda_check` (`ronda >= 1`) y cambia en `responder_oferta()` solo `ronda = 2` por `ronda = ronda + 1`. **Pide sí expreso por el borrado.** Aborta sola si `responder_oferta()` no es la esperada |
| 7 | `20260930120000_rpc_datos_carta_porte` | alecorona | Función `datos_carta_porte()` |

Todas se aplicaron ya en pruebas, con los mismos archivos. Antes de pedir la
confirmación, el guion muestra el **aviso de choques** (`supabase/choques-migraciones.sh`):
tienen que salir solo «ZONA», ningún «✗ CHOQUE».

Tiene que terminar con `✓ Aplicado a producción.` y las filas nuevas en el libro
mayor. Si aborta, **producción queda como estaba**: es una sola transacción.

### ⚠ Estas dos NO se aplican

| Archivo | Por qué no |
|---|---|
| `supabase/igualar-acl-por-defecto-pruebas.sql` | Es un ajuste **solo de pruebas**: iguala sus privilegios por omisión a los de producción |
| `20260922130000_vigencias_espejo_tolerante.sql` | Etapa **temporal** de H-04. La reemplazó `20260923120000_…_y_estricto.sql`, que ya está en producción desde el 24/09. Aplicarla volvería a poner `vigencias_espejo()` en modo tolerante. El aviso de choques la cuenta como pendiente solo porque le falta su fila de producción en el libro mayor |

## Paso 3 · La fusión `dev` → `main`

`js/config.js` es **el único archivo que no debe viajar**: en `main` apunta a
producción y en `dev` a pruebas. Si viaja, producción queda escribiendo en la base
de pruebas.

```bash
git checkout main && git pull
git merge dev --no-commit --no-ff
git checkout main -- js/config.js
grep -rn "xskgnudiznryhgagxadu" js/ app.html sw.js    # NO debe devolver nada
git commit
git push origin main
```

Los `?v=` de `app.html` y la versión de caché de `sw.js` ya vienen subidos desde `dev`.

## Paso 4 · Confirmar que Vercel terminó

Un push no es un despliegue. Antes de probar nada:

```bash
SHA=$(git rev-parse origin/main)
curl -s "https://api.github.com/repos/papelezz-cpu/Flotaapp/commits/$SHA/status" | grep '"state"' | head -1
```

Tiene que decir `"success"`. Con `"pending"`, la URL sigue sirviendo la versión anterior.

## Paso 5 · Qué probar en producción (Ctrl+Shift+R antes)

| Cambio | Cómo se ve | Detalle en |
|---|---|---|
| **Q-19** · Realtime vuelve a funcionar | La lista de unidades de una empresa y la de reservaciones se actualizan solas, sin salir del menú. **Es el de más impacto:** hoy en producción solo se refresca la campana | `docs/AUDITORIA.md` · `main.js` |
| **Q-10** · El cliente no se suscribe a flota | Nada visible; no debe salir ningún error en la consola del cliente | `main.js` |
| **Q-09** · Catálogo con resumen | Las tarjetas y la ficha de una empresa muestran el **mismo** promedio. La vista `calificaciones_resumen` ya está en producción | `catalogo.js` |
| **Q-14** · Rondas sin tope | Oferta → contraoferta del cliente → recontraoferta de la empresa → otra contraoferta del cliente, sin error | `pedidos.js` + migración 6 |
| **Q-16** · Nota de «Pedir corrección» | En un expediente, la ventana de la nota sale **encima** y se puede escribir | `components.css` |
| **Q-06** · Sin botón «Eliminar» | El superadmin ya no lo ve en Solicitudes | `pedidos.js` |
| **Q-11** · Aviso de consentimiento | Nada visible salvo que falle guardarlo | `auth.js`, `operadores.js` |
| **Carta Porte** | Lo que decida quien la desarrolló | `cartaporte.js`, `perfil.js`, … |

## Paso 6 · Traer `main` de vuelta a `dev`

La trampa que **no avisa**: git resuelve `js/config.js` a favor de `main` sin
conflicto y `dev` queda apuntando a producción.

```bash
git checkout dev
git merge main --no-commit --no-ff
git checkout HEAD -- js/config.js
grep -rn "xnyqsewaluezkkrlyhxg" js/ app.html sw.js    # NO debe devolver nada en dev
git commit && git push origin dev
```

---

## Si algo sale mal

- **Una migración aborta:** no entró nada; pega el error y se revisa.
- **El código rompe algo visible:** se puede volver a desplegar el commit anterior
  de `main` en Vercel. Las migraciones de columnas nuevas no molestan al código viejo.
- **Q-14 en concreto:** si hubiera que deshacerla, la restricción anterior era
  `CHECK (ronda IN (1, 2))`. Recrearla exige que no haya ofertas con ronda 3 o más.
- Cada cambio de la quinta auditoría tiene su desactivación documentada en
  `docs/AUDITORIA.md`, en su fila.

## Trabajo simultáneo

Dos personas promueven a la vez. Antes de empezar, `git pull` y mirar el libro
mayor: si alguien aplicó algo a producción después de la comparación del paso 1,
repítela. Las reglas están en `CLAUDE.md` (aviso «Two people work on PortGo at the
same time») y en la regla 43b de `docs/AUDITORIA.md`.
