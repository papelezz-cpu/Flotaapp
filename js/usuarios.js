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

  list.innerHTML = json.lista.map(u => `
    <div class="truck-list-item">
      <div class="truck-list-item-info">
        <div class="truck-list-item-name">${u.nombre}</div>
        <div class="truck-list-item-sub">${u.email} · ${ROL_LABEL[u.rol] || u.rol}</div>
      </div>
      ${u.rol !== 'superadmin'
        ? `<button class="btn-edit"
             style="background:rgba(239,68,68,0.12);border-color:rgba(239,68,68,0.3);color:var(--red)"
             onclick="eliminarUsuario('${u.user_id}','${u.nombre}')">Eliminar</button>`
        : ''}
    </div>`).join('');
}

async function crearUsuario() {
  const nombre = document.getElementById('nu-nombre').value.trim();
  const email  = document.getElementById('nu-email').value.trim();
  const pass   = document.getElementById('nu-pass').value;
  const rol    = document.getElementById('nu-rol').value;

  if (!nombre || !email || !pass) { alert('Completa todos los campos.'); return; }
  if (pass.length < 6) { alert('La contraseña debe tener al menos 6 caracteres.'); return; }

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
  if (!res.ok) { alert('Error: ' + (json.error || 'No se pudo crear.')); return; }

  document.getElementById('nu-nombre').value = '';
  document.getElementById('nu-email').value  = '';
  document.getElementById('nu-pass').value   = '';
  await renderUsuarios();
  showToast(`✓ Usuario ${nombre} creado`);
}

async function eliminarUsuario(userId, nombre) {
  if (!confirm(`¿Eliminar al usuario "${nombre}"? Esta acción no se puede deshacer.`)) return;

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
  if (!res.ok) { alert('Error: ' + (json.error || 'No se pudo eliminar.')); return; }

  await renderUsuarios();
  showToast(`Usuario ${nombre} eliminado`);
}
