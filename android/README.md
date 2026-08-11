# PortGo Android

App nativa en **Kotlin + Jetpack Compose**. Sin frameworks híbridos, sin WebView,
sin wrappers. Cliente del mismo backend de Supabase que la web.

---

## Qué necesitas para compilar

| Requisito | Versión |
|---|---|
| JDK | 17 |
| Android SDK | compileSdk 35 · minSdk 26 |
| Gradle | 8.9 (lo baja el wrapper) |

### Toolchain en este equipo

Ya está instalado con **scoop**, en ámbito de usuario (sin permisos de administrador):

```bash
scoop bucket add java && scoop bucket add extras
scoop install temurin17-jdk gradle android-clt
# licencias del SDK + componentes
yes | ~/scoop/apps/android-clt/current/cmdline-tools/latest/bin/sdkmanager.bat --licenses
~/scoop/apps/android-clt/current/cmdline-tools/latest/bin/sdkmanager.bat \
  --install "platform-tools" "platforms;android-35" "build-tools;35.0.0"
```

`local.properties` apunta al SDK y **no se commitea** (es específico del equipo; está en
`.gitignore`). Android Studio lo regenera solo al abrir el proyecto.

> Nota: scoop instaló Gradle 9.7 en el sistema, pero el proyecto usa el **wrapper**, que
> baja Gradle 8.9 — que es lo que soporta AGP 8.7.3. Compila siempre con `./gradlew`,
> nunca con el `gradle` del sistema.

### Compilar

```bash
cd android
export JAVA_HOME=~/scoop/apps/temurin17-jdk/current   # si no está en el entorno
./gradlew assembleDebug          # APK de depuración
./gradlew installDebug           # instalar en el dispositivo conectado
./gradlew assembleRelease        # requiere configurar la firma
```

El APK sale en `app/build/outputs/apk/debug/app-debug.apk`.

### Estado de compilación

Ambas variantes compilan verde en este equipo:

| Variante | Resultado | Tamaño |
|---|---|---|
| `assembleDebug` | ✅ BUILD SUCCESSFUL | 23 MB |
| `assembleRelease` | ✅ BUILD SUCCESSFUL | 3.4 MB (sin firmar) |

El release corre R8 con minificación y `shrinkResources`, así que el hecho de que pase
valida las reglas de `proguard-rules.pro` — que es donde normalmente truena la
serialización de kotlinx en release mientras el debug funciona perfecto.

`assembleRelease` genera un APK **sin firmar**. Para publicar hace falta agregar un
`signingConfig` en `app/build.gradle.kts` con un keystore propio.

Las credenciales de Supabase salen de `gradle.properties` y entran al código como
`BuildConfig`. Son las mismas que usa la web (`js/config.js`): la anon key es pública por
diseño — la frontera de seguridad son las políticas RLS, no la llave. **La service role
key no existe en ningún punto de esta app.**

> Las versiones del `libs.versions.toml` son las que estaban vigentes al escribir el
> proyecto. Si la sincronización falla por alguna, súbela: `supabase-kt` y Ktor van
> atadas (supabase-kt 3.x exige Ktor 3.x).

---

## Antes de que la app funcione de verdad

| Paso | Estado |
|---|---|
| `20260810120000_rpc_transacciones.sql` | ✅ **aplicada** — verificadas las 17 funciones en producción |
| `20260810140000_catalogos_y_config.sql` | ⏳ pendiente — probada en Postgres local, lista para pegar |
| Deep link `portgo://auth` en Authentication → URL Configuration → Redirect URLs | ⏳ pendiente |
| `20260810130000_sincronizar_estados_OPCIONAL.sql` | ⏳ opcional — toca un guard, lee su encabezado |

Sin la de catálogos la app funciona igual: usa los valores compilados de respaldo, que
son idénticos a los que había antes. Lo que no funciona hasta aplicarla es cambiar esas
listas sin publicar una versión, que es justamente el punto.

---

## Arquitectura

MVVM con una capa de repositorios que aísla el SDK de Supabase.

```
core/          Cliente de Supabase, sesión cifrada, biometría, formato, errores
data/model/    Modelos serializables — espejo del esquema de Postgres
data/repository/  Único punto que habla con Supabase
ui/viewmodel/  Estado de pantalla (StateFlow) y acciones
ui/screens/    Compose, sin lógica de negocio
ui/navigation/ Rutas y barra inferior por rol
di/            AppContainer: grafo manual de dependencias
```

**Sin Hilt** a propósito: son siete repositorios sin ciclos ni scopes. Un grafo así no
justifica sumar procesamiento de anotaciones al build. Los repositorios reciben todo por
constructor, así que migrar a Hilt después es mecánico.

### Flujo de datos

```
Pantalla → ViewModel → Repositorio → supabase-kt → PostgREST / GoTrue / Realtime / Storage
                            ↑
                      Resultado<T>: Ok | Error(AppError)
```

Nada de excepciones cruzando hacia el ViewModel: `Resultado<T>` obliga a decidir qué se
le muestra al usuario en cada caso. En este backend eso importa más de lo normal — una
consulta bloqueada por RLS devuelve **200 con lista vacía**, y confundir "no tienes
permiso" con "no hay nada" es el bug más caro del proyecto.

---

## Decisiones que conviene conocer

### Sesión persistente + biometría

La web guarda la sesión en `sessionStorage` a propósito: cerrar el navegador cierra
sesión. En un teléfono ese equivalente sería teclear correo y contraseña cada vez que se
abre la app, que nadie tolera en algo que se usa en el patio o en el puerto.

El acuerdo aquí: el refresh token vive en **EncryptedSharedPreferences** con la clave
maestra en el **Android Keystore**, y `BiometricGate` exige huella, rostro o PIN al
reabrir. La comodidad la da el almacenamiento; la protección, la biometría. El archivo se
excluye de backup y de transferencia entre dispositivos (`data_extraction_rules.xml`):
la clave del Keystore no sale del equipo, así que un respaldo restaurado en otro teléfono
sería un blob indescifrable.

`DEVICE_CREDENTIAL` va habilitado junto a la biometría porque en flota hay sensores
gastados y operadores con guantes; sin la alternativa del PIN la app quedaría inservible
justo donde se usa.

### Las acciones van por RPC, no por escrituras sueltas

Cancelar una reservación son siete escrituras que tienen que pasar juntas: cancelar,
liberar la unidad, reabrir el pedido, invalidar dos grupos de ofertas y avisar a dos
partes. En la web eso vive suelto en el navegador y **ya se rompió antes** (existe la
migración `20260728120000` justo por una de esas roturas).

Esta app no reimplementa esa coreografía: llama `cancelar_reservacion(...)` y el servidor
la ejecuta en una transacción. Lo mismo con ofertar, responder ofertas, avanzar
seguimiento, cerrar servicio, calificar y mandar mensajes.

Efecto secundario deseado: el candado anti-desintermediación del chat (no compartir
teléfonos) ahora se aplica en el servidor. En la web vive solo en el navegador, así que
cualquier cliente que no lo implemente lo salta — incluida esta app, si el mensaje fuera
un INSERT directo.

Lo que **sí** queda como escritura directa: publicar una solicitud (un solo INSERT que
RLS cubre; envolverlo obligaría a versionar sus ~60 columnas dentro de una función de
Postgres) y marcar notificaciones como leídas.

### Catálogos remotos: evitar publicar por cada cambio de negocio

Una app publicada queda congelada en el teléfono. En la web, cambiar "metros
cúbicos" por "tarimas" costó un commit; en móvil costaría un build, la revisión de la
tienda, y meses de usuarios con la versión vieja.

El historial dice qué cambia: de los últimos 15 commits, **cinco tocan el formulario de
solicitud**. Así que esas listas no viven en el binario:

| Antes (compilado) | Ahora |
|---|---|
| `PLAZOS_PAGO`, `TIPOS_CONTENEDOR`, `UNIDADES` | catálogo `plazo_pago`, `tipo_contenedor`, `tipo_unidad` |
| `enum CategoriaCarga` + propiedades `pide*` | catálogo `categoria_carga`, con `meta.campos` |
| `object Tracking` con los 5 pasos por recurso | catálogo `tracking_camion`, `tracking_custodio`… |

Todo llega en **una sola llamada** (`arranque_app`), porque esto corre en el puerto con
señal mala y cada viaje de red extra es otra forma de quedarse colgado en el arranque.

Tres niveles de respaldo, en este orden: caché en disco → valores compilados idénticos a
los de antes → la app **siempre** abre, con o sin red. Si un catálogo llega vacío por un
error de captura, se usa el respaldo en vez de mostrar un desplegable vacío.

Los catálogos se leen con `LocalCatalogos.current` (un `CompositionLocal`): son ambiente,
no datos, y las necesitan pantallas muy separadas del árbol.

### Versión mínima y aviso global

`app_config` permite dos cosas sin publicar nada:

- **Bloquear versiones viejas** — se sube `version_minima_android` y las anteriores se
  detienen en [PantallaActualizar](app/src/main/java/mx/portgo/app/ui/screens/auth/PantallaActualizar.kt),
  **antes del login**, sin poder saltárselo. No evita publicar versiones: hace que
  publicarlas sea seguro, porque una app vieja que escribiría datos mal se puede parar en
  seco. Sembrado en `0.0.0`, que no bloquea a nadie.
- **Mostrar un aviso** — mantenimiento, un cambio de proceso, un problema conocido.

Por eso `app_config` es legible **sin sesión**: la comprobación tiene que correr antes de
que nadie se autentique.

### Realtime acotado

La web escucha siete tablas completas (`portgo-changes` en `js/main.js`). En un teléfono
eso es batería y datos para refrescar pantallas que casi nunca están visibles.

Aquí hay dos canales y solo dos: `notif-{userId}` (permanente, alimenta la campana) y el
del hilo de chat abierto, que se cierra al salir de la pantalla. El resto se refresca al
entrar y con deslizar hacia abajo.

### Qué se dejó fuera, y por qué

| Fuera del MVP | Razón |
|---|---|
| **Registro de cuenta** | ~25 campos fiscales, hasta 8 documentos, y revisión manual de hasta 2 días. Trámite de escritorio que se hace una vez. La app lo abre en el navegador del sistema. |
| **Alta y edición de flota** | ~35 campos y cuatro documentos con vigencias por unidad; cada cambio redispara la aprobación del superadmin. La app **sí** consulta la flota, avisa de vigencias por vencer y permite sacar una unidad de servicio. |
| **Rol superadmin** | Su panel (aprobaciones, reportes, vigencias, gestión de usuarios) son tablas densas de escritorio. Si un superadmin inicia sesión, la app se lo dice y lo manda a la web. |
| **Push notifications** | Decisión acordada. Requiere tabla de device tokens, Edge Function con credenciales de APNs/FCM y cuenta de Apple Developer. Hoy: Realtime en primer plano + campana al reabrir, igual que la web. La capa de notificaciones está aislada para añadirlo sin retrabajo. |

---

## Divergencias conocidas con la web

Van documentadas porque son decisiones, no descuidos.

**1. Fecha local vs. UTC.** `today()` en `js/utils.js` hace
`new Date().toISOString().split('T')[0]`, que es **UTC**: entre las 18:00 y la medianoche
de México la web ya cree que es el día siguiente. `Fmt.hoy()` usa la fecha local de
`America/Mexico_City`, que es la correcta para un campo `date` que el usuario elige en un
calendario. El efecto práctico es chico (marcar una unidad como ocupada unas horas
antes), pero conviene corregirlo del lado web para que ambos coincidan.

**2. Reservaciones del cliente por `cliente_user_id`.** La web filtra por `cliente_email`
(`js/reservaciones.js:75`), así que alguien que cambió de correo pierde de vista su
historial. Esta app consulta por `cliente_user_id` **o** correo, para no heredar el hueco.

**3. Pasos de seguimiento.** `CLAUDE.md` documenta seis pasos para camión
(`Confirmado→En camino→En puerto→Cargando→En tránsito→Entregado`). El código vigente tiene
cinco y usa `En carga`. Manda el código: la app y la función `tracking_pasos()` de la base
replican los cinco de `js/tracking.js`.

**4. Cuentas suspendidas.** El bloqueo de cuentas `pendiente` / `rechazada` / `suspendida`
es **client-side** en la web y no está en RLS (gap G4 del análisis, que quedó fuera de
alcance por ahora). Esta app lo replica en `AuthRepository.evaluarPerfil()`. Mientras el
gate no baje a RLS, **es obligatorio**: sin él, la app sería la puerta de entrada para
cuentas bloqueadas.

---

## Pendiente antes de dar por cerrada la app

- [x] ~~Generar `gradle-wrapper.jar`~~ — hecho, el wrapper está en el repo.
- [x] ~~Compilar~~ — debug y release compilan verde (ver arriba).
- [ ] **Correr `supabase db pull`** y ajustar la nullability de los modelos. Hoy casi todo
      es opcional porque la línea base del esquema no está en el repo (gap G3): faltan los
      `CREATE TABLE` originales, solo hay migraciones incrementales.
- [ ] Aplicar la migración de RPCs y registrar el deep link (`supabase/aplicar-migraciones.sh`).
- [ ] **Ejecutar la app contra el Supabase real.** Compilar prueba que el código es válido,
      no que funciona: falta verificar login, RLS, Realtime y subida de archivos con datos
      de verdad, en un dispositivo o emulador.
- [ ] Iconos de lanzador en PNG por densidad. Hoy hay un icono adaptativo vectorial, que
      funciona en API 26+ (el `minSdk`), pero conviene un set diseñado.
- [ ] Firma de release: `assembleRelease` produce un APK sin firmar.
- [ ] Pruebas: no hay ninguna, igual que en el resto del proyecto. Los candidatos obvios
      son `Fmt`, `AppError.de()` y los enums con su `desconocido` de respaldo — lógica
      pura, sin Android, barata de cubrir.
