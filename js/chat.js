// ── CHAT EN PLATAFORMA ─────────────────────────────────
// Mensajería 1-a-1 contextual a una reserva o solicitud

let chatState = {
  open:          false,
  reservaId:     null,
  pedidoId:      null,
  participantes: [],  // [myId, otroId]
  subscription:  null,
};

// ─── Abrir chat desde una reservación ──────────────────
async function openChatReserva(reservaId, otroUserId, tituloExtra) {
  if (!currentUser.id) return;
  const participantes = [...new Set([currentUser.id, otroUserId].filter(Boolean))];
  await _abrirChat({
    reservaId,
    pedidoId: null,
    participantes,
    titulo: `💬 ${tituloExtra || 'Reserva'}`,
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
async function _abrirChat({ reservaId, pedidoId, participantes, titulo }) {
  // Desuscribir canal anterior
  if (chatState.subscription) {
    chatState.subscription.unsubscribe();
    chatState.subscription = null;
  }

  chatState = { open: true, reservaId, pedidoId, participantes, subscription: null };

  document.getElementById('chat-titulo').textContent = titulo;
  document.getElementById('chat-panel').classList.add('open');
  document.getElementById('chat-input').focus();

  await _cargarMensajes();
  _suscribirChat();
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

  // Marcar como leídos los del otro
  const noLeidos = (data || [])
    .filter(m => m.de_user_id !== currentUser.id && !m.leido)
    .map(m => m.id);
  if (noLeidos.length) {
    sb.from('mensajes').update({ leido: true }).in('id', noLeidos)
      .then(() => actualizarBadgeChat());
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
async function enviarMensaje() {
  const input = document.getElementById('chat-input');
  const texto = input.value.trim();
  if (!texto || !currentUser.id) return;
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
      if (m.de_user_id !== currentUser.id) {
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

// ─── Toggle desde ícono de navbar ──────────────────────
function toggleChatList() {
  // Si el panel está abierto, cerrarlo; si no, no hay lista global —
  // el chat siempre se abre desde una reserva u oferta.
  if (chatState.open) { closeChat(); return; }
  showToast('Abre un chat desde una reservación u oferta');
}

// ─── Badge global de mensajes no leídos ────────────────
async function actualizarBadgeChat() {
  if (!currentUser.id) {
    const b = document.getElementById('chat-badge');
    if (b) b.style.display = 'none';
    return;
  }

  const { count } = await sb.from('mensajes')
    .select('id', { count: 'exact', head: true })
    .eq('leido', false)
    .neq('de_user_id', currentUser.id)
    .contains('participantes', [currentUser.id]);

  const badge = document.getElementById('chat-badge');
  if (!badge) return;
  if (count > 0) {
    badge.textContent = count > 9 ? '9+' : count;
    badge.style.display = 'flex';
  } else {
    badge.style.display = 'none';
  }
}

// ─── Cerrar al hacer click fuera ───────────────────────
document.addEventListener('click', e => {
  if (!chatState.open) return;
  const panel  = document.getElementById('chat-panel');
  const btnChat = document.getElementById('btn-chat');
  if (panel.contains(e.target) || btnChat?.contains(e.target)) return;
  // Permitir clicks en botones que abren el chat
  if (e.target.closest('.btn-chat-hilo')) return;
  closeChat();
});
