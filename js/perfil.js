// ── MI PERFIL (cliente) ────────────────────────────────
// Espejo de renderPerfilEmpresa()/guardarPerfilEmpresa() (js/admin.js), pero
// para el cliente, que hasta ahora no tenía dónde ver ni corregir sus datos
// fiscales después del registro — se capturaban una vez, en el alta, y
// nunca más se podían tocar desde la app. Mismos cinco campos de domicilio
// que "Perfil de empresa"; sin documentos legales (permiso SCT, seguros):
// eso es solo del transportista.

async function renderMiPerfil() {
  if (!currentUser.id) return;
  const { data: p } = await sb.from('perfiles').select('*').eq('user_id', currentUser.id).single();
  if (!p) return;
  const set = (id, val) => { const el = document.getElementById(id); if (el) el.value = val ?? ''; };
  set('mp-razon',    p.razon_social);
  set('mp-rfc',      p.rfc);
  set('mp-telefono', p.telefono);
  set('mp-calle',    p.calle);
  set('mp-colonia',  p.colonia);
  set('mp-cp',       p.cp);
  set('mp-ciudad',   p.ciudad);
  set('mp-estado',   p.estado_mx);
}

async function guardarMiPerfil() {
  const payload = {
    razon_social: document.getElementById('mp-razon').value.trim()    || null,
    rfc:          document.getElementById('mp-rfc').value.trim()      || null,
    telefono:     document.getElementById('mp-telefono').value.trim() || null,
    calle:        document.getElementById('mp-calle').value.trim()    || null,
    colonia:      document.getElementById('mp-colonia').value.trim()  || null,
    cp:           document.getElementById('mp-cp').value.trim()       || null,
    ciudad:       document.getElementById('mp-ciudad').value.trim()   || null,
    estado_mx:    document.getElementById('mp-estado').value.trim()   || null,
  };
  // No actualizarConfirmado(): esa función hace .select('id'), y perfiles no
  // tiene columna `id` (su PK es user_id) — fallaría siempre. Mismo patrón
  // simple que guardarPerfilEmpresa() en js/admin.js.
  const { error } = await sb.from('perfiles').update(payload).eq('user_id', currentUser.id);
  if (error) { showToast('Error al guardar perfil: ' + error.message, 'error'); return; }
  showToast('✓ Perfil actualizado');
}
