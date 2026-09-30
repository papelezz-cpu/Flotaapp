-- ─────────────────────────────────────────────────────────────────────────
-- El bucket `documentos-empresa` existe (public=true) pero no tiene NINGUNA
-- política de storage.objects — confirmado listando las 11 políticas
-- existentes en portgo-pruebas el 2026-09-30: cubren unidades,
-- documentos-viaje, operadores y registros. documentos-empresa no aparece
-- en ninguna. Con RLS encendido por defecto y sin política que calce,
-- CUALQUIER operación se rechaza — "new row violates row-level security
-- policy" al intentar subir el permiso SCT / seguros desde Perfil de
-- empresa (js/admin.js, solicitarActualizacionDocs → _uploadDoc).
--
-- Ninguna migración rastreada creó nunca las políticas de este bucket —
-- como perfiles y otras piezas de la línea base, nació desde el dashboard.
--
-- Mismo patrón que ya usan los otros buckets públicos (operadores_upload/
-- _read, reg_upload/_select): sube quien tiene sesión, a su propia carpeta
-- (storage.foldername(name)[1] = auth.uid() — coincide con el path que ya
-- arma _uploadDoc: `${uid}/${nombre}_${ts}.${ext}`); lee cualquiera, porque
-- el bucket es público y el cliente usa getPublicUrl(), no createSignedUrl().
--
-- Sin política de UPDATE a propósito: cada subida lleva un timestamp en el
-- nombre (`${ts}`), así que upsert:true nunca choca con un objeto
-- existente de verdad — mismo motivo por el que operadores tampoco la tiene.

create policy docempresa_upload on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'documentos-empresa'
    and (storage.foldername(name))[1] = (auth.uid())::text
  );

create policy docempresa_read on storage.objects
  for select to public
  using (bucket_id = 'documentos-empresa');
