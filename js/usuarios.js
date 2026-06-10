// ── GESTIÓN DE USUARIOS (solo superadmin) ────────────

const ROL_LABEL = {
  superadmin: '⭐ Superadmin',
  admin:      '🔧 Admin',
  cliente:    '👤 Cliente'
};

async function renderUsuarios() {
  const list = document.getElementById('usuarios-list');
  list.innerHTML = `<div class="empty-state"><div class="icon">⏳</div>Cargando...</div>`;

  const { data: { session } } = await sb.auth.getSession();
  const res = await fetch(FN_URL, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${session.access_token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ accion: 'listar' })
  });
  const json = await res.json();

  if (!res.ok || !json.lista) {
    list.innerHTML = `<div class="empty-state"><div class="icon">❌</div>${json.error || 'Error'}</div>`;
    return;
  }
  if (!json.lista.length) {
    list.innerHTML = `<div class="empty-state"><div class="icon">👥</div>Sin usuarios registrados.</div>`;
    return;
  }

  const APR_BADGE = {
    pendiente:  `<span style="display:inline-block;font-size:0.68rem;font-weight:700;background:rgba(234,179,8,0.15);color:#ca8a04;border:1px solid rgba(234,179,8,0.35);border-radius:10px;padding:1px 7px;margin-left:6px;vertical-align:middle">Pendiente</span>`,
    rechazada:  `<span style="display:inline-block;font-size:0.68rem;font-weight:700;background:rgba(239,68,68,0.12);color:var(--danger);border:1px solid rgba(239,68,68,0.3);border-radius:10px;padding:1px 7px;margin-left:6px;vertical-align:middle">Rechazada</span>`,
    suspendida: `<span style="display:inline-block;font-size:0.68rem;font-weight:700;background:rgba(245,158,11,0.15);color:var(--amber);border:1px solid rgba(245,158,11,0.35);border-radius:10px;padding:1px 7px;margin-left:6px;vertical-align:middle">Suspendida</span>`,
  };

  // Cargar estados verificado desde perfiles
  const userIds = json.lista.map(u => u.user_id).filter(Boolean);
  let verificadoMap = {};
  if (userIds.length) {
    const { data: perfs } = await sb.from('perfiles').select('user_id, verificado').in('user_id', userIds);
    (perfs || []).forEach(p => { verificadoMap[p.user_id] = !!p.verificado; });
  }

  list.innerHTML = json.lista.map(u => {
    const verificado = verificadoMap[u.user_id] || false;
    const verBadge   = verificado
      ? `<span title="Usuario verificado" style="display:inline-block;font-size:0.7rem;font-weight:700;background:rgba(34,197,94,0.15);color:var(--green,#22c55e);border:1px solid rgba(34,197,94,0.4);border-radius:10px;padding:1px 7px;margin-left:6px;vertical-align:middle">✓ Verificado</span>`
      : '';
    return `
    <div class="truck-list-item">
      <div class="truck-list-item-info">
        <div class="truck-list-item-name">
          ${esc(u.nombre)}${APR_BADGE[u.aprobacion_cuenta] || ''}${verBadge}
        </div>
        <div class="truck-list-item-sub">${esc(u.email)} · ${ROL_LABEL[u.rol] || u.rol}</div>
      </div>
      <button class="btn-edit" onclick="abrirHistorialUsuario('${u.user_id}','${escJs(u.nombre)}','${u.rol}')">📋</button>
      <button class="btn-edit" onclick="abrirEditarUsuario('${u.user_id}','${escJs(u.nombre)}','${escJs(u.email)}','${u.rol}')">✏ Editar</button>
      ${u.rol !== 'superadmin' ? `
        <button class="btn-edit" style="font-size:0.72rem;${verificado ? 'color:var(--green,#22c55e);border-color:rgba(34,197,94,0.4)' : ''}"
          onclick="toggleVerificado('${u.user_id}','${escJs(u.nombre)}',${verificado})">${verificado ? '✓ Verificado' : '✓ Verificar'}</button>
        ${u.aprobacion_cuenta === 'suspendida'
          ? `<button class="btn-edit" style="color:var(--green);border-color:rgba(34,197,94,0.3)" onclick="reactivarUsuario('${u.user_id}','${escJs(u.nombre)}')">↑ Activar</button>`
          : `<button class="btn-edit" style="color:var(--amber);border-color:rgba(245,158,11,0.3)" onclick="suspenderUsuario('${u.user_id}','${escJs(u.nombre)}')">🚫</button>`}
        <button class="btn-edit btn-rechazar" onclick="eliminarUsuario('${u.user_id}','${escJs(u.nombre)}')">🗑</button>
      ` : ''}
    </div>`;
  }).join('');
}

async function toggleVerificado(userId, nombre, actualmente) {
  const nuevoValor = !actualmente;
  const { error } = await sb.from('perfiles').update({ verificado: nuevoValor }).eq('user_id', userId);
  if (error) { showToast('Error al actualizar verificación', 'error'); return; }
  showToast(nuevoValor ? `✓ ${esc(nombre)} marcado como verificado` : `${esc(nombre)} desmarcado como verificado`);
  renderUsuarios();
}

async function crearUsuario() {
  const nombre = document.getElementById('nu-nombre').value.trim();
  const email  = document.getElementById('nu-email').value.trim();
  const pass   = document.getElementById('nu-pass').value;
  const rol    = document.getElementById('nu-rol').value;

  if (!nombre || !email || !pass) { showToast('Completa todos los campos.', 'error'); return; }
  if (pass.length < 8) { showToast('La contraseña debe tener al menos 8 caracteres.', 'error'); return; }

  const { data: { session } } = await sb.auth.getSession();
  const res = await fetch(FN_URL, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${session.access_token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ accion: 'crear', nombre, email, password: pass, rol })
  });
  const json = await res.json();
  if (!res.ok) { showToast('Error: ' + (json.error || 'No se pudo crear.'), 'error'); return; }

  document.getElementById('nu-nombre').value = '';
  document.getElementById('nu-email').value  = '';
  document.getElementById('nu-pass').value   = '';
  await renderUsuarios();
  showToast(`✓ Usuario ${nombre} creado`);
}

function abrirEditarUsuario(userId, nombre, email, rol) {
  document.getElementById('eu-id').value     = userId;
  document.getElementById('eu-nombre').value = nombre;
  document.getElementById('eu-email').value  = email;
  document.getElementById('eu-pass').value   = '';
  document.getElementById('eu-rol').value    = rol;
  document.getElementById('modal-editar-usuario').classList.add('open');
}

function cerrarEditarUsuario() {
  document.getElementById('modal-editar-usuario').classList.remove('open');
}

async function guardarEdicionUsuario() {
  const userId = document.getElementById('eu-id').value;
  const nombre = document.getElementById('eu-nombre').value.trim();
  const email  = document.getElementById('eu-email').value.trim();
  const pass   = document.getElementById('eu-pass').value;
  const rol    = document.getElementById('eu-rol').value;

  if (!nombre || !email) { showToast('Completa nombre y correo.'); return; }
  if (pass && pass.length < 8) { showToast('La contraseña debe tener al menos 8 caracteres.'); return; }

  const body = { accion: 'editar', user_id: userId, nombre, email, rol };
  if (pass) body.password = pass;

  const { data: { session } } = await sb.auth.getSession();
  const res = await fetch(FN_URL, {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${session.access_token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });
  const json = await res.json();
  if (!res.ok) { showToast('Error: ' + (json.error || 'No se pudo guardar.')); return; }

  cerrarEditarUsuario();
  await renderUsuarios();
  showToast(`✓ Usuario ${nombre} actualizado`);
}

function eliminarUsuario(userId, nombre) {
  showConfirm(`¿Eliminar al usuario "${nombre}"? Esta acción no se puede deshacer.`, async () => {
    const { data: { session } } = await sb.auth.getSession();
    const res = await fetch(FN_URL, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${session.access_token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ accion: 'eliminar', user_id: userId })
    });
    const json = await res.json();
    if (!res.ok) { showToast('Error: ' + (json.error || 'No se pudo eliminar.'), 'error'); return; }
    await renderUsuarios();
    showToast(`Usuario ${nombre} eliminado`);
  }, { danger: true, confirmLabel: 'Eliminar' });
}

// ── HISTORIAL POR USUARIO ──────────────────────────────

async function abrirHistorialUsuario(userId, nombre, rol) {
  document.getElementById('hist-titulo').textContent = `Historial — ${nombre}`;
  document.getElementById('hist-body').innerHTML =
    '<div style="text-align:center;padding:24px;color:var(--text-muted)">Cargando…</div>';
  document.getElementById('modal-historial-usuario').classList.add('open');

  if (rol === 'cliente') {
    const { data: pedidos } = await sb.from('pedidos')
      .select('id, tipo_camion, estado, origen, destino, fecha_ini, created_at, precio_cliente')
      .eq('cliente_id', userId)
      .order('created_at', { ascending: false })
      .limit(50);

    const ESTADO_LABEL = {
      abierto: 'Abierto', en_negociacion: 'En negociación', acordado: '✓ Acordado',
      cancelado: 'Cancelado', rechazado: 'Rechazado', pendiente_revision: 'En revisión',
      pendiente_acuerdo: 'Acuerdo en revisión',
    };
    const ESTADO_COLOR = {
      acordado: 'var(--green)', cancelado: 'var(--text-muted)', rechazado: 'var(--danger)',
      abierto: 'var(--accent)', en_negociacion: 'var(--amber)',
    };

    document.getElementById('hist-body').innerHTML = pedidos?.length ? `
      <div style="margin-bottom:10px;color:var(--text-muted);font-size:0.82rem">${pedidos.length} solicitud${pedidos.length !== 1 ? 'es' : ''} encontrada${pedidos.length !== 1 ? 's' : ''}</div>
      <table class="rep-table">
        <thead><tr><th>Servicio</th><th>Ruta</th><th>Fecha</th><th>Estado</th></tr></thead>
        <tbody>
          ${pedidos.map(p => `<tr>
            <td>${esc(p.tipo_camion || '—')}</td>
            <td style="font-size:0.78rem">${esc(p.origen || '—')}${p.destino ? ' → ' + esc(p.destino) : ''}</td>
            <td style="font-size:0.78rem;color:var(--text-muted)">${fmtFecha(p.fecha_ini || (p.created_at||'').substring(0,10))}</td>
            <td style="color:${ESTADO_COLOR[p.estado]||'inherit'};font-size:0.8rem">${ESTADO_LABEL[p.estado] || p.estado}</td>
          </tr>`).join('')}
        </tbody>
      </table>` : '<div class="rep-empty">Este cliente no tiene solicitudes.</div>';

  } else if (rol === 'admin') {
    const [{ data: reservas }, { data: ofertas }] = await Promise.all([
      sb.from('reservaciones')
        .select('id, unidad, cliente, fecha_ini, fecha_fin, estado, precio_acordado, created_at')
        .eq('propietario_id', userId)
        .order('created_at', { ascending: false })
        .limit(50),
      sb.from('ofertas')
        .select('id, pedido_id, precio_oferta, estado, created_at')
        .eq('admin_id', userId)
        .order('created_at', { ascending: false })
        .limit(20),
    ]);

    const ganadas   = (ofertas || []).filter(o => o.estado === 'aceptada').length;
    const enviadas  = (ofertas || []).length;
    const ingresos  = (reservas || []).reduce((s, r) => s + (Number(r.precio_acordado) || 0), 0);

    document.getElementById('hist-body').innerHTML = `
      <div class="rep-cards" style="margin-bottom:16px">
        <div class="rep-kpi-card"><div class="rep-kpi-val">${reservas?.length || 0}</div><div class="rep-kpi-label">Reservaciones</div></div>
        <div class="rep-kpi-card"><div class="rep-kpi-val green">$${ingresos.toLocaleString('es-MX')}</div><div class="rep-kpi-label">Ingreso est.</div></div>
        <div class="rep-kpi-card"><div class="rep-kpi-val">${ganadas}/${enviadas}</div><div class="rep-kpi-label">Ofertas ganadas</div></div>
      </div>
      ${reservas?.length ? `
      <div class="rep-section-title" style="font-size:0.82rem;margin-bottom:8px">Últimas reservaciones</div>
      <table class="rep-table">
        <thead><tr><th>Cliente</th><th>Período</th><th>Precio</th><th>Estado</th></tr></thead>
        <tbody>
          ${reservas.slice(0, 20).map(r => `<tr>
            <td>${esc(r.cliente || '—')}</td>
            <td style="font-size:0.78rem">${fmtFecha(r.fecha_ini)} – ${fmtFecha(r.fecha_fin)}</td>
            <td style="color:var(--green);font-size:0.8rem">$${(Number(r.precio_acordado)||0).toLocaleString('es-MX')}</td>
            <td style="font-size:0.78rem;color:var(--text-muted)">${esc(r.estado)}</td>
          </tr>`).join('')}
        </tbody>
      </table>` : '<div class="rep-empty">Sin reservaciones aún.</div>'}`;

  } else {
    document.getElementById('hist-body').innerHTML =
      '<div class="rep-empty">No hay historial disponible para este rol.</div>';
  }
}

function cerrarHistorialUsuario() {
  document.getElementById('modal-historial-usuario').classList.remove('open');
}

// ── SUSPENDER / REACTIVAR ──────────────────────────────

function suspenderUsuario(userId, nombre) {
  showConfirm(`¿Suspender la cuenta de "${nombre}"? No podrá iniciar sesión hasta que sea reactivada.`, async () => {
    const { error } = await sb.from('perfiles').update({ aprobacion_cuenta: 'suspendida' }).eq('user_id', userId);
    if (error) { showToast('Error: ' + error.message, 'error'); return; }
    await renderUsuarios();
    showToast(`🚫 Cuenta de ${nombre} suspendida`);
  }, { danger: true, confirmLabel: 'Suspender' });
}

async function reactivarUsuario(userId, nombre) {
  const { error } = await sb.from('perfiles').update({ aprobacion_cuenta: null }).eq('user_id', userId);
  if (error) { showToast('Error: ' + error.message, 'error'); return; }
  await renderUsuarios();
  showToast(`✓ Cuenta de ${nombre} reactivada`);
}
