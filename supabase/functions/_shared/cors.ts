// CORS de las Edge Functions de PortGo, compartido por las dos (F-06).
//
// Antes respondían `Access-Control-Allow-Origin: *`: cualquier página de
// internet podía llamarlas desde el navegador. La sesión viaja en la cabecera
// Authorization y no en cookies, así que otra web no podía «montar» la sesión
// del usuario; el riesgo era bajo, pero no había motivo para dejarlo abierto.
//
// La regla, por petición:
//   · Origin de la lista        → se atiende y se devuelve ese mismo Origin.
//   · Sin cabecera Origin       → se atiende. Es lo que manda quien no es un
//                                 navegador: la app de Android (llama a
//                                 enviar-notificacion desde código nativo) y
//                                 cualquier llamada de servidor. CORS es una
//                                 regla de navegador; a ellos no les aplica.
//   · Cualquier otro Origin     → 403, sin ejecutar nada.
//
// La lista es la MISMA en los dos proyectos a propósito (el código de las
// funciones es idéntico en pruebas y producción; solo cambian los secretos).
// Las URL de despliegue sueltas de Vercel (portgo-<hash>-…vercel.app) NO
// entran: un patrón que las admitiera admitiría también un proyecto ajeno con
// ese nombre. Se prueba en el alias de la rama, como dice CLAUDE.md.
// Un dominio propio nuevo se añade AQUÍ y en la CSP de vercel.json.
const ORIGENES = new Set([
  'https://portgo-six.vercel.app',                                // main
  'https://portgo-git-dev-salvador-s-projects13.vercel.app',      // dev
])
// `npx serve .` y similares, en cualquier puerto.
const LOCAL = /^http:\/\/(localhost|127\.0\.0\.1)(:\d{1,5})?$/

export function origenPermitido(origen: string | null): boolean {
  if (origen === null) return true
  return ORIGENES.has(origen) || LOCAL.test(origen)
}

// Envuelve el manejador: rechaza el origen ajeno antes de que se ejecute nada
// (incluida la verificación del token) y añade las cabeceras CORS a TODAS las
// respuestas en un solo sitio, en vez de en cada `return json(...)`.
export function conCors(
  permitirCabeceras: string,
  manejar: (req: Request) => Promise<Response>,
): (req: Request) => Promise<Response> {
  return async (req: Request) => {
    const origen = req.headers.get('Origin')
    if (!origenPermitido(origen)) {
      return new Response(JSON.stringify({ error: 'Origen no permitido' }), {
        status: 403,
        headers: { 'Content-Type': 'application/json', 'Vary': 'Origin' },
      })
    }
    const res = req.method === 'OPTIONS'
      ? new Response(null, { status: 204 })
      : await manejar(req)
    // Vary: Origin siempre, para que ninguna caché intermedia sirva a un
    // origen la respuesta preparada para otro.
    res.headers.set('Vary', 'Origin')
    if (origen !== null) {
      res.headers.set('Access-Control-Allow-Origin', origen)
      res.headers.set('Access-Control-Allow-Headers', permitirCabeceras)
      res.headers.set('Access-Control-Allow-Methods', 'POST, OPTIONS')
    }
    return res
  }
}
