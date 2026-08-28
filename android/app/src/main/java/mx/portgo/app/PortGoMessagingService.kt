package mx.portgo.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Recibe los avisos push de FCM y los pinta en la bandeja del sistema.
 *
 * Solo entra en juego con la app cerrada o en segundo plano. Con la app abierta
 * el aviso ya llega por Realtime a la campana, que es más inmediato y no
 * depende de Google.
 */
class PortGoMessagingService : FirebaseMessagingService() {

    /**
     * FCM entrega aquí el token nuevo cuando lo rota.
     *
     * No se registra desde aquí: en este punto puede no haber sesión —el
     * servicio arranca aunque el usuario no haya entrado— y escribir sin sesión
     * fallaría por RLS. El registro lo hace [mx.portgo.app.data.repository.PushRepository]
     * en cada arranque con sesión activa, que cubre este caso sin necesidad de
     * coordinar nada.
     */
    override fun onNewToken(token: String) {
        super.onNewToken(token)
    }

    override fun onMessageReceived(mensaje: RemoteMessage) {
        super.onMessageReceived(mensaje)

        val titulo = mensaje.notification?.title ?: mensaje.data["titulo"] ?: return
        val cuerpo = mensaje.notification?.body  ?: mensaje.data["mensaje"].orEmpty()

        asegurarCanal()

        // Al tocar el aviso se abre la app. Los datos del mensaje viajan en el
        // intent para que MainActivity pueda llevar a la pantalla concreta:
        // `tipo` siempre, y lo que traiga `meta` de la notificación original.
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            mensaje.data.forEach { (k, v) -> putExtra(k, v) }
        }
        val pendiente = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val aviso = NotificationCompat.Builder(this, CANAL)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle(titulo)
            .setContentText(cuerpo)
            .setStyle(NotificationCompat.BigTextStyle().bigText(cuerpo))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendiente)
            .build()

        // El id se deriva del instante: así dos avisos seguidos no se pisan.
        // Si algún día conviene agrupar por servicio, aquí es donde se cambia.
        if (NotificationManagerCompat.from(this).areNotificationsEnabled()) {
            NotificationManagerCompat.from(this)
                .notify(System.currentTimeMillis().toInt(), aviso)
        }
    }

    /**
     * Desde Android 8 todo aviso necesita un canal, y el id tiene que coincidir
     * con el `channel_id` que manda la Edge Function. Crearlo es idempotente.
     */
    private fun asegurarCanal() {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.O) return
        val canal = NotificationChannel(
            CANAL, "Avisos de PortGo", NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Solicitudes, ofertas y cambios en tus servicios"
        }
        getSystemService(Context.NOTIFICATION_SERVICE)
            .let { it as NotificationManager }
            .createNotificationChannel(canal)
    }

    companion object {
        /** Debe coincidir con `android.notification.channel_id` de la Edge Function. */
        const val CANAL = "portgo_avisos"
    }
}
