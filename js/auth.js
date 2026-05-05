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
  const hash = new URLSearchParams(window.location.hash.slice(1));
  if (hash.get('type') === 'recovery') {
    await sb.auth.getSession();
    showPasswordResetModal();
    return;
  }

  const { data: { session } } = await sb.auth.getSession();
  if (!session) { showLoginOverlay(); return; }

  const { data: perfil } = await sb.from('perfiles')
    .select('nombre, rol, aprobacion_cuenta, nota_rechazo_cuenta')
    .eq('user_id', session.user.id)
    .single();

  if (perfil?.aprobacion_cuenta === 'pendiente' || perfil?.aprobacion_cuenta === 'rechazada') {
    await sb.auth.signOut();
    showLoginOverlay();
    return;
  }

  currentUser = {
    id:     session.user.id,
    email:  session.user.email,
    nombre: perfil?.nombre || session.user.email,
    rol:    perfil?.rol    || 'cliente',
  };
  applyUserUI();
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
  document.getElementById('login-error').classList.remove('show');
  const box = document.querySelector('.login-box');
  if (box) box.classList.remove('expanded');
  if (!esLogin) _renderRegSelector();
}

async function doLogin() {
  const email = document.getElementById('login-user').value.trim();
  const pass  = document.getElementById('login-pass').value;
  const err   = document.getElementById('login-error');
  err.classList.remove('show');

  const { data, error } = await sb.auth.signInWithPassword({ email, password: pass });
  if (error || !data.user) {
    err.textContent = 'Correo o contraseña incorrectos';
    err.classList.add('show'); return;
  }

  const { data: perfil } = await sb.from('perfiles')
    .select('nombre, rol, aprobacion_cuenta, nota_rechazo_cuenta')
    .eq('user_id', data.user.id)
    .single();

  if (perfil?.aprobacion_cuenta === 'pendiente') {
    await sb.auth.signOut();
    err.textContent = 'Tu cuenta está pendiente de aprobación. Te contactaremos cuando sea revisada.';
    err.classList.add('show'); return;
  }
  if (perfil?.aprobacion_cuenta === 'rechazada') {
    await sb.auth.signOut();
    err.textContent = `Tu solicitud fue rechazada.${perfil.nota_rechazo_cuenta ? ' Motivo: ' + perfil.nota_rechazo_cuenta : ' Contacta a soporte para más información.'}`;
    err.classList.add('show'); return;
  }

  currentUser = {
    id:     data.user.id,
    email:  data.user.email,
    nombre: perfil?.nombre || email,
    rol:    perfil?.rol    || 'cliente',
  };

  applyUserUI();
  showView('home', null);
  hideLoginOverlay();
  loadNotificaciones();
  actualizarBadgeChat();
  sb.channel('notif-' + currentUser.id)
    .on('postgres_changes', {
      event: 'INSERT', schema: 'public', table: 'notificaciones',
      filter: `user_id=eq.${currentUser.id}`
    }, () => loadNotificaciones())
    .subscribe();
}

// ── REGISTRO — SELECTOR Y FORMULARIOS ─────────────────

let _regRol = null;
let _regTipoPersona = 'fisica';

function _renderRegSelector() {
  document.getElementById('registro-panel').innerHTML = `
    <div class="reg-header">Crear cuenta</div>
    <div class="reg-sub">¿Cómo quieres registrarte?</div>
    <div class="reg-role-grid">
      <div class="reg-role-card" onclick="iniciarRegistro('cliente')">
        <div class="reg-role-icon">🛒</div>
        <div class="reg-role-title">Cliente</div>
        <div class="reg-role-desc">Solicita servicios de transporte, custodia y más</div>
      </div>
      <div class="reg-role-card" onclick="iniciarRegistro('admin')">
        <div class="reg-role-icon">🏢</div>
        <div class="reg-role-title">Empresa</div>
        <div class="reg-role-desc">Ofrece servicios: flota, operadores, custodios y más</div>
      </div>
    </div>
    <div id="registro-error" class="login-error"></div>
  `;
}

function iniciarRegistro(rol) {
  _regRol = rol;
  _regTipoPersona = 'fisica';
  document.querySelector('.login-box')?.classList.add('expanded');
  document.getElementById('registro-panel').innerHTML = _regFormHTML(rol);
}

function _regVolverInicio() {
  _regRol = null;
  document.querySelector('.login-box')?.classList.remove('expanded');
  _renderRegSelector();
}

function _regToggleMoral(tipo) {
  _regTipoPersona = tipo;
  document.getElementById('btn-fisica')?.classList.toggle('active', tipo === 'fisica');
  document.getElementById('btn-moral')?.classList.toggle('active', tipo === 'moral');
  const s = document.getElementById('reg-moral-section');
  if (s) s.style.display = tipo === 'moral' ? '' : 'none';
}

function updateRegFileLabel(id) {
  const input = document.getElementById(id);
  const nameEl = document.getElementById(id + '-name');
  if (input?.files[0] && nameEl) nameEl.textContent = input.files[0].name;
}

function _regFormHTML(rol) {
  const domFields = `
    <div class="form-group">
      <label>Calle *</label>
      <input type="text" id="reg-calle" placeholder="${rol === 'cliente' ? 'Av. Insurgentes' : 'Av. Industrial'}">
    </div>
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px">
      <div class="form-group">
        <label>Número *</label>
        <input type="text" id="reg-num" placeholder="123-A">
      </div>
      <div class="form-group">
        <label>Código postal *</label>
        <input type="text" id="reg-cp" placeholder="${rol === 'cliente' ? '06600' : '64000'}" maxlength="5">
      </div>
    </div>
    <div class="form-group">
      <label>Colonia *</label>
      <input type="text" id="reg-colonia" placeholder="${rol === 'cliente' ? 'Roma Norte' : 'Zona Industrial'}">
    </div>
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px">
      <div class="form-group">
        <label>Ciudad *</label>
        <input type="text" id="reg-ciudad" placeholder="${rol === 'cliente' ? 'CDMX' : 'Monterrey'}">
      </div>
      <div class="form-group">
        <label>Estado *</label>
        <input type="text" id="reg-estado" placeholder="${rol === 'cliente' ? 'Ciudad de México' : 'Nuevo León'}">
      </div>
    </div>`;

  if (rol === 'cliente') {
    return `
      <button class="reg-back-btn" onclick="_regVolverInicio()">← Volver</button>
      <div class="reg-role-badge">🛒 Cliente</div>
      <div id="registro-error" class="login-error"></div>
      <div class="reg-section-title">Datos personales</div>
      <div class="form-group">
        <label>Nombre completo *</label>
        <input type="text" id="reg-nombre" placeholder="Ej. María González López">
      </div>
      <div class="form-group">
        <label>Correo electrónico *</label>
        <input type="email" id="reg-email" placeholder="correo@ejemplo.com">
      </div>
      <div class="form-group">
        <label>Contraseña * <span class="reg-optional">mínimo 6 caracteres</span></label>
        <input type="password" id="reg-pass" placeholder="••••••••">
      </div>
      <div class="form-group">
        <label>Teléfono *</label>
        <input type="tel" id="reg-telefono" placeholder="55 1234 5678">
      </div>
      <div class="form-group">
        <label>RFC *</label>
        <input type="text" id="reg-rfc" placeholder="GOML900101ABC" maxlength="13" oninput="this.value=this.value.toUpperCase()">
      </div>
      <div class="form-group">
        <label>CURP *</label>
        <input type="text" id="reg-curp" placeholder="GOML900101MDFNBR01" maxlength="18" oninput="this.value=this.value.toUpperCase()">
      </div>
      <div class="reg-section-title">Domicilio</div>
      ${domFields}
      <div class="reg-section-title">Documentos de verificación</div>
      <div class="reg-docs-hint">📎 Necesitamos estos documentos para verificar tu identidad. Formatos aceptados: JPG, PNG, PDF.</div>
      <div class="form-group">
        <label>Identificación oficial (INE / Pasaporte) *</label>
        <label class="reg-file-label" for="reg-ine">
          <span id="reg-ine-name">Seleccionar archivo…</span>
          <input type="file" id="reg-ine" accept="image/*,.pdf" onchange="updateRegFileLabel('reg-ine')">
        </label>
      </div>
      <div class="form-group">
        <label>Comprobante de domicilio *</label>
        <label class="reg-file-label" for="reg-comp-dom">
          <span id="reg-comp-dom-name">Seleccionar archivo…</span>
          <input type="file" id="reg-comp-dom" accept="image/*,.pdf" onchange="updateRegFileLabel('reg-comp-dom')">
        </label>
      </div>
      <div class="form-group">
        <label>Fotografía exterior del domicilio *</label>
        <label class="reg-file-label" for="reg-foto-dom">
          <span id="reg-foto-dom-name">Seleccionar archivo…</span>
          <input type="file" id="reg-foto-dom" accept="image/*" onchange="updateRegFileLabel('reg-foto-dom')">
        </label>
      </div>
      <button class="btn-login" onclick="doRegistro()">Enviar solicitud de registro</button>`;
  }

  // Empresa (admin)
  return `
    <button class="reg-back-btn" onclick="_regVolverInicio()">← Volver</button>
    <div class="reg-role-badge">🏢 Empresa</div>
    <div id="registro-error" class="login-error"></div>
    <div class="reg-section-title">Datos del representante</div>
    <div class="form-group">
      <label>Nombre completo del contacto *</label>
      <input type="text" id="reg-nombre" placeholder="Ej. Carlos Martínez Ruiz">
    </div>
    <div class="form-group">
      <label>Correo electrónico *</label>
      <input type="email" id="reg-email" placeholder="contacto@empresa.com">
    </div>
    <div class="form-group">
      <label>Contraseña * <span class="reg-optional">mínimo 6 caracteres</span></label>
      <input type="password" id="reg-pass" placeholder="••••••••">
    </div>
    <div class="form-group">
      <label>Teléfono *</label>
      <input type="tel" id="reg-telefono" placeholder="55 1234 5678">
    </div>
    <div class="reg-section-title">Datos fiscales</div>
    <div class="form-group">
      <label>Razón social *</label>
      <input type="text" id="reg-razon-social" placeholder="TRANSPORTES ACME S.A. DE C.V." oninput="this.value=this.value.toUpperCase()">
    </div>
    <div class="form-group">
      <label>RFC de la empresa *</label>
      <input type="text" id="reg-rfc" placeholder="TACM9001ABC" maxlength="12" oninput="this.value=this.value.toUpperCase()">
    </div>
    <div class="form-group">
      <label>Tipo de persona *</label>
      <div class="reg-tipo-persona">
        <button type="button" class="reg-tipo-btn active" id="btn-fisica" onclick="_regToggleMoral('fisica')">Física</button>
        <button type="button" class="reg-tipo-btn" id="btn-moral" onclick="_regToggleMoral('moral')">Moral</button>
      </div>
    </div>
    <div id="reg-moral-section" style="display:none">
      <div class="form-group">
        <label>Acta constitutiva <span class="reg-optional">(opcional)</span></label>
        <label class="reg-file-label" for="reg-acta">
          <span id="reg-acta-name">Seleccionar archivo…</span>
          <input type="file" id="reg-acta" accept="image/*,.pdf" onchange="updateRegFileLabel('reg-acta')">
        </label>
      </div>
    </div>
    <div class="reg-section-title">Domicilio fiscal</div>
    ${domFields}
    <div class="reg-section-title">Documentos de verificación</div>
    <div class="reg-docs-hint">📎 Necesitamos estos documentos para verificar que tu empresa es legítima. Formatos: JPG, PNG, PDF.</div>
    <div class="form-group">
      <label>Constancia de Situación Fiscal (SAT) *</label>
      <label class="reg-file-label" for="reg-csf">
        <span id="reg-csf-name">Seleccionar archivo…</span>
        <input type="file" id="reg-csf" accept="image/*,.pdf" onchange="updateRegFileLabel('reg-csf')">
      </label>
    </div>
    <div class="form-group">
      <label>Comprobante de domicilio fiscal *</label>
      <label class="reg-file-label" for="reg-comp-dom">
        <span id="reg-comp-dom-name">Seleccionar archivo…</span>
        <input type="file" id="reg-comp-dom" accept="image/*,.pdf" onchange="updateRegFileLabel('reg-comp-dom')">
      </label>
    </div>
    <div class="form-group">
      <label>Identificación oficial del representante legal *</label>
      <label class="reg-file-label" for="reg-ine">
        <span id="reg-ine-name">Seleccionar archivo…</span>
        <input type="file" id="reg-ine" accept="image/*,.pdf" onchange="updateRegFileLabel('reg-ine')">
      </label>
    </div>
    <div class="form-group">
      <label>Fotografía de fachada / oficinas *</label>
      <label class="reg-file-label" for="reg-foto-dom">
        <span id="reg-foto-dom-name">Seleccionar archivo…</span>
        <input type="file" id="reg-foto-dom" accept="image/*" onchange="updateRegFileLabel('reg-foto-dom')">
      </label>
    </div>
    <div class="form-group">
      <label>Opinión de cumplimiento SAT <span class="reg-optional">(opcional)</span></label>
      <label class="reg-file-label" for="reg-opinion">
        <span id="reg-opinion-name">Seleccionar archivo…</span>
        <input type="file" id="reg-opinion" accept="image/*,.pdf" onchange="updateRegFileLabel('reg-opinion')">
      </label>
    </div>
    <button class="btn-login" onclick="doRegistro()">Enviar solicitud de registro</button>`;
}

async function doRegistro() {
  const errEl    = document.getElementById('registro-error');
  if (!errEl) return;
  errEl.classList.remove('show');

  const nombre   = document.getElementById('reg-nombre')?.value.trim()   || '';
  const email    = document.getElementById('reg-email')?.value.trim()    || '';
  const pass     = document.getElementById('reg-pass')?.value            || '';
  const telefono = document.getElementById('reg-telefono')?.value.trim() || '';
  const rfc      = document.getElementById('reg-rfc')?.value.trim()      || '';
  const calle    = document.getElementById('reg-calle')?.value.trim()    || '';
  const num      = document.getElementById('reg-num')?.value.trim()      || '';
  const colonia  = document.getElementById('reg-colonia')?.value.trim()  || '';
  const cp       = document.getElementById('reg-cp')?.value.trim()       || '';
  const ciudad   = document.getElementById('reg-ciudad')?.value.trim()   || '';
  const estadoMx = document.getElementById('reg-estado')?.value.trim()   || '';

  const ineFile     = document.getElementById('reg-ine')?.files[0];
  const compDomFile = document.getElementById('reg-comp-dom')?.files[0];
  const fotoDomFile = document.getElementById('reg-foto-dom')?.files[0];

  const showErr = msg => { errEl.textContent = msg; errEl.classList.add('show'); };

  if (!nombre || !email || !pass || !telefono || !rfc ||
      !calle || !num || !colonia || !cp || !ciudad || !estadoMx) {
    showErr('Completa todos los campos requeridos (*).'); return;
  }
  if (pass.length < 6) { showErr('La contraseña debe tener al menos 6 caracteres.'); return; }
  if (!ineFile || !compDomFile || !fotoDomFile) {
    showErr('Adjunta todos los documentos requeridos.'); return;
  }

  let curp = '', razonSocial = '', csfFile = null, opinionFile = null, actaFile = null;
  if (_regRol === 'cliente') {
    curp = document.getElementById('reg-curp')?.value.trim() || '';
    if (!curp) { showErr('El CURP es requerido.'); return; }
  } else {
    razonSocial = document.getElementById('reg-razon-social')?.value.trim() || '';
    csfFile     = document.getElementById('reg-csf')?.files[0];
    opinionFile = document.getElementById('reg-opinion')?.files[0];
    actaFile    = document.getElementById('reg-acta')?.files[0];
    if (!razonSocial) { showErr('La razón social es requerida.'); return; }
    if (!csfFile) { showErr('La Constancia de Situación Fiscal (SAT) es requerida.'); return; }
  }

  const btn = document.querySelector('#registro-panel .btn-login');
  if (btn) { btn.disabled = true; btn.textContent = 'Enviando…'; }

  const { data, error } = await sb.auth.signUp({ email, password: pass });
  if (error || !data.user) {
    showErr(error?.message || 'Error al crear la cuenta. El correo puede ya estar registrado.');
    if (btn) { btn.disabled = false; btn.textContent = 'Enviar solicitud de registro'; }
    return;
  }

  if (!data.session) {
    document.getElementById('registro-panel').innerHTML = `
      <div class="reg-success-msg">
        <div class="reg-success-icon">📧</div>
        <div class="reg-success-title">Confirma tu correo</div>
        <div class="reg-success-desc">
          Hemos enviado un enlace a <strong>${esc(email)}</strong>.<br>
          Una vez confirmado vuelve a intentar el registro con tus documentos.
        </div>
      </div>`;
    return;
  }

  const userId = data.user.id;

  const uploadDoc = async (file, name) => {
    if (!file) return null;
    const ext  = file.name.split('.').pop().toLowerCase();
    const path = `${userId}/${name}.${ext}`;
    const { error: upErr } = await sb.storage.from('registros').upload(path, file, { upsert: true });
    return upErr ? null : path;
  };

  const [docIne, docCompDom, docFotoDom, docCsf, docOpinion, docActa] = await Promise.all([
    uploadDoc(ineFile,     'ine'),
    uploadDoc(compDomFile, 'comprobante_domicilio'),
    uploadDoc(fotoDomFile, 'foto'),
    uploadDoc(csfFile,     'constancia_fiscal'),
    uploadDoc(opinionFile, 'opinion_cumplimiento'),
    uploadDoc(actaFile,    'acta_constitutiva'),
  ]);

  await sb.from('perfiles').upsert({
    user_id:           userId,
    nombre,
    rol:               _regRol === 'cliente' ? 'cliente' : 'admin',
    aprobacion_cuenta: 'pendiente',
  });

  await sb.from('solicitudes_cuenta').insert({
    user_id:              userId,
    rol:                  _regRol,
    nombre,
    email,
    telefono,
    rfc,
    curp:                 curp        || null,
    razon_social:         razonSocial || null,
    tipo_persona:         _regRol === 'admin' ? _regTipoPersona : null,
    calle:                `${calle} ${num}`.trim(),
    colonia,
    cp,
    ciudad,
    estado_mx:            estadoMx,
    doc_id_oficial:       _regRol === 'cliente' ? docIne : null,
    doc_id_representante: _regRol === 'admin'   ? docIne : null,
    doc_comprobante_dom:  docCompDom,
    doc_foto_domicilio:   _regRol === 'cliente' ? docFotoDom : null,
    doc_fotos_oficinas:   _regRol === 'admin' && docFotoDom ? [docFotoDom] : null,
    doc_constancia_fiscal: docCsf  || null,
    doc_acta_constitutiva: docActa || null,
    estado:               'pendiente',
  });

  const { data: superadmins } = await sb.from('perfiles').select('user_id').eq('rol', 'superadmin');
  if (superadmins?.length) {
    await sb.from('notificaciones').insert(superadmins.map(s => ({
      user_id: s.user_id,
      tipo:    'nueva_cuenta_pendiente',
      titulo:  'Nueva solicitud de cuenta',
      mensaje: `${nombre} quiere registrarse como ${_regRol === 'cliente' ? 'cliente' : 'empresa'}. Revisa en "Por aprobar".`,
      leido:   false,
    })));
  }

  await sb.auth.signOut();

  document.getElementById('registro-panel').innerHTML = `
    <div class="reg-success-msg">
      <div class="reg-success-icon">✅</div>
      <div class="reg-success-title">¡Solicitud enviada!</div>
      <div class="reg-success-desc">
        Tu solicitud está siendo revisada por nuestro equipo.<br><br>
        Te contactaremos al correo <strong>${esc(email)}</strong> cuando tu cuenta sea aprobada.<br><br>
        El proceso puede tardar hasta 2 días hábiles.
      </div>
    </div>`;
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

  // Reset: dejar view-home activo (detrás del overlay) para que el próximo login la muestre de inmediato
  document.querySelectorAll('.view').forEach(el => el.classList.remove('active'));
  document.getElementById('view-home')?.classList.add('active');
  document.getElementById('home-grid').innerHTML = '';

  switchLoginTab('login');
  showLoginOverlay();
}
