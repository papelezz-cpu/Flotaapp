// ── REPORTES SUPERADMIN ────────────────────────────────

async function renderReportes() {
  const el = document.getElementById('reportes-content');
  if (!el) return;
  el.innerHTML = `<div class="empty-state"><div class="icon">⏳</div>Calculando métricas…</div>`;

  // Inicializar inputs de fecha si no tienen valor
  const inputDesde = document.getElementById('rep-fecha-desde');
  const inputHasta = document.getElementById('rep-fecha-hasta');
  if (inputDesde && !inputDesde.value) {
    const d = new Date();
    d.setMonth(d.getMonth() - 5);
    d.setDate(1);
    inputDesde.value = d.toISOString().split('T')[0];
  }
  if (inputHasta && !inputHasta.value) {
    inputHasta.value = new Date().toISOString().split('T')[0];
  }
  const desde = inputDesde?.value || (() => {
    const d = new Date(); d.setMonth(d.getMonth() - 5); d.setDate(1);
    return d.toISOString().split('T')[0];
  })();
  const hasta = inputHasta?.value || new Date().toISOString().split('T')[0];

  const [
    { data: pedidos   },
    { data: reservas  },
    { data: perfiles  },
  ] = await Promise.all([
    sb.from('pedidos').select('id, estado, created_at, tipo_camion, cliente_id')
      .gte('created_at', desde).lte('created_at', hasta + 'T23:59:59'),
    sb.from('reservaciones').select('id, precio_acordado, propietario_id, created_at, estado')
      .gte('created_at', desde).lte('created_at', hasta + 'T23:59:59'),
    sb.from('perfiles').select('user_id, nombre, rol').eq('rol', 'admin'),
  ]);

  if (!pedidos || !reservas) {
    el.innerHTML = `<div class="empty-state"><div class="icon">❌</div>Error al cargar datos.</div>`;
    return;
  }

  // ── Totales ────────────────────────────────────────
  const totalPedidos   = pedidos.length;
  const acordados      = pedidos.filter(p => p.estado === 'acordado').length;
  const cancelados     = pedidos.filter(p => p.estado === 'cancelado').length;
  const abiertos       = pedidos.filter(p => p.estado === 'abierto').length;
  const totalReservas  = reservas.length;
  const ingresoEst     = reservas.reduce((s, r) => s + (Number(r.precio_acordado) || 0), 0);
  const tasaCierre     = totalPedidos ? Math.round((acordados / totalPedidos) * 100) : 0;

  // ── Pedidos por mes (rango seleccionado) ──────────
  const mesesMap = {};
  const dDesde = new Date(desde + 'T00:00:00');
  const dHasta = new Date(hasta + 'T00:00:00');
  const cur = new Date(dDesde.getFullYear(), dDesde.getMonth(), 1);
  while (cur <= dHasta) {
    const key = `${cur.getFullYear()}-${String(cur.getMonth() + 1).padStart(2, '0')}`;
    mesesMap[key] = { label: cur.toLocaleString('es-MX', { month: 'short', year: '2-digit' }), count: 0 };
    cur.setMonth(cur.getMonth() + 1);
  }
  pedidos.forEach(p => {
    const key = p.created_at?.substring(0, 7);
    if (key && mesesMap[key]) mesesMap[key].count++;
  });
  const meses = Object.values(mesesMap);
  const maxCount = Math.max(...meses.map(m => m.count), 1);

  const barChart = meses.map(m => {
    const pct = Math.round((m.count / maxCount) * 100);
    return `
      <div class="rep-bar-col">
        <div class="rep-bar-wrap">
          <div class="rep-bar-fill" style="height:${pct}%"></div>
        </div>
        <div class="rep-bar-val">${m.count}</div>
        <div class="rep-bar-label">${m.label}</div>
      </div>`;
  }).join('');

  // ── Top admins por reservaciones ──────────────────
  const adminMap = {};
  (perfiles || []).forEach(p => { adminMap[p.user_id] = p.nombre; });

  const contadorAdmin = {};
  const ingresoAdmin  = {};
  reservas.forEach(r => {
    const id = r.propietario_id;
    if (!id) return;
    contadorAdmin[id] = (contadorAdmin[id] || 0) + 1;
    ingresoAdmin[id]  = (ingresoAdmin[id]  || 0) + (Number(r.precio_acordado) || 0);
  });
  const topAdmins = Object.entries(contadorAdmin)
    .sort(([, a], [, b]) => b - a)
    .slice(0, 5)
    .map(([id, cnt]) => ({
      nombre:  adminMap[id] || 'Empresa',
      reservas: cnt,
      ingreso:  ingresoAdmin[id] || 0,
    }));

  // ── Tipos de servicio más solicitados ────────────
  const tipoMap = {};
  pedidos.forEach(p => {
    const t = p.tipo_camion || 'Otro';
    tipoMap[t] = (tipoMap[t] || 0) + 1;
  });
  const topTipos = Object.entries(tipoMap)
    .sort(([, a], [, b]) => b - a)
    .slice(0, 5);

  // ── Render ─────────────────────────────────────────
  el.innerHTML = `
    <div style="font-size:0.8rem;color:var(--text-muted);margin-bottom:12px">
      Mostrando datos del ${fmtFecha(desde)} al ${fmtFecha(hasta)}
    </div>
    <div class="rep-cards">
      <div class="rep-kpi-card">
        <div class="rep-kpi-val">${totalPedidos}</div>
        <div class="rep-kpi-label">Total solicitudes</div>
      </div>
      <div class="rep-kpi-card">
        <div class="rep-kpi-val green">${acordados}</div>
        <div class="rep-kpi-label">Acordadas</div>
      </div>
      <div class="rep-kpi-card">
        <div class="rep-kpi-val amber">${abiertos}</div>
        <div class="rep-kpi-label">Abiertas</div>
      </div>
      <div class="rep-kpi-card">
        <div class="rep-kpi-val">${tasaCierre}%</div>
        <div class="rep-kpi-label">Tasa de cierre</div>
      </div>
      <div class="rep-kpi-card">
        <div class="rep-kpi-val">${totalReservas}</div>
        <div class="rep-kpi-label">Reservaciones</div>
      </div>
      <div class="rep-kpi-card">
        <div class="rep-kpi-val green">$${ingresoEst.toLocaleString('es-MX')}</div>
        <div class="rep-kpi-label">Ingreso estimado (MXN)</div>
      </div>
    </div>

    <div class="rep-section">
      <div class="rep-section-title">📊 Solicitudes por mes</div>
      <div class="rep-bar-chart">${barChart}</div>
    </div>

    <div class="rep-cols">
      <div class="rep-section" style="flex:1;min-width:260px">
        <div class="rep-section-title">🏆 Admins más activos</div>
        ${topAdmins.length ? `
        <table class="rep-table">
          <thead><tr><th>Empresa</th><th>Reservas</th><th>Ingreso est.</th></tr></thead>
          <tbody>
            ${topAdmins.map((a, i) => `
            <tr>
              <td><span class="rep-rank">${i + 1}</span> ${esc(a.nombre)}</td>
              <td>${a.reservas}</td>
              <td style="color:var(--green)">$${a.ingreso.toLocaleString('es-MX')}</td>
            </tr>`).join('')}
          </tbody>
        </table>` : '<div class="rep-empty">Sin datos aún</div>'}
      </div>

      <div class="rep-section" style="flex:1;min-width:260px">
        <div class="rep-section-title">🚛 Servicios más solicitados</div>
        ${topTipos.length ? `
        <table class="rep-table">
          <thead><tr><th>Tipo</th><th>Solicitudes</th><th>%</th></tr></thead>
          <tbody>
            ${topTipos.map(([tipo, cnt]) => `
            <tr>
              <td>${esc(tipo)}</td>
              <td>${cnt}</td>
              <td style="color:var(--text-muted)">${Math.round((cnt / totalPedidos) * 100)}%</td>
            </tr>`).join('')}
          </tbody>
        </table>` : '<div class="rep-empty">Sin datos aún</div>'}
      </div>
    </div>`;
}
