-- ════════════════════════════════════════════════════════════════════════
-- S-01 paso 2, etapa C · Los buckets de documentos dejan de ser públicos
-- ════════════════════════════════════════════════════════════════════════
--
-- El último paso de S-01 (docs/AUDITORIA.md). `operadores`, `documentos-
-- empresa` y `custodios` eran públicos: cualquiera con la URL de un archivo
-- lo abría sin sesión y para siempre —exámenes médicos y toxicológicos de los
-- choferes, cartas de antecedentes, pólizas de las empresas, licencias SEDENA—.
-- Las etapas anteriores dejaron todo listo para cerrarlos:
--   A. la web abre siempre con URL firmada y guarda rutas
--      (en producción desde el 05/10, 671f132);
--   B. las URL guardadas ya son rutas (20261005170000, en producción el 05/10).
-- Con eso, volverlos privados no cambia nada en pantalla y sí deja sin valor
-- toda URL pública que alguien hubiera copiado.
--
-- Quién puede firmar después, por las políticas de lectura ya puestas:
--   operadores_read (S-01), docempresa_read (S-05), custodios_read (S-04):
--   el dueño de la carpeta o un superadmin. Nadie más necesita estos
--   documentos: la Carta Porte ya no los entrega (S-03) y el catálogo no los
--   muestra. Android no sube ni abre archivos de estos buckets.
--
-- Solo cambia la columna `public` de tres filas de storage.buckets. No borra
-- nada. Es reversible: `update storage.buckets set public = true where id in
-- (…)`. Si la actualización no pudiera aplicarse, la comprobación lo dice.
--
-- Reglas de docs/AUDITORIA.md §4: 2, 44, 44b.
-- ════════════════════════════════════════════════════════════════════════

update storage.buckets
   set public = false
 where id in ('operadores', 'documentos-empresa', 'custodios')
   and public;


-- ────────────────────────────────────────────────────────────────────────
-- Comprobación — falla si el objetivo no se cumplió
-- ────────────────────────────────────────────────────────────────────────
--   · existen los tres buckets y ninguno es público;
--   · cada uno conserva una política de lectura (SELECT) para authenticated
--     atada a la carpeta del dueño: sin ella, nadie podría firmar y los
--     documentos dejarían de abrir para todos;
--   · y ninguna columna de documentos guarda ya una URL pública (etapa B):
--     si la hubiera, esa URL dejaría de abrir.
-- Como sabe fallar: sin el UPDATE, los tres siguen públicos.

do $$
declare
  v_existen  int;
  v_publicos int;
  v_b        text;
  v_urls     int;
  v_fallos   text[] := '{}';
begin
  select count(*), count(*) filter (where public)
    into v_existen, v_publicos
    from storage.buckets where id in ('operadores', 'documentos-empresa', 'custodios');
  if v_existen <> 3 then
    v_fallos := v_fallos || format('se esperaban 3 buckets y hay %s', v_existen);
  end if;
  if v_publicos > 0 then
    v_fallos := v_fallos || format('%s de los buckets siguen públicos', v_publicos);
  end if;

  foreach v_b in array array['operadores', 'documentos-empresa', 'custodios'] loop
    if not exists (
      select 1 from pg_policy
       where polrelid = 'storage.objects'::regclass
         and polcmd = 'r'
         and polroles::regrole[]::text[] = array['authenticated']
         and pg_get_expr(polqual, polrelid) like '%''' || v_b || '''%'
         and pg_get_expr(polqual, polrelid) like '%foldername%') then
      v_fallos := v_fallos || format('el bucket %s no tiene política de lectura por carpeta: nadie podría firmar', v_b);
    end if;
  end loop;

  select count(*) into v_urls from (
    select unnest(array[foto_operador, foto_licencia, doc_examen_medico, doc_examen_toxicologico,
                        doc_carta_antecedentes, doc_licencia_peligrosa]) v from public.operadores
    union all select unnest(array[doc_permiso_sct, doc_seguro_rc, doc_seguro_carga, doc_permiso_sct_pendiente,
                        doc_seguro_rc_pendiente, doc_seguro_carga_pendiente]) from public.perfiles
    union all select doc_licencia_sedena from public.custodios) x
   where v like '%/object/public/%';
  if v_urls > 0 then
    v_fallos := v_fallos || format('quedan %s URL públicas guardadas: dejarían de abrir. Aplicar antes 20261005170000', v_urls);
  end if;

  if cardinality(v_fallos) > 0 then
    raise exception E'S-01 C: no quedó como debe:\n  %', array_to_string(v_fallos, E'\n  ');
  end if;

  raise notice 'S-01 C: operadores, documentos-empresa y custodios son privados; se leen solo con URL firmada del dueño o del superadmin.';
end $$;
