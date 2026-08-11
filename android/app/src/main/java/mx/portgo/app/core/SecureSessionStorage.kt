package mx.portgo.app.core

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import io.github.jan.supabase.auth.SessionManager
import io.github.jan.supabase.auth.user.UserSession
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * Persistencia de la sesión de Supabase en EncryptedSharedPreferences, con la
 * clave maestra en el Android Keystore (AES-256-GCM, respaldada por hardware
 * en los equipos que lo tienen).
 *
 * Por qué no vale reusar el criterio de la web: ahí la sesión vive en
 * `sessionStorage` a propósito, para que cerrar el navegador cierre sesión
 * (ver js/config.js y CLAUDE.md). En un teléfono ese equivalente sería pedir
 * correo y contraseña en cada apertura, que nadie tolera en una app que se usa
 * en patio o en el puerto. El compromiso acordado es: el refresh token
 * persiste cifrado, y [BiometricGate] exige huella o rostro para desbloquear
 * la app al reabrirla. La comodidad la da el almacenamiento; la protección, la
 * biometría.
 *
 * El archivo se excluye de backup y de transferencia entre dispositivos (ver
 * res/xml/data_extraction_rules.xml): la clave del Keystore no sale del
 * equipo, así que un respaldo restaurado en otro teléfono solo contendría un
 * blob indescifrable.
 */
class SecureSessionStorage(context: Context) : SessionManager {

    private val json = Json { ignoreUnknownKeys = true }

    private val prefs: SharedPreferences by lazy {
        val masterKey = MasterKey.Builder(context.applicationContext)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()

        EncryptedSharedPreferences.create(
            context.applicationContext,
            PREFS_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    override suspend fun saveSession(session: UserSession) = withContext(Dispatchers.IO) {
        prefs.edit().putString(KEY_SESSION, json.encodeToString(session)).apply()
    }

    override suspend fun loadSession(): UserSession? = withContext(Dispatchers.IO) {
        val raw = prefs.getString(KEY_SESSION, null) ?: return@withContext null
        runCatching { json.decodeFromString<UserSession>(raw) }
            .getOrElse {
                // Un blob que ya no se puede leer (rotación de clave del
                // Keystore tras restaurar el dispositivo, cambio de formato del
                // SDK) no debe dejar la app atorada en un arranque fallido:
                // se descarta y se pide login otra vez.
                prefs.edit().remove(KEY_SESSION).apply()
                null
            }
    }

    override suspend fun deleteSession() = withContext(Dispatchers.IO) {
        prefs.edit().remove(KEY_SESSION).apply()
    }

    /** Correo del último acceso, para prellenar el campo y etiquetar la biometría. */
    var ultimoCorreo: String?
        get() = prefs.getString(KEY_EMAIL, null)
        set(value) = prefs.edit().putString(KEY_EMAIL, value).apply()

    /** El usuario habilitó el desbloqueo biométrico. */
    var biometriaActiva: Boolean
        get() = prefs.getBoolean(KEY_BIOMETRIA, false)
        set(value) = prefs.edit().putBoolean(KEY_BIOMETRIA, value).apply()

    fun limpiarTodo() {
        prefs.edit().clear().apply()
    }

    private companion object {
        const val PREFS_NAME = "portgo_session"
        const val KEY_SESSION = "supabase_session"
        const val KEY_EMAIL = "ultimo_correo"
        const val KEY_BIOMETRIA = "biometria_activa"
    }
}
