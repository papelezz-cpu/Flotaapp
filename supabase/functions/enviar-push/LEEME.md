# Push en Android — lo que falta para encenderlo

Todo el código está escrito y aplicado. **El push no se envía todavía** porque
faltan cuatro cosas que dependen de cuentas externas y no se pueden hacer desde
el repositorio.

Mientras no se hagan, nada se rompe: el trigger comprueba si los secretos
existen y, si no, sale sin hacer nada. La campana en tiempo real sigue
funcionando igual, que es lo que cubre el caso «app abierta».

---

## 1 · Crear el proyecto de Firebase

En <https://console.firebase.google.com>, proyecto nuevo, y dentro añadir una
app **Android** con el `applicationId` exacto:

```
mx.portgo.app
```

Ojo: el build de depuración usa `mx.portgo.app.debug` (`applicationIdSuffix`).
Si quieres probar en debug, registra **las dos** en Firebase.

Descarga el `google-services.json` que genera y colócalo en:

```
android/app/google-services.json
```

**Ese archivo no debe subirse al repositorio.** Añádelo a `.gitignore`.

## 2 · Activar el plugin de Google en Gradle

Solo cuando el `google-services.json` esté en su sitio, porque el plugin falla
el build si no lo encuentra. Dos líneas:

En `android/gradle/libs.versions.toml`, dentro de `[versions]` y `[plugins]`:

```toml
googleServices = "4.4.2"
google-services = { id = "com.google.gms.google-services", version.ref = "googleServices" }
```

En `android/app/build.gradle.kts`, dentro del bloque `plugins { }`:

```kotlin
alias(libs.plugins.google.services)
```

La dependencia `firebase-messaging` **ya está puesta** y compila sin el plugin;
lo único que el plugin hace es procesar el JSON de configuración.

## 3 · Crear la cuenta de servicio y los secretos de la Edge Function

En Firebase → Configuración del proyecto → **Cuentas de servicio** → *Generar
nueva clave privada*. Descarga el JSON.

En Supabase → Edge Functions → **Secrets**, crea tres:

| Secreto | Valor |
|---|---|
| `FIREBASE_SERVICE_ACCOUNT` | El JSON completo de la cuenta de servicio, **en una sola línea** |
| `PUSH_SERVICE_KEY` | Una cadena aleatoria larga que inventes. Es la credencial con la que la base se identifica al llamar a la función |
| `SUPABASE_SERVICE_ROLE_KEY` | Suele estar ya; si no, la del proyecto |

Se usa FCM HTTP v1, no la API antigua de clave de servidor: esa está retirada
desde 2024 y por eso hace falta la cuenta de servicio en vez de una clave
simple.

## 4 · Desplegar la función y decirle a la base dónde está

```bash
supabase functions deploy enviar-push --project-ref <ref-del-proyecto>
```

Y después, en el **SQL Editor** de ese proyecto:

```sql
-- El mismo valor de PUSH_SERVICE_KEY del paso 3.
select vault.create_secret(
  'https://<ref>.supabase.co/functions/v1/enviar-push',
  'push_endpoint',
  'Destino del trigger de push');

select vault.create_secret(
  '<el mismo PUSH_SERVICE_KEY>',
  'push_service_key',
  'Credencial con la que la base llama a enviar-push');
```

En cuanto existan esos dos secretos, el trigger empieza a disparar. No hay que
reaplicar ninguna migración.

**Hazlo primero en `portgo-pruebas`.** Con un proyecto de Firebase distinto, o
al menos comprobando que los avisos de prueba no llegan a teléfonos reales.

---

## Cómo comprobar que funciona

```sql
-- 1. ¿Está configurado?
select name from vault.decrypted_secrets where name like 'push%';

-- 2. ¿Hay algún dispositivo registrado? (requiere haber entrado en la app)
select user_id, plataforma, modelo, visto_en from dispositivos_push;

-- 3. Provocar un aviso de un tipo que sí empuja
insert into notificaciones (user_id, tipo, titulo, mensaje, leido)
values ('<uuid-de-un-usuario-con-dispositivo>', 'nueva_solicitud',
        'Prueba de push', 'Si ves esto en el telefono, funciona', false);

-- 4. ¿Salió la petición? pg_net guarda el resultado un rato
select id, status_code, content from net._http_response order by id desc limit 5;
```

## Qué tipos despiertan el teléfono

Diez de los treinta y siete que existen, los que exigen una acción con ventana
de tiempo. La lista vive en `catalogos` y se cambia sin desplegar:

```sql
select valor, etiqueta from catalogos where clave = 'push_tipos' and activo;

-- Añadir uno:
insert into catalogos (clave, valor, etiqueta, orden, activo)
values ('push_tipos', 'servicio_completado', 'Servicio completado', 11, true);

-- Silenciar uno sin borrarlo:
update catalogos set activo = false
 where clave = 'push_tipos' and valor = 'tracking_actualizado';
```

Empujarlos todos sería el error que el propio código ya evitó con la campana:
*«una empresa que solo tiene plataformas recibía aviso de cada torton, y eso
entrena a ignorar la campana.»*

## Lo que queda sin hacer, a propósito

- **El permiso de Android 13+.** `POST_NOTIFICATIONS` está declarado en el
  manifiesto, pero nadie lo pide en tiempo de ejecución todavía. Sin pedirlo, en
  Android 13 o superior los avisos no se muestran aunque lleguen. Es una
  pantalla de permiso que conviene colocar donde tenga sentido en el flujo, no
  al arrancar en frío.
- **Navegar al tocar el aviso.** El servicio mete `tipo` y el `meta` de la
  notificación en el intent, pero `MainActivity` no los lee todavía: hoy el
  aviso abre la app en la pantalla donde estuviera.
- **iOS y web.** La tabla admite `plataforma`, pero solo Android está
  implementado. Web Push en iOS exige que el usuario instale la PWA en la
  pantalla de inicio, y el PWA se usa sobre todo en escritorio, donde el correo
  ya cumple.
