#!/usr/bin/env bash
#
# Levanta un emulador, instala PortGo y deja el registro abierto.
#
# Uso:
#   bash android/probar-emulador.sh            # crear (si hace falta), arrancar e instalar
#   bash android/probar-emulador.sh log        # solo seguir el registro de la app
#   bash android/probar-emulador.sh deeplink   # probar que portgo://auth abre la app
#   bash android/probar-emulador.sh apagar
#
set -uo pipefail

export JAVA_HOME="${JAVA_HOME:-/c/Users/Usuario/scoop/apps/temurin17-jdk/current}"
export ANDROID_HOME="${ANDROID_HOME:-/c/Users/Usuario/scoop/apps/android-clt/current}"
export PATH="$JAVA_HOME/bin:$PATH"

EMU="$ANDROID_HOME/emulator/emulator.exe"
ADB="$ANDROID_HOME/platform-tools/adb.exe"
AVDMGR="$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager.bat"
AVD="portgo_test"
IMG="system-images;android-35;google_apis;x86_64"
PKG="mx.portgo.app.debug"

case "${1:-arrancar}" in

  log)
    # -v time da la hora de cada línea; sin eso es imposible correlacionar con
    # lo que uno está tocando en pantalla.
    exec "$ADB" logcat -v time PortGo:V AndroidRuntime:E System.err:W '*:S'
    ;;

  deeplink)
    # Comprueba SOLO la mitad de la app: que el esquema abra PortGo. La otra
    # mitad (que Supabase permita la URL) solo se ve con el correo real.
    "$ADB" shell am start -W -a android.intent.action.VIEW -d "portgo://auth" "$PKG"
    exit $?
    ;;

  apagar)
    "$ADB" emu kill 2>/dev/null && echo "emulador apagado"
    exit 0
    ;;
esac

# ── Aceleración por hardware ──────────────────────────────────────────────
#
# El emulador de x86_64 NO arranca sin aceleración por hardware: no es que vaya
# lento, es que se niega con "x86_64 emulation currently requires hardware
# acceleration!".
#
# En este equipo (i7-1255U, Windows 10 Education) no la hay todavía, y el
# diagnóstico es enredado, así que vale la pena dejarlo escrito:
#
#   · `Windows Hypervisor Platform` ya está activado, y el propio emulador
#     reporta "hasCompatibleHypervisor: Ok". Eso ENGAÑA.
#   · Lo que manda es la comprobación de CPU, que dice "Virtualization
#     extension is not supported".
#   · WMI reporta VirtualizationFirmwareEnabled, SLAT y VMMonitorModeExtensions
#     todos en False. Con Hyper-V corriendo se esperaría al menos SLAT en True.
#
# Conclusión: falta activar VT-x en el BIOS/UEFI ("Intel Virtualization
# Technology"). Para entrar sin adivinar la tecla:
#   Configuración → Actualización y seguridad → Recuperación → Inicio avanzado
#   → Solucionar problemas → Opciones avanzadas → Configuración de firmware UEFI
#
# Las banderas de abajo piden WHPX explícitamente. Son necesarias una vez que
# VT-x esté activo, pero por sí solas no sustituyen al BIOS.
ACEL=(-accel on -feature WindowsHypervisorPlatform)

# ── Crear el AVD si no existe ─────────────────────────────────────────────
if ! "$AVDMGR" list avd 2>/dev/null | grep -q "Name: $AVD"; then
  echo "── Creando el AVD $AVD…"
  echo "no" | "$AVDMGR" create avd -n "$AVD" -k "$IMG" -d "pixel_6" --force
fi

# 1536 MB y no los 2048 de costumbre: este equipo tiene 8 GB en total y
# Gradle ya se queda con buena parte. Un emulador que provoca swap es peor
# que uno con menos memoria.
CFG="$HOME/.android/avd/$AVD.avd/config.ini"
if [ -f "$CFG" ]; then
  sed -i 's/^hw.ramSize=.*/hw.ramSize=1536/' "$CFG" 2>/dev/null
  grep -q '^hw.ramSize' "$CFG" || echo "hw.ramSize=1536" >> "$CFG"
fi

# ── Arrancar ──────────────────────────────────────────────────────────────
if ! "$ADB" devices | grep -q "emulator.*device$"; then
  echo "── Arrancando el emulador (tarda un par de minutos la primera vez)…"
  "$EMU" -avd "$AVD" "${ACEL[@]}" -no-snapshot-load -no-boot-anim -netdelay none -netspeed full &
  echo "── Esperando a que termine de arrancar…"
  "$ADB" wait-for-device
  until [ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
    sleep 3
  done
fi
echo "✓ Emulador listo"

# ── Instalar ──────────────────────────────────────────────────────────────
APK="$(dirname "$0")/app/build/outputs/apk/debug/app-debug.apk"
if [ ! -f "$APK" ]; then
  echo "── Compilando…"
  (cd "$(dirname "$0")" && ./gradlew assembleDebug -q)
fi

echo "── Instalando…"
"$ADB" install -r "$APK"

echo "── Abriendo PortGo…"
"$ADB" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1

echo
echo "Listo. Para ver el registro en vivo:"
echo "   bash android/probar-emulador.sh log"
