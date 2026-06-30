// ── CHAT EN PLATAFORMA ─────────────────────────────────
// Mensajería 1-a-1 contextual a una reserva o solicitud

let chatState = {
  open:          false,
  reservaId:     null,
  pedidoId:      null,
  participantes: [],  // [myId, otroId]
  readonly:      false,
  subscription:  null,
};

// ─── Abrir chat desde una reservación ──────────────────
// opts: { readonly, observador, participantes }
//   - readonly:    deshabilita el envío (servicio finalizado o supervisión)
//   - observador:  el superadmin mira el hilo cliente↔empresa sin participar
//   - participantes: hilo explícito [clienteId, propietarioId] (para observador)
async function openChatReserva(reservaId, otroUserId, tituloExtra, opts = {}) {
  if (!currentUser.id) return;
  const participantes = opts.participantes
    ? [...new Set(opts.participantes.filter(Boolean))]
    : [...new Set([currentUser.id, otroUserId].filter(Boolean))];
  await _abrirChat({
    reservaId,
    pedidoId: null,
    participantes,
    titulo: `💬 ${tituloExtra || 'Reserva'}`,
    readonly:  !!opts.readonly,
    observador: !!opts.observador,
  });
}

// ─── Abrir chat desde una oferta/solicitud ──────────────
async function openChatPedido(pedidoId, otroUserId, tituloExtra) {
  if (!currentUser.id) return;
  const participantes = [...new Set([currentUser.id, otroUserId].filter(Boolean))];
  await _abrirChat({
    reservaId: null,
    pedidoId,
    participantes,
    titulo: `💬 ${tituloExtra || 'Solicitud'}`,
  });
}

// ─── Core: abre el panel y carga mensajes ───────────────
async function _abrirChat({ reservaId, pedidoId, participantes, titulo, readonly, observador }) {
  // Desuscribir canal anterior
  if (chatState.subscription) {
    chatState.subscription.unsubscribe();
    chatState.subscription = null;
  }

  chatState = { open: true, reservaId, pedidoId, participantes, readonly: !!readonly, observador: !!observador, subscription: null };

  document.getElementById('chat-titulo').textContent = titulo;
  document.getElementById('chat-panel').classList.add('open');
  _aplicarModoChat(chatState.readonly, chatState.observador);

  await _cargarMensajes();
  _suscribirChat();
}

// ─── Modo del panel: lectura/escritura ──────────────────
function _aplicarModoChat(readonly, observador) {
  const footer = document.querySelector('#chat-panel .chat-footer');
  const aviso  = document.getElementById('chat-cerrado-aviso');
  const input  = document.getElementById('chat-input');
  if (readonly) {
    if (footer) footer.style.display = 'none';
    if (aviso) {
      aviso.textContent = observador
        ? '👁 Vista de supervisión — solo lectura.'
        : '🔒 Conversación cerrada — el servicio finalizó. Queda disponible como historial.';
      aviso.style.display = 'block';
    }
  } else {
    if (footer) footer.style.display = '';
    if (aviso)  aviso.style.display = 'none';
    if (input)  input.focus();
  }
}

// ─── Cargar historial ───────────────────────────────────
async function _cargarMensajes() {
  const el = document.getElementById('chat-msgs');
  el.innerHTML = `<div class="chat-empty">Cargando…</div>`;

  let query = sb.from('mensajes')
    .select('*')
    .order('created_at', { ascending: true });

  if (chatState.reservaId) {
    query = query.eq('reserva_id', chatState.reservaId);
  } else {
    query = query.eq('pedido_id', chatState.pedidoId);
  }
  // Filtrar al hilo 1-a-1 correcto: ambos IDs deben estar en participantes
  query = query.contains('participantes', chatState.participantes);

  const { data } = await query;
  _renderMensajes(data || []);

  // Un observador (superadmin) no marca como leídos los mensajes ajenos.
  if (chatState.observador) return;

  // Marcar como leídos los del otro
  const noLeidos = (data || [])
    .filter(m => m.de_user_id !== currentUser.id && !m.leido)
    .map(m => m.id);
  if (noLeidos.length) {
    sb.from('mensajes').update({ leido: true }).in('id', noLeidos)
      .then(() => {
        actualizarBadgeChat();
        // Quitar la "nubesita" de la fila ahora que el hilo quedó leído
        if (document.getElementById('view-reservaciones')?.classList.contains('active')) renderReserv();
      });
  }
}

// ─── Renderizar burbujas ────────────────────────────────
function _renderMensajes(msgs) {
  const el = document.getElementById('chat-msgs');
  if (!msgs.length) {
    el.innerHTML = `<div class="chat-empty">No hay mensajes aún.<br>¡Escribe el primero!</div>`;
    return;
  }
  el.innerHTML = msgs.map(m => _msgHTML(m)).join('');
  el.scrollTop = el.scrollHeight;
}

function _msgHTML(m) {
  const esMio = m.de_user_id === currentUser.id;
  return `
    <div class="chat-msg ${esMio ? 'chat-msg-mio' : 'chat-msg-otro'}">
      ${!esMio ? `<div class="chat-msg-nombre">${esc(m.de_nombre)}</div>` : ''}
      <div class="chat-bubble">${esc(m.texto)}</div>
      <div class="chat-msg-time">${fmtTimeAgo(m.created_at)}</div>
    </div>`;
}

// ─── Enviar mensaje ─────────────────────────────────────
let _chatLastSend = 0;

// Candado anti-desintermediación: detecta números de teléfono para evitar que
// se cierren tratos fuera de la plataforma. Considera "teléfono" a una secuencia
// de 10+ dígitos aunque venga separada por espacios, puntos, guiones o paréntesis
// (ej: "55 1234 5678", "+52 314-123-4567"). No bloquea precios/fechas (<10 dígitos
// o separados por comas).
function _contieneTelefono(texto) {
  return /(?:\+?\d[\s.\-()]*){10,}/.test(texto);
}

async function enviarMensaje() {
  if (chatState.readonly) return; // chat cerrado o en modo supervisión

  const input = document.getElementById('chat-input');
  const texto = input.value.trim();
  if (!texto || !currentUser.id) return;

  // No permitir compartir teléfonos por el chat (se conserva el texto escrito)
  if (_contieneTelefono(texto)) {
    showToast('Por seguridad no se permiten números de teléfono en el chat. Mantén el trato dentro de PortGo.', 'error');
    return;
  }

  const ahora = Date.now();
  if (ahora - _chatLastSend < 800) return; // throttle: máximo 1 msg cada 800ms
  _chatLastSend = ahora;

  input.value = '';
  input.focus();

  const { error } = await sb.from('mensajes').insert({
    de_user_id:    currentUser.id,
    de_nombre:     currentUser.nombre || currentUser.email || 'Usuario',
    texto,
    leido:         false,
    reserva_id:    chatState.reservaId || null,
    pedido_id:     chatState.pedidoId  || null,
    participantes: chatState.participantes,
  });
  if (error) showToast('Error al enviar mensaje');
}

// ─── Suscripción realtime ───────────────────────────────
function _suscribirChat() {
  const channelId = chatState.reservaId
    ? `chat-res-${chatState.reservaId}`
    : `chat-ped-${chatState.pedidoId}-${chatState.participantes.join('-')}`;

  const filter = chatState.reservaId
    ? `reserva_id=eq.${chatState.reservaId}`
    : `pedido_id=eq.${chatState.pedidoId}`;

  chatState.subscription = sb.channel(channelId)
    .on('postgres_changes', {
      event: 'INSERT', schema: 'public', table: 'mensajes', filter,
    }, payload => {
      const m = payload.new;
      // Ignorar mensajes de otros hilos (mismo pedido, distintos participantes)
      const mine = chatState.participantes;
      const overlap = (m.participantes || []).filter(id => mine.includes(id));
      if (overlap.length < 2) return;

      const el = document.getElementById('chat-msgs');
      const empty = el.querySelector('.chat-empty');
      if (empty) empty.remove();

      el.insertAdjacentHTML('beforeend', _msgHTML(m));
      el.scrollTop = el.scrollHeight;

      // Marcar como leído si el panel está abierto y el mensaje es del otro
      // (el observador/superadmin no altera el estado de lectura del hilo ajeno)
      if (!chatState.observador && m.de_user_id !== currentUser.id) {
        sb.from('mensajes').update({ leido: true }).eq('id', m.id).then(() => {});
      }
    })
    .subscribe();
}

// ─── Cerrar panel ───────────────────────────────────────
function closeChat() {
  document.getElementById('chat-panel').classList.remove('open');
  chatState.open = false;
  if (chatState.subscription) {
    chatState.subscription.unsubscribe();
    chatState.subscription = null;
  }
}

// ─── Aviso de mensajes nuevos ──────────────────────────
// La nube/globo de mensajes del banner se eliminó: los hilos solo se abren
// desde cada reservación (botón 💬 en la fila). El aviso de mensaje nuevo
// llega por la campana de notificaciones (trigger fn_notificar_nuevo_mensaje).
// Se conserva esta función como no-op seguro porque main.js/auth.js la llaman.
async function actualizarBadgeChat() {
  const badge = document.getElementById('chat-badge');
  if (badge) badge.style.display = 'none';
}

// ─── Cerrar al hacer click fuera ───────────────────────
document.addEventListener('click', e => {
  if (!chatState.open) return;
  const panel = document.getElementById('chat-panel');
  if (panel.contains(e.target)) return;
  // No cerrar si el click vino del botón 💬 de una fila de reserva
  if (e.target.closest('.btn-chat-hilo')) return;
  closeChat();
});
