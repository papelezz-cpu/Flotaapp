package mx.portgo.app.data.repository

import android.os.Build
import android.util.Log
import com.google.firebase.messaging.FirebaseMessaging
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import kotlinx.coroutines.tasks.await
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import mx.portgo.app.core.Resultado
import mx.portgo.app.core.intentar

/**
 * Registro del dispositivo para recibir avisos push.
 *
 * El push cubre el caso "app cerrada". Con la app abierta ya funciona la
 * campana en tiempo real, porque `notificaciones` está publicada por Realtime y
 * [NotificacionesRepository] se suscribe con filtro por usuario. Esto no
 * reemplaza aquello: lo complementa.
 *
 * Qué se envía NO se decide aquí sino en la base: un trigger sobre
 * `notificaciones` filtra por los tipos marcados en el catálogo `push_tipos` y
 * llama a la Edge Function `enviar-push`. Así los tres clientes comparten una
 * sola definición, y el aviso sale aunque quien lo provocó cierre su sesión a
 * mitad —que es el fallo que tiene hoy el correo, disparado desde el cliente.
 */
class PushRepository(private val supabase: SupabaseClient) {

    @Serializable
    private data class Dispositivo(
        @SerialName("user_id") val userId: String,
        val token: String,
        val plataforma: String = "android",
        val modelo: String? = null,
    )

    /**
     * Se llama en cada arranque con sesión activa, no solo la primera vez.
     *
     * FCM rota el token por su cuenta —al restaurar el dispositivo, al limpiar
     * los datos de la app, o cuando le parece—, así que registrarlo una única
     * vez al instalar dejaría de funcionar en silencio meses después.
     *
     * Se hace como borrar-e-insertar en lugar de un upsert: la tabla tiene
     * UNIQUE sobre `token`, y así el mismo aparato que cambia de usuario queda
     * asociado solo al actual. Reenviar el mismo token es idempotente y de paso
     * refresca `visto_en`, que es lo que usa la purga mensual para distinguir un
     * dispositivo vivo de uno desinstalado.
     */
    suspend fun registrar(userId: String): Resultado<Unit> = intentar {
        val token = FirebaseMessaging.getInstance().token.await()
        supabase.from("dispositivos_push").delete { filter { eq("token", token) } }
        supabase.from("dispositivos_push").insert(
            Dispositivo(
                userId = userId,
                token  = token,
                modelo = "${Build.MANUFACTURER} ${Build.MODEL}",
            )
        )
        Log.d(TAG, "dispositivo registrado para push")
    }

    /**
     * Al cerrar sesión se retira el token de ESTE dispositivo.
     *
     * Sin esto, el siguiente usuario que entre en el mismo teléfono seguiría
     * recibiendo los avisos del anterior: el token identifica al aparato, no a
     * la cuenta. Es el mismo motivo por el que la sesión vive cifrada y se
     * limpia al salir.
     */
    suspend fun retirar(): Resultado<Unit> = intentar {
        val token = FirebaseMessaging.getInstance().token.await()
        supabase.from("dispositivos_push").delete { filter { eq("token", token) } }
        // También en el propio FCM, para que deje de entregar a este aparato
        // aunque la fila sobreviviera por cualquier motivo.
        FirebaseMessaging.getInstance().deleteToken().await()
    }

    private companion object { const val TAG = "PushRepository" }
}
