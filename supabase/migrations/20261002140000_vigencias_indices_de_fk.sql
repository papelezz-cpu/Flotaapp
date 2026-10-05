-- ════════════════════════════════════════════════════════════════════════
-- S-11 · Dos FK de `vigencias` hacia auth.users sin índice de apoyo
-- ════════════════════════════════════════════════════════════════════════
--
-- El hallazgo (6ª auditoría, 2026-10-01): `vigencias` (H-04, creada después
-- de H-13) tiene tres FK sin índice. Medido el 02/10, antes de indexar nada:
--
--   revisado_por → auth.users ON DELETE SET NULL   0 de 60 filas con valor
--   subido_por   → auth.users ON DELETE SET NULL   0 de 60 filas con valor
--   (cat_clave, tipo_documento) → catalogos        cat_clave siempre 'vigencia_tipo'
--
-- Se indexan las DOS primeras, por el mismo motivo que H-13 indexó otras
-- ocho en 20260918120000: el borrado de una cuenta (y la vía ARCO de
-- cancelación, con plazo legal) pone a NULL estas columnas, y sin índice eso
-- es un recorrido completo de `vigencias` por cada usuario borrado. La tabla
-- crece con la flota (varios documentos por recurso). Parciales `WHERE … IS
-- NOT NULL`, como el precedente: hoy nacen vacíos y no cuestan nada.
--
-- La TERCERA NO se indexa, a propósito: solo la recorre editar o borrar un
-- valor del catálogo `vigencia_tipo`, una operación rara y manual; mientras
-- que `vigencias` se escribe en cada guardado de flota o perfil (el espejo).
-- Un índice ahí cobraría en lo frecuente para acelerar lo excepcional.
--
-- Solo crea índices; no toca datos. `vigencias` es pequeña: el CREATE INDEX
-- normal (no CONCURRENTLY, que no puede ir en una transacción) bloquea las
-- escrituras sobre ella una fracción de segundo.
--
-- Reglas de docs/AUDITORIA.md §4: 1, 2, 9 (nada de DROP).
-- ════════════════════════════════════════════════════════════════════════

create index if not exists idx_vigencias_revisado_por
  on public.vigencias (revisado_por) where revisado_por is not null;

create index if not exists idx_vigencias_subido_por
  on public.vigencias (subido_por) where subido_por is not null;


-- ────────────────────────────────────────────────────────────────────────
-- Comprobación — falla si el objetivo no se cumplió
-- ────────────────────────────────────────────────────────────────────────
--   · los dos índices existen, son válidos, y su primera columna es la de su
--     FK (que es lo que el borrado en cascada necesita para no recorrer la
--     tabla).
-- Como sabe fallar: sin los CREATE INDEX, las dos FK salen sin apoyo.

do $$
declare
  v_fk     record;
  v_fallos text[] := '{}';
  v_apoyo  boolean;
begin
  for v_fk in
    select k.conname, k.conkey,
           (select string_agg(a.attname, ',' order by u.ord)
              from unnest(k.conkey) with ordinality u(attnum, ord)
              join pg_attribute a on a.attrelid = k.conrelid and a.attnum = u.attnum) as cols
      from pg_constraint k
     where k.conrelid = 'public.vigencias'::regclass and k.contype = 'f'
  loop
    select exists (
      select 1 from pg_index x
       where x.indrelid = 'public.vigencias'::regclass
         and x.indisvalid
         and (x.indkey::int2[])[0:array_length(v_fk.conkey, 1) - 1] = v_fk.conkey
    ) into v_apoyo;

    if v_fk.cols in ('revisado_por', 'subido_por') and not v_apoyo then
      v_fallos := v_fallos || format('la FK %s (%s) sigue sin índice de apoyo', v_fk.conname, v_fk.cols);
    end if;
  end loop;

  if not exists (select 1 from pg_index x join pg_class i on i.oid = x.indexrelid
                  where i.relname = 'idx_vigencias_revisado_por' and x.indisvalid)
  or not exists (select 1 from pg_index x join pg_class i on i.oid = x.indexrelid
                  where i.relname = 'idx_vigencias_subido_por' and x.indisvalid) then
    v_fallos := v_fallos || 'falta alguno de los dos índices, o no es válido'::text;
  end if;

  if cardinality(v_fallos) > 0 then
    raise exception E'S-11: las FK de vigencias no quedaron indexadas:\n  %', array_to_string(v_fallos, E'\n  ');
  end if;

  raise notice 'S-11: revisado_por y subido_por de vigencias con índice de apoyo; la FK de catálogo se deja sin índice a propósito.';
end $$;
