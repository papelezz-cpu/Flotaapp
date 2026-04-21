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
        <div class="truck-list-item-name">${esc(u.nombre)}</div>
        <div class="truck-list-item-sub">${esc(u.email)} · ${ROL_LABEL[u.rol] || u.rol}</div>
      </div>
      <button class="btn-edit" onclick="abrirEditarUsuario('${u.user_id}','${esc(u.nombre)}','${esc(u.email)}','${u.rol}')">✏ Editar</button>
      ${u.rol !== 'superadmin'
        ? `<button class="btn-edit btn-rechazar" onclick="eliminarUsuario('${u.user_id}','${esc(u.nombre)}')">🗑</button>`
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
  if (pass && pass.length < 6) { showToast('La contraseña debe tener al menos 6 caracteres.'); return; }

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
