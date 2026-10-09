-- ════════════════════════════════════════════════════════════════════════
-- H-17 · A2-M11 · Cuatro índices que sobran
-- ════════════════════════════════════════════════════════════════════════
--
-- Uso medido en producción el 07/10 (supabase/medir-produccion.sh,
-- pg_stat_user_indexes, contado desde el 30/03):
--
--   idx_pedidos_categoria_carga  pedidos (categoria_carga)       0 lecturas
--       Ninguna consulta de la PWA ni de Android filtra por categoria_carga.
--   idx_consentimientos_tipo     consentimientos (tipo, version) 1 lectura
--       Ninguna consulta busca por tipo; la pantalla de privacidad busca por
--       usuario (idx_consentimientos_user).
--   idx_pedidos_fecha            pedidos (created_at DESC)       16 lecturas
--       Redundante: idx_pedidos_fecha_id (created_at DESC, id DESC) empieza
--       por la misma columna y responde a lo mismo.
--   idx_expedientes_reserva      expedientes (reserva_id)        154 lecturas
--       Redundante: el índice de UNIQUE (reserva_id, etapa) empieza por
--       reserva_id, y sirve también a la clave foránea.
--
-- Borrado autorizado por el usuario el 09/10, índice por índice (Regla #1).
-- Antes de borrar se comprueba que los índices que cubren a los dos
-- redundantes existen: si faltara alguno, no se borra nada.
--
-- Para recrear cualquiera, su definición exacta:
--   create index idx_pedidos_categoria_carga on public.pedidos (categoria_carga) where categoria_carga is not null;
--   create index idx_consentimientos_tipo    on public.consentimientos (tipo, version);
--   create index idx_pedidos_fecha           on public.pedidos (created_at desc);
--   create index idx_expedientes_reserva     on public.expedientes (reserva_id);
--
-- A este volumen (la tabla mayor de estas tiene 41 filas) no cambia el
-- rendimiento: es orden, y escrituras algo más baratas. No toca datos.
-- Reglas de docs/AUDITORIA.md §4: 9 (DROP con su dato de uso), 13.
-- ════════════════════════════════════════════════════════════════════════

do $$
declare
  v_falta text[] := '{}';
begin
  if to_regclass('public.idx_pedidos_fecha_id') is null then
    v_falta := v_falta || 'idx_pedidos_fecha_id (cubre a idx_pedidos_fecha)'::text;
  end if;
  if to_regclass('public.expedientes_reserva_id_etapa_key') is null then
    v_falta := v_falta || 'expedientes_reserva_id_etapa_key (cubre a idx_expedientes_reserva)'::text;
  end if;
  if to_regclass('public.idx_consentimientos_user') is null then
    v_falta := v_falta || 'idx_consentimientos_user (lo que sí usa la pantalla de privacidad)'::text;
  end if;
  if cardinality(v_falta) > 0 then
    raise exception E'H-17/A2-M11: no se borra nada; falta lo que cubre a estos índices:\n  %',
      array_to_string(v_falta, E'\n  ');
  end if;
end $$;

drop index if exists public.idx_pedidos_categoria_carga;
drop index if exists public.idx_consentimientos_tipo;
drop index if exists public.idx_pedidos_fecha;
drop index if exists public.idx_expedientes_reserva;


-- ────────────────────────────────────────────────────────────────────────
-- Comprobación — falla si el objetivo no se cumplió
-- ────────────────────────────────────────────────────────────────────────
-- Los cuatro ya no existen y los tres que cubren siguen ahí, con la forma
-- que se supuso: fecha_id empieza por created_at y la UNIQUE de expedientes
-- por reserva_id. Como sabe fallar: sin los DROP, los cuatro siguen.
do $$
declare
  v_fallos text[] := '{}';
  v_i      text;
begin
  foreach v_i in array array['idx_pedidos_categoria_carga', 'idx_consentimientos_tipo',
                             'idx_pedidos_fecha', 'idx_expedientes_reserva'] loop
    if to_regclass('public.' || v_i) is not null then
      v_fallos := v_fallos || format('%s sigue existiendo', v_i);
    end if;
  end loop;

  if (select a.attname from pg_index x
        join pg_attribute a on a.attrelid = x.indrelid and a.attnum = x.indkey[0]
       where x.indexrelid = 'public.idx_pedidos_fecha_id'::regclass) is distinct from 'created_at' then
    v_fallos := v_fallos || 'idx_pedidos_fecha_id no empieza por created_at'::text;
  end if;
  if (select a.attname from pg_index x
        join pg_attribute a on a.attrelid = x.indrelid and a.attnum = x.indkey[0]
       where x.indexrelid = 'public.expedientes_reserva_id_etapa_key'::regclass) is distinct from 'reserva_id' then
    v_fallos := v_fallos || 'el índice UNIQUE de expedientes no empieza por reserva_id'::text;
  end if;

  if cardinality(v_fallos) > 0 then
    raise exception E'H-17/A2-M11: no quedó como debe:\n  %', array_to_string(v_fallos, E'\n  ');
  end if;
  raise notice 'H-17/A2-M11: cuatro índices sobrantes borrados; los que los cubren siguen en su sitio.';
end $$;
