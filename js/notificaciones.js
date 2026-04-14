// ── NOTIFICACIONES ────────────────────────────────────

let notifPanel = null;
let notifPanelOpen = false;

async function loadNotificaciones() {
  if (!currentUser.id) {
    document.getElementById('notif-badge').style.display = 'none';
    return;
  }

  const { data } = await sb.from('notificaciones')
    .select('*')
    .eq('user_id', currentUser.id)
    .order('created_at', { ascending: false })
    .limit(20);

  const notifs = data || [];
  const unread = notifs.filter(n => !n.leido).length;
  const badge  = document.getElementById('notif-badge');

  if (unread > 0) {
    badge.textContent = unread > 9 ? '9+' : unread;
    badge.style.display = 'flex';
  } else {
    badge.style.display = 'none';
  }

  // Guardar para el panel
  notifPanel = notifs;
}

function toggleNotifPanel() {
  const panel = document.getElementById('notif-panel');
  notifPanelOpen = !notifPanelOpen;
  if (notifPanelOpen) {
    renderNotifPanel();
    panel.classList.add('open');
  } else {
    panel.classList.remove('open');
  }
}

function renderNotifPanel() {
  const list = document.getElementById('notif-list');
  if (!notifPanel || !notifPanel.length) {
    list.innerHTML = `<div class="notif-empty">Sin notificaciones</div>`;
    return;
  }
  list.innerHTML = notifPanel.map(n => {
    const timeAgo = fmtTimeAgo(n.created_at);
    return `
      <div class="notif-item ${n.leido ? 'leida' : ''}" onclick="onNotifClick('${n.id}', '${n.tipo}')">
        <div class="notif-dot"></div>
        <div class="notif-content">
          <div class="notif-titulo">${esc(n.titulo)}</div>
          <div class="notif-msg">${esc(n.mensaje || '')}</div>
          <div class="notif-time">${timeAgo}</div>
        </div>
      </div>`;
  }).join('');
}

async function onNotifClick(id, tipo) {
  // Marcar como leída
  await sb.from('notificaciones').update({ leido: true }).eq('id', id);
  notifPanel = (notifPanel || []).map(n => n.id === id ? { ...n, leido: true } : n);
  loadNotificaciones();

  // Navegar a la vista correspondiente
  const tabs = document.querySelectorAll('.nav-tab');
  if (tipo === 'reserva_pendiente') {
    const tab = [...tabs].find(t => t.textContent.trim() === 'Reservaciones');
    if (tab) showView('reservaciones', tab);
  }
  toggleNotifPanel();
}

async function markAllRead() {
  if (!currentUser.id) return;
  await sb.from('notificaciones').update({ leido: true })
    .eq('user_id', currentUser.id).eq('leido', false);
  notifPanel = (notifPanel || []).map(n => ({ ...n, leido: true }));
  loadNotificaciones();
  renderNotifPanel();
}

function fmtTimeAgo(isoStr) {
  const diff = Date.now() - new Date(isoStr).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 1)  return 'Ahora';
  if (mins < 60) return `Hace ${mins} min`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24)  return `Hace ${hrs} h`;
  const days = Math.floor(hrs / 24);
  return `Hace ${days} día${days > 1 ? 's' : ''}`;
}

// Cerrar panel al click fuera
document.addEventListener('click', e => {
  if (!notifPanelOpen) return;
  const btn   = document.getElementById('btn-notif');
  const panel = document.getElementById('notif-panel');
  if (!btn.contains(e.target) && !panel.contains(e.target)) {
    panel.classList.remove('open');
    notifPanelOpen = false;
  }
});
