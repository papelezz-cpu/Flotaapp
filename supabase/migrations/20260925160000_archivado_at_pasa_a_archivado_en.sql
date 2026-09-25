-- ============================================================================
-- `reservaciones_historico.archivado_at` → `archivado_en` (H-22)
-- ============================================================================
--
-- ── Por qué ───────────────────────────────────────────────────────────────
--
-- El esquema usa `_en` para las marcas de momento: `solicitado_en`,
-- `atendida_en`, `pagado_en`, `completado_en`, `cancelacion_solicitada_en`,
-- `docs_aprobados_en`… y **dos columnas rompen el patrón, cada una por su lado**:
-- `reservaciones_historico.archivado_at` y `app_config.actualizado_en` (esta al
-- revés: sigue `_en` pero traduce el verbo).
--
-- No hay impacto en ejecución. Es coste de lectura: obliga a mirar el esquema
-- cada vez, y quien escriba código nuevo acertará la mitad de las veces.
--
-- ── Por qué es seguro, y por qué no hay ventana de rotura ─────────────────
--
-- **Nadie lee esta columna.** Medido el 2026-09-25 en `js/`, en las migraciones y
-- en el volcado del esquema: no se pinta en ninguna pantalla, no se ordena por
-- ella, y no aparece en ninguna política, vista ni función. Su única aparición era
-- una escritura, `js/reservaciones.js` al archivar una reservación.
--
-- Y esa escritura **se retiró primero**, en el mismo cambio de código: la columna
-- tiene `DEFAULT now()`, así que el cliente no necesita mandarla. Con el cliente
-- callado, el renombrado es invisible y **el orden de despliegue deja de
-- importar** — si esta migración llega antes que el código, o después, nada se
-- rompe. Es la misma táctica que `_pv()` en H-05.
--
-- De paso el dato mejora: antes la marca venía de `new Date()` del **navegador**;
-- ahora del servidor, que es el mismo reloj para todas las filas.
--
-- ── Lo que NO se toca ─────────────────────────────────────────────────────
--
-- `app_config.actualizado_en` se queda: ya sigue el sufijo correcto, y renombrar
-- el verbo sería ruido por ruido.
--
-- Las otras cuatro inconsistencias de H-22 no son trabajo:
--   · **PK `text` con prefijo** (camiones, custodios, patios, lavados,
--     operadores) frente a `uuid` en el resto: **se deja**. El id legible se le
--     enseña al usuario, y cambiarlo tocaría `reservaciones.unidad` y las
--     políticas de Storage, que usan el id en la ruta.
--   · **Mismo nombre, distinto tipo** (`tipo_carga`, `certificaciones`): son
--     deliberados — uno es lista, el otro texto libre.
--   · **Fechas de vigencia con tres nombres** y **rutas de ficheros con tres
--     formas**: las resolvió H-04 al unificar en `vigencias`.
-- ============================================================================

do $$
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'reservaciones_historico'
                and column_name = 'archivado_at') then
    alter table public.reservaciones_historico rename column archivado_at to archivado_en;
    raise notice '  archivado_at renombrada a archivado_en';
  else
    raise notice '  ya estaba renombrada; nada que hacer';
  end if;
end $$;

comment on column public.reservaciones_historico.archivado_en is
  'H-22: se llamaba archivado_at y rompia la convencion _en del resto del esquema. La escribe el DEFAULT now() del servidor, no el cliente: asi el renombrado no tuvo ventana de rotura. Nadie la lee.';


-- ── Comprobación ───────────────────────────────────────────────────────────

do $$
declare
  v_def  text;
  v_id   uuid := gen_random_uuid();
  v_marca timestamptz;
begin
  if exists (select 1 from information_schema.columns
              where table_schema='public' and table_name='reservaciones_historico'
                and column_name='archivado_at') then
    raise exception 'H-22: archivado_at sigue existiendo.';
  end if;

  select column_default into v_def from information_schema.columns
   where table_schema='public' and table_name='reservaciones_historico'
     and column_name='archivado_en';
  if v_def is null then
    raise exception 'H-22: archivado_en no existe, o perdio su DEFAULT. Sin el default el cliente no manda nada y la columna quedaria NULL siempre.';
  end if;
  if v_def not like '%now()%' then
    raise exception 'H-22: el DEFAULT de archivado_en no es now(), es "%".', v_def;
  end if;

  -- Comportamiento: insertar SIN mencionar la columna la sella igual, que es de
  -- lo que depende el cliente desde este cambio. Se descarta al final.
  begin
    insert into public.reservaciones_historico (id, estado) values (v_id, 'Completada');
    select archivado_en into v_marca from public.reservaciones_historico where id = v_id;
    if v_marca is null then
      raise exception 'H-22: una insercion sin mencionar archivado_en la dejo NULL. El cliente ya no la manda, asi que el historico perderia la fecha.';
    end if;
    if v_marca <> now() then
      raise exception 'H-22: la marca no es la hora del servidor (%). Revisa el DEFAULT.', v_marca;
    end if;
    raise exception 'H22-DESCARTAR';
  exception
    when others then
      if sqlerrm <> 'H22-DESCARTAR' then
        raise;
      end if;
  end;

  raise notice 'H-22: archivado_en en su sitio, con DEFAULT now(). Ejercitado: una insercion que no la menciona queda sellada con la hora del servidor.';
end $$;
