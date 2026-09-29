-- ─────────────────────────────────────────────────────────────────────────
-- El domicilio fiscal se pide en el registro y se pierde — mismo hueco que
-- 20260910120000, sin cerrar para estos cinco campos
-- ─────────────────────────────────────────────────────────────────────────
--
-- js/auth.js pide calle, número, colonia, código postal, ciudad y estado —
-- para cliente y para empresa (js/auth.js:245-274, payload en :742-782) —
-- pero solo escribe en `perfiles` cuatro columnas: user_id, nombre, rol y
-- aprobacion_cuenta (js/auth.js:805-810). El domicilio se queda en
-- `solicitudes_cuenta` y `aprobarCuenta()` (js/aprobaciones.js, lista
-- _CAMPOS_FICHA) nunca lo copiaba — es el mismo defecto que
-- 20260910120000_ficha_empresa_desde_la_solicitud.sql cerró para
-- razon_social/rfc/telefono/tipo_persona, sin cerrar para el domicilio.
--
-- js/aprobaciones.js se corrige aparte (sumar estas 5 claves a
-- _CAMPOS_FICHA, para que las aprobaciones nuevas ya las copien). Esta
-- migración resuelve las cuentas aprobadas ANTES de ese cambio.
--
-- Sobre el guard: guard_perfil_self_update solo lanza excepción si cambian
-- rol, aprobacion_cuenta o los campos de verificación/acreditación
-- (confirmado leyendo la función completa). Este UPDATE no toca ninguno,
-- así que pasa aunque corra sin JWT y auth.uid() sea NULL — no hace falta
-- apartar el trigger.

-- BEGIN/COMMIT explícitos: este archivo se pegó directo en el SQL Editor,
-- no por aplicar-a-pruebas.sh (que envuelve la tanda entera en
-- --single-transaction). Sin esto, si el UPDATE de más abajo fallara después
-- del DISABLE TRIGGER, el trigger podría quedar apagado — nadie se enteraría
-- hasta que un documento dejara de reflejarse en vigencias.
begin;

alter table public.perfiles
  add column if not exists calle     text,
  add column if not exists colonia   text,
  add column if not exists cp        text,
  add column if not exists ciudad    text,
  add column if not exists estado_mx text;

comment on column public.perfiles.calle is
  'Domicilio fiscal, capturado en el registro (solicitudes_cuenta) y copiado aquí al aprobar la cuenta — ver _CAMPOS_FICHA en js/aprobaciones.js. Editable después desde Mi perfil (cliente) o Perfil de empresa (admin).';

-- ── El espejo de vigencias se atraviesa aquí, y hay que rodearlo ──────────
--
-- trg_vigencias_espejo (AFTER INSERT OR UPDATE, FOR EACH ROW, en
-- 20260922120000_vigencias_etapa3_doble_escritura.sql) corre en CUALQUIER
-- UPDATE de `perfiles` — no mira qué columna cambió, siempre repite el
-- reflejo completo de permiso_sct/seguro_rc/seguro_carga hacia `vigencias`.
-- Ese reflejo pasa por guard_vigencia_update(), que rechaza tocar una fila
-- ya 'vigente' salvo que is_superadmin() sea cierto — y en una sesión SQL
-- sin JWT (psql, el SQL Editor) auth.uid() es NULL, así que is_superadmin()
-- siempre da falso aquí, sin importar qué usuario pegue el script.
--
-- Resultado medido: este UPDATE —que no toca ni una columna de documentos—
-- fallaba con «VIGENCIA_ACREDITADA: solo el superadmin puede modificar un
-- documento acreditado de empresa» en cuanto tocaba la fila de una empresa
-- con el permiso SCT ya acreditado. El espejo se volvió estricto en
-- 20260923120000 (falla la transacción entera si el reflejo falla) — antes
-- de eso este mismo problema habría pasado en silencio.
--
-- Se apaga el trigger para este UPDATE nada más: no se pierde nada, porque
-- ninguna columna que refleja cambia aquí — y se prende de vuelta antes de
-- terminar la migración, pase lo que pase.
alter table public.perfiles disable trigger trg_vigencias_espejo;

-- Solo rellena huecos: nunca pisa un valor que el usuario ya haya escrito
-- desde Mi perfil / Perfil de empresa. nullif(btrim(...),'') trata la cadena
-- vacía como ausencia, igual que 20260910120000.
update public.perfiles p
   set calle     = coalesce(nullif(btrim(p.calle),     ''), nullif(btrim(s.calle),     '')),
       colonia   = coalesce(nullif(btrim(p.colonia),   ''), nullif(btrim(s.colonia),   '')),
       cp        = coalesce(nullif(btrim(p.cp),        ''), nullif(btrim(s.cp),        '')),
       ciudad    = coalesce(nullif(btrim(p.ciudad),    ''), nullif(btrim(s.ciudad),    '')),
       estado_mx = coalesce(nullif(btrim(p.estado_mx), ''), nullif(btrim(s.estado_mx), ''))
  from public.solicitudes_cuenta s
 where s.user_id = p.user_id
   and s.estado  = 'aprobada'
   and (
        (nullif(btrim(p.calle),     '') is null and nullif(btrim(s.calle),     '') is not null)
     or (nullif(btrim(p.colonia),   '') is null and nullif(btrim(s.colonia),   '') is not null)
     or (nullif(btrim(p.cp),        '') is null and nullif(btrim(s.cp),        '') is not null)
     or (nullif(btrim(p.ciudad),    '') is null and nullif(btrim(s.ciudad),    '') is not null)
     or (nullif(btrim(p.estado_mx), '') is null and nullif(btrim(s.estado_mx), '') is not null)
   );

alter table public.perfiles enable trigger trg_vigencias_espejo;

commit;

-- ── Comprobación ─────────────────────────────────────────────────────────
-- Cuántas cuentas aprobadas siguen sin domicilio después de esto. Las que
-- salgan aquí no lo tienen ni en la solicitud: hay que pedírselo aparte.
--
--   select p.user_id, p.nombre, p.rol,
--          p.calle is null as sin_domicilio
--     from public.perfiles p
--    where p.aprobacion_cuenta is null
--      and p.calle is null
--    order by p.nombre;
