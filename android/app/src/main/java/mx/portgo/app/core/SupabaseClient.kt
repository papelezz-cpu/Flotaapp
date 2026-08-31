package mx.portgo.app.core

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.FlowType
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.functions.Functions
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.realtime.Realtime
import io.github.jan.supabase.serializer.KotlinXSerializer
import io.github.jan.supabase.storage.Storage
import kotlinx.serialization.json.Json
import mx.portgo.app.BuildConfig

/**
 * Cliente único contra el mismo proyecto de Supabase que usa la web.
 *
 * La anon key es pública por diseño: quien la tenga solo puede hacer lo que
 * las políticas RLS permitan a un `authenticated` (o a `anon`). La frontera de
 * seguridad son las políticas, no la llave. La service role key no existe en
 * ninguna parte de esta app.
 */
object SupabaseFactory {

    /**
     * `ignoreUnknownKeys` es obligatorio, no una comodidad: `pedidos` tiene
     * ~60 columnas y el esquema crece con cada migración. Sin esto, la primera
     * columna que alguien agregue en la web rompe la app publicada.
     *
     * `explicitNulls = false` evita mandar `"campo": null` en cada insert, que
     * pisaría defaults de la base con NULL.
     */
    val json: Json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        coerceInputValues = true
        isLenient = true
    }

    fun create(sessionStorage: SecureSessionStorage): SupabaseClient =
        createSupabaseClient(
            supabaseUrl = BuildConfig.SUPABASE_URL,
            supabaseKey = BuildConfig.SUPABASE_ANON_KEY,
        ) {
            defaultSerializer = KotlinXSerializer(json)

            install(Auth) {
                sessionManager = sessionStorage
                alwaysAutoRefresh = true
                autoLoadFromStorage = true
                // PKCE para el enlace de recuperación de contraseña: el código
                // se canjea en el dispositivo que lo pidió, no en el navegador
                // que abrió el correo.
                flowType = FlowType.PKCE
                scheme = "portgo"
                host = "auth"
            }

            install(Postgrest)
            install(Realtime)
            install(Storage)
            // Para `enviar-notificacion`, la Edge Function del correo. La app
            // solo escribia la campana, asi que un aviso mandado desde el
            // telefono no llegaba a quien no tuviera la app abierta.
            install(Functions)
        }
}
