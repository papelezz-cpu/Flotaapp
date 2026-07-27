// ── VERIFICACIÓN DE USUARIOS CON FOTOS (solo superadmin) ──

let _verifUserId = null;
let _verifNombre = null;

function abrirVerificacion(userId, nombre) {
  _verifUserId = userId;
  _verifNombre = nombre;
  showView('verificacion', null);
}

async function renderVerificacion() {
  const cont = document.getElementById('verificacion-content');
  if (!cont) return;
  if (!_verifUserId) {
    cont.innerHTML = `<div class="empty-state"><div class="icon">⚠</div>Selecciona un usuario desde Usuarios.</div>`;
    return;
  }
  cont.innerHTML = `<div class="empty-state"><div class="icon">⏳</div>Cargando...</div>`;

  const { data: perfil, error } = await sb.from('perfiles')
    .select('verificado, fotos_verificacion')
    .eq('user_id', _verifUserId)
    .maybeSingle();

  if (error) {
    cont.innerHTML = `<div class="empty-state"><div class="icon">❌</div>Error al cargar el usuario.</div>`;
    return;
  }

  const fotos      = Array.isArray(perfil?.fotos_verificacion) ? perfil.fotos_verificacion : [];
  const verificado = !!perfil?.verificado;

  let fotosHtml = '<span style="font-size:0.78rem;color:var(--text-muted)">Sin fotos subidas aún</span>';
  if (fotos.length) {
    const enlaces = await Promise.all(fotos.map(p => sb.storage.from('registros').createSignedUrl(p, 3600)));
    fotosHtml = `<div style="display:flex;flex-wrap:wrap;gap:8px">` + enlaces.map((r, i) => r.data
      ? `<a href="${esc(r.data.signedUrl)}" target="_blank" class="btn-edit" style="font-size:0.75rem">🖼 Foto ${i + 1}</a>`
      : `<span style="font-size:0.75rem;color:var(--text-muted)">🖼 Foto ${i + 1} (no disponible)</span>`
    ).join('') + `</div>`;
  }

  cont.innerHTML = `
    <h3>${esc(_verifNombre)} ${verificado ? '<span style="color:var(--green,#22c55e);font-size:0.8rem;font-weight:700">✓ Verificado</span>' : ''}</h3>
    <p class="sub">Sube entre 1 y 5 fotos tomadas en persona del cliente/empresa (identificación, fachada, etc.) para confirmar la verificación.</p>

    <div class="form-group">
      <label>Fotos ya subidas</label>
      ${fotosHtml}
    </div>

    <div class="form-group">
      <label>Agregar fotos (máx. 5 en total)</label>
      <input type="file" id="verif-files" multiple accept="image/*" onchange="updateVerifFilesLabel()">
      <span id="verif-files-label" style="font-size:0.78rem;color:var(--text-muted)"></span>
    </div>

    <div style="display:flex;gap:10px;margin-top:16px">
      <button class="btn-add" onclick="confirmarVerificacion()">${verificado ? '✓ Actualizar verificación' : '✓ Confirmar verificación'}</button>
      ${verificado ? `<button class="btn-edit" style="color:var(--danger)" onclick="quitarVerificacion()">Quitar verificación</button>` : ''}
    </div>`;
}

function updateVerifFilesLabel() {
  const files = document.getElementById('verif-files')?.files || [];
  const label = document.getElementById('verif-files-label');
  if (label) label.textContent = files.length ? `${files.length} archivo(s) seleccionado(s)` : '';
}

async function confirmarVerificacion() {
  if (!_verifUserId) return;
  const files = Array.from(document.getElementById('verif-files')?.files || []);

  const { data: perfil } = await sb.from('perfiles').select('fotos_verificacion').eq('user_id', _verifUserId).maybeSingle();
  const existentes = Array.isArray(perfil?.fotos_verificacion) ? perfil.fotos_verificacion : [];

  if (!files.length && !existentes.length) {
    showToast('Sube al menos 1 foto para verificar.', 'error');
    return;
  }
  if (existentes.length + files.length > 5) {
    showToast(`Máximo 5 fotos en total. Ya hay ${existentes.length}.`, 'error');
    return;
  }

  const nuevosPaths = [];
  for (const f of files) {
    const ext  = f.name.split('.').pop();
    const path = `${currentUser.id}/verificacion/${_verifUserId}/${Date.now()}_${Math.random().toString(36).slice(2)}.${ext}`;
    const { error: upErr } = await sb.storage.from('registros').upload(path, f);
    if (upErr) { showToast('Error al subir foto: ' + upErr.message, 'error'); return; }
    nuevosPaths.push(path);
  }

  const { error } = await sb.from('perfiles').update({
    verificado: true,
    fotos_verificacion: [...existentes, ...nuevosPaths]
  }).eq('user_id', _verifUserId);

  if (error) { showToast('Error al actualizar verificación', 'error'); return; }
  showToast(`✓ ${esc(_verifNombre)} verificado`);
  showView('usuarios', null);
}

async function quitarVerificacion() {
  if (!_verifUserId) return;
  showConfirm(`¿Quitar la verificación de ${esc(_verifNombre)}?`, async () => {
    const { error } = await sb.from('perfiles').update({ verificado: false }).eq('user_id', _verifUserId);
    if (error) { showToast('Error al actualizar verificación', 'error'); return; }
    showToast(`${esc(_verifNombre)} desmarcado como verificado`);
    renderVerificacion();
  }, { danger: true, confirmLabel: 'Quitar' });
}
