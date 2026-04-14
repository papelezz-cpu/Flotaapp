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

// Restaura la sesión guardada (si existe) sin forzar login
async function checkExistingSession() {
  const { data: { session } } = await sb.auth.getSession();
  if (!session) return; // usuario no autenticado — modo público

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
}

function showLoginOverlay() {
  document.getElementById('login-overlay').classList.add('show');
}

function hideLoginOverlay() {
  document.getElementById('login-overlay').classList.remove('show');
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
  init();
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

async function logout() {
  await sb.auth.signOut();
  currentUser = { id: null, nombre: null, rol: null };
  document.body.classList.remove('role-admin', 'role-superadmin', 'logged-in');
  document.getElementById('login-user').value = '';
  document.getElementById('login-pass').value = '';
  document.getElementById('login-error').textContent = 'Correo o contraseña incorrectos';

  // Volver a vista pública
  document.querySelectorAll('.view').forEach(el => el.classList.remove('active'));
  document.querySelectorAll('.nav-tab').forEach(el => el.classList.remove('active'));
  document.getElementById('view-cliente').classList.add('active');
  document.querySelector('.nav-tab').classList.add('active');
  renderCamiones();
}
