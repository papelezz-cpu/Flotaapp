-- ============================================================================
-- Una plantilla guarda valores, no un esquema entero (H-05)
-- ============================================================================
--
-- ── El defecto ────────────────────────────────────────────────────────────
--
-- Una plantilla es un pedido sin fechas y con nombre. Estaba modelada como una
-- SEGUNDA TABLA que replica el esquema de pedidos columna por columna:
--
--     pedidos            63 columnas
--     plantillas_pedido  52 columnas
--     en comun           49
--     solo en plantillas nombre, veces_usada, ultima_vez_usada
--
-- Anadir un campo de carga obligaba a tocar dos tablas, dos migraciones y el
-- mapa PLANTILLA_CAMPOS de js/plantillas.js. Olvidar uno de los tres no da
-- error: la plantilla pierde ese dato en silencio.
--
-- ── Y ya se habia separado, en siete sitios ───────────────────────────────
--
-- Medido contra el esquema de produccion el 2026-09-15. De las 49 columnas
-- compartidas, SIETE no coinciden:
--
--     capacidad_min      pedidos integer      plantillas numeric
--     tipo_camion        pedidos NOT NULL      plantillas nullable
--     carga_peligrosa    pedidos nullable      plantillas NOT NULL
--     temp_controlada    pedidos nullable      plantillas NOT NULL
--     requiere_seguro    pedidos nullable      plantillas NOT NULL
--     requiere_factura   pedidos nullable      plantillas NOT NULL
--     cliente_id         pedidos nullable      plantillas NOT NULL
--
-- Nadie decidio ninguna de esas siete. Se escribieron dos veces y salieron
-- distintas.
--
-- Ninguna hace dano HOY, y conviene decirlo sin adornar: capacidad_min, la mas
-- llamativa, ni siquiera esta en PLANTILLA_CAMPOS, asi que las plantillas nunca
-- la guardan ni la restauran. Es una columna que existe solo porque se copio el
-- esquema entero. Las siete son sintoma del defecto —dos esquemas escritos a
-- mano que deberian ser uno— no un fallo en curso. El defecto es que la octava
-- divergencia llegara sin que nadie la decida tampoco, y esa puede doler.
--
-- ── Por que jsonb aqui, si en el resto del esquema seria un error ──────────
--
-- Porque estos valores NO SE CONSULTAN. No se filtra por ellos, no se agregan,
-- no se unen con nada: se recuperan enteros por id para rellenar un formulario.
-- Es exactamente el caso en que una columna por campo no aporta nada y cuesta
-- una migracion cada vez.
--
-- Lo contrario de pedidos, donde cada columna aparece en un WHERE, un indice o
-- un guard. Ahi seguirian siendo columnas, y este cambio no las toca.
--
-- ── Lo que esta migracion NO hace ─────────────────────────────────────────
--
-- NO retira las 49 columnas. El codigo nuevo deja de leerlas, pero se quedan
-- hasta que lo nuevo lleve tiempo funcionando. Retirarlas es un DROP y eso es
-- otra conversacion, con la Regla #1 delante.
--
-- Mientras tanto la tabla tiene el dato dos veces. Es a proposito: permite
-- volver atras revirtiendo solo el codigo.
--
-- ── Y por que el orden de despliegue da igual ─────────────────────────────
--
-- js/plantillas.js lee con `p.datos?.[col] ?? p[col]`, asi que funciona con las
-- filas viejas (columnas) y con las nuevas (datos). Migracion antes o codigo
-- antes, da lo mismo: no hay ventana rota.
--
-- Se hace asi por lo que paso con H-02, donde migracion-primero dejaba
-- "Guardar perfil" fallando hasta que el push terminaba de desplegar.
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1. La columna
-- ─────────────────────────────────────────────────────────────────────────

alter table public.plantillas_pedido
  add column if not exists datos jsonb not null default '{}'::jsonb;

comment on column public.plantillas_pedido.datos is
  'Valores del formulario de la solicitud, tal cual. Es el unico sitio donde jsonb esta justificado en este esquema: no se filtra ni se agrega por ellos, se recuperan enteros por id para rellenar el formulario. Las fechas NO se guardan, a proposito.';


-- ─────────────────────────────────────────────────────────────────────────
-- 2. Pasar lo que ya hay
-- ─────────────────────────────────────────────────────────────────────────
-- to_jsonb(fila) menos las columnas que siguen siendo columnas. Se construye
-- restando en vez de enumerando las 49: una lista escrita a mano envejece en
-- cuanto alguien anada un campo, y esa leccion ya la dejo escrita la migracion
-- A6 (20260911150000) cuando se dejo una relacion fuera.
--
-- Solo se rellenan las filas que aun no lo tengan, asi que es idempotente.
-- Los nulos se descartan: no aportan y engordan el jsonb.

update public.plantillas_pedido p
   set datos = (
     select jsonb_strip_nulls(
       to_jsonb(p)
         - 'id' - 'cliente_id' - 'nombre'
         - 'veces_usada' - 'ultima_vez_usada' - 'created_at'
         - 'datos'
     )
   )
 where p.datos = '{}'::jsonb;


-- ─────────────────────────────────────────────────────────────────────────
-- 3. Comprobacion
-- ─────────────────────────────────────────────────────────────────────────
-- No basta con que la columna exista: hay que comprobar que el contenido
-- SOBREVIVIO. Se verifica fila a fila contra las columnas originales, que
-- siguen ahi justamente para poder hacer esto.

do $$
declare
  v_total      int;
  v_vacias     int;
  v_discrepa   int;
begin
  select count(*) into v_total from public.plantillas_pedido;

  -- Una fila con algun dato en las columnas viejas no puede quedar con datos
  -- vacio. Una plantilla recien creada y totalmente en blanco si puede.
  select count(*) into v_vacias
    from public.plantillas_pedido
   where datos = '{}'::jsonb
     and (origen is not null or destino is not null or tipo_carga is not null
          or peso_carga is not null or tipo_camion is not null);

  if v_vacias > 0 then
    raise exception 'H-05: % fila(s) con datos en las columnas y datos jsonb vacio.', v_vacias;
  end if;

  -- Y que lo copiado coincida, en los campos que de verdad se usan.
  select count(*) into v_discrepa
    from public.plantillas_pedido
   where (origen      is not null and datos->>'origen'      is distinct from origen)
      or (destino     is not null and datos->>'destino'     is distinct from destino)
      or (tipo_carga  is not null and datos->>'tipo_carga'  is distinct from tipo_carga)
      or (tipo_camion is not null and datos->>'tipo_camion' is distinct from tipo_camion);

  if v_discrepa > 0 then
    raise exception 'H-05: % fila(s) donde datos no coincide con las columnas.', v_discrepa;
  end if;

  raise notice 'H-05: % plantilla(s) con sus valores en datos jsonb, verificadas contra las columnas.', v_total;
end $$;


-- ─────────────────────────────────────────────────────────────────────────
-- Como revertir
-- ─────────────────────────────────────────────────────────────────────────
--   Basta con revertir el codigo: las 49 columnas siguen intactas y con su
--   contenido. La columna datos se puede dejar sin tocar; si se quiere quitar:
--
--     alter table public.plantillas_pedido drop column datos;
--
--   ⚠ Eso SI destruye lo escrito por el codigo nuevo. Cualquier plantilla
--   creada despues de esta migracion vive solo en datos, porque el codigo
--   nuevo ya no rellena las columnas.
