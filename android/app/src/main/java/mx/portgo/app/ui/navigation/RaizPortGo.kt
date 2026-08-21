package mx.portgo.app.ui.navigation

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.WarningAmber
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import mx.portgo.app.data.model.Rol
import mx.portgo.app.di.AppContainer
import mx.portgo.app.ui.LocalCatalogos
import mx.portgo.app.ui.SesionViewModel
import mx.portgo.app.ui.components.BarraInferiorPortGo
import mx.portgo.app.ui.components.CargandoCentrado
import mx.portgo.app.ui.components.EncabezadoPortGo
import mx.portgo.app.ui.components.RecargarAlVolver
import mx.portgo.app.ui.screens.auth.PantallaActualizar
import mx.portgo.app.ui.screens.auth.PantallaBloqueo
import mx.portgo.app.ui.screens.auth.PantallaNuevaContrasena
import mx.portgo.app.ui.screens.auth.PantallaLogin
import mx.portgo.app.ui.screens.expedientes.PantallaExpediente
import mx.portgo.app.ui.screens.flota.PantallaAltaCamion
import mx.portgo.app.ui.screens.flota.PantallaFlota
import mx.portgo.app.ui.screens.inicio.PantallaInicio
import mx.portgo.app.ui.screens.notificaciones.PantallaNotificaciones
import mx.portgo.app.ui.screens.PantallaPendiente
import mx.portgo.app.ui.screens.perfil.PantallaPerfil
import mx.portgo.app.ui.screens.reservaciones.PantallaReservacionDetalle
import mx.portgo.app.ui.screens.reservaciones.PantallaReservaciones
import mx.portgo.app.ui.screens.solicitudes.PantallaNuevaSolicitud
import mx.portgo.app.ui.screens.solicitudes.PantallaSolicitudDetalle
import mx.portgo.app.ui.screens.solicitudes.PantallaSolicitudes
import mx.portgo.app.ui.theme.ColoresEstado
import mx.portgo.app.ui.theme.PortGoColor
import mx.portgo.app.ui.viewmodel.NotificacionesViewModel
import mx.portgo.app.ui.viewmodel.vmFactory

/** Decide qué se ve según el estado de la sesión. */
@Composable
fun RaizPortGo(
    estado: SesionViewModel.Estado,
    sesionVm: SesionViewModel,
    container: AppContainer,
    activity: FragmentActivity,
    recuperacionEnCurso: Boolean = false,
    onRecuperacionResuelta: () -> Unit = {},
    errorEnlace: String? = null,
    onErrorEnlaceVisto: () -> Unit = {},
) {
    // Catálogos y configuración remota. Se piden una vez al arrancar; mientras
    // llegan, el StateFlow ya trae lo que había en disco (o el respaldo
    // compilado), así que nada espera por la red.
    val catalogos by container.configuracion.catalogos.collectAsStateWithLifecycle()
    val estadoApp by container.configuracion.estado.collectAsStateWithLifecycle()

    LaunchedEffect(Unit) { container.configuracion.refrescar() }

    // El bloqueo por versión va ANTES que todo, incluido el login: una versión
    // incompatible no debe llegar siquiera a autenticarse.
    if (!estadoApp.soportada) {
        PantallaActualizar(
            versionMinima = estadoApp.versionMinima,
            urlDescarga = estadoApp.urlDescarga,
        )
        return
    }

    // El enlace del correo de recuperación gana sobre cualquier otra pantalla,
    // incluida una sesión ya abierta: el usuario viene de su correo justamente
    // porque no puede entrar, o porque quiere cambiar la contraseña.
    if (recuperacionEnCurso) {
        PantallaNuevaContrasena(
            vm = sesionVm,
            onListo = {
                onRecuperacionResuelta()
                // Se cierra la sesión del enlace: entrar con la contraseña
                // nueva confirma que se recuerda, e invalida el correo.
                sesionVm.cerrarSesion()
            },
        )
        return
    }

    CompositionLocalProvider(LocalCatalogos provides catalogos) {
        when (estado) {
            is SesionViewModel.Estado.Cargando -> CargandoCentrado()

            is SesionViewModel.Estado.SinSesion -> {
                // Los ViewModels viven en el store de la Activity, que sobrevive
                // al cierre de sesión. Las claves por usuario ya impiden que el
                // siguiente reciba instancias ajenas; esto vacía además lo que
                // el anterior dejó cargado en memoria, en vez de esperar a que
                // muera la Activity.
                val duenoStore = LocalViewModelStoreOwner.current
                LaunchedEffect(Unit) { duenoStore?.viewModelStore?.clear() }

                PantallaLogin(
                    vm = sesionVm,
                    // Si el enlace del correo falló, el motivo tiene prioridad:
                    // es lo que el usuario intenta entender en ese momento.
                    mensajeInicial = errorEnlace ?: estado.mensaje,
                    onMensajeVisto = onErrorEnlaceVisto,
                )
            }

            is SesionViewModel.Estado.Bloqueada -> PantallaBloqueo(
                usuario = estado.usuario,
                activity = activity,
                onDesbloqueado = sesionVm::desbloquear,
                onSalir = sesionVm::cancelarDesbloqueo,
            )

            is SesionViewModel.Estado.Dentro -> NavegacionPrincipal(
                usuario = estado.usuario,
                container = container,
                onCerrarSesion = sesionVm::cerrarSesion,
                sesionVm = sesionVm,
            )
        }

        // Aviso que el superadmin puede publicar desde `app_config` sin sacar
        // una versión: mantenimiento programado, un cambio de proceso, un
        // problema conocido. Se muestra una vez por apertura de la app — no en
        // cada recomposición ni en cada cambio de pantalla.
        AvisoGlobalDialogo(estadoApp.aviso)
    }
}

@Composable
private fun AvisoGlobalDialogo(aviso: mx.portgo.app.data.model.AvisoGlobal?) {
    if (aviso == null) return

    // La clave incluye el contenido: si el superadmin publica un aviso nuevo,
    // vuelve a aparecer aunque el usuario ya hubiera cerrado el anterior.
    var visto by rememberSaveable(aviso.titulo + aviso.mensaje) { mutableStateOf(false) }
    if (visto) return

    AlertDialog(
        onDismissRequest = { visto = true },
        icon = {
            Icon(
                if (aviso.tipo == "alerta") Icons.Default.WarningAmber else Icons.Default.Info,
                contentDescription = null,
                tint = if (aviso.tipo == "alerta") ColoresEstado.alerta else ColoresEstado.info,
            )
        },
        title = { Text(aviso.titulo) },
        text = { Text(aviso.mensaje) },
        confirmButton = {
            TextButton(onClick = { visto = true }) { Text("Entendido") }
        },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NavegacionPrincipal(
    usuario: mx.portgo.app.data.model.UsuarioActual,
    container: AppContainer,
    onCerrarSesion: () -> Unit,
    sesionVm: SesionViewModel,
) {
    val nav: NavHostController = rememberNavController()
    val destinos = remember(usuario.rol) { pestanasDe(usuario.rol) }
    val snackbar = remember { SnackbarHostState() }

    // La campana vive en el andamio, no en cada pantalla: es global y así el
    // contador es uno solo, alimentado por un único canal de Realtime.
    //
    // La clave lleva el id del usuario a propósito, y lo mismo hacen todas las
    // demás pantallas. Sin ella, `viewModel()` devuelve SIEMPRE la misma
    // instancia mientras viva la Activity: al cambiar de cuenta sin cerrar la
    // app, el ViewModel del usuario anterior seguía en pie con sus datos en
    // pantalla. RLS impide leer lo ajeno del servidor, pero lo que ya estaba
    // cargado en memoria quedaba a la vista de quien entrara después.
    val notifVm: NotificacionesViewModel = viewModel(
        key = usuario.id,
        factory = vmFactory { NotificacionesViewModel(container.notificaciones, usuario) },
    )
    val noLeidas by notifVm.noLeidas.collectAsStateWithLifecycle()

    // El contador se cargaba al arrancar y se mantenia por Realtime. Pero
    // mientras la app esta en segundo plano —que es justo cuando el otro lado
    // hace su parte desde la web— el canal se cae y los avisos que llegan
    // entretanto no se cuentan. Al volver, se relee.
    RecargarAlVolver(notifVm::cargar)

    val entradaActual by nav.currentBackStackEntryAsState()
    val rutaActual = entradaActual?.destination?.route
    val esRaiz = destinos.any { it.ruta == rutaActual }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbar) },
        bottomBar = {
            AnimatedVisibility(visible = esRaiz) {
                BarraInferiorPortGo(
                    pestanas = destinos,
                    rutaActual = rutaActual,
                    onPestana = { ruta ->
                        nav.navigate(ruta) {
                            // Sin esto, cambiar de pestana apila pantallas y el
                            // boton atras recorre todo el historial de pestanas
                            // antes de salir.
                            popUpTo(nav.graph.findStartDestination().id) { saveState = true }
                            launchSingleTop = true
                            restoreState = true
                        }
                    },
                    etiquetaAccion = etiquetaAccion(usuario.rol),
                    // El handoff destaca la etiqueta cuando la pantalla actual
                    // es el destino natural de la accion.
                    accionDestacada = rutaActual == Rutas.INICIO,
                    onAccion = { nav.navigate(rutaAccion(usuario.rol)) },
                )
            }
        },
    ) { relleno ->
        Box(
            Modifier
                .fillMaxSize()
                .background(PortGoColor.Arena)
                .padding(relleno),
        ) {
            NavHost(navController = nav, startDestination = Rutas.INICIO) {

                composable(Rutas.INICIO) {
                    Column(Modifier.fillMaxSize()) {
                        EncabezadoPortGo(
                            esInicio = true,
                            titulo = "",
                            noLeidas = noLeidas,
                            onCampana = { nav.navigate(Rutas.NOTIFICACIONES) },
                        )
                        PantallaInicio(
                            usuario = usuario,
                            container = container,
                            onIrA = { ruta -> nav.navigate(ruta) },
                        )
                    }
                }

                composable(Rutas.SOLICITUDES) {
                    PantallaSolicitudes(
                        usuario = usuario,
                        container = container,
                        onAbrir = { nav.navigate(Rutas.solicitud(it)) },
                        // El boton de atras solo si hay a donde volver: en una
                        // pestana de la barra inferior seria un boton muerto.
                        onAtras = if (nav.previousBackStackEntry != null) {
                            { nav.popBackStack() }
                        } else null,
                        noLeidas = noLeidas,
                        onCampana = { nav.navigate(Rutas.NOTIFICACIONES) },
                    )
                }

                composable(
                    Rutas.SOLICITUD_PATRON,
                    arguments = listOf(navArgument("pedidoId") { type = NavType.StringType }),
                ) { entrada ->
                    PantallaSolicitudDetalle(
                        pedidoId = entrada.arguments?.getString("pedidoId").orEmpty(),
                        usuario = usuario,
                        container = container,
                        onAtras = { nav.popBackStack() },
                    )
                }

                composable(Rutas.NUEVA_SOLICITUD) {
                    PantallaNuevaSolicitud(
                        usuario = usuario,
                        container = container,
                        onAtras = { nav.popBackStack() },
                        onPublicada = {
                            nav.popBackStack()
                        },
                    )
                }

                composable(Rutas.RESERVACIONES) {
                    PantallaReservaciones(
                        usuario = usuario,
                        container = container,
                        onAbrir = { nav.navigate(Rutas.reservacion(it)) },
                        onAtras = if (nav.previousBackStackEntry != null) {
                            { nav.popBackStack() }
                        } else null,
                        noLeidas = noLeidas,
                        onCampana = { nav.navigate(Rutas.NOTIFICACIONES) },
                    )
                }

                composable(
                    Rutas.RESERVACION_PATRON,
                    arguments = listOf(navArgument("reservaId") { type = NavType.StringType }),
                ) { entrada ->
                    PantallaReservacionDetalle(
                        reservaId = entrada.arguments?.getString("reservaId").orEmpty(),
                        usuario = usuario,
                        container = container,
                        onAtras = { nav.popBackStack() },
                        onAbrirExpediente = { reservaId, etapa ->
                            nav.navigate(Rutas.expediente(reservaId, etapa))
                        },
                    )
                }

                composable(
                    Rutas.EXPEDIENTE_PATRON,
                    arguments = listOf(
                        navArgument("reservaId") { type = NavType.StringType },
                        navArgument("etapa") { type = NavType.StringType },
                    ),
                ) { entrada ->
                    PantallaExpediente(
                        reservaId = entrada.arguments?.getString("reservaId").orEmpty(),
                        etapaClave = entrada.arguments?.getString("etapa").orEmpty(),
                        usuario = usuario,
                        container = container,
                        onAtras = { nav.popBackStack() },
                    )
                }


                composable(Rutas.NOTIFICACIONES) {
                    PantallaNotificaciones(
                        vm = notifVm,
                        onAtras = { nav.popBackStack() },
                        onNavegar = { ruta -> nav.navigate(ruta) },
                    )
                }

                if (usuario.rol == Rol.EMPRESA) {
                    composable(Rutas.FLOTA) {
                        PantallaFlota(
                            usuario = usuario,
                            container = container,
                            onNuevaUnidad = { nav.navigate(Rutas.ALTA_CAMION) },
                            onAtras = if (nav.previousBackStackEntry != null) {
                                { nav.popBackStack() }
                            } else null,
                        )
                    }
                }


                if (usuario.rol == Rol.EMPRESA) {
                    composable(Rutas.ALTA_CAMION) {
                        PantallaAltaCamion(
                            usuario = usuario,
                            container = container,
                            onAtras = { nav.popBackStack() },
                            onGuardada = { nav.popBackStack() },
                        )
                    }
                }


                // Modulos que el diseno ya coloca en el inicio pero que todavia
                // no estan construidos. Muestran a donde van en vez de fingir.
                composable(Rutas.CATALOGO) {
                    PantallaPendiente("Catálogo", "Directorio de empresas verificadas con sus unidades y calificaciones.", onAtras = { nav.popBackStack() })
                }
                composable(Rutas.PAGOS) {
                    PantallaPendiente("Mis pagos", "Consulta de lo que has pagado y lo que está por vencer.", onAtras = { nav.popBackStack() })
                }
                composable(Rutas.PRIVACIDAD) {
                    PantallaPendiente("Privacidad", "Tus datos y las solicitudes de derechos ARCO.", onAtras = { nav.popBackStack() })
                }
                composable(Rutas.VIGENCIAS) {
                    PantallaPendiente("Vigencias", "Seguimiento de todos los documentos de tu flota y su vencimiento.", onAtras = { nav.popBackStack() })
                }
                composable(Rutas.OPERADORES) {
                    PantallaPendiente("Operadores", "Alta y expediente del personal de conducción.", onAtras = { nav.popBackStack() })
                }
                composable(Rutas.COBROS) {
                    PantallaPendiente("Cobros", "Pagos recibidos y vencimientos por cobrar.", onAtras = { nav.popBackStack() })
                }

                composable(Rutas.PERFIL) {
                    PantallaPerfil(
                        usuario = usuario,
                        container = container,
                        sesionVm = sesionVm,
                        onCerrarSesion = onCerrarSesion,
                        onAtras = if (nav.previousBackStackEntry != null) {
                            { nav.popBackStack() }
                        } else null,
                    )
                }
            }
        }
    }
}
