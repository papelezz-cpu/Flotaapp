-- Soporte tecnico para cumplimiento en materia de datos personales:
--   1) rastro de auditoria de los consentimientos otorgados (aviso de
--      privacidad, terminos, y la declaracion de la empresa sobre los datos
--      sensibles de sus operadores);
--   2) recepcion y seguimiento de solicitudes de derechos ARCO.
--
-- NOTA: el contenido legal (texto del aviso, de los terminos, plazos de
-- respuesta, responsable del tratamiento) NO se define aqui: debe redactarlo
-- o validarlo un abogado. Estas tablas solo registran QUE se acepto, QUE
-- version y CUANDO, que es lo que permite demostrarlo despues.

-- ── CONSENTIMIENTOS ────────────────────────────────────────────────
create table if not exists public.consentimientos (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  tipo        text not null check (tipo in (
                'aviso_privacidad',
                'terminos',
                'datos_sensibles_operador'  -- la empresa declara tener el
              )),                            -- consentimiento del operador
  version     text not null,
  aceptado_en timestamptz not null default now(),
  contexto    text,                          -- 'registro' | 'alta_operador' | ...
  referencia  text,                          -- id del operador, cuando aplique
  created_at  timestamptz not null default now()
);

create index if not exists idx_consentimientos_user on public.consentimientos(user_id);
create index if not exists idx_consentimientos_tipo on public.consentimientos(tipo, version);

alter table public.consentimientos enable row level security;

-- Cada quien inserta y lee sus propios consentimientos; superadmin lee todo.
-- No se permite UPDATE ni DELETE a nadie: un rastro de auditoria que se puede
-- editar no sirve como evidencia.
drop policy if exists consentimientos_insert_propio on public.consentimientos;
create policy consentimientos_insert_propio on public.consentimientos
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists consentimientos_select_propio on public.consentimientos;
create policy consentimientos_select_propio on public.consentimientos
  for select to authenticated
  using (user_id = auth.uid() or public.is_superadmin());

-- ── SOLICITUDES ARCO ───────────────────────────────────────────────
-- Acceso, Rectificacion, Cancelacion, Oposicion.
create table if not exists public.solicitudes_arco (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid references auth.users(id) on delete set null,
  nombre       text not null,
  email        text not null,
  tipo         text not null check (tipo in ('acceso','rectificacion','cancelacion','oposicion')),
  descripcion  text not null,
  estado       text not null default 'pendiente'
                 check (estado in ('pendiente','en_proceso','atendida','rechazada')),
  respuesta    text,
  atendida_por uuid references auth.users(id) on delete set null,
  atendida_en  timestamptz,
  created_at   timestamptz not null default now()
);

create index if not exists idx_arco_estado on public.solicitudes_arco(estado, created_at desc);
create index if not exists idx_arco_user   on public.solicitudes_arco(user_id);

alter table public.solicitudes_arco enable row level security;

-- El titular crea su solicitud y puede seguir el estado de las suyas.
drop policy if exists arco_insert_propio on public.solicitudes_arco;
create policy arco_insert_propio on public.solicitudes_arco
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists arco_select_propio on public.solicitudes_arco;
create policy arco_select_propio on public.solicitudes_arco
  for select to authenticated
  using (user_id = auth.uid() or public.is_superadmin());

-- Solo superadmin resuelve. El titular no puede editar su solicitud una vez
-- enviada (evita alterar la evidencia del plazo de respuesta).
drop policy if exists arco_update_superadmin on public.solicitudes_arco;
create policy arco_update_superadmin on public.solicitudes_arco
  for update to authenticated
  using (public.is_superadmin())
  with check (public.is_superadmin());
