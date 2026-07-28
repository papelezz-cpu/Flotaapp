// ── PRIVACIDAD Y DATOS PERSONALES (derechos ARCO) ──────
// Recepción y seguimiento de solicitudes de Acceso, Rectificación,
// Cancelación y Oposición. El titular envía y consulta las suyas; el
// superadmin las resuelve. Ver tabla `solicitudes_arco`.

const ARCO_TIPOS = {
  acceso:        { label: 'Acceso',        desc: 'Saber qué datos míos tienen y cómo los usan' },
  rectificacion: { label: 'Rectificación', desc: 'Corregir datos míos que están mal' },
  cancelacion:   { label: 'Cancelación',   desc: 'Que eliminen mis datos' },
  oposicion:     { label: 'Oposición',     desc: 'Que dejen de usarlos para un fin específico' },
};

const ARCO_ESTADO_BADGE = {
  pendiente:  'badge-revision',
  en_proceso: 'badge-busy',
  atendida:   'badge-avail',
  rechazada:  'badge-maint',
};
const ARCO_ESTADO_LABEL = {
  pendiente:  '⏳ Pendiente',
  en_proceso: '⚙ En proceso',
  atendida:   '✓ Atendida',
  rechazada:  '✕ Rechazada',
};

async function renderPrivacidad() {
  const cont = document.getElementById('privacidad-content');
  if (!cont) return;
  if (!currentUser.id) {
    cont.innerHTML = `<div class="empty-state"><div class="icon">🔒</div>Inicia sesión para gestionar tus datos personales.</div>`;
    return;
  }
  cont.innerHTML = `<div class="empty-state"><div class="icon">⏳</div>Cargando…</div>`;

  const esSuper = currentUser.rol === 'superadmin';

  // El superadmin ve todas; cualquier otro rol solo las suyas (además lo
  // impone RLS, esto es solo la consulta).
  let q = sb.from('solicitudes_arco').select('*').order('created_at', { ascending: false });
  if (!esSuper) q = q.eq('user_id', currentUser.id);
  const { data: solicitudes, error } = await q;

  if (error) {
    cont.innerHTML = `<div class="empty-state"><div class="icon">❌</div>Error al cargar las solicitudes.</div>`;
    return;
  }

  // Consentimientos que el usuario ha otorgado (su propio historial)
  const { data: consents } = await sb.from('consentimientos')
    .select('tipo, version, aceptado_en')
    .eq('user_id', currentUser.id)
    .order('aceptado_en', { ascending: false });

  cont.innerHTML = `
    ${_arcoDocsHTML()}
    ${esSuper ? '' : _arcoFormHTML()}
    ${_arcoListaHTML(solicitudes || [], esSuper)}
    ${esSuper ? '' : _arcoConsentimientosHTML(consents || [])}`;
}

function _arcoDocsHTML() {
  return `
    <div class="admin-card" style="margin-bottom:18px">
      <h3>📄 Documentos legales</h3>
      <p class="sub" style="margin-bottom:12px">Consulta cómo tratamos tus datos y bajo qué condiciones se usa la plataforma.</p>
      <div style="display:flex;flex-wrap:wrap;gap:8px">
        <a class="btn-edit" href="privacidad.html" target="_blank" rel="noopener">Aviso de Privacidad</a>
        <a class="btn-edit" href="terminos.html" target="_blank" rel="noopener">Términos y Condiciones</a>
      </div>
    </div>`;
}

function _arcoFormHTML() {
  const opciones = Object.entries(ARCO_TIPOS).map(([k, v]) =>
    `<option value="${k}">${v.label} — ${v.desc}</option>`).join('');
  return `
    <div class="admin-card" style="margin-bottom:18px">
      <h3>🙋 Ejercer mis derechos ARCO</h3>
      <p class="sub" style="margin-bottom:14px">
        Puedes solicitar acceder a tus datos, corregirlos, eliminarlos u oponerte a un uso concreto.
        Tu solicitud queda registrada con fecha y podrás seguir su estado aquí mismo.
      </p>
      <div class="form-group">
        <label>¿Qué necesitas?</label>
        <select id="arco-tipo">${opciones}</select>
      </div>
      <div class="form-group">
        <label>Cuéntanos con detalle</label>
        <textarea id="arco-desc" rows="4"
          placeholder="Ej. Quiero que corrijan mi teléfono, o que eliminen los documentos que subí al registrarme."></textarea>
      </div>
      <button class="btn-add" onclick="enviarSolicitudArco()">Enviar solicitud</button>
    </div>`;
}

function _arcoListaHTML(lista, esSuper) {
  const titulo = esSuper ? '📋 Solicitudes ARCO recibidas' : '🗂 Mis solicitudes';
  if (!lista.length) {
    return `
      <div class="admin-card">
        <h3>${titulo}</h3>
        <div class="empty-state"><div class="icon">📭</div>
          ${esSuper ? 'No hay solicitudes por atender.' : 'Aún no has enviado ninguna solicitud.'}</div>
      </div>`;
  }

  const filas = lista.map(s => {
    const tipo = ARCO_TIPOS[s.tipo]?.label || s.tipo;
    const acciones = esSuper && ['pendiente', 'en_proceso'].includes(s.estado)
      ? `<div style="display:flex;flex-wrap:wrap;gap:6px;margin-top:8px">
           ${s.estado === 'pendiente'
             ? `<button class="btn-edit" onclick="cambiarEstadoArco('${s.id}','en_proceso')">⚙ Marcar en proceso</button>` : ''}
           <button class="btn-edit btn-aprobar" onclick="resolverArco('${s.id}','atendida')">✓ Marcar atendida</button>
           <button class="btn-edit btn-rechazar" onclick="resolverArco('${s.id}','rechazada')">✕ Rechazar</button>
         </div>`
      : '';
    return `
      <div class="truck-list-item" style="flex-direction:column;align-items:stretch" id="arco-${s.id}">
        <div class="truck-list-item-info">
          <div class="truck-list-item-name">
            <span>${esc(tipo)}</span>
            <span class="badge ${ARCO_ESTADO_BADGE[s.estado] || 'badge-maint'}">${ARCO_ESTADO_LABEL[s.estado] || esc(s.estado)}</span>
          </div>
          <div class="truck-list-item-sub">
            ${esSuper ? `${esc(s.nombre)} · ${esc(s.email)} · ` : ''}${fmtFecha(s.created_at)}
          </div>
          <div style="font-size:0.83rem;color:var(--text-main);margin-top:6px;white-space:pre-wrap">${esc(s.descripcion)}</div>
          ${s.respuesta ? `<div class="apr-rechazo-nota" style="margin-top:8px">Respuesta: ${esc(s.respuesta)}</div>` : ''}
        </div>
        ${acciones}
      </div>`;
  }).join('');

  return `<div class="admin-card"><h3>${titulo}</h3><div class="truck-list-admin">${filas}</div></div>`;
}

function _arcoConsentimientosHTML(consents) {
  if (!consents.length) return '';
  const TIPO_LBL = {
    aviso_privacidad:         'Aviso de Privacidad',
    terminos:                 'Términos y Condiciones',
    datos_sensibles_operador: 'Declaración sobre datos de un operador',
  };
  const filas = consents.map(c => `
    <div class="truck-list-item">
      <div class="truck-list-item-info">
        <div class="truck-list-item-name"><span>${esc(TIPO_LBL[c.tipo] || c.tipo)}</span></div>
        <div class="truck-list-item-sub">Versión ${esc(c.version)} · ${fmtFecha(c.aceptado_en)}</div>
      </div>
    </div>`).join('');
  return `
    <div class="admin-card" style="margin-top:18px">
      <h3>✅ Lo que he aceptado</h3>
      <p class="sub" style="margin-bottom:12px">Registro de las aceptaciones asociadas a tu cuenta.</p>
      <div class="truck-list-admin">${filas}</div>
    </div>`;
}

async function enviarSolicitudArco() {
  const tipo = document.getElementById('arco-tipo')?.value;
  const desc = document.getElementById('arco-desc')?.value.trim();
  if (!desc) { showToast('Describe tu solicitud para poder atenderla.', 'error'); return; }
  if (desc.length < 15) { showToast('Danos un poco más de detalle (mínimo 15 caracteres).', 'error'); return; }

  const { error } = await sb.from('solicitudes_arco').insert({
    user_id:     currentUser.id,
    nombre:      currentUser.nombre || '',
    email:       currentUser.email  || '',
    tipo,
    descripcion: desc,
  });
  if (error) { showToast('Error al enviar: ' + error.message, 'error'); return; }

  // Avisar a superadmin: estas solicitudes suelen tener plazo legal de respuesta.
  const { data: supers } = await sb.from('perfiles').select('user_id').eq('rol', 'superadmin');
  if (supers?.length) {
    await sb.from('notificaciones').insert(supers.map(s => ({
      user_id: s.user_id,
      tipo:    'solicitud_arco',
      titulo:  'Nueva solicitud de derechos ARCO',
      mensaje: `${esc(currentUser.nombre || 'Un usuario')} envió una solicitud de ${ARCO_TIPOS[tipo]?.label || tipo}. Tiene plazo de respuesta.`,
      leido:   false,
    })));
  }

  showToast('✓ Solicitud enviada — te responderemos por correo');
  renderPrivacidad();
}

async function cambiarEstadoArco(id, estado) {
  const { error } = await sb.from('solicitudes_arco').update({ estado }).eq('id', id);
  if (error) { showToast('Error al actualizar: ' + error.message, 'error'); return; }
  showToast('Estado actualizado');
  renderPrivacidad();
}

function resolverArco(id, estado) {
  const esRechazo = estado === 'rechazada';
  _abrirRechazarNota(
    esRechazo ? 'Rechazar solicitud' : 'Marcar como atendida',
    esRechazo ? 'Motivo del rechazo:' : 'Respuesta al titular:',
    async (nota) => {
      const { error } = await sb.from('solicitudes_arco').update({
        estado,
        respuesta:    nota || null,
        atendida_por: currentUser.id,
        atendida_en:  new Date().toISOString(),
      }).eq('id', id);
      if (error) { showToast('Error al guardar: ' + error.message, 'error'); return; }
      showToast(esRechazo ? 'Solicitud rechazada' : '✓ Solicitud marcada como atendida');
      renderPrivacidad();
    },
    esRechazo
      ? { confirmLabel: '✕ Confirmar rechazo', danger: true }
      : { confirmLabel: '✓ Marcar atendida',   danger: false }
  );
}
