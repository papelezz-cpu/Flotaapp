-- Buckets de Storage copiados de producción.
-- Ojo con la columna public: unidades, registros y documentos-viaje
-- son privados y se leen con URL firmada.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('custodios', 'custodios', 't', null, null) on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('documentos-empresa', 'documentos-empresa', 't', null, null) on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('documentos-viaje', 'documentos-viaje', 'f', null, null) on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('operadores', 'operadores', 't', null, null) on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('registros', 'registros', 'f', null, null) on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('unidades', 'unidades', 'f', null, null) on conflict (id) do nothing;
