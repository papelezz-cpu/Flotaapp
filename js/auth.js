// ── AUTENTICACIÓN ─────────────────────────────────────

// Estado del usuario actual (accesible por todos los módulos)
let currentUser = { id: null, nombre: null, rol: null };

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

  currentUser = {
    id:     data.user.id,
    nombre: perfil?.nombre || email,
    rol:    perfil?.rol    || 'cliente',
  };

  document.getElementById('user-label').textContent = currentUser.nombre;
  document.getElementById('login-overlay').style.display = 'none';

  document.body.classList.remove('role-admin', 'role-superadmin');
  if (currentUser.rol === 'admin')      document.body.classList.add('role-admin');
  if (currentUser.rol === 'superadmin') document.body.classList.add('role-superadmin');

  init();
}

async function logout() {
  await sb.auth.signOut();
  currentUser = { id: null, nombre: null, rol: null };
  document.body.classList.remove('role-admin', 'role-superadmin');
  document.getElementById('login-user').value = '';
  document.getElementById('login-pass').value = '';
  document.getElementById('login-overlay').style.display = 'flex';

  document.querySelectorAll('.view').forEach(el => el.classList.remove('active'));
  document.querySelectorAll('.nav-tab').forEach(el => el.classList.remove('active'));
  document.getElementById('view-cliente').classList.add('active');
  document.querySelector('.nav-tab').classList.add('active');
}
