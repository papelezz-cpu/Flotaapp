// ── AUTENTICACIÓN ─────────────────────────────────────

let currentUser = { id: null, nombre: null, rol: null };

// Aplica clases de rol y estado en el body
function applyUserUI() {
  document.body.classList.remove('role-admin', 'role-superadmin', 'logged-in');
  document.getElementById('user-label').textContent = currentUser.nombre || '—';
  if (currentUser.rol === 'admin')      document.body.classList.add('role-admin', 'logged-in');
  if (currentUser.rol === 'superadmin') document.body.classList.add('role-superadmin', 'logged-in');
  if (currentUser.rol === 'cliente')    document.body.classList.add('logged-in');
  // Sincronizar ícono del tema
  const isLight = document.body.classList.contains('light');
  const btnTheme = document.getElementById('btn-theme');
  if (btnTheme) btnTheme.textContent = isLight ? '☀️' : '🌙';
}

// Restaura la sesión guardada (si existe); si no, muestra el login como pantalla completa
async function checkExistingSession() {
  // Detectar flujo de recovery (link de "olvidé mi contraseña")
  const hash = new URLSearchParams(window.location.hash.slice(1));
  if (hash.get('type') === 'recovery') {
    await sb.auth.getSession(); // Supabase procesa el token del hash automáticamente
    showPasswordResetModal();
    return;
  }

  const { data: { session } } = await sb.auth.getSession();
  if (!session) {
    // Sin sesión → login obligatorio, no hay vista pública
    showLoginOverlay();
    return;
  }

  const { data: perfil } = await sb.from('perfiles')
    .select('nombre, rol')
    .eq('user_id', session.user.id)
    .single();

  currentUser = {
    id:     session.user.id,
    email:  session.user.email,
    nombre: perfil?.nombre || session.user.email,
    rol:    perfil?.rol    || 'cliente',
  };
  applyUserUI();
  // Realtime de notificaciones para esta sesión restaurada
  sb.channel('notif-' + currentUser.id)
    .on('postgres_changes', {
      event: 'INSERT', schema: 'public', table: 'notificaciones',
      filter: `user_id=eq.${currentUser.id}`
    }, () => loadNotificaciones())
    .subscribe();
}

function showLoginOverlay() {
  document.getElementById('login-overlay').classList.add('show');
}

function hideLoginOverlay() {
  // Solo se puede cerrar si ya hay sesión activa
  if (!currentUser.id) return;
  document.getElementById('login-overlay').classList.remove('show');
}

// ── TABS DEL LOGIN ─────────────────────────────────────
function switchLoginTab(tab) {
  const esLogin = tab === 'login';
  document.getElementById('tab-login').classList.toggle('active', esLogin);
  document.getElementById('tab-registro').classList.toggle('active', !esLogin);
  document.getElementById('login-panel').classList.toggle('hide', !esLogin);
  document.getElementById('registro-panel').classList.toggle('show', !esLogin);
  // Limpiar errores al cambiar
  document.getElementById('login-error').classList.remove('show');
  document.getElementById('registro-error').classList.remove('show');
  document.getElementById('registro-success').classList.remove('show');
}

async function doLogin() {
  const email = document.getElementById('login-user').value.trim();
  const pass  = document.getElementById('login-pass').value;
  const err   = document.getElementById('login-error');
  err.classList.remove('show');

  const { data, error } = await sb.auth.signInWithPassword({ email, password: pass });
  if (error || !data.user) { err.classList.add('show'); return; }

  const { data: perfil } = await sb.from('perfiles')
    .select('nombre, rol')
    .eq('user_id', data.user.id)
    .single();

  currentUser = {
    id:     data.user.id,
    email:  data.user.email,
    nombre: perfil?.nombre || email,
    rol:    perfil?.rol    || 'cliente',
  };

  hideLoginOverlay();
  applyUserUI();
  loadNotificaciones();
  // Realtime para notificaciones de este usuario
  sb.channel('notif-' + currentUser.id)
    .on('postgres_changes', {
      event: 'INSERT', schema: 'public', table: 'notificaciones',
      filter: `user_id=eq.${currentUser.id}`
    }, () => loadNotificaciones())
    .subscribe();
  init();
}

// ── REGISTRO DE NUEVOS CLIENTES ────────────────────────
async function doRegistro() {
  const nombre = document.getElementById('reg-nombre').value.trim();
  const email  = document.getElementById('reg-email').value.trim();
  const pass   = document.getElementById('reg-pass').value;
  const errEl  = document.getElementById('registro-error');
  const okEl   = document.getElementById('registro-success');

  errEl.classList.remove('show');
  okEl.classList.remove('show');

  if (!nombre || !email || !pass) {
    errEl.textContent = 'Completa todos los campos.';
    errEl.classList.add('show'); return;
  }
  if (pass.length < 6) {
    errEl.textContent = 'La contraseña debe tener al menos 6 caracteres.';
    errEl.classList.add('show'); return;
  }

  const { data, error } = await sb.auth.signUp({ email, password: pass });
  if (error || !data.user) {
    errEl.textContent = error?.message || 'Error al crear la cuenta.';
    errEl.classList.add('show'); return;
  }

  // Crear perfil con rol cliente
  await sb.from('perfiles').upsert({
    user_id: data.user.id,
    nombre,
    rol: 'cliente',
  });

  // Si Supabase no requiere confirmación de email, iniciar sesión directo
  if (data.session) {
    currentUser = {
      id:     data.user.id,
      email:  data.user.email,
      nombre,
      rol:    'cliente',
    };
    hideLoginOverlay();
    applyUserUI();
    loadNotificaciones();
    sb.channel('notif-' + currentUser.id)
      .on('postgres_changes', {
        event: 'INSERT', schema: 'public', table: 'notificaciones',
        filter: `user_id=eq.${currentUser.id}`
      }, () => loadNotificaciones())
      .subscribe();
    init();
  } else {
    // Supabase envió email de confirmación
    okEl.classList.add('show');
    document.getElementById('reg-nombre').value = '';
    document.getElementById('reg-email').value  = '';
    document.getElementById('reg-pass').value   = '';
  }
}

// #3 — Olvidé mi contraseña
async function forgotPassword() {
  const email = document.getElementById('login-user').value.trim();
  if (!email) {
    document.getElementById('login-error').textContent = 'Ingresa tu correo primero.';
    document.getElementById('login-error').classList.add('show');
    return;
  }
  const { error } = await sb.auth.resetPasswordForEmail(email, {
    redirectTo: window.location.origin + window.location.pathname
  });
  document.getElementById('login-error').classList.remove('show');
  if (error) { alert('Error: ' + error.message); return; }
  showToast('✓ Revisa tu correo para restablecer tu contraseña');
}

function showPasswordResetModal() {
  const overlay = document.getElementById('login-overlay');
  overlay.classList.add('show');

  // Reutilizamos el panel de login insertando un formulario temporal
  const panel = document.getElementById('login-panel');
  panel.innerHTML = `
    <h2 style="margin-bottom:16px">Nueva contraseña</h2>
    <input id="reset-pass-new" type="password" placeholder="Nueva contraseña" style="width:100%;margin-bottom:10px;padding:10px;border:1px solid var(--border);border-radius:8px;background:var(--surface);color:var(--text)">
    <input id="reset-pass-confirm" type="password" placeholder="Confirmar contraseña" style="width:100%;margin-bottom:10px;padding:10px;border:1px solid var(--border);border-radius:8px;background:var(--surface);color:var(--text)">
    <div id="reset-error" class="login-error" style="display:none;color:var(--danger);margin-bottom:8px"></div>
    <button onclick="doPasswordReset()" class="btn-login" style="width:100%">Guardar contraseña</button>
  `;
}

async function doPasswordReset() {
  const pass    = document.getElementById('reset-pass-new').value;
  const confirm = document.getElementById('reset-pass-confirm').value;
  const errEl   = document.getElementById('reset-error');

  errEl.style.display = 'none';

  if (pass.length < 6) {
    errEl.textContent = 'La contraseña debe tener al menos 6 caracteres.';
    errEl.style.display = 'block'; return;
  }
  if (pass !== confirm) {
    errEl.textContent = 'Las contraseñas no coinciden.';
    errEl.style.display = 'block'; return;
  }

  const { error } = await sb.auth.updateUser({ password: pass });
  if (error) {
    errEl.textContent = error.message;
    errEl.style.display = 'block'; return;
  }

  // Limpiar hash de la URL y redirigir al login normal
  history.replaceState(null, '', window.location.pathname);
  await sb.auth.signOut();
  showToast('✓ Contraseña actualizada. Inicia sesión.');
  location.reload();
}

async function logout() {
  await sb.auth.signOut();
  currentUser = { id: null, nombre: null, rol: null };
  document.body.classList.remove('role-admin', 'role-superadmin', 'logged-in');
  document.getElementById('login-user').value = '';
  document.getElementById('login-pass').value = '';
  document.getElementById('login-error').textContent = 'Correo o contraseña incorrectos';
  document.getElementById('login-error').classList.remove('show');

  // Reset all views to default so the next user starts clean
  document.querySelectorAll('.view').forEach(el => el.classList.remove('active'));
  document.querySelectorAll('.nav-tab').forEach(el => el.classList.remove('active'));

  switchLoginTab('login');
  showLoginOverlay();
}
