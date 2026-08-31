# Conexión a Postgres, compartida por los scripts de supabase/.
#
# No se ejecuta sola: se incluye con
#   source "$(dirname "${BASH_SOURCE[0]}")/lib-conexion.sh"
#   conectar_a "PRODUCCIÓN" "$REF" "PORTGO_DB_URL"
#
# Al terminar deja la cadena lista en la variable global CONN, y la contraseña
# en PGPASSWORD si se tecleó aparte.
#
# Existe porque el error "no se pudo conectar" sin más detalle no ayuda a
# nadie: casi siempre el problema es el host o el usuario, no la contraseña.

# El panel de Supabase a veces ofrece la cadena dentro del comando completo
#   psql "postgresql://…"
# y con comillas. Si eso llega tal cual, psql no lo reconoce como URI: lo toma
# por nombre de base y termina intentando localhost, con un error que no dice
# nada del verdadero motivo. Se limpia antes de usarla.
_limpiar_cadena() {
  local c="$1"
  # espacios de los extremos
  c="${c#"${c%%[![:space:]]*}"}"
  c="${c%"${c##*[![:space:]]}"}"
  # el comando de adelante, si viene
  c="${c#psql }"
  c="${c#"${c%%[![:space:]]*}"}"
  # comillas envolventes, simples o dobles
  c="${c#\"}"; c="${c%\"}"
  c="${c#\'}"; c="${c%\'}"
  c="${c#"${c%%[![:space:]]*}"}"
  c="${c%"${c##*[![:space:]]}"}"
  printf '%s' "$c"
}

# Descompone la cadena sin enseñar nunca la contraseña.
_radiografia() {
  local conn="$1"
  local sin_esquema="${conn#*://}"
  local creds="${sin_esquema%%@*}"
  local resto="${sin_esquema#*@}"
  CONN_USUARIO="${creds%%:*}"
  local hostpuerto="${resto%%/*}"
  CONN_HOST="${hostpuerto%%:*}"
  CONN_PUERTO="${hostpuerto##*:}"
  # Sin puerto explícito, host y puerto salen iguales del recorte.
  if [ "$CONN_PUERTO" = "$CONN_HOST" ]; then CONN_PUERTO="5432 (por omisión)"; fi
  return 0
}

conectar_a() {
  local etiqueta="$1" ref="$2" var_env="${3:-}"

  CONN=""
  if [ -n "$var_env" ]; then CONN="${!var_env:-}"; fi

  if [ -z "$CONN" ]; then
    echo "Pega la cadena de conexión de $etiqueta."
    echo "  Supabase → proyecto → botón Connect → pestaña Session pooler → URI"
    echo "  (puerto 5432; el modo Transaction / 6543 no sirve para esto)"
    read -r -p "Cadena: " CONN
  fi

  if [ -z "$CONN" ]; then
    echo "❌ No pegaste ninguna cadena."
    return 1
  fi

  CONN="$(_limpiar_cadena "$CONN")"

  # Si tras limpiar no es un URI, psql se iría a localhost y el error no diría
  # por qué. Mejor cortar aquí y explicarlo.
  case "$CONN" in
    postgresql://*|postgres://*) ;;
    *)
      echo
      echo "❌ Eso no parece una cadena de conexión."
      echo "   Recibí: ${CONN:0:40}…"
      echo
      echo "   Tiene que empezar con postgresql:// — solo la cadena, sin el"
      echo "   comando psql delante ni comillas alrededor. Del panel copia"
      echo "   únicamente la parte que va de postgresql:// en adelante."
      return 1 ;;
  esac

  # Si la cadena trae el marcador, o de plano no trae contraseña, se pide
  # aparte: así no queda en el historial del shell.
  if [[ "$CONN" == *"[YOUR-PASSWORD]"* ]] || [[ "$CONN" != *":"*"@"* ]]; then
    echo
    echo "Contraseña de la base (Supabase → Settings → Database → Database password)."
    echo "No se va a ver mientras la tecleas."
    # IFS= es obligatorio: sin eso, read recorta espacios al inicio y al final,
    # y una contraseña que de verdad lleve uno se leería mal sin avisar.
    IFS= read -r -s -p "Contraseña: " DBPASS
    echo

    # Pegar desde Windows suele arrastrar un retorno de carro al final. Ese
    # nunca es parte de una contraseña, así que se quita sin preguntar.
    DBPASS="${DBPASS%$'
'}"

    # No se enseña la contraseña, pero sí su largo: si no coincide con lo que
    # esperas, ahí está el problema y no en el servidor.
    echo "   (recibí ${#DBPASS} caracteres)"
    case "$DBPASS" in
      " "*|*" ") echo "   ⚠ Empieza o termina con espacio. Casi siempre se coló al pegar." ;;
    esac
    if [ ${#DBPASS} -eq 0 ]; then
      echo "   ❌ No recibí ninguna contraseña."
      return 1
    fi

    export PGPASSWORD="$DBPASS"
    CONN="${CONN/\[YOUR-PASSWORD\]/}"
    CONN="${CONN//:@/@}"
  fi

  _radiografia "$CONN"

  echo
  echo "── Así entendí la cadena ──"
  echo "   usuario : $CONN_USUARIO"
  echo "   host    : $CONN_HOST"
  echo "   puerto  : $CONN_PUERTO"
  echo "   clave   : $([ -n "${PGPASSWORD:-}" ] && echo 'tecleada aparte' || echo 'venía dentro de la cadena')"
  echo

  # Los dos tropiezos clásicos, avisados antes de intentar.
  if [[ "$CONN_HOST" == db.*.supabase.co ]]; then
    echo "   ⚠ Ese es el host de conexión DIRECTA. Supabase ya solo lo publica en"
    echo "     IPv6, y desde Windows con IPv4 no se alcanza. Usa el POOLER:"
    echo "     Connect → Session pooler → aws-N-….pooler.supabase.com"
    echo
  fi
  if [[ "$CONN_HOST" == *pooler.supabase.com ]] && [[ "$CONN_USUARIO" != *.* ]]; then
    echo "   ⚠ Con el pooler el usuario debe llevar el ref del proyecto:"
    echo "     postgres.$ref   (no 'postgres' a secas)"
    echo
  fi
  if [[ "$CONN_PUERTO" == 6543 ]]; then
    echo "   ⚠ El puerto 6543 es el modo Transaction: no admite DDL ni pg_dump."
    echo "     Cambia a Session pooler (5432)."
    echo
  fi

  echo "── Probando conexión ──"
  local salida
  if salida=$(psql "$CONN" -Atc "select 1" 2>&1); then
    echo "✓ Conectado a $etiqueta."
    echo
    return 0
  fi

  echo
  echo "❌ No se pudo conectar. Esto respondió psql:"
  echo
  echo "$salida" | sed 's/^/   /'
  echo
  echo "── Qué suele significar ──"
  # psql habla el idioma del sistema: hay que reconocer el mensaje en inglés
  # y en español, o el diagnóstico se cae al caso genérico.
  case "$salida" in
    *"Tenant or user not found"*|*"ENOIDENTIFIER"*|*"no tenant identifier"*)
      echo "   El usuario no trae el ref del proyecto. Con el pooler debe ser"
      echo "   postgres.$ref y no 'postgres' a secas." ;;
    *"password authentication failed"*|*"autentificación password falló"*|*"la autentificación falló"*)
      echo "   La contraseña no coincide. Si tiene símbolos (@ # ? / %) y la pegaste"
      echo "   DENTRO de la cadena, ahí está el problema: rompen el formato del URI."
      echo "   Deja el marcador [YOUR-PASSWORD] en la cadena y tecléala cuando"
      echo "   el script te la pida aparte." ;;
    *"could not translate host name"*|*"no se pudo traducir el nombre"*)
      echo "   Ese host no existe en el DNS. Revisa que lo hayas copiado completo"
      echo "   del panel: Supabase → Connect → Session pooler." ;;
    *"Network is unreachable"*|*"Connection timed out"*|*"could not connect to server"*|    *"no se pudo conectar con el servidor"*|*"expiró el tiempo de conexión"*|*"Red inalcanzable"*)
      echo "   No hay ruta hasta el servidor. Casi siempre es la conexión directa"
      echo "   (db.$ref.supabase.co), que hoy es IPv6 y desde Windows no se alcanza."
      echo "   Usa la cadena del Session pooler." ;;
    *"no pg_hba.conf entry"*|*"no hay una línea en pg_hba.conf"*|*SSL*)
      echo "   El servidor rechazó la conexión por SSL o por restricción de red." ;;
    *localhost*|*"127.0.0.1"*|*"::1"*)
      echo "   psql intentó conectarse a localhost, no al servidor: eso significa"
      echo "   que no reconoció la cadena como URI y usó sus valores por omisión."
      echo "   Suele pasar al pegar el comando entero (psql \"postgresql://…\")"
      echo "   en vez de solo la cadena." ;;
    *"does not exist"*|*"no existe"*)
      echo "   La base indicada no existe: la cadena debe terminar en /postgres" ;;
    *)
      echo "   Compara host y puerto de arriba contra lo que muestra el panel." ;;
  esac
  echo
  echo "   La pantalla correcta: Supabase → proyecto → Connect → Session pooler."
  return 1
}

# ── Cadena autónoma: la contraseña va DENTRO, codificada ───────────────────
#
# PGPASSWORD es una sola variable de entorno. En cuanto un guion habla con dos
# bases en la misma corrida (producción como origen, pruebas como destino), la
# segunda conexión hereda la contraseña de la primera y falla con un
# "password authentication failed" que no dice nada del verdadero motivo.
#
# cadena_autonoma() devuelve la cadena con la contraseña incrustada y ya
# escapada, para poder guardarla en una variable por base. Después de llamarla
# conviene limpiar PGPASSWORD con: unset PGPASSWORD
_urlenc() {
  # Se recorre por BYTES (LC_ALL=C) para que una contraseña con acentos o
  # símbolos fuera de ASCII se codifique bien y no a medias.
  local LC_ALL=C
  local s="$1" o="" i c
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
      [A-Za-z0-9._~-]) o+="$c" ;;
      *) o+=$(printf '%%%02X' "'$c") ;;
    esac
  done
  printf '%s' "$o"
}

cadena_autonoma() {
  local conn="$1"
  if [ -n "${PGPASSWORD:-}" ]; then
    local esquema="${conn%%://*}"
    local resto="${conn#*://}"
    local creds="${resto%%@*}"
    local cola="${resto#*@}"
    local usuario="${creds%%:*}"
    conn="$esquema://$usuario:$(_urlenc "$PGPASSWORD")@$cola"
  fi
  printf '%s' "$conn"
}
