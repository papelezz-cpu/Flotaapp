-- ──────────────────────────────────────────────────────────────────────────
-- Preferencia de correo por usuario.
--
-- Cada usuario decide si quiere recibir los correos FRECUENTES:
--   · empresa      → nuevas solicitudes publicadas (nueva_solicitud, solicitudes_lote)
--   · cliente      → ofertas recibidas en sus solicitudes (nueva_oferta)
--   · superadmin   → solicitudes y acuerdos por revisar (revision_solicitud, acuerdo)
--
-- Los correos TRANSACCIONALES no se pueden apagar, porque son parte del
-- servicio contratado y no avisos: confirmación de reserva, reserva aceptada
-- o rechazada, y acuerdo aprobado. Quien los apagara se enteraría tarde de
-- algo que ya se comprometió a cumplir.
--
-- La campana dentro de la app no se ve afectada: siempre llega ahí.
--
-- No hace falta tocar RLS ni el trigger guard_perfil_self_update: ese trigger
-- es lista negra (bloquea rol, aprobacion_cuenta y los campos de
-- verificación), así que una columna nueva la puede editar su propio dueño
-- con la política de UPDATE que ya existe sobre perfiles.
-- ──────────────────────────────────────────────────────────────────────────

ALTER TABLE public.perfiles
  ADD COLUMN IF NOT EXISTS notif_email boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN public.perfiles.notif_email IS
  'Si el usuario quiere recibir los correos frecuentes (oportunidades, ofertas, cola de revisión). Los correos transaccionales se envían siempre. Default true.';
