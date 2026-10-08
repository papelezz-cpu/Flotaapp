// ── RESERVACIONES ─────────────────────────────────────

// Filtro de estado de la vista de reservaciones. Por defecto "Activa": al
// entrar desde el cuadro del home se ven primero las activas; los demás
// estados se ven con las pills.
let _reservFiltro = 'Activa';

// Ids de reservación con el panel de acciones secundarias abierto. Se guarda
// aparte del DOM porque renderReserv() se vuelve a llamar seguido (realtime,
// notificaciones) y sin esto cada refresh cerraría lo que el usuario acababa
// de abrir.
const _reservAbiertas = new Set();

function toggleReservDetalle(id) {
  const panel  = document.getElementById(`reserv-detalle-${id}`);
  const toggle = document.getElementById(`reserv-toggle-${id}`);
  if (!panel || !toggle) return;
  const abrir = !panel.classList.contains('open');
  panel.classList.toggle('open', abrir);
  toggle.classList.toggle('open', abrir);
  toggle.setAttribute('aria-expanded', abrir ? 'true' : 'false');
  if (abrir) _reservAbiertas.add(id); else _reservAbiertas.delete(id);
}

const _RESERV_FILTRO_LABEL = {
  Activa: 'activas', Pendiente: 'pendientes', PorAprobar: 'por aprobar', Completada: 'completadas',
  Cancelada: 'canceladas', CancelacionSolicitada: 'con cancelación en revisión', PorCobrar: 'por cobrar', Vencido: 'con pago vencido', todas: '',
};

// Texto legible del estado (la DB guarda 'PorAprobar' sin espacio)
const _ESTADO_LABEL = { PorAprobar: 'Por aprobar', CancelacionSolicitada: 'Cancelación en revisión' };
const _estadoLabel = estado => _ESTADO_LABEL[estado] || estado;

// ── COLUMNAS DEL LISTADO (H-08) ───────────────────────
//
// `reservaciones` tiene 50 columnas y la lista se traía todas. Medido contra
// la base el 2026-09-18, con las 20 filas: 31.429 bytes con '*' frente a
// 16.472 con esta lista — 1,91x. La ficha del hallazgo prometía «entre 3 y 5
// veces»; no es cierto, y conviene que el número escrito sea el medido.
//
// Derivada del código, no de memoria: columnas reales del esquema cruzadas
// con los accesos `algo.columna` de reservaciones.js, cobros.js, tracking.js,
// expedientes.js, detalle.js y aprobaciones.js. Las 18 que faltan —el
// vocabulario de Carta Porte, los detalles de pago ya registrado y las notas
// de resolución— no aparecen en NINGÚN fichero de js/, comprobado uno a uno.
//
// Vigilada por pruebas/13-sonda-columnas-listado.mjs: si alguna de las
// omitidas empieza a usarse, falla. Olvidar una columna no da error, deja un
// hueco en la interfaz — y un hueco no avisa.
const RES_COLS_LISTA = [
  'id','unidad','cliente','telefono','fecha_ini','fecha_fin','descripcion','estado',
  'created_at','cliente_email','cliente_user_id','tracking_estado','precio_acordado',
  'recurso_tipo','propietario_id','completado_en','calificado','pagado','evidencias',
  'pedido_id','evidencias_cliente','finalizacion_solicitada_por','plazo_pago',
  'fecha_vencimiento_pago','cancelacion_solicitada_en','cancelacion_motivo',
  'cancelacion_detalle','cancelacion_tracking_estado','operador_id','operador_nombre',
  'documentos_carga','gps_link',
].join(',');

// ── SIGUIENTE PASO ────────────────────────────────────
// Le dice a la empresa qué toca ahora en una reservación, para que no tenga
// que adivinarlo entre diez botones. Se deriva de lo que la fila ya trae
// (chofer, seguimiento, expedientes, cobro) — no se guarda nada, igual que
// estadoCobro. Es una guía, no un candado: lo único que se bloquea es lo que
// el sistema ya bloqueaba (avanzar sin chofer, completar sin llegar al último
// paso del seguimiento).
//
// Devuelve un ARRAY, no un solo paso: revisar documentos y avanzar el
// seguimiento son pistas independientes —una no espera a la otra—, así que
// pueden estar pendientes las dos a la vez y las dos se resaltan. Solo se
// excluyen entre sí las que de verdad son incompatibles: avanzar y completar
// (son pasos distintos del mismo seguimiento) y avanzar cuando falta el
// chofer que lo bloquea (ver tracking.js) — eso sí seguiría dando error.
//   clave   → qué botón(es) se resaltan: chofer | avanzar | puerto | vacios | completar | cobro
//   corto   → texto del chip en la fila (uno por paso pendiente)
//   detalle → frase completa dentro del panel
//   accion  → el onclick que lleva directo a hacerlo (lo usa el chip de la fila)
//   espera  → lo que depende del cliente, igual en todos los pasos devueltos
function _trackingEnUltimoPaso(r) {
  const pasos = _getEstados(r.recurso_tipo);
  return (r.tracking_estado || pasos[0].key) === pasos[pasos.length - 1].key;
}

function _siguientesPasosReserva(r) {
  const ACCION = {
    chofer:    `abrirAsignarChofer('${r.id}')`,
    puerto:    `abrirExpediente('${r.id}','ingreso_puerto')`,
    vacios:    `abrirExpediente('${r.id}','entrega_vacios')`,
    avanzar:   `openTracking('${r.id}')`,
    completar: `abrirEvidencias('${r.id}','evidencias')`,
    cobro:     `abrirRegistrarPago('${r.id}')`,
  };
  if (r.estado === 'Completada') {
    return r.pagado ? [] : [{
      clave: 'cobro', corto: 'Registrar pago', accion: ACCION.cobro,
      detalle: 'El servicio ya se completó: registra el pago cuando lo recibas.', espera: null,
    }];
  }
  if (r.estado !== 'Activa' || typeof _getEstados !== 'function') return [];

  // "solicitado" = la pelota la tiene el cliente; "en_revision" = ya subió
  // todo y le toca a la empresa aprobar o rechazar (ver expedientes.js).
  const pendCliente = [];
  if (r._expIngreso?.estado === 'solicitado') pendCliente.push('Puerto');
  if (r._expVacios?.estado  === 'solicitado') pendCliente.push('Vacíos');
  const espera = pendCliente.length
    ? `Esperando que el cliente suba los documentos de ${pendCliente.join(' y ')}.` : null;
  const paso = (clave, corto, detalle) => ({ clave, corto, detalle, accion: ACCION[clave], espera });

  const pasos = [];
  const esCamion    = !r.recurso_tipo || r.recurso_tipo === 'camion';
  const choferFalta = esCamion && !r.operador_nombre;
  if (choferFalta) {
    pasos.push(paso('chofer', 'Asignar chofer', 'Asigna un chofer: sin él no se puede avanzar el seguimiento del viaje.'));
  }
  if (r._expIngreso?.estado === 'en_revision') {
    pasos.push(paso('puerto', 'Revisar docs de Puerto', 'El cliente ya subió los documentos de Puerto: revísalos y apruébalos o recházalos.'));
  }
  if (r._expVacios?.estado === 'en_revision') {
    pasos.push(paso('vacios', 'Revisar docs de Vacíos', 'El cliente ya subió los documentos de Vacíos: revísalos y apruébalos o recházalos.'));
  }

  const pasosTracking = _getEstados(r.recurso_tipo);
  const idx = Math.max(0, pasosTracking.findIndex(p => p.key === (r.tracking_estado || pasosTracking[0].key)));
  // Solo el primer paso exige chofer (tracking.js); de ahí en adelante avanzar
  // no depende de él, así que sí se muestra junto con lo demás pendiente.
  const avanzarBloqueado = choferFalta && idx === 0;
  if (!avanzarBloqueado) {
    if (idx < pasosTracking.length - 1) {
      const sig = pasosTracking[idx + 1];
      pasos.push(paso('avanzar', `Marcar: ${sig.label}`, `Cuando ocurra, marca en el seguimiento: «${sig.label}».`));
    } else {
      pasos.push(paso('completar', 'Completar servicio', 'El seguimiento llegó al final: completa el servicio subiendo tu evidencia.'));
    }
  }
  return pasos;
}

// ── PAGINACIÓN ────────────────────────────────────────
// Mismo patrón que renderPedidos: un bloque inicial y un botón que añade el
// siguiente. Antes esta vista se traía la tabla ENTERA —para el superadmin,
// sin un solo filtro— y descartaba en el navegador lo que acababa de
// transferir. Con realtime re-renderizando en cada cambio de cualquier
// reservación, eso se repetía constantemente.
const RESERV_PAGE = 30;
let _reservCursor = null;   // { created_at, id } de la última fila traída
let _reservAccum  = [];

// El filtro de las pills, traducido a SQL. Es la contraparte servidor de lo
// que hacía _aplicaFiltroReserva en memoria.
//
// 'PorCobrar' y 'Vencido' no son estados guardados: los deriva estadoCobro()
// en js/cobros.js a partir de pagado + fecha_vencimiento_pago. La derivación
// es determinista, así que se puede expresar en SQL — y el índice parcial
// idx_reservaciones_cobro (pagado, fecha_vencimiento_pago) WHERE
// estado='Completada' la cubre exactamente.
function _filtroReservaSQL(q, filtro = _reservFiltro) {
  const hoy = today();
  // Las archivadas no salen en la lista, en ninguna pestaña ni en sus globos
  // (A2-C2). Siguen en reportes y desempeño, y el superadmin las ve en el
  // Historial. Solo se archiva lo cerrado y cobrado, así que nunca falta algo
  // de «Por cobrar» ni de «Vencido».
  q = q.is('archivada_en', null);
  switch (filtro) {
    case 'todas':
      return q;
    case 'Cancelada':
      return q.in('estado', ['Cancelada', 'Rechazada']);
    case 'PorCobrar':
      // Sin vencer: o no tiene fecha límite, o aún no ha llegado.
      return q.eq('estado', 'Completada').eq('pagado', false)
              .or(`fecha_vencimiento_pago.is.null,fecha_vencimiento_pago.gte.${hoy}`);
    case 'Vencido':
      return q.eq('estado', 'Completada').eq('pagado', false)
              .lt('fecha_vencimiento_pago', hoy);
    default:
      return q.eq('estado', filtro);
  }
}

// ── BADGES DE LAS PILLS ────────────────────────────────
// Cuántas reservaciones hay en cada pill, para que no haya que hacer clic en
// cada una para enterarse — mismo problema que resuelve el chip "siguiente
// paso" dentro de la fila, un nivel arriba: si la pestaña por defecto
// ("Activas") está vacía, nada avisaba que "Por aprobar" tenía algo
// esperando. Reutiliza _filtroReservaSQL, así que el número nunca puede
// decir algo distinto de lo que se ve al hacer clic (R-05: un globo que
// cuenta distinto de lo que la pantalla lista es peor que no tener globo).
//
// Solo estas: son las que de verdad significan "algo pendiente".
// 'Pendiente' se queda fuera a propósito — es un estado inalcanzable hoy
// (hueco 6, docs/FLUJO-OPERATIVO.md), badgearlo siempre mostraría 0.
const _RESERV_PILLS_BADGE = ['PorAprobar', 'CancelacionSolicitada', 'PorCobrar', 'Vencido'];

async function actualizarBadgesPillsReserv() {
  if (!currentUser?.id) return;
  await Promise.all(_RESERV_PILLS_BADGE.map(async filtro => {
    const el = document.querySelector(`#reserv-filtros-bar .ped-filtro-pill[data-rest="${filtro}"] .pill-count`);
    if (!el) return;
    let q = sb.from('reservaciones').select('id', { count: 'exact', head: true });
    if (currentUser.rol === 'cliente')    q = q.eq('cliente_user_id', currentUser.id);
    else if (currentUser.rol === 'admin') q = q.eq('propietario_id', currentUser.id);
    q = _filtroReservaSQL(q, filtro);
    const { count } = await q;
    if (count > 0) {
      el.textContent = count > 99 ? '99+' : count;
      el.style.display = 'inline-flex';
    } else {
      el.style.display = 'none';
    }
  }));
}

function filtrarReservas(est) {
  _reservFiltro = est;
  document.querySelectorAll('#reserv-filtros-bar .ped-filtro-pill').forEach(el =>
    el.classList.toggle('active', el.dataset.rest === est));
  renderReserv();   // sin append: reinicia cursor y acumulado
}

let _cargandoMasReservas = false;

async function cargarMasReservas() {
  if (_cargandoMasReservas) return;
  _cargandoMasReservas = true;
  await renderReserv(true);
  _cargandoMasReservas = false;
}

// Botón "Cargar más": solo si la última página vino llena. Que venga llena no
// garantiza que haya más, pero pedir un count exacto en cada render cuesta más
// que un viaje de vacío al final.
function _btnMasReservas(nRecibidas) {
  return nRecibidas === RESERV_PAGE
    ? `<div style="text-align:center;padding:16px 0"><button class="btn-cargar-mas" onclick="cargarMasReservas()">Cargar más reservaciones</button></div>`
    : '';
}

async function renderReserv(append = false) {
  const body   = document.getElementById('reserv-body');
  const header = document.getElementById('reserv-header');

  if (!append) {
    _reservCursor = null;
    _reservAccum  = [];
    body.innerHTML = skeletonRows(4);
  }

  // Sincronizar las pills con el filtro activo (p. ej. al llegar desde el home)
  document.querySelectorAll('#reserv-filtros-bar .ped-filtro-pill').forEach(el =>
    el.classList.toggle('active', el.dataset.rest === _reservFiltro));
  // Misma pill para las tres vistas, pero "cobrar" es la empresa y "pagar" es
  // el cliente — ver el comentario en estadoCobro() (js/cobros.js).
  const pillPorCobrar = document.querySelector('#reserv-filtros-bar .ped-filtro-pill[data-rest="PorCobrar"] .pill-label');
  if (pillPorCobrar) pillPorCobrar.textContent = currentUser.rol === 'cliente' ? 'Por pagar' : 'Por cobrar';
  // No se espera: son 3 COUNT aparte y no deben retrasar la lista principal.
  actualizarBadgesPillsReserv();

  // Sin sesión
  if (!currentUser.id) {
    body.innerHTML = `<div class="empty-state"><div class="icon">🔒</div>Inicia sesión para ver tus reservaciones.</div>`;
    return;
  }

  // ── VISTA CLIENTE (solo sus propias reservas, solo lectura) ──
  if (currentUser.rol === 'cliente') {
    header.innerHTML = `<div>Unidad</div><div>Empresa</div><div>Inicio</div><div>Fin</div><div>Estado</div>`;
    header.classList.add('cli');

    // Se filtra por cliente_user_id, NO por cliente_email: el correo es texto
    // que el usuario puede cambiar, y al cambiarlo su historial entero
    // desaparecía de esta vista aunque RLS se lo siguiera permitiendo.
    // cliente_user_id es además la columna sobre la que decide RLS.
    let qCli = sb.from('reservaciones')
      .select(RES_COLS_LISTA)
      .eq('cliente_user_id', currentUser.id)
      .order('created_at', { ascending: false })
      .order('id',          { ascending: false })
      .limit(RESERV_PAGE);
    if (_reservCursor) {
      qCli = qCli.or(
        `created_at.lt.${_reservCursor.created_at},` +
        `and(created_at.eq.${_reservCursor.created_at},id.lt.${_reservCursor.id})`
      );
    }
    qCli = _filtroReservaSQL(qCli);

    const { data: _pagCli, error } = await qCli;
    if (error) { body.innerHTML = `<div class="empty-state"><div class="icon">❌</div>Error al cargar.</div>`; return; }

    if (_pagCli?.length) {
      const ultimo = _pagCli[_pagCli.length - 1];
      _reservCursor = { created_at: ultimo.created_at, id: ultimo.id };
    }

    const _vistosCli = new Set(_reservAccum.map(r => r.id));
    (_pagCli || []).forEach(r => { if (!_vistosCli.has(r.id)) { _reservAccum.push(r); _vistosCli.add(r.id); } });
    const data = _reservAccum;

    if (!data.length) {
      // 'por cobrar' es del lado de la empresa; aquí siempre es el cliente.
      const lbl = _reservFiltro === 'PorCobrar' ? 'por pagar' : (_RESERV_FILTRO_LABEL[_reservFiltro] || '');
      body.innerHTML = `<div class="empty-state"><div class="icon">📋</div>No tienes reservaciones${lbl ? ' ' + lbl : ''}.</div>`;
      return;
    }

    // Obtener empresa según tipo de recurso
    // camionIds ya no hace falta: su consulta solo daba propietario_id.
    const custodioIds = data.filter(r => r.recurso_tipo === 'custodio').map(r => r.unidad).filter(Boolean);
    const patioIds    = data.filter(r => r.recurso_tipo === 'patio').map(r => r.unidad).filter(Boolean);
    const lavadoIds   = data.filter(r => r.recurso_tipo === 'lavado').map(r => r.unidad).filter(Boolean);

    const recursoNombreMap = {};
    const perfMap = {};   // propietario_id → nombre de la empresa

    // H-06 (b): la empresa sale de reservaciones.propietario_id, que ya está
    // en la fila y es sobre el que decide el RLS. Antes se llegaba a ella
    // dando la vuelta por la tabla del recurso — hasta cuatro consultas más
    // por render de la pantalla más usada — cuando el dato estaba delante.
    // El propio código ya lo sabía: la línea del botón de calificar leía
    // `ownerIdMap[r.unidad] || r.propietario_id` desde hace tiempo.
    //
    // Comprobado antes de sustituir (pruebas/12-sonda-propietario-reserva.mjs):
    // en las 20 reservaciones los dos orígenes coinciden, ninguna está sin
    // propietario_id, y ninguna unidad ha cambiado de dueño. Además arregla
    // una: la reservación cuyo recurso ya no se alcanza salía con empresa «—».
    //
    // Y para una reservación pasada el dueño DE ENTONCES —el de la fila— es
    // más correcto que el de hoy, aunque hoy no haya ningún caso.

    // Vistas *_publico y no las tablas: el cliente no es dueño de estos
    // recursos, y la fila entera de un camión lleva VIN, motor, placas y las
    // rutas de sus documentos. Ver H-10.
    //
    // No cambia lo que ve: hoy el cliente ya solo alcanza unidades aprobadas,
    // que es justo lo que la vista filtra dentro. La rama de empresa (más
    // abajo) SÍ sigue leyendo las tablas, a propósito — ahí el dueño las ve por
    // camiones_owner_read sin importar el estado de aprobación, y editar una
    // unidad la devuelve a revisión: con la vista, una reserva activa de una
    // unidad en edición se quedaría sin nombre.
    // Ya solo se pregunta por el NOMBRE de custodios, patios y lavados. Los
    // camiones se enseñan por su id legible (C-001), así que su consulta no
    // aportaba nada que no estuviera en la fila: se retira entera.
    const fetches = [];
    if (custodioIds.length) fetches.push(
      sb.from('custodios_publico').select('id, nombre').in('id', custodioIds)
        .then(({ data: d }) => (d || []).forEach(c => { recursoNombreMap[c.id] = `👮 ${c.nombre}`; }))
    );
    if (patioIds.length) fetches.push(
      sb.from('patios_publico').select('id, nombre').in('id', patioIds)
        .then(({ data: d }) => (d || []).forEach(p => { recursoNombreMap[p.id] = `🏭 ${p.nombre}`; }))
    );
    // Los lavados faltaban aquí: sus reservaciones nunca resolvían nombre ni
    // empresa y salían siempre como «—».
    if (lavadoIds.length) fetches.push(
      sb.from('lavados_publico').select('id, nombre').in('id', lavadoIds)
        .then(({ data: d }) => (d || []).forEach(l => { recursoNombreMap[l.id] = `🧼 ${l.nombre}`; }))
    );

    // Y la ficha de empresa ya no espera a las anteriores: los propietario_id
    // salen de las propias reservaciones, así que esta consulta es
    // independiente y entra en el mismo Promise.all. Antes iba detrás por
    // fuerza, porque hasta resolver los recursos no se sabía a quién pedir.
    const propIds = [...new Set(data.map(r => r.propietario_id).filter(Boolean))];
    if (propIds.length) fetches.push(
      sb.from('empresas_publico').select('user_id, nombre').in('user_id', propIds)
        .then(({ data: d }) => (d || []).forEach(p => { perfMap[p.user_id] = p.nombre; }))
    );
    await Promise.all(fetches);

    // Los expedientes documentales de todas las filas, en una sola consulta.
    if (typeof cargarExpedientes === 'function') await cargarExpedientes(data);

    body.innerHTML = data.map(r => {
      const badgeCls = r.estado === 'Pendiente'   ? 'badge-busy'
                     : r.estado === 'Activa'      ? 'badge-avail'
                     : r.estado === 'PorAprobar'  ? 'badge-acuerdo-rev'
                     : r.estado === 'CancelacionSolicitada' ? 'badge-revision'
                     : r.estado === 'Completada'  ? 'badge-completado'
                     : 'badge-maint';
      const trackBtn = r.estado === 'Activa'
        ? `<button class="btn-edit" onclick="openTracking('${r.id}')" style="font-size:0.7rem">📍 ${esc(r.tracking_estado || 'Confirmado')}</button>`
        : '';
      // El GPS solo se muestra una vez que el viaje realmente arrancó (mismo
      // punto en que ya se exige tener chofer asignado) — antes de eso el
      // link no sirve de nada.
      const primerPasoKey = (typeof _getEstados === 'function' ? _getEstados(r.recurso_tipo)[0]?.key : 'Confirmado') || 'Confirmado';
      const gpsBtnCli = (r.estado === 'Activa' && r.gps_link && r.tracking_estado && r.tracking_estado !== primerPasoKey)
        ? `<a href="${esc(r.gps_link)}" target="_blank" class="btn-edit" style="font-size:0.7rem">📍 Ver ubicación en vivo</a>`
        : '';
      // Cancelar un acuerdo ya aprobado no es unilateral: se solicita y el
      // superadmin decide (ver solicitarCancelacion).
      const cancelBtn = r.estado === 'Activa'
        ? `<button class="btn-cancelar-reserva" style="font-size:0.7rem" onclick="solicitarCancelacion('${r.id}')">Solicitar cancelación</button>`
        : r.estado === 'CancelacionSolicitada'
          ? `<span style="font-size:0.7rem;color:var(--text-muted)">⏳ Cancelación en revisión</span>`
          : '';
      // El servicio se cierra cuando cliente Y empresa marcan completado (cada
      // quien sube su propia evidencia) y el superadmin aprueba la revisión.
      const miEvidenciaCli = r.evidencias_cliente?.length || 0;
      const unidadLabel = recursoNombreMap[r.unidad] || esc(r.unidad) || '—';
      const propId = r.propietario_id || '';
      const nombreEmpresa = perfMap[r.propietario_id] || '';

      // ── SIGUIENTE PASO (cliente) ──────────────────────────
      // Espejo de _siguientesPasosReserva (más abajo, lado empresa): qué
      // le toca al CLIENTE, no a la empresa. Mismo criterio — solo se
      // sugiere lo que el sistema ya sabe pendiente (expediente 'solicitado',
      // tracking en el último paso, evidencia sin subir, calificación sin
      // dar); nunca se inventa un paso que no tenga un dato detrás.
      const ACCION_CLI = {
        puerto:    `abrirExpediente('${r.id}','ingreso_puerto')`,
        vacios:    `abrirExpediente('${r.id}','entrega_vacios')`,
        completar: `abrirEvidencias('${r.id}','evidencias_cliente')`,
        calificar: `openCalificar('${r.id}','${propId}','${escJs(nombreEmpresa)}')`,
      };
      // Array, no un solo paso: subir documentos y marcar completado no se
      // esperan entre sí (ver _siguientesPasosReserva, lado empresa), así
      // que pueden estar pendientes los dos a la vez.
      const pasosCli = (() => {
        if (r.estado === 'Completada') {
          return (!r.calificado && propId) ? [{
            clave: 'calificar', corto: 'Calificar servicio', accion: ACCION_CLI.calificar,
            detalle: 'El servicio ya se completó: califica cómo te fue.',
          }] : [];
        }
        if (r.estado === 'PorAprobar') {
          return miEvidenciaCli ? [] : [{
            clave: 'completar', corto: 'Subir mi evidencia', accion: ACCION_CLI.completar,
            detalle: 'La empresa ya marcó el servicio como terminado: sube tu evidencia para que el superadmin apruebe el cierre.',
          }];
        }
        if (r.estado !== 'Activa') return [];
        const pasos = [];
        // "solicitado" = la pelota está en tu cancha (ver expedientes.js).
        if (r._expIngreso?.estado === 'solicitado') pasos.push({
          clave: 'puerto', corto: 'Subir docs de Puerto', accion: ACCION_CLI.puerto,
          detalle: 'La empresa pidió los documentos para entrar a puerto: súbelos para que el viaje no se atore.',
        });
        if (r._expVacios?.estado === 'solicitado') pasos.push({
          clave: 'vacios', corto: 'Subir docs de Vacíos', accion: ACCION_CLI.vacios,
          detalle: 'La empresa pidió los documentos para entregar el contenedor vacío: súbelos antes de que corran las demoras.',
        });
        if (typeof _trackingEnUltimoPaso === 'function' && _trackingEnUltimoPaso(r)) pasos.push({
          clave: 'completar', corto: 'Marcar completado', accion: ACCION_CLI.completar,
          detalle: 'El seguimiento llegó al final: marca el servicio como completado.',
        });
        return pasos; // vacío = nada pendiente de tu lado — el envío sigue su curso
      })();
      const clavesPasosCli = pasosCli.map(p => p.clave);
      const nxCli = clave => (clavesPasosCli.includes(clave) ? ' reserv-next' : '');

      const completarBtn = r.estado === 'Activa'
        ? `<button class="btn-completar-reserva${nxCli('completar')}" style="font-size:0.7rem" onclick="abrirEvidencias('${r.id}','evidencias_cliente')">✓ Marcar completado</button>`
        : r.estado === 'PorAprobar'
          ? (miEvidenciaCli
              ? `<span style="font-size:0.7rem;color:var(--text-muted)">⏳ Esperando aprobación</span>`
              : `<button class="btn-completar-reserva${nxCli('completar')}" style="font-size:0.7rem" onclick="abrirEvidencias('${r.id}','evidencias_cliente')">📎 Subir mi evidencia</button>`)
          : '';
      const calBtn = (r.estado === 'Completada' && !r.calificado && propId)
        ? `<button class="btn-calificar${nxCli('calificar')}" onclick="openCalificar('${r.id}','${propId}','${escJs(nombreEmpresa)}')">⭐ Calificar</button>`
        : '';
      // El cliente ve su estado de cobro: pagado, por cobrar o vencido.
      const pagoLbl = cobroBadgeHTML(r);
      const precioLbl = r.precio_acordado
        ? `<span style="font-size:0.7rem;color:var(--text-muted)">$${Number(r.precio_acordado).toLocaleString('es-MX')} MXN</span>`
        : '';
      // Antes solo aparecía en 'Activa', que es cuando el cliente TODAVÍA no
      // debe nada — estadoCobro() no devuelve nada hasta 'Completada'. Ahí es
      // donde de verdad hay algo que pagar (badge "Por cobrar"/"Vencido"), y
      // era justo donde no había ningún botón. Sigue deshabilitado — no hay
      // pasarela conectada todavía (Stripe, sin dar de alta) — pero el
      // cliente ya debe ver DÓNDE va a poder pagar cuando esté lista.
      const debeCobro = typeof estadoCobro === 'function' && !!estadoCobro(r);
      const pagarBtn = ((r.estado === 'Activa' && !r.pagado) || debeCobro)
        ? `<button class="btn-prox" disabled title="Pago con tarjeta en línea — próximamente">💳 Pagar <span class="prox-badge">Prox.</span></button>`
        : '';
      // El botón «📄 Carta Porte / documentos» (subida libre de documentos de
      // carga, abrirDocumentosCarga) se retiró de la vista del cliente el
      // 2026-10-01 por decisión del usuario. La empresa conserva «Documentos
      // del cliente» y la petición por aviso.
      // Documento de referencia (no fiscal) — ver js/cartaporte.js. La RPC
      // datos_carta_porte ya verifica que el cliente sea parte de ESTA
      // reservación, así que puede generarla igual que la empresa.
      const cartaPorteRefBtnCli = typeof generarCartaPorte === 'function'
        ? `<button class="btn-edit" style="font-size:0.7rem" onclick="generarCartaPorte('${r.id}')" title="Documento de referencia — no es válido ante el SAT">🧾 Carta Porte</button>` : '';
      const expedientePills = typeof expedienteBotonesHTML === 'function' ? expedienteBotonesHTML(r, true, clavesPasosCli) : '';
      const abierta = _reservAbiertas.has(r.id);
      const chipsHTMLCli = pasosCli.map(p =>
        `<button class="reserv-next-chip" title="Ir directo a este paso" onclick="${p.accion}">👉 ${esc(p.corto)}</button>`
      ).join('');
      const grupo = (label, html) => html ? `
        <div class="reserv-detail-group">
          <span class="reserv-detail-group-label">${label}</span>
          <div class="reserv-detail-group-btns">${html}</div>
        </div>` : '';
      return `
      <div class="reserv-item">
      <div class="reserv-row reserv-row-cli">
        <div class="reserv-id">${unidadLabel}</div>
        <div class="reserv-empresa">${esc(perfMap[r.propietario_id] || '—')}</div>
        <div>${fmtFecha(r.fecha_ini)}</div>
        <div>${fmtFecha(r.fecha_fin)}</div>
        <div style="display:flex;gap:5px;align-items:center;flex-wrap:wrap">
          <span class="badge ${badgeCls}">${esc(_estadoLabel(r.estado))}</span>
          ${trackBtn}
          ${pagoLbl}
          ${chipsHTMLCli}
          <button id="reserv-toggle-${r.id}" class="reserv-toggle${abierta ? ' open' : ''}" aria-expanded="${abierta}" title="Más acciones" onclick="toggleReservDetalle('${r.id}')">▾</button>
        </div>
      </div>
      <div id="reserv-detalle-${r.id}" class="reserv-detail${abierta ? ' open' : ''}">
        ${pasosCli.length ? `<div class="reserv-next-hint">${pasosCli.map(p => `<span><strong>👉</strong> ${esc(p.detalle)}</span>`).join('')}</div>` : ''}
        ${grupo('Operación', gpsBtnCli)}
        ${grupo('Documentos', expedientePills + cartaPorteRefBtnCli)}
        ${grupo('Pago', precioLbl + pagarBtn)}
        ${grupo('Avisos', r.estado === 'Activa' ? `<button class="btn-edit" onclick="abrirReportarCambio('${r.id}')" title="Avisar a la empresa que algo cambió o hay un problema">⚠ Reportar cambio o problema</button>` : '')}
        ${grupo('Cierre', completarBtn + calBtn + cancelBtn)}
      </div>
      </div>`;
    }).join('') + _btnMasReservas((_pagCli || []).length);
    return;
  }

  // ── VISTA ADMIN / SUPERADMIN ──
  header.innerHTML = `<div>Unidad</div><div>Empresa</div><div>Cliente</div><div>Inicio</div><div>Fin</div><div>Estado</div>`;
  header.classList.remove('cli');

  let reservQuery = sb.from('reservaciones')
    .select(RES_COLS_LISTA)
    .order('created_at', { ascending: false })
    .order('id',          { ascending: false })
    .limit(RESERV_PAGE);
  if (_reservCursor) {
    reservQuery = reservQuery.or(
      `created_at.lt.${_reservCursor.created_at},` +
      `and(created_at.eq.${_reservCursor.created_at},id.lt.${_reservCursor.id})`
    );
  }

  if (currentUser.rol !== 'superadmin') {
    reservQuery = reservQuery.eq('propietario_id', currentUser.id);
  }
  reservQuery = _filtroReservaSQL(reservQuery);

  const { data: _pagAdm, error } = await reservQuery;
  if (error) { body.innerHTML = `<div class="empty-state"><div class="icon">❌</div>Error al cargar.</div>`; return; }

  if (_pagAdm?.length) {
    const ultimo = _pagAdm[_pagAdm.length - 1];
    _reservCursor = { created_at: ultimo.created_at, id: ultimo.id };
  }

  const _vistosAdm = new Set(_reservAccum.map(r => r.id));
  (_pagAdm || []).forEach(r => { if (!_vistosAdm.has(r.id)) { _reservAccum.push(r); _vistosAdm.add(r.id); } });
  const data = _reservAccum;

  if (!data.length) {
    const lbl = _RESERV_FILTRO_LABEL[_reservFiltro] || '';
    body.innerHTML = `<div class="empty-state"><div class="icon">📋</div>No hay reservaciones${lbl ? ' ' + lbl : ''}.</div>`;
    return;
  }

  // Construir mapa de empresa y etiqueta por tipo de recurso
  // camionIds ya no hace falta: su consulta solo daba propietario_id.
  const custodioIds = [...new Set(data.filter(r => r.recurso_tipo === 'custodio').map(r => r.unidad).filter(Boolean))];
  const patioIds    = [...new Set(data.filter(r => r.recurso_tipo === 'patio').map(r => r.unidad).filter(Boolean))];
  const lavadoIds   = [...new Set(data.filter(r => r.recurso_tipo === 'lavado').map(r => r.unidad).filter(Boolean))];

  const recursoLabelMap = {};
  const perfMap2        = {};   // propietario_id → nombre de la empresa

  // H-06 (b), igual que en la rama de cliente: la empresa y el dueño salen de
  // reservaciones.propietario_id. Aquí se siguen leyendo las TABLAS y no las
  // vistas *_publico, a propósito: el dueño ve sus unidades aunque estén en
  // revisión, y con la vista una reserva activa de una unidad en edición se
  // quedaría sin nombre. Pero eso solo justifica pedir el NOMBRE — el
  // propietario ya venía en la fila.
  const fetches = [];
  if (custodioIds.length) fetches.push(
    sb.from('custodios').select('id, nombre').in('id', custodioIds)
      .then(({ data: d }) => (d || []).forEach(c => { recursoLabelMap[c.id] = `👮 ${c.nombre}`; }))
  );
  if (patioIds.length) fetches.push(
    sb.from('patios').select('id, nombre').in('id', patioIds)
      .then(({ data: d }) => (d || []).forEach(p => { recursoLabelMap[p.id] = `🏭 ${p.nombre}`; }))
  );
  // Los lavados faltaban aquí igual que en la rama de cliente.
  if (lavadoIds.length) fetches.push(
    sb.from('lavados').select('id, nombre').in('id', lavadoIds)
      .then(({ data: d }) => (d || []).forEach(l => { recursoLabelMap[l.id] = `🧼 ${l.nombre}`; }))
  );

  const propIds2 = [...new Set(data.map(r => r.propietario_id).filter(Boolean))];
  if (propIds2.length) fetches.push(
    sb.from('empresas_publico').select('user_id, nombre').in('user_id', propIds2)
      .then(({ data: d }) => (d || []).forEach(p => { perfMap2[p.user_id] = p.nombre; }))
  );
  await Promise.all(fetches);

  // Los expedientes documentales de todas las filas, en una sola consulta.
  // renderReserv tiene DOS rutas de render —cliente y empresa/superadmin— y
  // las dos necesitan esto: si solo se carga en una, la otra ve el botón de
  // "Solicitar documentación" para siempre porque nunca se entera de que el
  // expediente ya existe.
  if (typeof cargarExpedientes === 'function') await cargarExpedientes(data);

  body.innerHTML = data.map(r => {
    const esCancelada = r.estado === 'Cancelada';
    const esRechazada = r.estado === 'Rechazada';
    const esPendiente = r.estado === 'Pendiente';
    const esActiva    = r.estado === 'Activa';
    const inactiva    = esCancelada || esRechazada;

    const esCompletada  = r.estado === 'Completada';
    const esPorAprobar  = r.estado === 'PorAprobar';
    const badgeCls = r.estado === 'CancelacionSolicitada' ? 'badge-revision'
                   : esPendiente   ? 'badge-busy'
                   : esActiva      ? 'badge-avail'
                   : esPorAprobar  ? 'badge-acuerdo-rev'
                   : esCompletada  ? 'badge-acordado'
                   : 'badge-maint';

    const esDueno = currentUser.rol === 'superadmin' || r.propietario_id === currentUser.id;

    // Fila compacta: solo lo decisivo a simple vista. Todo lo demás
    // (chofer, unidad, GPS, documentos, cierre) vive en el panel expandible
    // — ver toggleReservDetalle. Pendiente se deja tal cual: son solo 2
    // botones y ambos son la decisión que importa, no hay nada que ocultar.
    let primaria = '';
    const gruposDetalle = [];
    const grupo = (label, html) => { if (html) gruposDetalle.push({ label, html }); };
    // Guía de "qué sigue": resalta TODOS los botones pendientes a la vez
    // (clase reserv-next), no solo el de mayor prioridad — ver
    // _siguientesPasosReserva.
    const pasos = esDueno ? _siguientesPasosReserva(r) : [];
    const clavesPasos = pasos.map(p => p.clave);
    const nx = clave => (clavesPasos.includes(clave) ? ' reserv-next' : '');

    if (esDueno && esPendiente) {
      primaria = `
        <button class="btn-aceptar-reserva"  onclick="aceptarReserva('${r.id}','${escJs(r.unidad)}','${r.recurso_tipo||'camion'}')">✓ Aceptar</button>
        <button class="btn-rechazar-reserva" onclick="rechazarReserva('${r.id}','${escJs(r.unidad)}')">✕ Rechazar</button>`;
    } else if (esDueno && esActiva) {
      const trackStep = r.tracking_estado || 'Confirmado';
      // El chofer ya no es obligatorio al ofertar: se asigna aquí, en
      // cualquier momento mientras el viaje sigue Activo. El tracking no
      // deja avanzar del primer paso sin uno asignado (ver tracking.js) —
      // por eso, si falta, es uno de los pasos que marca _siguientesPasosReserva.
      const esCamion = r.recurso_tipo === 'camion' || !r.recurso_tipo;
      const choferBtn = esCamion
        ? `<button class="btn-edit${nx('chofer')}" onclick="abrirAsignarChofer('${r.id}')" title="${r.operador_nombre ? 'Cambiar chofer' : 'Asignar chofer antes de iniciar el viaje'}">👷 ${r.operador_nombre ? esc(r.operador_nombre) : 'Asignar chofer'}</button>`
        : '';
      // El link se puede guardar en cualquier momento; el cliente solo lo ve
      // una vez que el tracking avanzó del primer paso (ver vista cliente).
      const gpsBtn = `<button class="btn-edit" onclick="abrirGpsLink('${r.id}')" title="Link de GPS temporal">🛰️ GPS${r.gps_link ? ' ✓' : ''}</button>`;
      const numDocsCargaDueno = r.documentos_carga?.length || 0;
      const docsCargaBtnDueno = `<button class="btn-edit" onclick="abrirDocumentosCarga('${r.id}')" title="Ver Carta Porte y documentos que subió el cliente">📄 ${numDocsCargaDueno ? `Documentos (${numDocsCargaDueno})` : 'Documentos del cliente'}</button>`;
      // Documento de referencia (no fiscal) — ver js/cartaporte.js. La RPC
      // datos_carta_porte verifica que quien llama sea parte de ESTA
      // reservación (cliente, propietario o superadmin), así que cliente y
      // empresa lo ven igual — no es un privilegio del dueño.
      const cartaPorteRefBtn = typeof generarCartaPorte === 'function'
        ? `<button class="btn-edit" onclick="generarCartaPorte('${r.id}')" title="Documento de referencia — no es válido ante el SAT">🧾 Carta Porte</button>` : '';
      const expedientePillsActiva = typeof expedienteBotonesHTML === 'function'
        ? expedienteBotonesHTML(r, r.cliente_user_id === currentUser.id, clavesPasos) : '';
      // Completar solo se habilita al llegar al último paso del seguimiento:
      // abrirEvidencias ya lo exigía, pero con un aviso de error DESPUÉS de
      // pulsar. Mejor que el botón lo diga desde antes.
      const enUltimoPaso = _trackingEnUltimoPaso(r);
      const ultimoLabel  = _getEstados(r.recurso_tipo).slice(-1)[0].label;
      const completarBtn = enUltimoPaso
        ? `<button class="btn-completar-reserva${nx('completar')}" onclick="abrirEvidencias('${r.id}','evidencias')">✓ Completar</button>`
        : `<button class="btn-completar-reserva" disabled title="${esc(`Disponible al llegar a «${ultimoLabel}» en el seguimiento`)}">✓ Completar</button>`;

      primaria = `
        <button class="btn-edit${nx('avanzar')}" onclick="openTracking('${r.id}')" title="Ver seguimiento">📍 ${esc(trackStep)}</button>`;
      grupo('Operación', choferBtn + `<button class="btn-edit" onclick="abrirCambiarUnidad('${r.id}')" title="Reasignar a otra unidad (p. ej. si se descompuso)">🔧 Cambiar unidad</button>` + gpsBtn);
      grupo('Documentos', docsCargaBtnDueno + expedientePillsActiva + cartaPorteRefBtn);
      // Avisos al cliente sin necesidad de chat: un aviso puntual (campana +
      // correo) en vez de un mensaje libre.
      grupo('Avisos', `<button class="btn-edit" onclick="confirmarLugarHora('${r.id}')" title="Pedirle al cliente que confirme lugar y hora">📍 Confirmar lugar y hora</button>` +
        `<button class="btn-edit" onclick="avisarRetraso('${r.id}')" title="Avisar que el transporte va a llegar tarde">⏰ Avisar retraso</button>`);
      grupo('Cierre', completarBtn +
        `<button class="btn-cancelar-reserva" onclick="cancelarReserva('${r.id}','${escJs(r.unidad)}')">Cancelar</button>`);
    } else if (esDueno && esPorAprobar) {
      // El servicio se cierra cuando cliente Y empresa marcan completado (cada
      // quien sube su propia evidencia); el superadmin aprueba la revisión.
      const miEvidencia = r.evidencias?.length || 0;
      primaria = miEvidencia
        ? `<span style="font-size:0.72rem;color:var(--text-muted)">⏳ Esperando aprobación del superadmin</span>`
        : `<button class="btn-completar-reserva" style="font-size:0.72rem" onclick="abrirEvidencias('${r.id}','evidencias')">📎 Subir mi evidencia</button>`;
      const expedientePillsAprobar = typeof expedienteBotonesHTML === 'function'
        ? expedienteBotonesHTML(r, r.cliente_user_id === currentUser.id) : '';
      grupo('Documentos', expedientePillsAprobar);
    } else if (esDueno && esCompletada) {
      const diasPasados = r.completado_en
        ? Math.floor((new Date() - new Date(r.completado_en)) / 86400000) : 99;
      const numEv = r.evidencias?.length || 0;
      const evBtnLabel = numEv > 0 ? `📎 Evidencias (${numEv})` : '📎 Subir evidencias';
      const evBtn = diasPasados <= 5 || numEv > 0
        ? `<button class="btn-edit" style="font-size:0.72rem" onclick="abrirEvidencias('${r.id}','evidencias')">${evBtnLabel}</button>`
        : '';
      // Cobro: quien recibe el dinero (la empresa) o el superadmin lo registra.
      const cobroBtn = r.pagado
        ? `<button class="btn-edit" style="font-size:0.72rem" title="Revertir el cobro registrado" onclick="revertirPago('${r.id}')">↩ Revertir cobro</button>`
        : `<button class="btn-edit${nx('cobro')}" style="font-size:0.72rem;color:var(--amber);border-color:rgba(245,158,11,0.4)" onclick="abrirRegistrarPago('${r.id}')">💰 Registrar pago</button>`;
      primaria = cobroBadgeHTML(r);
      grupo('Cierre', cobroBtn + evBtn);
    }

    const unidadLabel = recursoLabelMap[r.unidad] || esc(r.unidad) || '—';
    // Archivar — solo superadmin y solo lo cerrado: cancelada, rechazada o
    // completada con el cobro registrado. Es la misma regla que impone
    // guard_reservacion_archivo (A2-C2); aquí solo evita ofrecer un botón que
    // la base iba a rechazar. No es una acción de todos los días: va al panel.
    const archivable = ['Cancelada', 'Rechazada'].includes(r.estado)
                    || (r.estado === 'Completada' && r.pagado);
    if (currentUser.rol === 'superadmin' && archivable) {
      grupo('Superadmin', `<button class="btn-edit" style="font-size:0.72rem" onclick="archivarReserva('${r.id}')">🗃 Archivar</button>`);
    }

    const abierta = _reservAbiertas.has(r.id);
    // Una línea de "Siguiente" por paso pendiente, y la espera (si la hay) una
    // sola vez al final — es el mismo dato en todos los pasos devueltos.
    const hintHTML = (pasos.length && gruposDetalle.length) ? `
        <div class="reserv-next-hint">
          ${pasos.map(p => `<span><strong>👉</strong> ${esc(p.detalle)}</span>`).join('')}
          ${pasos[0].espera ? `<span class="reserv-next-espera">⏳ ${esc(pasos[0].espera)}</span>` : ''}
        </div>` : '';
    const detalleHTML = gruposDetalle.length ? hintHTML + gruposDetalle.map(g => `
        <div class="reserv-detail-group">
          <span class="reserv-detail-group-label">${g.label}</span>
          <div class="reserv-detail-group-btns">${g.html}</div>
        </div>`).join('') : '';
    const chipsHTML = (pasos.length && detalleHTML) ? pasos.map(p =>
      `<button class="reserv-next-chip" title="Ir directo a este paso" onclick="${p.accion}">👉 ${esc(p.corto)}</button>`
    ).join('') : '';

    return `
    <div class="reserv-item">
    <div class="reserv-row ${inactiva ? 'reserv-cancelada' : ''}">
      <div class="reserv-id">${unidadLabel}</div>
      <div class="reserv-empresa">${esc(perfMap2[r.propietario_id] || '—')}</div>
      <div>${esc(r.cliente)}</div>
      <div>${fmtFecha(r.fecha_ini)}</div>
      <div>${fmtFecha(r.fecha_fin)}</div>
      <div style="display:flex;gap:5px;align-items:center;flex-wrap:wrap">
        <span class="badge ${badgeCls}">${esc(_estadoLabel(r.estado))}</span>
        ${primaria}
        ${chipsHTML}
        ${detalleHTML ? `<button id="reserv-toggle-${r.id}" class="reserv-toggle${abierta ? ' open' : ''}" aria-expanded="${abierta}" title="Más acciones" onclick="toggleReservDetalle('${r.id}')">▾</button>` : ''}
      </div>
    </div>
    ${detalleHTML ? `<div id="reserv-detalle-${r.id}" class="reserv-detail${abierta ? ' open' : ''}">${detalleHTML}</div>` : ''}
    </div>`;
  }).join('') + _btnMasReservas((_pagAdm || []).length);
}

// ── ACCIONES ───────────────────────────────────────────

let _reservaActiva = false; // guard anti-double-click

async function aceptarReserva(reservaId, unidad, recurso_tipo) {
  if (_reservaActiva) return;
  _reservaActiva = true;
  // Obtener datos antes de actualizar para el email
  const { data: r } = await sb.from('reservaciones').select('*').eq('id', reservaId).single();
  const tipoFinal = recurso_tipo || r?.recurso_tipo || 'camion';
  await sb.from('reservaciones').update({ estado: 'Activa' }).eq('id', reservaId);

  // Notificar al cliente que su reservación fue aceptada
  if (r?.cliente_user_id) {
    await sb.from('notificaciones').insert({
      user_id: r.cliente_user_id,
      tipo:    'reserva_aceptada',
      titulo:  '✓ Reservación confirmada',
      mensaje: `${currentUser.nombre} confirmó tu servicio de ${r?.descripcion ? '' : ''}. Revisa tus reservaciones para más detalles.`,
      leido:   false,
    });
  }

  // Marcar recurso como ocupado solo si ya inició y es un camión
  const fechaIni = r?.fecha_ini ? r.fecha_ini.split('T')[0] : null;
  if (tipoFinal === 'camion' && fechaIni && fechaIni <= today()) {
    await sb.from('camiones').update({ estado: 'ocupado' }).eq('id', unidad);
  } else if (tipoFinal === 'custodio' && fechaIni && fechaIni <= today()) {
    await sb.from('custodios').update({ estado: 'ocupado' }).eq('id', unidad);
  } else if (tipoFinal === 'patio' && fechaIni && fechaIni <= today()) {
    await sb.from('patios').update({ estado: 'ocupado' }).eq('id', unidad);
  }

  // Email al cliente: reserva aceptada (con CC al superadmin)
  _enviarEmail('reserva_aceptada', {
    clienteEmail:  r?.cliente_email,
    clienteNombre: r?.cliente,
    camion: unidad,
    empresa: currentUser.nombre,
    fecha_ini: r?.fecha_ini,
    fecha_fin: r?.fecha_fin
  });

  _reservaActiva = false;
  await renderReserv();
  await loadNotificaciones();
  const recursoLabel = tipoFinal === 'custodio' ? 'custodio' : tipoFinal === 'patio' ? 'patio' : 'camión';
  const toastMsg = fechaIni && fechaIni <= today()
    ? `✓ Reserva aceptada — ${recursoLabel} marcado como en servicio`
    : `✓ Reserva aceptada — el ${recursoLabel} quedará en servicio a partir del ` + fmtFecha(fechaIni);
  showToast(toastMsg);
}

function rechazarReserva(reservaId, unidad) {
  if (_reservaActiva) return;
  showConfirm('¿Rechazar esta solicitud de reserva?', async () => {
  _reservaActiva = true;
  const { data: r } = await sb.from('reservaciones').select('*').eq('id', reservaId).single();
  await sb.from('reservaciones').update({ estado: 'Rechazada' }).eq('id', reservaId);

  // Email al cliente: rechazada (con CC al superadmin)
  _enviarEmail('reserva_rechazada', {
    clienteEmail:  r?.cliente_email,
    clienteNombre: r?.cliente,
    camion: unidad,
    fecha_ini: r?.fecha_ini,
    fecha_fin: r?.fecha_fin
  });

  _reservaActiva = false;
  await renderReserv();
  await loadNotificaciones();
  showToast('Solicitud rechazada');
  }, { danger: true, confirmLabel: 'Rechazar' });
}

function cancelarReserva(reservaId, unidad) {
  if (_reservaActiva) return;
  showConfirm('¿Cancelar esta reserva? El recurso volverá a estar disponible y la solicitud se reabrirá para nuevas ofertas.', async () => {
    _reservaActiva = true;
    // cancelar_reservacion (RPC, ver supabase/migrations/20260810120000 +
    // 20260901140000) hace las 7 escrituras de antes en una sola transacción:
    // cancela la reserva, libera el recurso (incluido lavado, que este
    // código antes omitía), reabre el pedido, invalida las ofertas y
    // notifica al cliente y a los superadmins. Ver H-10 en la auditoría.
    const { error } = await sb.rpc('cancelar_reservacion', { p_reserva_id: reservaId });
    _reservaActiva = false;
    if (error) { showToast(error.message || 'No se pudo cancelar la reserva', 'error'); return; }
    await renderReserv();
    showToast('Reserva cancelada — solicitud reabierta para nuevas ofertas');
  }, { danger: true, confirmLabel: 'Sí, cancelar' });
}

// ── ARCHIVAR / RESTAURAR (superadmin) ──
// Archivar es una MARCA, no un traslado (A2-C2, 07/10). Antes esto copiaba 14
// de 55 columnas a reservaciones_historico y BORRABA la original: se perdían el
// precio, el pago, las evidencias y la cancelación, caían en cascada el
// expediente y los mensajes, y el servicio desaparecía de los reportes.
// Ahora la fila se queda donde está y solo sale de la lista.
//
// El valor de archivada_en que se manda es solo un «sí»: guard_reservacion_archivo
// lo sustituye por now() del servidor y pone archivada_por. También es el guard
// —no este código— el que decide quién (solo superadmin) y qué (solo lo cerrado).
function archivarReserva(reservaId) {
  showConfirm('¿Archivar esta reservación? Sale de la lista, pero sigue contando en reportes y desempeño, y puedes restaurarla desde el Historial.', async () => {
    const ok = await actualizarConfirmado('reservaciones', { id: reservaId },
      { archivada_en: new Date().toISOString() }, 'la reservación');
    if (!ok) return;
    await renderReserv();
    showToast('✓ Reservación archivada');
  }, { confirmLabel: 'Archivar' });
}

function restaurarReserva(reservaId) {
  showConfirm('¿Restaurar esta reservación? Vuelve a la lista de Reservaciones.', async () => {
    const ok = await actualizarConfirmado('reservaciones', { id: reservaId },
      { archivada_en: null }, 'la reservación');
    if (!ok) return;
    await renderHistorialReservas();
    showToast('✓ Reservación restaurada');
  }, { confirmLabel: 'Restaurar' });
}

// ── GPS TEMPORAL (empresa guarda, cliente ve al iniciar) ──
// La empresa puede guardar el link en cualquier momento mientras la reserva
// está Activa; el cliente solo lo ve una vez que el tracking avanzó del
// primer paso (ver el botón en la vista cliente de renderReserv).

async function abrirGpsLink(reservaId) {
  const { data: r } = await sb.from('reservaciones').select('gps_link').eq('id', reservaId).single();
  document.getElementById('gps-reserva-id').value = reservaId;
  document.getElementById('gps-link-input').value = r?.gps_link || '';
  document.getElementById('modal-gps-link').classList.add('open');
}

function cerrarGpsLink() {
  document.getElementById('modal-gps-link').classList.remove('open');
}

async function guardarGpsLink() {
  const reservaId = document.getElementById('gps-reserva-id').value;
  const link = document.getElementById('gps-link-input')?.value?.trim() || null;
  const { error } = await sb.from('reservaciones').update({ gps_link: link }).eq('id', reservaId);
  if (error) { showToast('No se pudo guardar: ' + error.message, 'error'); return; }
  cerrarGpsLink();
  await renderReserv();
  showToast(link ? '✓ Link de GPS guardado' : 'Link de GPS quitado');
}

// ── DOCUMENTOS DE CARGA (sube el cliente, ve la empresa) ──
// Carta Porte, documentos de maniobra, etc. — subida libre, sin checklist
// (a diferencia de los expedientes de puerto/vacíos). Disponible en cuanto
// hay match, sin importar el estado de la reservación. Solo el cliente
// sube (policy de storage + guard_reservacion_update); la empresa solo ve.

async function abrirDocumentosCarga(reservaId) {
  const { data: r } = await sb.from('reservaciones').select('documentos_carga, cliente_user_id').eq('id', reservaId).single();
  const soyCliente = r?.cliente_user_id === currentUser.id;

  document.getElementById('dc-reserva-id').value = reservaId;
  document.getElementById('dc-files').value = '';
  document.getElementById('dc-lista-actual').innerHTML = '<span style="color:var(--text-muted);font-size:0.82rem">Cargando…</span>';

  const subirWrap = document.getElementById('dc-subir-wrap');
  if (subirWrap) subirWrap.style.display = soyCliente ? '' : 'none';
  const btnSubir = document.getElementById('dc-btn-subir');
  if (btnSubir) btnSubir.style.display = soyCliente ? '' : 'none';
  const btnSolicitar = document.getElementById('dc-btn-solicitar');
  if (btnSolicitar) btnSolicitar.style.display = soyCliente ? 'none' : '';
  const titulo = document.getElementById('dc-titulo');
  if (titulo) titulo.textContent = soyCliente ? '📄 Carta Porte / documentos de carga' : '📄 Documentos de carga del cliente';

  document.getElementById('modal-documentos-carga').classList.add('open');

  const existentes = r?.documentos_carga || [];
  const listaEl = document.getElementById('dc-lista-actual');
  if (existentes.length) {
    const enlaces = await Promise.all(existentes.map(async (e) => {
      const { data } = await sb.storage.from('unidades').createSignedUrl(e, 3600);
      return data?.signedUrl || null;
    }));
    listaEl.innerHTML = enlaces.map((url, i) => url
      ? `<a href="${esc(url)}" target="_blank" class="btn-edit" style="font-size:0.75rem">📄 Documento ${i + 1}</a>`
      : `<span style="font-size:0.75rem;color:var(--text-muted)">📄 Documento ${i + 1} (no disponible)</span>`
    ).join('');
  } else {
    listaEl.innerHTML = '<span style="font-size:0.78rem;color:var(--text-muted)">Sin documentos aún</span>';
  }
}

function cerrarDocumentosCarga() {
  document.getElementById('modal-documentos-carga').classList.remove('open');
}

// La empresa pide la Carta Porte / documentos de carga sin necesidad de
// chat: un aviso puntual (campana + correo) en vez de un mensaje libre.
function solicitarDocumentosCarga() {
  const reservaId = document.getElementById('dc-reserva-id').value;
  if (!reservaId) return;
  showConfirm('¿Solicitar al cliente la Carta Porte y documentos de carga? Le llegará aviso por campana y correo.', async () => {
    const { data: r } = await sb.from('reservaciones')
      .select('cliente_user_id, unidad').eq('id', reservaId).single();
    if (!r?.cliente_user_id) { showToast('No se pudo solicitar', 'error'); return; }

    const mensaje = `${esc(currentUser.nombre)} necesita la Carta Porte y/o documentos de carga para el servicio "${esc(r.unidad || '')}". Súbelos desde Reservaciones.`;
    const { error } = await sb.from('notificaciones').insert({
      user_id: r.cliente_user_id,
      tipo:    'documentos_carga_solicitados',
      titulo:  '📄 Documentos de carga solicitados',
      mensaje,
      leido:   false,
    });
    if (error) { showToast('No se pudo solicitar: ' + error.message, 'error'); return; }

    _notificarEmail({
      tipo: 'resolucion', destinoIds: [r.cliente_user_id],
      titulo: 'Documentos de carga solicitados', mensaje, aprobado: true,
    });

    showToast('✓ Solicitud enviada al cliente');
  });
}

// La empresa le pide al cliente que confirme lugar y hora — un aviso, no
// una conversación. Si el pedido ya trae detalles capturados al aceptar la
// oferta los usa; si no, cae a origen/fecha del pedido.
function confirmarLugarHora(reservaId) {
  showConfirm('¿Pedirle al cliente que confirme el lugar y la hora? Le llegará aviso por campana y correo.', async () => {
    const { data: r } = await sb.from('reservaciones')
      .select('cliente_user_id, unidad, pedido_id').eq('id', reservaId).single();
    if (!r?.cliente_user_id) { showToast('No se pudo enviar', 'error'); return; }

    let lugar = null, hora = null;
    if (r.pedido_id) {
      const { data: p } = await sb.from('pedidos')
        .select('detalles_lugar, detalles_hora, origen, fecha_ini').eq('id', r.pedido_id).maybeSingle();
      lugar = p?.detalles_lugar || p?.origen || null;
      hora  = p?.detalles_hora  || (p?.fecha_ini ? fmtFecha(p.fecha_ini) : null);
    }
    const detalle = [lugar ? `lugar: ${lugar}` : null, hora ? `hora: ${hora}` : null].filter(Boolean).join(', ');
    const mensaje = `${esc(currentUser.nombre)} quiere confirmar contigo${detalle ? ` — ${esc(detalle)}` : ''} para el servicio "${esc(r.unidad || '')}". Si algo cambió, repórtalo desde Reservaciones.`;

    const { error } = await sb.from('notificaciones').insert({
      user_id: r.cliente_user_id,
      tipo:    'confirmar_lugar_hora',
      titulo:  '📍 Confirma lugar y hora',
      mensaje,
      leido:   false,
    });
    if (error) { showToast('No se pudo enviar: ' + error.message, 'error'); return; }

    _notificarEmail({
      tipo: 'resolucion', destinoIds: [r.cliente_user_id],
      titulo: 'Confirma lugar y hora', mensaje, aprobado: true,
    });
    showToast('✓ Aviso enviado al cliente');
  });
}

// Aviso de retraso — el detalle (cuánto tiempo, por qué) es opcional, se
// puede mandar solo el aviso sin nada más si no hace falta explicar.
function avisarRetraso(reservaId) {
  _abrirRechazarNota(
    '⏰ Avisar retraso',
    'Detalle (opcional) — cuánto tiempo o el motivo:',
    async nota => {
      const { data: r } = await sb.from('reservaciones')
        .select('cliente_user_id, unidad').eq('id', reservaId).single();
      if (!r?.cliente_user_id) { showToast('No se pudo enviar', 'error'); return; }

      const mensaje = `El transporte de tu servicio "${esc(r.unidad || '')}" va a llegar tarde.${nota ? ` ${esc(nota)}` : ''}`;
      const { error } = await sb.from('notificaciones').insert({
        user_id: r.cliente_user_id,
        tipo:    'aviso_retraso',
        titulo:  '⏰ Aviso de retraso',
        mensaje,
        leido:   false,
      });
      if (error) { showToast('No se pudo enviar: ' + error.message, 'error'); return; }

      _notificarEmail({
        tipo: 'resolucion', destinoIds: [r.cliente_user_id],
        titulo: 'Aviso de retraso', mensaje, aprobado: false,
      });
      showToast('✓ Aviso de retraso enviado');
    },
    { confirmLabel: '⏰ Enviar aviso', danger: false }
  );
}

// ── ACTUALIZAR LUGAR/HORA O REPORTAR PROBLEMA (cliente → empresa + superadmin) ──
// El lugar/hora se editan de verdad (se guardan en el pedido, la empresa ve
// el dato real); los otros motivos son alertas fijas, sin textarea, porque
// no hay un campo concreto que editar para "hay un problema con la carga".
const _RC_MOTIVOS = {
  carga: '📦 El cliente reporta un problema con la carga o los documentos.',
  otro:  '⚠ El cliente reporta un problema urgente y pide que lo contacten.',
};

async function abrirReportarCambio(reservaId) {
  document.getElementById('rc-reserva-id').value = reservaId;
  document.getElementById('rc-pedido-id').value = '';
  document.getElementById('rc-lugar').value = '';
  document.getElementById('rc-hora').value = '';
  _ocultarFormActualizarViaje();
  document.getElementById('modal-reportar-cambio').classList.add('open');

  // Se precarga el lugar/hora actuales aunque el formulario empiece oculto,
  // para que ya estén listos si el usuario elige "Actualizar viaje".
  const { data: r } = await sb.from('reservaciones').select('pedido_id').eq('id', reservaId).single();
  if (!r?.pedido_id) return;
  document.getElementById('rc-pedido-id').value = r.pedido_id;

  const { data: p } = await sb.from('pedidos')
    .select('detalles_lugar, detalles_hora, origen').eq('id', r.pedido_id).maybeSingle();
  document.getElementById('rc-lugar').value = p?.detalles_lugar || p?.origen || '';
  document.getElementById('rc-hora').value  = p?.detalles_hora || '';
}
function cerrarReportarCambio() {
  document.getElementById('modal-reportar-cambio').classList.remove('open');
}
function _mostrarFormActualizarViaje() {
  document.getElementById('rc-menu').style.display = 'none';
  document.getElementById('rc-form').style.display = '';
}
function _ocultarFormActualizarViaje() {
  document.getElementById('rc-form').style.display = 'none';
  document.getElementById('rc-menu').style.display = '';
}

// Le avisa a la empresa (dueña de la reservación) y a todo superadmin —
// mismo destinatario para el cambio de lugar/hora y para los reportes fijos.
async function _notificarCambioReserva(reservaId, titulo, mensaje) {
  const { data: r } = await sb.from('reservaciones')
    .select('propietario_id').eq('id', reservaId).single();
  if (!r?.propietario_id) { showToast('No se pudo enviar', 'error'); return false; }

  // Este es el único sitio que necesita la LISTA de superadmins en vez de
  // usar notificar_superadmins(): _notificarEmail necesita los ids para el
  // correo, así que hace falta traerlos. Cambiarlo a la RPC daría tres
  // viajes en vez de dos.
  //
  // Va por ids_superadmins() y no por un select a perfiles porque quien
  // llama aquí es un admin o un cliente: con la tabla cerrada (H-01) el
  // select devolvería vacío SIN error y los superadmins dejarían de recibir
  // el aviso en silencio. La función solo devuelve ids, ninguna columna
  // de datos personales.
  const { data: supers } = await sb.rpc('ids_superadmins');
  const destinatarios = [r.propietario_id, ...((supers || []).map(s => s.user_id ?? s))];

  const { error } = await sb.from('notificaciones').insert(destinatarios.map(uid => ({
    user_id: uid, tipo: 'cambio_reportado', titulo, mensaje, leido: false,
  })));
  if (error) { showToast('No se pudo enviar: ' + error.message, 'error'); return false; }

  _notificarEmail({ tipo: 'resolucion', destinoIds: destinatarios, titulo, mensaje, aprobado: false });
  return true;
}

async function _guardarCambioLugarHora() {
  const reservaId = document.getElementById('rc-reserva-id').value;
  const pedidoId  = document.getElementById('rc-pedido-id').value;
  const lugar = document.getElementById('rc-lugar')?.value?.trim() || '';
  const hora  = document.getElementById('rc-hora')?.value?.trim() || '';
  if (!reservaId || !pedidoId) return;
  if (!lugar && !hora) { showToast('Indica el lugar y/o la hora', 'error'); return; }

  const { error } = await sb.from('pedidos')
    .update({ detalles_lugar: lugar || null, detalles_hora: hora || null }).eq('id', pedidoId);
  if (error) { showToast('No se pudo guardar: ' + error.message, 'error'); return; }

  const detalle = [lugar ? `lugar: ${lugar}` : null, hora ? `hora: ${hora}` : null].filter(Boolean).join(', ');
  const mensaje = `✏️ El cliente actualizó el viaje — ${esc(detalle)}.`;
  const ok = await _notificarCambioReserva(reservaId, '✏️ El cliente actualizó lugar/hora', mensaje);
  if (!ok) return;

  cerrarReportarCambio();
  await renderReserv();
  showToast('✓ Guardado y avisado a la empresa');
}

// El motivo ya viene fijo (no hay que elegirlo a mano), pero el detalle de
// qué pasó exactamente sí se puede agregar — opcional, mismo modal de nota
// que ya usa el resto del sitio para esto.
function _enviarReporteCambio(motivoClave) {
  const reservaId = document.getElementById('rc-reserva-id').value;
  const texto = _RC_MOTIVOS[motivoClave];
  if (!reservaId || !texto) return;
  cerrarReportarCambio();

  _abrirRechazarNota(
    '⚠ Reportar problema',
    'Detalle (opcional) — qué pasó exactamente:',
    async nota => {
      const { data: r } = await sb.from('reservaciones')
        .select('unidad, cliente').eq('id', reservaId).single();
      const mensaje = `${texto}${nota ? ` ${esc(nota)}` : ''} Servicio "${esc(r?.unidad || '')}" — ${esc(r?.cliente || 'cliente')}.`;
      const ok = await _notificarCambioReserva(reservaId, '⚠ Cliente reporta un problema', mensaje);
      if (!ok) return;
      showToast('✓ Reporte enviado a la empresa y al superadmin');
    },
    { confirmLabel: '⚠ Enviar reporte', danger: false }
  );
}

async function subirDocumentosCarga() {
  const reservaId = document.getElementById('dc-reserva-id').value;
  const files = Array.from(document.getElementById('dc-files')?.files || []);
  if (!files.length) { showToast('Selecciona al menos un archivo', 'error'); return; }

  const { data: r } = await sb.from('reservaciones').select('documentos_carga').eq('id', reservaId).single();
  const existentes = r?.documentos_carga || [];
  if (existentes.length + files.length > 8) {
    showToast(`Máximo 8 documentos. Ya tienes ${existentes.length}.`, 'error'); return;
  }

  const nuevosPaths = [];
  for (const f of files) {
    const ext  = f.name.split('.').pop();
    const path = `${currentUser.id}/documentos-carga/${reservaId}/${Date.now()}_${Math.random().toString(36).slice(2)}.${ext}`;
    const { error: upErr } = await sb.storage.from('unidades').upload(path, f);
    if (upErr) { showToast('Error al subir: ' + upErr.message, 'error'); return; }
    nuevosPaths.push(path);
  }

  const { error } = await sb.from('reservaciones')
    .update({ documentos_carga: [...existentes, ...nuevosPaths] }).eq('id', reservaId);
  if (error) { showToast('No se pudo guardar: ' + error.message, 'error'); return; }

  cerrarDocumentosCarga();
  await renderReserv();
  showToast(`✓ ${nuevosPaths.length} documento${nuevosPaths.length !== 1 ? 's' : ''} subido${nuevosPaths.length !== 1 ? 's' : ''}`);
}

// ── ASIGNAR CHOFER (empresa, reserva activa) ──────────
// El chofer ya no es obligatorio al ofertar: se puede asignar en cualquier
// momento mientras el viaje sigue Activo, y tracking.js bloquea avanzar del
// primer paso sin uno (ver avanzarTracking).

async function abrirAsignarChofer(reservaId) {
  const { data: r } = await sb.from('reservaciones')
    .select('operador_id, pedido_id').eq('id', reservaId).single();
  if (!r) { showToast('No se encontró la reserva', 'error'); return; }

  let esCargaPeligrosa = false;
  if (r.pedido_id) {
    const { data: ped } = await sb.from('pedidos').select('carga_peligrosa').eq('id', r.pedido_id).maybeSingle();
    esCargaPeligrosa = !!ped?.carga_peligrosa;
  }

  const { data: opsRaw } = await sb.from('operadores')
    .select('id, nombre, primer_apellido')
    .eq('propietario_id', currentUser.id).eq('aprobacion', 'aprobada');

  // H-04: la licencia HAZMAT se lee de `vigencias`, no de la columna del
  // operador. Su fecha ES la caducidad (vigencia_meses null en el catálogo),
  // así que el filtro va en la base y se apoya en el índice de fecha_documento.
  let ops = opsRaw || [];
  if (esCargaPeligrosa) {
    const { data: licencias } = await sb.from('vigencias')
      .select('entidad_id')
      .eq('entidad_tipo', 'operador')
      .eq('tipo_documento', 'licencia_peligrosa')
      .eq('estado', 'vigente')
      .gte('fecha_documento', today());
    const conLicencia = new Set((licencias || []).map(v => v.entidad_id));
    ops = ops.filter(o => conLicencia.has(o.id));
  }

  const sel = document.getElementById('ac-operador');
  sel.innerHTML = ops.length
    ? '<option value="">— Selecciona un chofer —</option>' + ops.map(o =>
        `<option value="${esc(o.id)}">${esc(`${o.nombre} ${o.primer_apellido || ''}`.trim())}</option>`).join('')
    : esCargaPeligrosa
      ? '<option value="">Sin choferes con licencia HAZMAT vigente</option>'
      : '<option value="">Sin operadores registrados</option>';
  if (r.operador_id) sel.value = r.operador_id;

  document.getElementById('ac-reserva-id').value = reservaId;
  const aviso = document.getElementById('ac-aviso-hazmat');
  if (aviso) aviso.style.display = esCargaPeligrosa ? '' : 'none';
  document.getElementById('modal-asignar-chofer').classList.add('open');
}

function cerrarAsignarChofer() {
  document.getElementById('modal-asignar-chofer').classList.remove('open');
}

async function confirmarAsignarChofer() {
  const reservaId = document.getElementById('ac-reserva-id').value;
  const sel = document.getElementById('ac-operador');
  const operadorId = sel?.value;
  const operadorNombre = sel?.options[sel.selectedIndex]?.textContent?.trim() || null;
  if (!operadorId) { showToast('Selecciona un chofer', 'error'); return; }

  const { error } = await sb.from('reservaciones').update({
    operador_id:     operadorId,
    operador_nombre: operadorNombre,
  }).eq('id', reservaId);
  if (error) { showToast('No se pudo asignar: ' + error.message, 'error'); return; }

  cerrarAsignarChofer();
  await renderReserv();
  showToast('✓ Chofer asignado');
}

// ── CAMBIAR UNIDAD (empresa, reserva activa) ──────────
// Para cuando la unidad asignada se descompone o no puede seguir el
// servicio: la empresa reasigna a otra unidad propia disponible del mismo
// tipo, con motivo obligatorio (lo exige guard_reservacion_update en DB).

async function abrirCambiarUnidad(reservaId) {
  const { data: r } = await sb.from('reservaciones')
    .select('unidad, recurso_tipo').eq('id', reservaId).single();
  if (!r) { showToast('No se encontró la reserva', 'error'); return; }

  const tabla = r.recurso_tipo === 'custodio' ? 'custodios'
    : r.recurso_tipo === 'patio' ? 'patios'
    : r.recurso_tipo === 'lavado' ? 'lavados' : 'camiones';

  const { data: opciones } = await sb.from(tabla)
    .select('id, tipo, nombre')
    .eq('propietario_id', currentUser.id)
    .eq('aprobacion', 'aprobada')
    .eq('estado', 'disponible')
    .neq('id', r.unidad || '');

  const sel = document.getElementById('cu-unidad-nueva');
  sel.innerHTML = opciones?.length
    ? '<option value="">Selecciona…</option>' + opciones.map(o =>
        `<option value="${esc(o.id)}">${esc(o.id)}${o.tipo ? ' — ' + esc(o.tipo) : ''}${o.nombre ? ' — ' + esc(o.nombre) : ''}</option>`).join('')
    : '<option value="">No tienes otra unidad disponible del mismo tipo</option>';

  document.getElementById('cu-reserva-id').value     = reservaId;
  document.getElementById('cu-tabla').value          = tabla;
  document.getElementById('cu-unidad-actual').value  = r.unidad || '';
  document.getElementById('cu-unidad-actual-label').textContent = r.unidad || '—';
  document.getElementById('cu-motivo').value = '';
  document.getElementById('modal-cambiar-unidad').classList.add('open');
}

function cerrarCambiarUnidad() {
  document.getElementById('modal-cambiar-unidad').classList.remove('open');
}

async function confirmarCambiarUnidad() {
  const reservaId   = document.getElementById('cu-reserva-id').value;
  const tabla       = document.getElementById('cu-tabla').value;
  const unidadVieja = document.getElementById('cu-unidad-actual').value;
  const unidadNueva = document.getElementById('cu-unidad-nueva').value;
  const motivo      = document.getElementById('cu-motivo').value.trim();

  if (!unidadNueva) { showToast('Selecciona la nueva unidad', 'error'); return; }
  if (!motivo) { showToast('Indica el motivo del cambio', 'error'); return; }

  const { error } = await sb.from('reservaciones').update({
    unidad: unidadNueva,
    motivo_cambio_unidad: motivo,
  }).eq('id', reservaId);
  if (error) { showToast('No se pudo cambiar la unidad: ' + (error.message || ''), 'error'); return; }

  if (unidadVieja) await sb.from(tabla).update({ estado: 'disponible' }).eq('id', unidadVieja);
  await sb.from(tabla).update({ estado: 'ocupado' }).eq('id', unidadNueva);

  const { data: r } = await sb.from('reservaciones').select('cliente_user_id, cliente').eq('id', reservaId).single();
  const notifs = [];
  if (r?.cliente_user_id) notifs.push({
    user_id: r.cliente_user_id, tipo: 'unidad_cambiada', titulo: '🔧 Se cambió la unidad de tu servicio',
    mensaje: `La empresa cambió la unidad asignada de "${unidadVieja}" a "${unidadNueva}". Motivo: ${motivo}`, leido: false,
  });
  if (notifs.length) await sb.from('notificaciones').insert(notifs);

  await sb.rpc('notificar_superadmins', {
    p_tipo:    'unidad_cambiada',
    p_titulo:  '🔧 Cambio de unidad en un servicio activo',
    p_mensaje: `${esc(currentUser.nombre || 'Una empresa')} cambió la unidad de "${unidadVieja}" a "${unidadNueva}" en el servicio de ${esc(r?.cliente || 'un cliente')}. Motivo: ${motivo}`,
  });

  cerrarCambiarUnidad();
  await renderReserv();
  showToast('✓ Unidad cambiada');
}

// ── COMPLETAR SERVICIO (cliente y empresa, con aprobación del superadmin) ──
//
// Ni cliente ni empresa cierran el servicio directamente: cada quien marca
// su lado como completado subiendo su propia evidencia (evidencias = empresa,
// evidencias_cliente = cliente). En cuanto el primero lo hace, la reserva
// pasa a 'PorAprobar' y el superadmin revisa ambas evidencias antes de
// aprobar (-> 'Completada', cierra el pedido) o rechazar (-> 'Activa').

async function abrirEvidencias(reservaId, campo = 'evidencias') {
  const { data: r } = await sb.from('reservaciones')
    .select('estado, tracking_estado, recurso_tipo, completado_en, evidencias, evidencias_cliente, cliente_user_id, propietario_id, cliente, pedido_id')
    .eq('id', reservaId).single();
  if (!r) { showToast('No se encontró la reserva', 'error'); return; }

  const modo = r.estado === 'Activa' ? 'solicitar' : 'agregar';

  // Solo la empresa, y solo al solicitar el cierre, debe haber avanzado el
  // seguimiento hasta el último paso.
  if (campo === 'evidencias' && modo === 'solicitar') {
    const estados   = _getEstados(r.recurso_tipo);
    const estadoFin = estados[estados.length - 1];
    const actual    = r.tracking_estado || estados[0].key;
    if (actual !== estadoFin.key) {
      showToast(`Primero avanza el seguimiento 📍 hasta "${estadoFin.label}". Estado actual: "${esc(actual)}".`, 'error');
      return;
    }
  }

  const campoInput = document.getElementById('ev-campo');
  if (!campoInput) {
    // El HTML del modal está desactualizado en este navegador (falta el
    // campo nuevo) — avisar en vez de fallar en silencio.
    showToast('Tu app está desactualizada. Recarga la página (Ctrl+Shift+R) e inténtalo de nuevo.', 'error');
    return;
  }
  document.getElementById('ev-reserva-id').value = reservaId;
  campoInput.value = campo;
  document.getElementById('ev-files').value = '';
  document.getElementById('ev-lista-actual').innerHTML = '<span style="color:var(--text-muted);font-size:0.82rem">Cargando…</span>';
  document.getElementById('modal-evidencias').classList.add('open');

  const tituloEl = document.getElementById('ev-titulo');
  const btnEl    = document.getElementById('btn-subir-evidencias');
  if (tituloEl) tituloEl.textContent = modo === 'solicitar' ? '✓ Marcar servicio completado' : '📎 Evidencias del servicio';
  if (btnEl)    btnEl.textContent    = modo === 'solicitar' ? '✓ Confirmar y enviar a revisión' : '📤 Subir evidencias';

  const infoEl = document.getElementById('ev-plazo-info');
  if (modo === 'solicitar') {
    if (infoEl) infoEl.textContent = 'Sube al menos una foto como evidencia. La otra parte también deberá subir la suya antes de que el superadmin apruebe el cierre.';
  } else {
    const hoy = new Date();
    const fechaComp = r.completado_en ? new Date(r.completado_en) : hoy;
    const diasRestantes = 5 - Math.floor((hoy - fechaComp) / 86400000);
    if (infoEl) infoEl.textContent = diasRestantes > 0
      ? `Tienes ${diasRestantes} día${diasRestantes !== 1 ? 's' : ''} para subir evidencias (máx. 5 archivos en total).`
      : 'El plazo de 5 días para subir evidencias ha vencido.';
    const fileInput = document.getElementById('ev-files');
    if (fileInput) fileInput.disabled = diasRestantes <= 0;
  }

  // El bucket es privado: se guardan paths y se firman URLs al momento de ver.
  // Entradas legadas con URL completa se muestran tal cual.
  const existentes = r[campo] || [];
  const listaEl = document.getElementById('ev-lista-actual');
  if (existentes.length) {
    const enlaces = await Promise.all(existentes.map(async (e) => {
      if (String(e).startsWith('http')) return e;
      const { data } = await sb.storage.from('unidades').createSignedUrl(e, 3600);
      return data?.signedUrl || null;
    }));
    listaEl.innerHTML = enlaces.map((url, i) => url
      ? `<a href="${esc(url)}" target="_blank" class="btn-edit" style="font-size:0.75rem">📎 Evidencia ${i + 1}</a>`
      : `<span style="font-size:0.75rem;color:var(--text-muted)">📎 Evidencia ${i + 1} (no disponible)</span>`
    ).join('');
  } else {
    listaEl.innerHTML = '<span style="font-size:0.78rem;color:var(--text-muted)">Sin evidencias aún</span>';
  }
}

function cerrarEvidencias() {
  document.getElementById('modal-evidencias').classList.remove('open');
}

async function subirEvidencias() {
  const reservaId = document.getElementById('ev-reserva-id').value;
  const campo     = document.getElementById('ev-campo')?.value || 'evidencias';
  const files     = Array.from(document.getElementById('ev-files')?.files || []);
  if (!files.length) { showToast('Selecciona al menos un archivo', 'error'); return; }

  // Lectura ligera solo para no subir archivos a Storage que la RPC vaya a
  // rechazar (plazo/tope) y para el texto del toast. registrar_evidencias
  // revalida todo esto de forma autoritativa.
  const { data: r } = await sb.from('reservaciones')
    .select('estado, completado_en, evidencias, evidencias_cliente')
    .eq('id', reservaId).single();
  if (!r) { showToast('No se encontró la reserva', 'error'); return; }

  const solicitando = r.estado === 'Activa';

  // Verificar plazo (5 días) — solo aplica cuando ya se solicitó el cierre.
  if (!solicitando) {
    const diasPasados = r.completado_en
      ? Math.floor((new Date() - new Date(r.completado_en)) / 86400000)
      : 0;
    if (diasPasados > 5) { showToast('El plazo de 5 días para subir evidencias ha vencido.', 'error'); return; }
  }

  const existentes = r[campo] || [];
  if (existentes.length + files.length > 5) {
    showToast(`Solo puedes tener 5 evidencias. Ya tienes ${existentes.length}.`, 'error'); return;
  }

  // Se guarda el path (no una URL pública): el bucket es privado y los
  // enlaces se firman al verlos en abrirEvidencias().
  const nuevosPaths = [];
  for (const f of files) {
    const ext  = f.name.split('.').pop();
    const path = `${currentUser.id}/evidencias/${reservaId}/${Date.now()}_${Math.random().toString(36).slice(2)}.${ext}`;
    const { error: upErr } = await sb.storage.from('unidades').upload(path, f);
    if (upErr) { showToast('Error al subir: ' + upErr.message, 'error'); return; }
    nuevosPaths.push(path);
  }

  // registrar_evidencias (RPC, ver supabase/migrations/20260810120000): los
  // archivos ya están en Storage; la función agrega las rutas a la columna del
  // lado que corresponde (cliente o empresa, según auth.uid()), y si es la
  // solicitud de cierre mueve el estado a PorAprobar, fija completado_en y
  // avisa a la otra parte y a los superadmins — todo en una transacción. Antes
  // eran hasta 4 escrituras sueltas. Revalida plazo, tope y paso del tracking.
  // Ver H-10 en la auditoría.
  const { error } = await sb.rpc('registrar_evidencias', {
    p_reserva_id: reservaId,
    p_paths:      nuevosPaths,
  });
  if (error) { showToast(error.message || 'Error al guardar', 'error'); return; }

  cerrarEvidencias();
  await renderReserv();
  showToast(solicitando
    ? '✓ Enviado a revisión del superadmin'
    : `✓ ${nuevosPaths.length} evidencia${nuevosPaths.length !== 1 ? 's' : ''} subida${nuevosPaths.length !== 1 ? 's' : ''}`);
}

// ── CALIFICAR SERVICIO (cliente) ───────────────────────

let _calReservaId = null;
let _calAdminId   = null;
let _calRating    = 5;

function openCalificar(reservaId, adminId, adminNombre) {
  _calReservaId = reservaId;
  _calAdminId   = adminId;
  _calRating    = 5;
  document.getElementById('cal-reservacion-id').value = reservaId;
  document.getElementById('cal-admin-id').value       = adminId;
  document.getElementById('cal-subtitulo').textContent = adminNombre ? `Califica a ${adminNombre}` : '';
  seleccionarEstrella(5);
  document.getElementById('cal-comentario').value = '';
  document.getElementById('modal-calificar').classList.add('open');
}

function closeCalificar() {
  document.getElementById('modal-calificar').classList.remove('open');
  _calReservaId = null;
  _calAdminId   = null;
}

function seleccionarEstrella(val) {
  _calRating = val;
  const labels = ['', 'Malo', 'Regular', 'Bueno', 'Muy bueno', 'Excelente'];
  document.querySelectorAll('#cal-stars .star').forEach((el, i) => {
    el.classList.toggle('star-on', i < val);
  });
  const lbl = document.getElementById('cal-rating-label');
  if (lbl) lbl.textContent = labels[val] || '';
}

async function enviarCalificacion() {
  if (!_calReservaId || !_calAdminId) return;
  const comentario = document.getElementById('cal-comentario')?.value?.trim() || null;

  // calificar_servicio (RPC, ver supabase/migrations/20260810120000): inserta
  // la calificación, marca la reserva como calificada y avisa al proveedor en
  // una sola transacción. Antes eran 3 escrituras sueltas sin atomicidad — el
  // admin_id lo deriva la función del propietario de la reserva. Ver H-10.
  const { error } = await sb.rpc('calificar_servicio', {
    p_reserva_id: _calReservaId,
    p_rating:     _calRating,
    p_comentario: comentario,
  });
  if (error) { showToast(error.message || 'Error al enviar calificación', 'error'); return; }

  closeCalificar();
  await renderReserv();
  showToast('⭐ ¡Gracias por tu calificación!');
}

// El registro de cobros vive en js/cobros.js (abrirRegistrarPago /
// revertirPago), que además captura forma de pago y referencia.

// ── SOLICITUD DE CANCELACIÓN (cliente) ─────────────────
// El acuerdo ya fue aprobado y la empresa comprometió una unidad, así que el
// cliente no cancela por su cuenta: lo solicita con un motivo y el superadmin
// resuelve. La empresa se entera de inmediato, porque puede tener un camión
// ya en camino.
let _cancelReservaId = null;

function solicitarCancelacion(reservaId) {
  _cancelReservaId = reservaId;
  document.getElementById('sc-motivo').value = '';
  document.getElementById('sc-detalle').value = '';
  document.getElementById('modal-solicitar-cancelacion').classList.add('open');
}

function cerrarSolicitarCancelacion() {
  document.getElementById('modal-solicitar-cancelacion').classList.remove('open');
  _cancelReservaId = null;
}

async function confirmarSolicitudCancelacion() {
  if (!_cancelReservaId) return;
  const motivo  = document.getElementById('sc-motivo').value;
  const detalle = document.getElementById('sc-detalle').value.trim();
  if (!motivo) { showToast('Selecciona el motivo de la cancelación.', 'error'); return; }

  // solicitar_cancelacion (RPC, ver supabase/migrations/20260810120000): pone
  // la reserva en CancelacionSolicitada, congela el punto del viaje en
  // cancelacion_tracking_estado y avisa a la empresa (puede detener la unidad)
  // y a los superadmins, que resuelven — todo en una transacción. Antes eran 3
  // escrituras sueltas. Ver H-10 en la auditoría.
  const { error } = await sb.rpc('solicitar_cancelacion', {
    p_reserva_id: _cancelReservaId,
    p_motivo:     motivo,
    p_detalle:    detalle || null,
  });

  cerrarSolicitarCancelacion();
  if (error) { showToast(error.message || 'No se pudo enviar la solicitud', 'error'); return; }

  showToast('✓ Solicitud enviada — te avisaremos cuando se resuelva');
  await renderReserv();
  await loadNotificaciones();
}

// ── HISTORIAL DE RESERVACIONES ARCHIVADAS (superadmin) ─

async function renderHistorialReservas() {
  const el = document.getElementById('historial-reservas-content');
  if (!el) return;
  el.innerHTML = `<div class="empty-state"><div class="icon">⏳</div>Cargando historial…</div>`;

  // Dos fuentes (A2-C2, 07/10):
  //   · las archivadas con la marca, que siguen enteras en reservaciones y se
  //     pueden restaurar;
  //   · el archivo antiguo (reservaciones_historico, solo lectura): lo
  //     archivado antes del 07/10, con 14 columnas; lo demás se perdió al
  //     borrar la original, así que no se puede devolver a la lista.
  // Las dos, por FECHA DE ARCHIVADO: un historial se lee por lo último que
  // entró en él (lo encontró el usuario el 2026-09-28, probando H-22).
  const [nuevas, antiguas] = await Promise.all([
    sb.from('reservaciones')
      .select('id,unidad,cliente,propietario_id,fecha_ini,fecha_fin,estado,archivada_en')
      .not('archivada_en', 'is', null)
      .order('archivada_en', { ascending: false })
      .limit(100),
    sb.from('reservaciones_historico')
      .select('id,unidad,cliente,empresa,fecha_ini,fecha_fin,estado,archivado_en')
      .order('archivado_en', { ascending: false })
      .limit(100),
  ]);
  if (nuevas.error || antiguas.error) {
    console.error('Historial de reservaciones', nuevas.error || antiguas.error);
    el.innerHTML = `<div class="empty-state"><div class="icon">❌</div>Error al cargar historial.</div>`;
    return;
  }
  const filas = nuevas.data || [], viejas = antiguas.data || [];
  if (!filas.length && !viejas.length) {
    el.innerHTML = `<div class="empty-state"><div class="icon">🗃</div>No hay reservaciones archivadas.</div>`;
    return;
  }

  // La empresa sale de propietario_id, que está en la fila (como en renderReserv).
  const ids = [...new Set(filas.map(r => r.propietario_id).filter(Boolean))];
  const empresa = {};
  if (ids.length) {
    const { data: perf } = await sb.from('perfiles').select('user_id,nombre').in('user_id', ids);
    (perf || []).forEach(p => { empresa[p.user_id] = p.nombre; });
  }

  const cabecera = extra => `
      <thead>
        <tr>
          <th>Unidad</th><th>Cliente</th><th>Empresa</th><th>Inicio</th><th>Fin</th>
          <th>Estado</th><th>Archivado</th>${extra}
        </tr>
      </thead>`;
  const celdas = (r, emp, archivado) => `
          <td>${esc(r.unidad || '—')}</td>
          <td>${esc(r.cliente || '—')}</td>
          <td>${esc(emp || '—')}</td>
          <td>${fmtFecha(r.fecha_ini)}</td>
          <td>${fmtFecha(r.fecha_fin)}</td>
          <td><span class="badge badge-maint">${esc(r.estado || '—')}</span></td>
          <td style="font-size:0.75rem;color:var(--text-muted)">${archivado ? fmtFecha(archivado) : '—'}</td>`;

  el.innerHTML = `
    ${filas.length ? `
    <table class="rep-table" style="width:100%">
      ${cabecera('<th></th>')}
      <tbody>
        ${filas.map(r => `
        <tr>${celdas(r, empresa[r.propietario_id], r.archivada_en)}
          <td><button class="btn-edit" style="font-size:0.72rem" onclick="restaurarReserva('${r.id}')">↩ Restaurar</button></td>
        </tr>`).join('')}
      </tbody>
    </table>` : `<div class="empty-state"><div class="icon">🗃</div>No hay reservaciones archivadas desde el 07/10.</div>`}
    ${viejas.length ? `
    <div class="section-title" style="margin-top:1.5rem;font-size:0.95rem">Archivo antiguo (antes del 07/10/2026)</div>
    <p style="font-size:0.8rem;color:var(--text-muted);margin:0 0 0.5rem">
      Solo se conservaron estos datos: el resto de cada reservación se perdió al archivarla. No se pueden restaurar.
    </p>
    <table class="rep-table" style="width:100%">
      ${cabecera('')}
      <tbody>
        ${viejas.map(r => `<tr>${celdas(r, r.empresa, r.archivado_en)}</tr>`).join('')}
      </tbody>
    </table>` : ''}`;
}

// Helper: envía email via edge function (fire-and-forget)
async function _enviarEmail(tipo, payload) {
  try {
    const session = (await sb.auth.getSession()).data.session;
    const fnBase  = typeof FN_URL !== 'undefined'
      ? FN_URL.replace('gestionar-usuario', 'enviar-notificacion') : null;
    if (!fnBase || !session?.access_token || !payload.clienteEmail) return;
    fetch(fnBase, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${session.access_token}` },
      body: JSON.stringify({ tipo, ...payload })
    });
  } catch (_) { /* silencioso */ }
}
