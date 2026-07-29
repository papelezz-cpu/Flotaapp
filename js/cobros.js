// ── ESTADOS DE COBRO ───────────────────────────────────
// El mercado opera a crédito: el cliente paga N días después del servicio.
// El estado de cobro NO se guarda: se deriva de `pagado` + la fecha de
// vencimiento, para no depender de un proceso que actualice estados a diario.

// Plazos ofrecidos en el formulario de solicitud → días.
// "Anticipado" vence el mismo día; "" (a convenir) no genera vencimiento.
const PLAZO_PAGO_DIAS = {
  'Anticipado': 0,
  '3 días':  3,
  '7 días':  7,
  '15 días': 15,
  '30 días': 30,
  '45 días': 45,
  '60 días': 60,
};

function plazoPagoADias(plazo) {
  if (!plazo) return null;
  if (PLAZO_PAGO_DIAS[plazo] !== undefined) return PLAZO_PAGO_DIAS[plazo];
  // Tolerante a variantes ("30 dias", "30") por si el texto cambia
  const m = String(plazo).match(/\d+/);
  return m ? parseInt(m[0], 10) : null;
}

// Fecha de vencimiento a partir de la fecha de cierre del servicio.
function calcularVencimientoPago(plazo, desdeISO) {
  const dias = plazoPagoADias(plazo);
  if (dias === null) return null;
  const d = desdeISO ? new Date(desdeISO) : new Date();
  d.setDate(d.getDate() + dias);
  return d.toISOString().split('T')[0];
}

// Estado derivado de una reservación.
// Devuelve null cuando el cobro todavía no aplica (servicio no completado).
function estadoCobro(r) {
  if (r.estado !== 'Completada') return null;
  if (r.pagado) {
    return { clave: 'pagado', label: '💰 Pagado', cls: 'cobro-pagado', dias: null };
  }
  const venc = r.fecha_vencimiento_pago;
  if (!venc) {
    return { clave: 'por_cobrar', label: 'Por cobrar', cls: 'cobro-pendiente', dias: null };
  }
  // Comparación por fecha (sin hora) para que "vence hoy" no cuente vencido
  const hoyStr = new Date().toISOString().split('T')[0];
  const dias = Math.round((new Date(venc + 'T00:00:00') - new Date(hoyStr + 'T00:00:00')) / 86400000);
  if (dias < 0) {
    const n = Math.abs(dias);
    return { clave: 'vencido', label: `⚠ Vencido · ${n} día${n !== 1 ? 's' : ''}`, cls: 'cobro-vencido', dias };
  }
  if (dias === 0) return { clave: 'por_cobrar', label: 'Vence hoy', cls: 'cobro-porvencer', dias };
  if (dias <= 3) return { clave: 'por_cobrar', label: `Vence en ${dias} día${dias !== 1 ? 's' : ''}`, cls: 'cobro-porvencer', dias };
  return { clave: 'por_cobrar', label: `Por cobrar · ${fmtFecha(venc)}`, cls: 'cobro-pendiente', dias };
}

function cobroBadgeHTML(r) {
  const e = estadoCobro(r);
  if (!e) return '';
  return `<span class="cobro-badge ${e.cls}">${e.label}</span>`;
}

// ── REGISTRAR COBRO ────────────────────────────────────
let _cobroReservaId = null;

function abrirRegistrarPago(reservaId) {
  _cobroReservaId = reservaId;
  const set = (id, v) => { const el = document.getElementById(id); if (el) el.value = v; };
  set('pg-metodo', '');
  set('pg-referencia', '');
  set('pg-fecha', today());
  document.getElementById('modal-registrar-pago').classList.add('open');
}

function cerrarRegistrarPago() {
  document.getElementById('modal-registrar-pago').classList.remove('open');
  _cobroReservaId = null;
}

async function confirmarRegistrarPago() {
  if (!_cobroReservaId) return;
  const metodo = document.getElementById('pg-metodo').value;
  const refer  = document.getElementById('pg-referencia').value.trim();
  const fecha  = document.getElementById('pg-fecha').value;
  if (!metodo) { showToast('Selecciona la forma de pago.', 'error'); return; }

  const { error } = await sb.from('reservaciones').update({
    pagado:          true,
    pagado_en:       fecha ? new Date(fecha + 'T12:00:00').toISOString() : new Date().toISOString(),
    pagado_por:      currentUser.id,
    pago_metodo:     metodo,
    pago_referencia: refer || null,
  }).eq('id', _cobroReservaId);

  cerrarRegistrarPago();
  if (error) { showToast('Error al registrar el pago: ' + error.message, 'error'); return; }
  showToast('✓ Pago registrado');
  await renderReserv();
  actualizarBadgeCobros();
}

function revertirPago(reservaId) {
  showConfirm('¿Marcar este servicio como NO pagado? Se borrarán los datos del cobro registrado.', async () => {
    // El trigger sync_datos_pago limpia fecha, método y referencia.
    const { error } = await sb.from('reservaciones').update({ pagado: false }).eq('id', reservaId);
    if (error) { showToast('Error: ' + error.message, 'error'); return; }
    showToast('Cobro revertido');
    await renderReserv();
    actualizarBadgeCobros();
  }, { danger: true, confirmLabel: 'Sí, revertir' });
}

// ── BADGE DE COBROS VENCIDOS (inicio) ──────────────────
// Cliente: lo que él debe. Empresa: lo que le deben. Superadmin: todo.
async function actualizarBadgeCobros() {
  const badge = document.getElementById('home-cobros-badge');
  if (!badge || !currentUser.id) return;
  const hoy = new Date().toISOString().split('T')[0];
  let q = sb.from('reservaciones')
    .select('id', { count: 'exact', head: true })
    .eq('estado', 'Completada')
    .eq('pagado', false)
    .lt('fecha_vencimiento_pago', hoy);
  if (currentUser.rol === 'cliente')      q = q.eq('cliente_email', currentUser.email);
  else if (currentUser.rol === 'admin')   q = q.eq('propietario_id', currentUser.id);
  const { count } = await q;
  if (count > 0) {
    badge.textContent = count > 99 ? '99+' : count;
    badge.style.display = 'inline-block';
  } else {
    badge.style.display = 'none';
  }
}
