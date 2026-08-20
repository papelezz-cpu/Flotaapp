package mx.portgo.app.di

import android.content.Context
import io.github.jan.supabase.SupabaseClient
import mx.portgo.app.core.SecureSessionStorage
import mx.portgo.app.core.SupabaseFactory
import mx.portgo.app.data.repository.AuthRepository
import mx.portgo.app.data.repository.AvisosRepository
import mx.portgo.app.data.repository.ConfiguracionRepository
import mx.portgo.app.data.repository.FlotaRepository
import mx.portgo.app.data.repository.NotificacionesRepository
import mx.portgo.app.data.repository.PedidosRepository
import mx.portgo.app.data.repository.ReservacionesRepository
import mx.portgo.app.data.repository.StorageRepository

/**
 * Inyección de dependencias a mano.
 *
 * Sin Hilt a propósito: son siete repositorios sin ciclos ni scopes, todos
 * singletons de proceso. Un grafo de este tamaño no justifica añadir
 * procesamiento de anotaciones al build — que es tiempo de compilación en cada
 * cambio y una capa más que entender para quien tome el proyecto después.
 * Si el grafo creciera hasta necesitar scopes de verdad, cambiar a Hilt es
 * mecánico porque los repositorios ya reciben sus dependencias por constructor.
 */
class AppContainer(context: Context) {

    private val appContext = context.applicationContext

    val almacenSesion: SecureSessionStorage by lazy { SecureSessionStorage(appContext) }

    val supabase: SupabaseClient by lazy { SupabaseFactory.create(almacenSesion) }

    val auth: AuthRepository by lazy { AuthRepository(supabase, almacenSesion) }
    val configuracion: ConfiguracionRepository by lazy {
        ConfiguracionRepository(supabase, appContext)
    }
    val pedidos: PedidosRepository by lazy { PedidosRepository(supabase) }
    val reservaciones: ReservacionesRepository by lazy { ReservacionesRepository(supabase) }
    val avisos: AvisosRepository by lazy { AvisosRepository(supabase) }
    val notificaciones: NotificacionesRepository by lazy { NotificacionesRepository(supabase) }
    val flota: FlotaRepository by lazy { FlotaRepository(supabase) }
    val storage: StorageRepository by lazy {
        StorageRepository(supabase, appContext.contentResolver)
    }
}
