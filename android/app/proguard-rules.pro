# ── kotlinx.serialization ─────────────────────────────────────────────────
# Los modelos se serializan por reflexión sobre el serializer generado; sin
# esto R8 borra los métodos estáticos y el release truena al decodificar la
# primera respuesta de PostgREST — con el debug funcionando perfecto.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**

-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}

-keep,includedescriptorclasses class mx.portgo.app.data.model.**$$serializer { *; }
-keepclassmembers class mx.portgo.app.data.model.** {
    *** Companion;
}
-keepclasseswithmembers class mx.portgo.app.data.model.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# ── Ktor / OkHttp ─────────────────────────────────────────────────────────
-dontwarn org.slf4j.**
-dontwarn okhttp3.**
-dontwarn okio.**
-keepclassmembers class io.ktor.** { volatile <fields>; }

# ── supabase-kt ───────────────────────────────────────────────────────────
-keep class io.github.jan.supabase.** { *; }
-dontwarn io.github.jan.supabase.**

# ── Tink (androidx.security-crypto) ───────────────────────────────────────
# Tink referencia anotaciones de Error Prone que solo existen en tiempo de
# compilación y no viajan en el artefacto. R8 las reporta como clases faltantes
# y aborta. No hay nada que conservar: son anotaciones, no código en ejecución.
-dontwarn com.google.errorprone.annotations.**
