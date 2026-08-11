package mx.portgo.app

import android.app.Application
import mx.portgo.app.di.AppContainer

class PortGoApplication : Application() {

    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
    }
}
