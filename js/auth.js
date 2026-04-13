// ── AUTENTICACIÓN ─────────────────────────────────────

async function doLogin() {
  const email = document.getElementById('login-user').value.trim();
  const pass  = document.getElementById('login-pass').value;
  const err   = document.getElementById('login-error');
  err.classList.remove('show');

  const { data, error } = await sb.auth.signInWithPassword({ email, password: pass });
  if (error || !data.user) { err.classList.add('show'); return; }

  // Obtener perfil y rol desde la tabla perfiles
  const { data: perfil } = await sb.from('perfiles')
    .select('nombre, rol')
    .eq('user_id', data.user.id)
    .single();

  const rol    = perfil?.rol    || 'cliente';
  const nombre = perfil?.nombre || email;

  document.getElementById('user-label').textContent = nombre;
  document.getElementById('login-overlay').style.display = 'none';

  document.body.classList.remove('role-admin', 'role-superadmin');
  if (rol === 'admin')      document.body.classList.add('role-admin');
  if (rol === 'superadmin') document.body.classList.add('role-superadmin');

  init();
}

async function logout() {
  await sb.auth.signOut();
  document.body.classList.remove('role-admin', 'role-superadmin');
  document.getElementById('login-user').value = '';
  document.getElementById('login-pass').value = '';
  document.getElementById('login-overlay').style.display = 'flex';

  // Regresar a la pestaña inicial
  document.querySelectorAll('.view').forEach(el => el.classList.remove('active'));
  document.querySelectorAll('.nav-tab').forEach(el => el.classList.remove('active'));
  document.getElementById('view-cliente').classList.add('active');
  document.querySelector('.nav-tab').classList.add('active');
}
