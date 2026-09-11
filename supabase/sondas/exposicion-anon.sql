-- Que puede ver `anon` —el rol SIN sesion— en el esquema public.
-- Solo lee. Si las cuatro consultas salen vacias, no hay nada expuesto.
--
-- ── Por que existe ────────────────────────────────────────────────────────
--
-- Nace porque A5 no se pudo aplicar. El plan era cerrar los privilegios por
-- defecto de supabase_admin, que reparten GRANT ALL a anon en cada tabla nueva
-- que cree ese rol. No se pudo: cambiarlos exige ser miembro de supabase_admin,
-- y ni el rol que aplica migraciones ni el SQL Editor del panel lo son
-- (ERROR 42501, comprobado el 2026-09-11 en pruebas).
--
-- Asi que en vez de PREVENIR, se DETECTA. Y detectar sale ganando, porque cubre
-- tambien el fallo mas probable, que A5 no cubria: que alguien cree una tabla
-- —da igual con que rol— y se olvide de activarle RLS. Ese olvido no lo impide
-- ninguna plantilla de permisos.
--
-- ── Por que no basta verificar-paridad.sh ─────────────────────────────────
--
-- Porque compara las dos bases entre si. Si a las dos les falta RLS en la misma
-- tabla, la paridad sale "identica" y todo parece correcto. Esta sonda no
-- compara: afirma. Cada consulta describe un invariante que debe cumplirse en
-- cualquier proyecto, por si solo.
--
-- ── Como leerla ───────────────────────────────────────────────────────────
--
-- Se corre contra el proyecto que se quiera auditar, pruebas o produccion:
--   psql "<cadena>" -f supabase/sondas/exposicion-anon.sql
--
-- Las cuatro primeras deben salir VACIAS. La quinta es informativa y hoy
-- devuelve una fila: es justo A5, que sigue abierto.

\echo ''
\echo '=== 1. Tablas de public SIN RLS activada ==='
\echo '    Cualquier fila aqui es una tabla cuyo contenido no filtra ninguna'
\echo '    politica. Si ademas anon tiene el GRANT (consulta 3), esta abierta'
\echo '    a internet: la clave anon es publica, vive en js/config.js.'
SELECT c.relname AS tabla,
       CASE WHEN has_table_privilege('anon', c.oid, 'SELECT')
            THEN 'SI — ABIERTA A INTERNET' ELSE 'no' END AS anon_puede_leer
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public'
   AND c.relkind IN ('r', 'p')
   AND NOT c.relrowsecurity
 ORDER BY 2 DESC, 1;

\echo ''
\echo '=== 2. Tablas con RLS activada pero SIN ninguna politica ==='
\echo '    No es un fallo en si —sin politicas no se lee nada— pero casi'
\echo '    siempre significa que alguien activo RLS y dejo el trabajo a medias.'
SELECT c.relname AS tabla
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public'
   AND c.relkind IN ('r', 'p')
   AND c.relrowsecurity
   AND NOT EXISTS (SELECT 1 FROM pg_policy p WHERE p.polrelid = c.oid)
 ORDER BY 1;

\echo ''
\echo '=== 3. Privilegios de tabla de anon, fuera de lo permitido ==='
\echo '    Lo unico que anon debe poder es SELECT sobre app_config, que la app'
\echo '    lee antes de que nadie inicie sesion. Ver 20260827160000.'
SELECT table_name, privilege_type
  FROM information_schema.table_privileges
 WHERE grantee = 'anon'
   AND table_schema = 'public'
   AND NOT (table_name = 'app_config' AND privilege_type = 'SELECT')
 ORDER BY 1, 2;

\echo ''
\echo '=== 4. Funciones SECURITY DEFINER sin search_path fijado ==='
\echo '    Una SECURITY DEFINER sin search_path se puede secuestrar creando'
\echo '    objetos que le salgan al paso. Deben ser CERO.'
SELECT p.proname AS funcion
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.prosecdef
   AND (p.proconfig IS NULL
        OR NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search\_path=%'))
 ORDER BY 1;

\echo ''
\echo '=== 5. INFORMATIVO — plantilla de permisos para tablas futuras (A5) ==='
\echo '    Cada fila que mencione a anon significa que las tablas que cree ESE'
\echo '    rol naceran con permisos para anon. Hoy sale supabase_admin, y no se'
\echo '    puede cambiar sin ser miembro de ese rol: es A5, que sigue abierto.'
\echo '    Mientras siga asi, la consulta 1 es la red que lo cubre.'
SELECT pg_get_userbyid(d.defaclrole) AS rol_que_crea,
       CASE d.defaclobjtype WHEN 'r' THEN 'tablas' WHEN 'S' THEN 'secuencias'
                            WHEN 'f' THEN 'funciones' ELSE d.defaclobjtype::text END AS sobre,
       array_to_string(d.defaclacl, ', ') AS plantilla
  FROM pg_default_acl d
  JOIN pg_namespace n ON n.oid = d.defaclnamespace
 WHERE n.nspname = 'public'
   AND EXISTS (SELECT 1 FROM unnest(d.defaclacl) a WHERE a::text LIKE 'anon=%')
 ORDER BY 1, 2;

\echo ''
