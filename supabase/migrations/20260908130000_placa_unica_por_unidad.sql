-- ============================================================================
-- H-15 (resto): deshace el duplicado de placa y pone el candado
-- ============================================================================
--
-- La auditoria propuso un indice unico sobre camiones.placas y dijo que
-- aplicaba limpio. Era falso: la medicion original leyo el volcado separando
-- por espacios en vez de por tabuladores, y el campo que salia no era el de
-- la placa. Al medirlo bien aparecio un duplicado real:
--
--     T-001         Torton caja seca   alta 2026-04-29   placa 12345
--     R-8C5DEE8E    Rabon              alta 2026-06-09   placa 12345
--
-- Las dos en aprobacion = 'aprobada', y de tipo distinto: no es una fila
-- repetida, son dos vehiculos con la misma placa registrada.
--
-- Confirmado con el dueno el 2026-09-08: el duplicado salio de una prueba, y
-- la placa se queda en la unidad ORIGINAL (T-001, la mas antigua). A la otra
-- se le asigna otra.
--
-- ── Por que 'PRUEBA-001' y no una placa de aspecto real ───────────────────
--
-- Porque la placa verdadera de esa unidad no se sabe, y un valor con pinta de
-- placa federal autentica seria peor que uno obviamente falso: alguien podria
-- darlo por bueno e imprimirlo en un documento de viaje o una carta porte.
-- 'PRUEBA-001' no se puede confundir con un dato real y se ve a simple vista
-- en cualquier listado, que es justo lo que hace falta para que se corrija
-- cuando alguien sepa la placa buena.
--
-- Si mas adelante se conoce, es un UPDATE de una linea. El indice unico de
-- abajo ya impide que se vuelva a chocar con otra.
--
-- ── Orden y atomicidad ────────────────────────────────────────────────────
--
-- El UPDATE y el CREATE UNIQUE INDEX van en el mismo archivo a proposito: si
-- el indice fallara por cualquier otro duplicado que no hayamos visto, el
-- UPDATE revierte con el. O queda todo coherente, o no queda nada.
--
-- Sin CONCURRENTLY: 11 filas. Ver la cabecera de 20260908120000.
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1. Liberar la placa de la unidad de prueba
-- ─────────────────────────────────────────────────────────────────────────
-- El WHERE es defensivo y hace la migracion idempotente: solo toca la fila si
-- SIGUE compartiendo placa con T-001. Si alguien ya le puso la placa buena
-- entre que esto se escribio y se aplica, no se la pisa.

update public.camiones
   set placas = 'PRUEBA-001'
 where id = 'R-8C5DEE8E'
   and placas is not null
   and placas = (select placas from public.camiones where id = 'T-001');


-- ─────────────────────────────────────────────────────────────────────────
-- 2. El candado
-- ─────────────────────────────────────────────────────────────────────────
-- Una placa identifica un vehiculo en todo el pais: dos unidades no pueden
-- compartirla. Parcial sobre NOT NULL porque hay camiones sin placa dada de
-- alta todavia (2 de 11 hoy) y varios NULL no se estorban entre si.
--
-- A partir de aqui, intentar repetir una placa devuelve un error visible en
-- vez de aceptarse en silencio, que es como se coló este duplicado.

create unique index if not exists uq_camiones_placas
  on public.camiones (placas)
  where placas is not null;


-- ─────────────────────────────────────────────────────────────────────────
-- 3. Comprobacion
-- ─────────────────────────────────────────────────────────────────────────
-- Si el indice se creo, no quedan duplicados por definicion. Esto es para que
-- la salida del guion lo diga en voz alta en vez de tener que ir a mirarlo.

do $$
declare v_dups int;
begin
  select count(*) into v_dups
    from (select placas from public.camiones
           where placas is not null
           group by placas having count(*) > 1) d;
  raise notice 'camiones con placa duplicada: % (debe ser 0)', v_dups;
end $$;
