// ── PREFERENCIAS DE NOTIFICACIÓN ────────────────────────
// Un interruptor por usuario (perfiles.notif_email) que apaga los correos
// frecuentes. Los transaccionales y la campana dentro de la app no se tocan:
// ver el comentario de TIPOS_SILENCIABLES en supabase/functions/enviar-notificacion.

// Qué se apaga y qué sigue llegando, según el rol. Se muestra explícito para
// que nadie apague el interruptor creyendo que dejará de recibir todo.
const PREF_CORREOS = {
  cliente: {
    silenciable: [
      'Ofertas nuevas que recibes en tus solicitudes',
    ],
    siempre: [
      'Confirmación de que tu solicitud se envió',
      'Tu reserva fue aceptada o rechazada',
      'Tu acuerdo fue aprobado',
    ],
  },
  admin: {
    silenciable: [
      'Nuevas solicitudes publicadas que coinciden con tu flota',
    ],
    siempre: [
      'Solicitudes de reserva de tus unidades',
      'Acuerdos aprobados en los que participas',
    ],
  },
  superadmin: {
    silenciable: [
      'Solicitudes nuevas por revisar',
      'Acuerdos por aprobar',
    ],
    siempre: [],
  },
};

let _prefActual = null;

async function renderPreferencias() {
  const cont = document.getElementById('pref-content');
  if (!cont || !currentUser?.id) return;
  cont.innerHTML = '<div class="empty-state"><div class="icon">⏳</div>Cargando...</div>';

  const { data: p, error } = await sb.from('perfiles')
    .select('notif_email').eq('user_id', currentUser.id).single();

  if (error) {
    console.error(error);
    cont.innerHTML = `<div class="pref-error">No se pudieron cargar tus preferencias. ${esc(error.message || '')}</div>`;
    showToast('No se pudieron cargar tus preferencias', 'error');
    return;
  }

  // Si la columna todavía no existe en la base, el select truena arriba; aquí
  // ya sabemos que existe, pero un perfil viejo podría traer null.
  _prefActual = p?.notif_email !== false;

  const cfg = PREF_CORREOS[currentUser.rol] || PREF_CORREOS.cliente;

  cont.innerHTML = `
    <div class="pref-card">
      <label class="pref-switch-row" for="pref-notif-email">
        <input type="checkbox" id="pref-notif-email" ${_prefActual ? 'checked' : ''}
               onchange="guardarPreferenciaCorreo(this.checked)">
        <span class="pref-switch-txt">
          <strong>Quiero recibir avisos por correo</strong>
          <small>Si lo apagas seguirás viendo todo en la campana 🔔 dentro de la app.</small>
        </span>
      </label>

      <div class="pref-listas">
        <div class="pref-lista">
          <div class="pref-lista-title">Esto es lo que se apaga</div>
          <ul>${cfg.silenciable.map(t => `<li>${esc(t)}</li>`).join('')}</ul>
        </div>
        ${cfg.siempre.length ? `
        <div class="pref-lista pref-lista--fija">
          <div class="pref-lista-title">Esto te llega siempre</div>
          <ul>${cfg.siempre.map(t => `<li>${esc(t)}</li>`).join('')}</ul>
          <small>Son parte del servicio, no avisos: si se apagaran, podrías
          enterarte tarde de algo que ya te comprometiste a cumplir.</small>
        </div>` : ''}
      </div>

      <div class="pref-estado" id="pref-estado">${_prefEstadoHTML(_prefActual)}</div>
    </div>`;
}

function _prefEstadoHTML(activo) {
  return activo
    ? '<span class="pref-badge pref-badge--on">✓ Avisos por correo activados</span>'
    : '<span class="pref-badge pref-badge--off">🔕 Avisos por correo apagados</span>';
}

async function guardarPreferenciaCorreo(valor) {
  const chk = document.getElementById('pref-notif-email');
  if (chk) chk.disabled = true;

  const { error } = await sb.from('perfiles')
    .update({ notif_email: !!valor }).eq('user_id', currentUser.id);

  if (chk) chk.disabled = false;

  if (error) {
    console.error(error);
    // Revertir la casilla: si no revertimos, el usuario cree que se guardó.
    if (chk) chk.checked = _prefActual;
    showToast('No se pudo guardar: ' + (error.message || ''), 'error');
    return;
  }

  _prefActual = !!valor;
  const est = document.getElementById('pref-estado');
  if (est) est.innerHTML = _prefEstadoHTML(_prefActual);
  showToast(valor ? '✓ Recibirás avisos por correo' : '✓ Avisos por correo apagados');
}
