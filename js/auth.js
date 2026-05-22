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
    .maybeSingle();

  if (['pendiente','rechazada','suspendida'].includes(perfil?.aprobacion_cuenta)) {
    await sb.auth.signOut();
    showLoginOverlay();
    return;
  }

  // Fallback: sin perfil pero con solicitud pendiente/rechazada
  if (!perfil) {
    const { data: sc } = await sb.from('solicitudes_cuenta')
      .select('estado').eq('user_id', session.user.id).maybeSingle();
    if (sc?.estado === 'pendiente' || sc?.estado === 'rechazada') {
      await sb.auth.signOut();
      showLoginOverlay();
      return;
    }
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
    .maybeSingle();

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
  if (perfil?.aprobacion_cuenta === 'suspendida') {
    await sb.auth.signOut();
    err.textContent = `Tu cuenta ha sido suspendida. Contacta a soporte: ${SOPORTE_EMAIL}`;
    err.classList.add('show'); return;
  }

  // Fallback: si no hay perfil, revisar si hay solicitud pendiente/rechazada en solicitudes_cuenta
  if (!perfil) {
    const { data: sc } = await sb.from('solicitudes_cuenta')
      .select('estado, nota_rechazo')
      .eq('user_id', data.user.id)
      .maybeSingle();
    if (sc?.estado === 'pendiente') {
      await sb.auth.signOut();
      err.textContent = 'Tu cuenta está pendiente de aprobación. Te contactaremos cuando sea revisada.';
      err.classList.add('show'); return;
    }
    if (sc?.estado === 'rechazada') {
      await sb.auth.signOut();
      err.textContent = `Tu solicitud fue rechazada.${sc.nota_rechazo ? ' Motivo: ' + sc.nota_rechazo : ''}`;
      err.classList.add('show'); return;
    }
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
  const errEl = document.getElementById('registro-error');
  if (errEl) errEl.classList.remove('show');
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

function updateRegFotosLabel() {
  const input = document.getElementById('reg-fotos-empresa');
  const nameEl = document.getElementById('reg-fotos-empresa-name');
  if (!input || !nameEl) return;
  const count = input.files?.length || 0;
  nameEl.textContent = count === 0 ? 'Seleccionar fotos…'
    : count === 1 ? input.files[0].name
    : `${count} fotos seleccionadas`;
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

      <div class="reg-section-title">Datos de la empresa</div>
      <div class="form-group">
        <label>Nombre de la empresa *</label>
        <input type="text" id="reg-nombre-empresa" placeholder="Ej. Comercializadora ACME S.A. de C.V.">
      </div>
      <div class="form-group">
        <label>RFC de la empresa *</label>
        <input type="text" id="reg-rfc" placeholder="ACM900101ABC" maxlength="13" oninput="this.value=this.value.toUpperCase()">
      </div>
      <div class="form-group">
        <label>Giro de la empresa *</label>
        <select id="reg-giro">
          <option value="">— Selecciona el giro —</option>
          <option>Importación / Exportación</option>
          <option>Manufactura e Industria</option>
          <option>Comercio y Distribución</option>
          <option>Alimentos y Bebidas</option>
          <option>Automotriz</option>
          <option>Farmacéutica</option>
          <option>Química y Petroquímica</option>
          <option>Construcción y Materiales</option>
          <option>Tecnología y Electrónica</option>
          <option>Minería y Recursos Naturales</option>
          <option>Agroindustria</option>
          <option>Logística y Almacenaje</option>
          <option>Otro</option>
        </select>
      </div>
      <div class="form-group">
        <label>Tipo de mercancía que manejan *</label>
        <input type="text" id="reg-tipo-mercancia" placeholder="Ej. Electrónicos, alimentos secos, autopartes">
      </div>
      <div class="form-group">
        <label>Certificaciones <span class="reg-optional">opcional — ISO, CTPAT, OEA, etc.</span></label>
        <input type="text" id="reg-certificaciones" placeholder="Ej. ISO 9001, CTPAT">
      </div>

      <div class="reg-section-title">Domicilio fiscal</div>
      <div class="form-group">
        <label>Calle *</label>
        <input type="text" id="reg-calle" placeholder="Av. Insurgentes">
      </div>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px">
        <div class="form-group">
          <label>Número *</label>
          <input type="text" id="reg-num" placeholder="123-A">
        </div>
        <div class="form-group">
          <label>Código postal *</label>
          <input type="text" id="reg-cp" placeholder="06600" maxlength="5">
        </div>
      </div>
      <div class="form-group">
        <label>Colonia *</label>
        <input type="text" id="reg-colonia" placeholder="Roma Norte">
      </div>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px">
        <div class="form-group">
          <label>Ciudad *</label>
          <input type="text" id="reg-ciudad" placeholder="CDMX">
        </div>
        <div class="form-group">
          <label>Estado *</label>
          <input type="text" id="reg-estado" placeholder="Ciudad de México">
        </div>
      </div>

      <div class="reg-section-title">Domicilio de oficinas</div>
      <div class="form-group">
        <label>Calle *</label>
        <input type="text" id="reg-of-calle" placeholder="Av. Reforma">
      </div>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px">
        <div class="form-group">
          <label>Número *</label>
          <input type="text" id="reg-of-num" placeholder="456">
        </div>
        <div class="form-group">
          <label>Código postal *</label>
          <input type="text" id="reg-of-cp" placeholder="06600" maxlength="5">
        </div>
      </div>
      <div class="form-group">
        <label>Colonia *</label>
        <input type="text" id="reg-of-colonia" placeholder="Juárez">
      </div>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px">
        <div class="form-group">
          <label>Ciudad *</label>
          <input type="text" id="reg-of-ciudad" placeholder="CDMX">
        </div>
        <div class="form-group">
          <label>Estado *</label>
          <input type="text" id="reg-of-estado" placeholder="Ciudad de México">
        </div>
      </div>

      <div class="reg-section-title">Datos del representante</div>
      <div class="form-group">
        <label>Nombre completo del representante *</label>
        <input type="text" id="reg-nombre" placeholder="Ej. María González López">
      </div>
      <div class="form-group">
        <label>Correo electrónico *</label>
        <input type="email" id="reg-email" placeholder="correo@empresa.com">
      </div>
      <div class="form-group">
        <label>Contraseña * <span class="reg-optional">mínimo 6 caracteres</span></label>
        <input type="password" id="reg-pass" placeholder="••••••••">
      </div>
      <div class="form-group">
        <label>Confirmar contraseña *</label>
        <input type="password" id="reg-pass-confirm" placeholder="••••••••">
      </div>
      <div class="form-group">
        <label>Teléfono *</label>
        <input type="tel" id="reg-telefono" placeholder="55 1234 5678">
      </div>
      <div class="form-group">
        <label>CURP del representante *</label>
        <input type="text" id="reg-curp" placeholder="GOML900101MDFNBR01" maxlength="18" oninput="this.value=this.value.toUpperCase()">
      </div>

      <div class="reg-section-title">Documentos de verificación</div>
      <div class="reg-docs-hint">📎 Formatos aceptados: JPG, PNG, PDF (máx. 10 MB por archivo).</div>
      <div class="form-group">
        <label>Constancia de Situación Fiscal (SAT) *</label>
        <label class="reg-file-label" for="reg-csf">
          <span id="reg-csf-name">Seleccionar archivo…</span>
          <input type="file" id="reg-csf" accept="image/*,.pdf" onchange="updateRegFileLabel('reg-csf')">
        </label>
      </div>
      <div class="form-group">
        <label>Acta constitutiva *</label>
        <label class="reg-file-label" for="reg-acta">
          <span id="reg-acta-name">Seleccionar archivo…</span>
          <input type="file" id="reg-acta" accept="image/*,.pdf" onchange="updateRegFileLabel('reg-acta')">
        </label>
      </div>
      <div class="form-group">
        <label>Opinión de cumplimiento positiva (SAT) *</label>
        <label class="reg-file-label" for="reg-opinion-sat">
          <span id="reg-opinion-sat-name">Seleccionar archivo…</span>
          <input type="file" id="reg-opinion-sat" accept="image/*,.pdf" onchange="updateRegFileLabel('reg-opinion-sat')">
        </label>
      </div>
      <div class="form-group">
        <label>Fotos reales de instalaciones / empresa * <span class="reg-optional">hasta 3 fotos</span></label>
        <label class="reg-file-label" for="reg-fotos-empresa">
          <span id="reg-fotos-empresa-name">Seleccionar fotos…</span>
          <input type="file" id="reg-fotos-empresa" accept="image/*" multiple onchange="updateRegFotosLabel()">
        </label>
      </div>
      <div class="form-group">
        <label>Identificación oficial del representante (INE / Pasaporte) *</label>
        <label class="reg-file-label" for="reg-ine">
          <span id="reg-ine-name">Seleccionar archivo…</span>
          <input type="file" id="reg-ine" accept="image/*,.pdf" onchange="updateRegFileLabel('reg-ine')">
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
      <label>Confirmar contraseña *</label>
      <input type="password" id="reg-pass-confirm" placeholder="••••••••">
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
    <div class="reg-section-title">Información operativa</div>
    <div class="form-group">
      <label>Número de operaciones mensuales <span class="reg-optional">aproximado</span></label>
      <input type="number" id="reg-num-ops" placeholder="Ej. 25" min="1" max="9999">
    </div>
    <div class="form-group">
      <label>Mercancía que importan o exportan <span class="reg-optional">opcional</span></label>
      <input type="text" id="reg-mercancia-ops" placeholder="Ej. Electrónicos, autopartes, alimentos">
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
  const compDomFile = _regRol === 'admin' ? document.getElementById('reg-comp-dom')?.files[0] : null;
  const fotoDomFile = _regRol === 'admin' ? document.getElementById('reg-foto-dom')?.files[0] : null;

  const showErr = msg => { errEl.textContent = msg; errEl.classList.add('show'); };

  if (!nombre || !email || !pass || !telefono || !rfc ||
      !calle || !num || !colonia || !cp || !ciudad || !estadoMx) {
    showErr('Completa todos los campos requeridos (*).'); return;
  }
  const passConfirm = document.getElementById('reg-pass-confirm')?.value || '';
  if (pass.length < 6) { showErr('La contraseña debe tener al menos 6 caracteres.'); return; }
  if (pass !== passConfirm) { showErr('Las contraseñas no coinciden.'); return; }
  if (_regRol === 'admin' && (!ineFile || !compDomFile || !fotoDomFile)) {
    showErr('Adjunta todos los documentos requeridos.'); return;
  }

  const MAX_SIZE = 10 * 1024 * 1024; // 10 MB
  const TIPOS_OK = ['image/jpeg','image/png','image/webp','application/pdf'];
  const validarDoc = (f, label) => {
    if (!f) return true;
    if (f.size > MAX_SIZE) { showErr(`"${label}" excede 10 MB. Usa una imagen o PDF más pequeño.`); return false; }
    if (!TIPOS_OK.includes(f.type)) { showErr(`"${label}" debe ser JPG, PNG o PDF.`); return false; }
    return true;
  };
  if (!validarDoc(ineFile, 'Identificación oficial')) return;
  if (!validarDoc(compDomFile, 'Comprobante de domicilio')) return;
  if (!validarDoc(fotoDomFile, 'Fotografía')) return;

  let curp = '', razonSocial = '', csfFile = null, opinionFile = null, actaFile = null;
  let nombreEmpresa = '', giro = '', tipoMercancia = '', certificaciones = '';
  let ofCalle = '', ofNum = '', ofColonia = '', ofCp = '', ofCiudad = '', ofEstado = '';
  let opinionSatFile = null, fotosEmpresaFiles = [];

  if (_regRol === 'cliente') {
    nombreEmpresa   = document.getElementById('reg-nombre-empresa')?.value.trim() || '';
    giro            = document.getElementById('reg-giro')?.value || '';
    tipoMercancia   = document.getElementById('reg-tipo-mercancia')?.value.trim() || '';
    certificaciones = document.getElementById('reg-certificaciones')?.value.trim() || '';
    ofCalle         = document.getElementById('reg-of-calle')?.value.trim() || '';
    ofNum           = document.getElementById('reg-of-num')?.value.trim() || '';
    ofColonia       = document.getElementById('reg-of-colonia')?.value.trim() || '';
    ofCp            = document.getElementById('reg-of-cp')?.value.trim() || '';
    ofCiudad        = document.getElementById('reg-of-ciudad')?.value.trim() || '';
    ofEstado        = document.getElementById('reg-of-estado')?.value.trim() || '';
    curp            = document.getElementById('reg-curp')?.value.trim() || '';
    csfFile         = document.getElementById('reg-csf')?.files[0];
    actaFile        = document.getElementById('reg-acta')?.files[0];
    opinionSatFile  = document.getElementById('reg-opinion-sat')?.files[0];
    fotosEmpresaFiles = Array.from(document.getElementById('reg-fotos-empresa')?.files || []).slice(0, 3);

    if (!nombreEmpresa) { showErr('El nombre de la empresa es requerido.'); return; }
    if (!giro) { showErr('Selecciona el giro de la empresa.'); return; }
    if (!tipoMercancia) { showErr('Indica el tipo de mercancía que manejan.'); return; }
    if (!ofCalle || !ofNum || !ofColonia || !ofCp || !ofCiudad || !ofEstado) {
      showErr('Completa todos los campos del domicilio de oficinas.'); return;
    }
    if (!curp) { showErr('El CURP del representante es requerido.'); return; }
    if (!ineFile) { showErr('Adjunta la identificación oficial del representante.'); return; }
    if (!csfFile) { showErr('La Constancia de Situación Fiscal es requerida.'); return; }
    if (!actaFile) { showErr('El Acta constitutiva es requerida.'); return; }
    if (!opinionSatFile) { showErr('La Opinión de cumplimiento positiva (SAT) es requerida.'); return; }
    if (!fotosEmpresaFiles.length) { showErr('Adjunta al menos una foto de las instalaciones.'); return; }
    if (!validarDoc(ineFile,         'Identificación oficial')) return;
    if (!validarDoc(csfFile,         'Constancia de Situación Fiscal')) return;
    if (!validarDoc(actaFile,        'Acta constitutiva')) return;
    if (!validarDoc(opinionSatFile,  'Opinión de cumplimiento')) return;
    for (const f of fotosEmpresaFiles) {
      if (!validarDoc(f, 'Foto de instalaciones')) return;
    }
  } else {
    razonSocial = document.getElementById('reg-razon-social')?.value.trim() || '';
    csfFile     = document.getElementById('reg-csf')?.files[0];
    opinionFile = document.getElementById('reg-opinion')?.files[0];
    actaFile    = document.getElementById('reg-acta')?.files[0];
    if (!razonSocial) { showErr('La razón social es requerida.'); return; }
    if (!csfFile) { showErr('La Constancia de Situación Fiscal (SAT) es requerida.'); return; }
  }

  const numOpsMensuales = _regRol === 'admin'
    ? (parseInt(document.getElementById('reg-num-ops')?.value) || null)
    : null;
  const mercanciaOps = _regRol === 'admin'
    ? (document.getElementById('reg-mercancia-ops')?.value.trim() || null)
    : null;

  const btn = document.querySelector('#registro-panel .btn-login');
  if (btn) { btn.disabled = true; btn.textContent = 'Enviando…'; }

  // Intentar crear usuario nuevo
  let userId = null;
  let esReregistro = false;
  const { data, error } = await sb.auth.signUp({ email, password: pass });

  if (error || !data.user) {
    // Si el correo ya existe, revisar si es una cuenta rechazada (permitir re-registro)
    const yaExiste = error?.message?.toLowerCase().includes('already registered') ||
                     error?.message?.toLowerCase().includes('already been registered');
    if (!yaExiste) {
      showErr(error?.message || 'Error al crear la cuenta.');
      if (btn) { btn.disabled = false; btn.textContent = 'Enviar solicitud de registro'; }
      return;
    }
    // Intentar login para verificar estado
    const { data: ld, error: le } = await sb.auth.signInWithPassword({ email, password: pass });
    if (le || !ld?.user) {
      showErr('El correo ya está registrado con otra contraseña. Si tu solicitud fue rechazada, usa la contraseña original para volver a solicitarla.');
      if (btn) { btn.disabled = false; btn.textContent = 'Enviar solicitud de registro'; }
      return;
    }
    const { data: sc } = await sb.from('solicitudes_cuenta')
      .select('estado').eq('user_id', ld.user.id).maybeSingle();
    if (sc?.estado !== 'rechazada') {
      await sb.auth.signOut();
      showErr(sc?.estado === 'pendiente'
        ? 'Tu solicitud ya está en revisión. Te avisaremos cuando sea aprobada.'
        : 'Ya tienes una cuenta activa. Inicia sesión directamente.');
      if (btn) { btn.disabled = false; btn.textContent = 'Enviar solicitud de registro'; }
      return;
    }
    // Cuenta rechazada → permitir re-registro con el mismo user_id
    userId = ld.user.id;
    esReregistro = true;
  } else {
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
    userId = data.user.id;
  }

  const uploadDoc = async (file, name) => {
    if (!file) return null;
    const ext  = file.name.split('.').pop().toLowerCase();
    const path = `${userId}/${name}.${ext}`;
    const { error: upErr } = await sb.storage.from('registros').upload(path, file, { upsert: true });
    return upErr ? null : path;
  };

  let docIne, docCompDom, docFotoDom, docCsf, docActa, docOpinionSat, docFotosEmpresa;
  if (_regRol === 'cliente') {
    const fotosPaths = await Promise.all(
      fotosEmpresaFiles.map((f, i) => uploadDoc(f, `foto_empresa_${i + 1}`))
    );
    [docIne, docCsf, docActa, docOpinionSat] = await Promise.all([
      uploadDoc(ineFile,        'ine'),
      uploadDoc(csfFile,        'constancia_fiscal'),
      uploadDoc(actaFile,       'acta_constitutiva'),
      uploadDoc(opinionSatFile, 'opinion_sat'),
    ]);
    docFotosEmpresa = fotosPaths.filter(Boolean);
  } else {
    [docIne, docCompDom, docFotoDom, docCsf, , docActa] = await Promise.all([
      uploadDoc(ineFile,     'ine'),
      uploadDoc(compDomFile, 'comprobante_domicilio'),
      uploadDoc(fotoDomFile, 'foto'),
      uploadDoc(csfFile,     'constancia_fiscal'),
      Promise.resolve(null),
      uploadDoc(actaFile,    'acta_constitutiva'),
    ]);
  }

  const solicitudPayload = {
    nombre,
    email,
    telefono,
    rfc,
    curp:        curp || null,
    tipo_persona: _regRol === 'admin' ? _regTipoPersona : null,
    calle:        `${calle} ${num}`.trim(),
    colonia,
    cp,
    ciudad,
    estado_mx:    estadoMx,
    estado:       'pendiente',
    ...(_regRol === 'cliente' ? {
      razon_social:          nombreEmpresa || null,
      giro_empresa:          giro          || null,
      tipo_mercancia:        tipoMercancia || null,
      certificaciones:       certificaciones || null,
      nombre_representante:  nombre,
      of_calle:              `${ofCalle} ${ofNum}`.trim() || null,
      of_colonia:            ofColonia  || null,
      of_cp:                 ofCp       || null,
      of_ciudad:             ofCiudad   || null,
      of_estado_mx:          ofEstado   || null,
      doc_id_oficial:        docIne     || null,
      doc_constancia_fiscal: docCsf     || null,
      doc_acta_constitutiva: docActa    || null,
      doc_opinion_sat:       docOpinionSat || null,
      doc_fotos_oficinas:    docFotosEmpresa?.length ? docFotosEmpresa : null,
    } : {
      razon_social:               razonSocial     || null,
      num_operaciones_mensuales:  numOpsMensuales || null,
      mercancia_operaciones:      mercanciaOps    || null,
      doc_id_representante:       docIne          || null,
      doc_comprobante_dom:        docCompDom      || null,
      doc_foto_domicilio:         docFotoDom      || null,
      doc_fotos_oficinas:         docFotoDom      ? [docFotoDom] : null,
      doc_constancia_fiscal:      docCsf          || null,
      doc_acta_constitutiva:      docActa         || null,
    }),
  };

  if (esReregistro) {
    // Actualizar registros existentes
    await Promise.all([
      sb.from('perfiles').update({ nombre, aprobacion_cuenta: 'pendiente', nota_rechazo_cuenta: null })
        .eq('user_id', userId),
      sb.from('solicitudes_cuenta').update(solicitudPayload).eq('user_id', userId),
    ]);
  } else {
    await sb.from('perfiles').upsert({
      user_id:           userId,
      nombre,
      rol:               _regRol === 'cliente' ? 'cliente' : 'admin',
      aprobacion_cuenta: 'pendiente',
    });
    await sb.from('solicitudes_cuenta').insert({ user_id: userId, rol: _regRol, ...solicitudPayload });
  }

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
  const errEl = document.getElementById('login-error');
  errEl.classList.remove('show');
  if (error) {
    errEl.textContent = 'Error al enviar el correo. Verifica tu dirección e intenta de nuevo.';
    errEl.classList.add('show'); return;
  }
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

// ── PERFIL PROPIO (desde header) ──────────────────────
function abrirMiPerfil() {
  if (!currentUser.id) return;
  const ROL_LABEL_MAP = { superadmin: '⭐ Superadmin', admin: '🏢 Empresa', cliente: '🛒 Cliente' };
  const rolLabel = ROL_LABEL_MAP[currentUser.rol] || currentUser.rol;
  const initial  = (currentUser.nombre || '?')[0].toUpperCase();
  document.getElementById('mi-perfil-body').innerHTML = `
    <div style="text-align:center;padding:8px 0 16px">
      <div style="width:60px;height:60px;border-radius:50%;background:var(--accent);color:#fff;display:flex;align-items:center;justify-content:center;font-size:1.5rem;font-weight:700;margin:0 auto 12px">${esc(initial)}</div>
      <div style="font-size:1.1rem;font-weight:700;color:var(--text)">${esc(currentUser.nombre || '—')}</div>
      <div style="font-size:0.85rem;color:var(--text-muted);margin-top:4px">${esc(currentUser.email || '')}</div>
      <span class="badge badge-avail" style="margin-top:8px;display:inline-block">${rolLabel}</span>
    </div>
    <hr style="border:none;border-top:1px solid var(--steel);margin:4px 0 16px">
    <button class="btn-add" style="width:100%;margin-bottom:10px" onclick="cerrarMiPerfil();showPasswordResetModal()">🔑 Cambiar contraseña</button>
    <button class="btn-edit" style="width:100%" onclick="cerrarMiPerfil();logout()">🚪 Cerrar sesión</button>
  `;
  document.getElementById('modal-mi-perfil').classList.add('open');
}

function cerrarMiPerfil() {
  document.getElementById('modal-mi-perfil').classList.remove('open');
}

// Detecta expiración de sesión en background (token refresh failure)
sb.auth.onAuthStateChange((event) => {
  if (event === 'SIGNED_OUT' && currentUser.id) {
    currentUser = { id: null, nombre: null, rol: null };
    document.body.classList.remove('role-admin', 'role-superadmin', 'logged-in');
    showLoginOverlay();
    showToast('Tu sesión ha expirado. Por favor inicia sesión de nuevo.', 'error');
  }
});

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
