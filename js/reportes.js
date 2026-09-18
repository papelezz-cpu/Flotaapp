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

  // Los agregados los calcula la base. Antes esta pantalla se descargaba
  // TODOS los pedidos y TODAS las reservaciones del rango —más todas las
  // empresas, sin filtro— para pintar siete cifras: el coste crecía con el
  // histórico y no con lo que se enseña. Ver H-07 y la migración 20260918150000.
  const { data: kpi, error } = await sb.rpc('reporte_kpis', { p_desde: desde, p_hasta: hasta });

  if (error || !kpi) {
    console.error('reporte_kpis falló:', error?.message || 'sin datos');
    el.innerHTML = `<div class="empty-state"><div class="icon">❌</div>Error al cargar datos.</div>`;
    return;
  }

  // ── Totales ────────────────────────────────────────
  const totalPedidos   = kpi.total_pedidos;
  const acordados      = kpi.acordados;
  const abiertos       = kpi.abiertos;
  const totalReservas  = kpi.total_reservas;
  const ingresoEst     = Number(kpi.ingreso) || 0;
  // La tasa se sigue redondeando aquí y no en SQL: Math.round y round() de
  // PostgreSQL no coinciden en los empates, y el número tiene que ser el mismo.
  const tasaCierre     = totalPedidos ? Math.round((acordados / totalPedidos) * 100) : 0;
  // kpi.cancelados también viene, pero ninguna tarjeta lo pinta: se calculaba
  // aquí desde siempre y no se usaba.

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
  // El rango y las etiquetas se siguen construyendo aquí; la base solo
  // devuelve el mapa 'YYYY-MM' -> pedidos, una entrada por mes con datos.
  Object.entries(kpi.meses || {}).forEach(([key, n]) => {
    if (mesesMap[key]) mesesMap[key].count = n;
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
  // Ya viene ordenado y recortado a cinco, con el nombre resuelto contra
  // empresas_publico. El desempate es por ingreso y luego por nombre: antes lo
  // decidía el orden de descarga, que no significaba nada.
  const topAdmins = (kpi.top_admins || []).map(a => ({
    nombre:   a.nombre,
    reservas: a.reservas,
    ingreso:  Number(a.ingreso) || 0,
  }));

  // ── Tipos de servicio más solicitados ────────────
  const topTipos = (kpi.top_tipos || []).map(t => [t.tipo, t.n]);

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
