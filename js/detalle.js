// ── MODAL DE DETALLE ──────────────────────────────────

// Distintivo de seguro. Sale de la vigencia aprobada, no de una casilla que la
// empresa marcaba sola: sin fecha no hay documento revisado, y con fecha pasada
// lo hubo pero ya no vale. Tres estados, no dos.
function _seguroBadge(etiqueta, fecha) {
  const hoy = new Date().toISOString().slice(0, 10);
  if (!fecha)      return `<div class="seguro-badge no">✕ ${etiqueta} — sin acreditar</div>`;
  if (fecha < hoy) return `<div class="seguro-badge no">⛔ ${etiqueta} — vencido</div>`;
  return `<div class="seguro-badge ok">✓ ${etiqueta}</div>`;
}

let detalleTab    = 'unidad';
let calYear       = new Date().getFullYear();
let calMonth      = new Date().getMonth();
let detalleReservas = [];
let detalleCamion   = null;
let detallePerfil   = null;

async function openDetail(id) {
  const c = allCamiones.find(x => x.id === id);
  if (!c) return;
  detalleCamion = c;

  const modal = document.getElementById('modal-detalle');
  modal.classList.add('open');
  // Resetear reservas del camión anterior para evitar datos cruzados
  detalleReservas = [];

  // Mostrar cargando directamente en el body (evita bugs si el modal se abre varias veces)
  const body = document.getElementById('detalle-body');
  body.innerHTML = `<div style="display:flex;align-items:center;justify-content:center;height:180px;color:var(--text-muted);font-size:0.88rem">Cargando...</div>`;

  // Cargar perfil de la empresa y reservas en paralelo
  const hoy = today();
  const [{ data: perfil }, { data: reservas }] = await Promise.all([
    // Ficha publica: la vista trae solo lo que esta pantalla pinta. Antes era
    // select('*') sobre perfiles, que entregaba las 37 columnas —documentos,
    // estado de moderacion, fotos de verificacion— para mostrar un nombre.
    sb.from('empresas_publico').select('*').eq('user_id', c.propietario_id).maybeSingle(),
    // H-06: `unidad` guarda el id de un camión, un custodio, un patio o un
    // lavado, así que sin acotar el tipo esta consulta pintaría las fechas
    // ocupadas de OTRO recurso que compartiera cadena de id. Aquí el tipo es
    // siempre 'camion' —`c` sale de `allCamiones`— así que va fijo y no de una
    // variable que pueda venir vacía.
    sb.from('reservaciones')
      .select('fecha_ini, fecha_fin, estado')
      .eq('unidad', id)
      .eq('recurso_tipo', 'camion')
      .in('estado', ['Activa', 'Pendiente'])
      .gte('fecha_fin', hoy)
  ]);
  detalleReservas = reservas || [];

  // Botón Agendar solo si disponible
  const btnAgendar = document.getElementById('btn-detalle-agendar');
  btnAgendar.disabled = c.estado !== 'disponible';
  btnAgendar.textContent = c.estado === 'disponible' ? 'Agendar esta unidad' : '⏳ No disponible';

  // Header del modal
  const stars = c.calificacion ? renderStars(c.calificacion) : '';
  document.getElementById('detalle-titulo').innerHTML =
    `${esc(c.emoji)} ${esc(c.id)} — ${esc(c.tipo)}
     ${stars ? `<span style="margin-left:6px">${stars}</span>` : ''}`;
  document.getElementById('detalle-empresa-header').textContent =
    perfil?.razon_social || c.empresaNombre || '—';

  // Guardar estado global del modal
  detallePerfil = perfil;
  detalleTab    = 'unidad';
  calYear       = new Date().getFullYear();
  calMonth      = new Date().getMonth();
  // Activar tab inicial
  document.querySelectorAll('.detalle-tab').forEach(b => b.classList.toggle('active', b.dataset.tab === 'unidad'));
  renderDetalleTab();
}

function switchDetalleTab(tab) {
  detalleTab = tab;
  document.querySelectorAll('.detalle-tab').forEach(b => b.classList.toggle('active', b.dataset.tab === tab));
  renderDetalleTab();
}

async function renderDetalleTab() {
  const c    = detalleCamion;
  const body = document.getElementById('detalle-body');

  if (detalleTab === 'unidad') {
    const cargaChips = (c.tipo_carga || [])
      .map(t => `<span class="carga-chip">${esc(t)}</span>`).join('');
    const badgeCls = c.estado === 'disponible' ? 'badge-avail' : c.estado === 'ocupado' ? 'badge-busy' : 'badge-maint';
    const label    = c.estado === 'disponible' ? '✓ Disponible' : c.estado === 'ocupado' ? '⏳ En servicio' : '🔧 Mantenimiento';

    body.innerHTML = `
      <div class="detalle-grid">
        <div class="detalle-item"><div class="detalle-lbl">Estado</div>
          <span class="badge ${badgeCls}" style="width:fit-content">${label}</span></div>
        <div class="detalle-item"><div class="detalle-lbl">Capacidad</div>
          <div class="detalle-val">${esc(String(c.capacidad))} toneladas</div></div>
        <div class="detalle-item"><div class="detalle-lbl">Placas</div>
          <div class="detalle-val">${esc(c.placas || '—')}</div></div>
        <div class="detalle-item detalle-full"><div class="detalle-lbl">Dimensiones del vehículo</div>
          <div class="detalle-val">📐 ${esc(c.dimensiones || '—')}</div></div>
        <div class="detalle-item detalle-full"><div class="detalle-lbl">Operador asignado</div>
          <div class="detalle-val">👤 ${esc(c.operador)}</div></div>
        ${cargaChips ? `
        <div class="detalle-item detalle-full">
          <div class="detalle-lbl">Tipo de carga que maneja</div>
          <div class="detalle-chips">${cargaChips}</div>
        </div>` : ''}
      </div>`;

  } else if (detalleTab === 'empresa') {
    if (!detallePerfil) {
      const { data: p } = await sb.from('empresas_publico').select('*').eq('user_id', c.propietario_id).maybeSingle();
      detallePerfil = p;
    }
    const p = detallePerfil || {};
    body.innerHTML = `
      <div class="detalle-empresa">
        <div class="empresa-nombre">${esc(p.razon_social || p.nombre || '—')}</div>
        <div class="empresa-desc">${esc(p.descripcion || 'Sin descripción.')}</div>
        <div class="detalle-grid" style="margin-top:16px">
          <div class="detalle-item"><div class="detalle-lbl">RFC</div>
            <div class="detalle-val">${esc(p.rfc || '—')}</div></div>
          <div class="detalle-item"><div class="detalle-lbl">Años en operación</div>
            <div class="detalle-val">${p.anos_operacion ? p.anos_operacion + ' años' : '—'}</div></div>
          <div class="detalle-item"><div class="detalle-lbl">Unidades en flota</div>
            <div class="detalle-val">${p.num_unidades ? p.num_unidades + ' unidades' : '—'}</div></div>
          <div class="detalle-item"><div class="detalle-lbl">Teléfono</div>
            <div class="detalle-val">${esc(p.telefono || '—')}</div></div>
          <div class="detalle-item detalle-full"><div class="detalle-lbl">Permiso SCT</div>
            <div class="detalle-val">📋 ${p.fecha_vencimiento_permiso_sct ? esc(p.permiso_sct || 'registrado') : '—'}</div></div>
        </div>
        <div class="empresa-seguros">
          ${_seguroBadge('Seguro RC',       p.fecha_vencimiento_seguro_rc)}
          ${_seguroBadge('Seguro de Carga', p.fecha_vencimiento_seguro_carga)}
        </div>
      </div>`;

  } else if (detalleTab === 'calendario') {
    body.innerHTML = `<div id="cal-container"></div>`;
    renderCalendar();
  }
}

// ── CALENDARIO ────────────────────────────────────────

function renderCalendar() {
  const container = document.getElementById('cal-container');
  if (!container) return;

  const hoy      = new Date(); hoy.setHours(0,0,0,0);
  const firstDay = new Date(calYear, calMonth, 1);
  const lastDay  = new Date(calYear, calMonth + 1, 0);
  const meses    = ['Enero','Febrero','Marzo','Abril','Mayo','Junio',
                    'Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'];

  // Pre-calcular días reservados
  const booked  = new Set();
  const pending = new Set();
  detalleReservas.forEach(r => {
    // Tomar solo la parte de fecha (Supabase puede devolver timestamp completo)
    const from = new Date(r.fecha_ini.split('T')[0] + 'T00:00');
    const to   = new Date(r.fecha_fin.split('T')[0] + 'T00:00');
    for (let d = new Date(from); d <= to; d.setDate(d.getDate() + 1)) {
      if (d.getFullYear() === calYear && d.getMonth() === calMonth) {
        const key = d.getDate();
        r.estado === 'Pendiente' ? pending.add(key) : booked.add(key);
      }
    }
  });

  // Día de la semana del primer día (lunes=0)
  const startOffset = (firstDay.getDay() + 6) % 7;
  const totalCells  = startOffset + lastDay.getDate();
  const rows        = Math.ceil(totalCells / 7);

  let cells = '';
  for (let i = 0; i < rows * 7; i++) {
    const day = i - startOffset + 1;
    if (day < 1 || day > lastDay.getDate()) {
      cells += `<div class="cal-cell empty"></div>`;
    } else {
      const date = new Date(calYear, calMonth, day); date.setHours(0,0,0,0);
      const isPast   = date < hoy;
      const isToday  = date.getTime() === hoy.getTime();
      const isBooked = booked.has(day);
      const isPend   = pending.has(day) && !isBooked;
      const cls = isToday  ? 'cal-today'
                : isBooked ? 'cal-booked'
                : isPend   ? 'cal-pending'
                : isPast   ? 'cal-past'
                : 'cal-free';
      cells += `<div class="cal-cell ${cls}">${day}</div>`;
    }
  }

  container.innerHTML = `
    <div class="cal-nav">
      <button class="cal-btn" onclick="calPrev()">‹</button>
      <span class="cal-titulo">${meses[calMonth]} ${calYear}</span>
      <button class="cal-btn" onclick="calNext()">›</button>
    </div>
    <div class="cal-grid">
      <div class="cal-dow">Lu</div><div class="cal-dow">Ma</div><div class="cal-dow">Mi</div>
      <div class="cal-dow">Ju</div><div class="cal-dow">Vi</div>
      <div class="cal-dow">Sá</div><div class="cal-dow">Do</div>
      ${cells}
    </div>
    <div class="cal-leyenda">
      <span class="leyenda-item"><span class="leyenda-dot free"></span>Disponible</span>
      <span class="leyenda-item"><span class="leyenda-dot pending"></span>Pendiente</span>
      <span class="leyenda-item"><span class="leyenda-dot booked"></span>Ocupado</span>
      <span class="leyenda-item"><span class="leyenda-dot today"></span>Hoy</span>
    </div>`;
}

function calPrev() {
  calMonth--;
  if (calMonth < 0) { calMonth = 11; calYear--; }
  renderCalendar();
}
function calNext() {
  calMonth++;
  if (calMonth > 11) { calMonth = 0; calYear++; }
  renderCalendar();
}

function closeDetalle() {
  document.getElementById('modal-detalle').classList.remove('open');
}

function detalleAgendar() {
  closeDetalle();
  openNuevoPedido();
}
