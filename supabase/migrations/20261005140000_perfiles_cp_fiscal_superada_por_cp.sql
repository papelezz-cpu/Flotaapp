-- ════════════════════════════════════════════════════════════════════════
-- S-07 · perfiles.cp_fiscal y perfiles.cp guardan el mismo dato
-- ════════════════════════════════════════════════════════════════════════
--
-- El hallazgo (6ª auditoría, 2026-10-01). Carta Porte (20260929140000) añadió
-- perfiles.cp para el código postal del domicilio fiscal, y ya existía
-- perfiles.cp_fiscal para lo mismo, marcada «SIN USO» desde H-15.
-- Medido el 05/10:
--
--                         cp_fiscal      cp
--   referencias          0              9 (Perfil de empresa, Mi perfil,
--                                          aprobarCuenta, Carta Porte)
--   vistas / funciones   0              0
--   filas con valor      0 de 13        7 de 13   (volcado del 28/09)
--
-- Decisión del usuario (05/10): documentar, sin borrar — lo mismo que H-15
-- decidió para las columnas muertas (regla 9 de docs/AUDITORIA.md: nada de
-- DROP por iniciativa propia). cp_fiscal se queda, vacía, marcada como
-- superada; el dato vive en cp.
--
-- El comentario anterior de cp_fiscal decía «El dato vive en
-- solicitudes_cuenta»: dejó de ser cierto el 29/09, cuando el domicilio
-- empezó a copiarse a perfiles al aprobar la cuenta. Se reemplaza por uno que
-- dice lo que hay hoy. Ningún dato cambia.
--
-- Reglas de docs/AUDITORIA.md §4: 2, 9.
-- ════════════════════════════════════════════════════════════════════════

comment on column public.perfiles.cp_fiscal is
  'SUPERADA por perfiles.cp (S-07, 20261005140000). Sin uso y vacía: 0 referencias en web, Android, Edge Functions, vistas y funciones (medido el 2026-10-05). No usar: el código postal del domicilio fiscal vive en perfiles.cp. Se conserva sin DROP por la regla 9 de docs/AUDITORIA.md.';

comment on column public.perfiles.cp is
  'Código postal del domicilio fiscal (Carta Porte, 20260929140000). Se captura en el registro (solicitudes_cuenta.cp), se copia aquí al aprobar la cuenta (_CAMPOS_FICHA en js/aprobaciones.js) y es editable desde Mi perfil y Perfil de empresa. Sustituye a perfiles.cp_fiscal, que está vacía y no se usa (S-07).';


-- ────────────────────────────────────────────────────────────────────────
-- Comprobación — falla si el objetivo no se cumplió
-- ────────────────────────────────────────────────────────────────────────
--   · los dos comentarios dicen lo que se acaba de escribir;
--   · cp_fiscal sigue vacía: si alguien la empezara a llenar, documentarla
--     como «vacía, no usar» sería falso, y este bloque lo dice en vez de
--     callarlo.

do $$
declare
  v_fiscal text := col_description('public.perfiles'::regclass,
                     (select attnum from pg_attribute where attrelid = 'public.perfiles'::regclass and attname = 'cp_fiscal'));
  v_cp     text := col_description('public.perfiles'::regclass,
                     (select attnum from pg_attribute where attrelid = 'public.perfiles'::regclass and attname = 'cp'));
  v_llenas int;
begin
  if v_fiscal is null or v_fiscal not like 'SUPERADA por perfiles.cp (S-07%' then
    raise exception 'S-07: el comentario de perfiles.cp_fiscal no quedó como se escribió: %', coalesce(v_fiscal, '(ninguno)');
  end if;
  if v_cp is null or v_cp not like 'Código postal del domicilio fiscal%S-07%' then
    raise exception 'S-07: el comentario de perfiles.cp no quedó como se escribió: %', coalesce(v_cp, '(ninguno)');
  end if;

  select count(*) into v_llenas from public.perfiles where cp_fiscal is not null;
  if v_llenas > 0 then
    raise exception 'S-07: perfiles.cp_fiscal tiene % filas con valor: no está vacía, y el comentario diría algo falso. Revisar antes de documentarla.', v_llenas;
  end if;

  raise notice 'S-07: perfiles.cp_fiscal documentada como superada por perfiles.cp (vacía, sin DROP).';
end $$;
