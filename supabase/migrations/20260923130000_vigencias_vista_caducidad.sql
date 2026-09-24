-- ============================================================================
-- H-04 · Etapa 4.7 — Una vista que expone la caducidad ya calculada
-- ============================================================================
--
-- ── Para qué ──────────────────────────────────────────────────────────────
--
-- `vigencias.fecha_documento` guarda LO QUE EL USUARIO CAPTURÓ, y para tres
-- tipos (examen médico, toxicológico, carta de antecedentes) eso no es la
-- caducidad: es la fecha del examen, y vence 12 meses después. La regla vive
-- en `catalogos.meta->>'vigencia_meses'` y la aplica `vigencia_vence_el()`.
--
-- El problema es filtrar por ella. `actualizarBadgeVigencias()` quiere «dame
-- los recursos con algún documento que venza en menos de 30 días», y hoy lo
-- resuelve con cinco consultas y restando 335 días a mano:
--
--     anioAtras = hoy - (365 - 30)        // js/vigencias.js
--     .or(`fecha_examen_medico.lte.${anioAtrasStr}, …`)
--
-- Esa aritmética es la regla del catálogo copiada en JavaScript, con 365 en
-- vez de «12 meses». El día que un examen valga dos años, el catálogo lo dirá
-- y el badge seguirá contando con 365. Es exactamente la duplicación que H-04
-- existe para quitar.
--
-- Con `vence_el` como columna, eso pasa a ser `.lte('vence_el', limite)`.
--
-- ── security_invoker = true, y aquí sí importa ────────────────────────────
--
-- Las otras vistas del proyecto (`empresas_publico`, `camiones_publico`…) van
-- con `security_invoker = false` **a propósito**: existen para enseñar a
-- cualquiera con sesión unos pocos campos públicos de filas que la RLS de la
-- tabla le tapa. Medido el 2026-09-23: una empresa lee `camiones` directo y
-- obtiene 0 filas de flota ajena, y por `camiones_publico` obtiene las 5.
--
-- **Esta vista es lo contrario.** El panel de vigencias es privado: cada
-- empresa ve sus documentos y el superadmin ve todos. Con `false`, la vista
-- correría como su dueño y le enseñaría a cualquier empresa los documentos de
-- las demás — una fuga de datos, no una ficha pública.
--
-- Con `true`, las políticas de `vigencias` siguen decidiendo:
--   · `vigencias_lee_dueno_o_sa`  → el dueño de la entidad, o el superadmin
--
-- No se añade ninguna política nueva ni se relaja ninguna: la vista hereda las
-- que ya había.
-- ============================================================================

create or replace view public.vigencias_caducidad
with (security_invoker = true) as
  select v.id,
         v.entidad_tipo,
         v.entidad_id,
         v.tipo_documento,
         v.archivo_path,
         v.fecha_documento,
         v.estado,
         v.nota_rechazo,
         v.subido_en,
         v.subido_por,
         v.revisado_en,
         v.revisado_por,
         public.vigencia_vence_el(v.tipo_documento, v.fecha_documento) as vence_el
    from public.vigencias v;

comment on view public.vigencias_caducidad is
  'H-04: vigencias mas la caducidad efectiva (vence_el), que aplica la regla vigencia_meses del catalogo. security_invoker=true A PROPOSITO: el panel de vigencias es privado y la RLS de vigencias tiene que seguir aplicandose por usuario. No cambiar a false.';

-- anon fuera, como la tabla. `authenticated` solo lee: lo que se escribe es la
-- tabla, nunca la vista (misma linea que 20260914130000 y 20260918140000).
revoke all on public.vigencias_caducidad from anon, public;
grant select on public.vigencias_caducidad to authenticated;

-- Y retirar las escrituras EXPLÍCITAMENTE, que no es redundante: `pg_default_acl`
-- de este proyecto concede `arwdDxtm` —todo— a `authenticated` sobre cada
-- relación nueva, así que **toda vista nace escribible** y el `grant select` de
-- arriba no lo deshace. Es la causa que documentó 20260914130000 cuando
-- `empresas_publico` llevaba meses aceptando INSERT, UPDATE y DELETE de
-- cualquiera con sesión (H-01). El bloque de comprobación de abajo lo cazó al
-- primer intento de aplicar esta migración.
--
-- MAINTAIN va por higiene: sobre una vista no materializada no habilita nada.
revoke insert, update, delete, maintain on public.vigencias_caducidad from authenticated;


-- ── Comprobación ───────────────────────────────────────────────────────────

do $$
declare
  v_inv  text;
  v_n    int;
begin
  -- security_invoker DEBE estar en true. Si algún día alguien la recrea sin la
  -- cláusula WITH, Postgres la deja en false y la vista empezaría a enseñar
  -- los documentos de todas las empresas sin que nada falle a la vista.
  select coalesce((
    select option_value from pg_options_to_table(c.reloptions)
     where option_name = 'security_invoker'), 'false')
    into v_inv
    from pg_class c
   where c.oid = 'public.vigencias_caducidad'::regclass;
  if v_inv is distinct from 'true' then
    raise exception 'H-04 etapa 4.7: vigencias_caducidad tiene security_invoker=%. Con false ensena los documentos de todas las empresas a cualquiera con sesion.', v_inv;
  end if;

  if has_table_privilege('anon', 'public.vigencias_caducidad', 'SELECT') then
    raise exception 'H-04 etapa 4.7: anon puede leer vigencias_caducidad.';
  end if;
  if not has_table_privilege('authenticated', 'public.vigencias_caducidad', 'SELECT') then
    raise exception 'H-04 etapa 4.7: authenticated no puede leer la vista; el panel de vigencias quedaria vacio.';
  end if;
  -- Y que no se pueda escribir por la vista.
  if has_table_privilege('authenticated', 'public.vigencias_caducidad', 'INSERT')
  or has_table_privilege('authenticated', 'public.vigencias_caducidad', 'UPDATE')
  or has_table_privilege('authenticated', 'public.vigencias_caducidad', 'DELETE') then
    raise exception 'H-04 etapa 4.7: la vista acepta escrituras. Ver 20260914130000.';
  end if;

  -- La caducidad calculada tiene que coincidir con la regla del catálogo: los
  -- tipos sin vigencia_meses devuelven la fecha capturada tal cual, y los de
  -- 12 meses le suman un año.
  select count(*) into v_n
    from public.vigencias_caducidad c
    join public.catalogos k on k.clave = 'vigencia_tipo' and k.valor = c.tipo_documento
   where c.fecha_documento is not null
     and c.vence_el is distinct from (
       case when (k.meta->>'vigencia_meses') is null then c.fecha_documento
            else (c.fecha_documento + make_interval(months => (k.meta->>'vigencia_meses')::int))::date
       end);
  if v_n > 0 then
    raise exception 'H-04 etapa 4.7: % filas con vence_el que no sigue la regla del catalogo.', v_n;
  end if;

  raise notice 'H-04 etapa 4.7: vista creada, security_invoker=true, % filas con caducidad coherente.',
    (select count(*) from public.vigencias_caducidad where fecha_documento is not null);
end $$;
