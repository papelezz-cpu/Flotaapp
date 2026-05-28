// ── MÓDULO VIGENCIAS ───────────────────────────────────

const DIAS_ALERTA = 30;

const _VIG_EMOJI = {
  'Camión':    '🚛',
  'Operador':  '👷',
  'Custodio':  '👮',
  'Patio':     '🏭',
  'Empresa':   '🏢',
};

async function renderVigencias() {
  const content = document.getElementById('vigencias-content');
  if (!content) return;
  content.innerHTML = '<div style="text-align:center;padding:32px;color:var(--text-muted)">Cargando…</div>';

  const esSA = currentUser.rol === 'superadmin';
  const uid  = currentUser.id;

  let camQ  = sb.from('camiones').select('id, tipo, propietario_id, propietario:perfiles(nombre), vigencia_caat, fecha_vencimiento_tc, fecha_vencimiento_seguro, fecha_vencimiento_permiso_sct, fecha_vencimiento_verificacion').in('aprobacion', ['aprobada', 'pendiente']);
  let opQ   = sb.from('operadores').select('id, nombre, primer_apellido, propietario_id, propietario:perfiles(nombre), fecha_vencimiento, fecha_examen_medico, fecha_examen_toxicologico, fecha_carta_antecedentes').in('aprobacion', ['aprobada', 'pendiente']);
  let cusQ  = sb.from('custodios').select('id, nombre, propietario_id, propietario:perfiles(nombre), fecha_vencimiento_cert, porta_arma, fecha_vencimiento_licencia_sedena').in('aprobacion', ['aprobada', 'pendiente']);
  let patQ  = sb.from('patios').select('id, nombre, propietario_id, propietario:perfiles(nombre), fecha_vencimiento_permiso').in('aprobacion', ['aprobada', 'pendiente']);
  let perfQ = sb.from('perfiles').select('user_id, nombre, fecha_vencimiento_permiso_sct, fecha_vencimiento_seguro_rc, fecha_vencimiento_seguro_carga').eq('rol', 'admin');

  if (!esSA) {
    camQ  = camQ.eq('propietario_id', uid);
    opQ   = opQ.eq('propietario_id', uid);
    cusQ  = cusQ.eq('propietario_id', uid);
    patQ  = patQ.eq('propietario_id', uid);
    perfQ = perfQ.eq('user_id', uid);
  }

  const [{ data: camiones }, { data: operadores }, { data: custodios }, { data: patios }, { data: perfiles }] =
    await Promise.all([camQ, opQ, cusQ, patQ, perfQ]);

  const hoy = new Date();
  hoy.setHours(0, 0, 0, 0);
  const items = [];

  const _add = (empId, empNombre, tipo, nombre, docLabel, fecha) => {
    if (!fecha) return;
    const d = new Date(fecha + 'T00:00:00');
    const dias = Math.ceil((d - hoy) / 86400000);
    const estado = dias < 0 ? 'vencido' : dias <= DIAS_ALERTA ? 'proximo' : 'vigente';
    if (estado === 'vigente') return;
    items.push({ empId, empNombre, tipo, nombre, docLabel, fecha, dias, estado });
  };

  (camiones || []).forEach(c => {
    const emp = c.propietario?.nombre || c.propietario_id;
    const nom = `${c.tipo} (${c.id})`;
    _add(c.propietario_id, emp, 'Camión', nom, 'Tarjeta de Circulación',  c.fecha_vencimiento_tc);
    _add(c.propietario_id, emp, 'Camión', nom, 'Seguro',                  c.fecha_vencimiento_seguro);
    _add(c.propietario_id, emp, 'Camión', nom, 'Permiso SCT',             c.fecha_vencimiento_permiso_sct);
    _add(c.propietario_id, emp, 'Camión', nom, 'CAAT',                    c.vigencia_caat);
    _add(c.propietario_id, emp, 'Camión', nom, 'Verificación vehicular',  c.fecha_vencimiento_verificacion);
  });

  (operadores || []).forEach(o => {
    const emp = o.propietario?.nombre || o.propietario_id;
    const nom = [o.nombre, o.primer_apellido].filter(Boolean).join(' ') || o.id;
    _add(o.propietario_id, emp, 'Operador', nom, 'Licencia de conducir', o.fecha_vencimiento);
    if (o.fecha_examen_medico) {
      const dEx = new Date(o.fecha_examen_medico + 'T00:00:00');
      dEx.setFullYear(dEx.getFullYear() + 1);
      _add(o.propietario_id, emp, 'Operador', nom, 'Examen médico (1 año)', dEx.toISOString().slice(0, 10));
    }
    if (o.fecha_examen_toxicologico) {
      const dTox = new Date(o.fecha_examen_toxicologico + 'T00:00:00');
      dTox.setFullYear(dTox.getFullYear() + 1);
      _add(o.propietario_id, emp, 'Operador', nom, 'Examen toxicológico (1 año)', dTox.toISOString().slice(0, 10));
    }
    if (o.fecha_carta_antecedentes) {
      const dAnt = new Date(o.fecha_carta_antecedentes + 'T00:00:00');
      dAnt.setFullYear(dAnt.getFullYear() + 1);
      _add(o.propietario_id, emp, 'Operador', nom, 'Carta de no antecedentes (1 año)', dAnt.toISOString().slice(0, 10));
    }
  });

  (custodios || []).forEach(c => {
    const emp = c.propietario?.nombre || c.propietario_id;
    _add(c.propietario_id, emp, 'Custodio', esc(c.nombre || c.id), 'Certificación', c.fecha_vencimiento_cert);
    if (c.porta_arma) {
      _add(c.propietario_id, emp, 'Custodio', esc(c.nombre || c.id), 'Licencia SEDENA (portación de arma)', c.fecha_vencimiento_licencia_sedena);
    }
  });

  (patios || []).forEach(p => {
    const emp = p.propietario?.nombre || p.propietario_id;
    _add(p.propietario_id, emp, 'Patio', esc(p.nombre || p.id), 'Permiso operativo', p.fecha_vencimiento_permiso);
  });

  (perfiles || []).forEach(p => {
    _add(p.user_id, p.nombre, 'Empresa', p.nombre, 'Permiso SCT',      p.fecha_vencimiento_permiso_sct);
    _add(p.user_id, p.nombre, 'Empresa', p.nombre, 'Seguro RC',         p.fecha_vencimiento_seguro_rc);
    _add(p.user_id, p.nombre, 'Empresa', p.nombre, 'Seguro de carga',   p.fecha_vencimiento_seguro_carga);
  });

  if (!items.length) {
    content.innerHTML = `<div class="vig-empty">✅ Todo en orden — no hay documentos vencidos ni próximos a vencer en los próximos ${DIAS_ALERTA} días.</div>`;
    return;
  }

  items.sort((a, b) => {
    if (a.estado !== b.estado) return a.estado === 'vencido' ? -1 : 1;
    return a.dias - b.dias;
  });

  let html = '';

  if (esSA) {
    const porEmpresa = {};
    items.forEach(item => {
      if (!porEmpresa[item.empId]) porEmpresa[item.empId] = { nombre: item.empNombre, items: [] };
      porEmpresa[item.empId].items.push(item);
    });

    for (const [empId, grupo] of Object.entries(porEmpresa)) {
      const nV = grupo.items.filter(i => i.estado === 'vencido').length;
      const nP = grupo.items.filter(i => i.estado === 'proximo').length;
      const uid_safe = empId.replace(/[^a-z0-9]/gi, '');
      html += `
        <div class="vig-empresa-card${nV ? ' vig-empresa-card--danger' : ''}">
          <div class="vig-empresa-header" onclick="toggleVigEmpresa('${uid_safe}')">
            <div class="vig-empresa-name">🏢 ${esc(grupo.nombre)}</div>
            <div class="vig-empresa-badges">
              ${nV ? `<span class="vig-badge vig-badge--danger">⛔ ${nV} vencido${nV>1?'s':''}</span>` : ''}
              ${nP ? `<span class="vig-badge vig-badge--warn">⚠ ${nP} próximo${nP>1?'s':''}</span>` : ''}
            </div>
            <span class="apr-emp-toggle" id="vig-tog-${uid_safe}">▼</span>
          </div>
          <div class="vig-empresa-items" id="vig-items-${uid_safe}" style="display:none">
            ${grupo.items.map(_vigItemHTML).join('')}
          </div>
        </div>`;
    }
  } else {
    const nV = items.filter(i => i.estado === 'vencido').length;
    const nP = items.filter(i => i.estado === 'proximo').length;

    if (nV) {
      html += `<div class="vig-seccion-title vig-seccion--danger">⛔ Documentos vencidos (${nV})</div>`;
      html += items.filter(i => i.estado === 'vencido').map(_vigItemHTML).join('');
    }
    if (nP) {
      html += `<div class="vig-seccion-title vig-seccion--warn" style="margin-top:20px">⚠ Próximos a vencer — menos de ${DIAS_ALERTA} días (${nP})</div>`;
      html += items.filter(i => i.estado === 'proximo').map(_vigItemHTML).join('');
    }
  }

  content.innerHTML = html;
}

function _vigItemHTML(item) {
  const isVencido = item.estado === 'vencido';
  const diasAbs   = Math.abs(item.dias);
  const diasLabel = isVencido
    ? `Venció hace ${diasAbs} día${diasAbs !== 1 ? 's' : ''}`
    : item.dias === 0 ? 'Vence hoy'
    : `Vence en ${item.dias} día${item.dias !== 1 ? 's' : ''}`;

  return `
    <div class="vig-item vig-item--${item.estado}">
      <div class="vig-item-left">
        <div class="vig-item-nombre">${_VIG_EMOJI[item.tipo] || '📄'} ${esc(item.nombre)}</div>
        <div class="vig-item-doc">${esc(item.tipo)} · ${esc(item.docLabel)}</div>
      </div>
      <div class="vig-item-right">
        <div class="vig-item-fecha">${fmtFecha(item.fecha)}</div>
        <div class="vig-item-dias vig-item-dias--${item.estado}">${diasLabel}</div>
      </div>
    </div>`;
}

function toggleVigEmpresa(uid) {
  const el  = document.getElementById(`vig-items-${uid}`);
  const tog = document.getElementById(`vig-tog-${uid}`);
  if (!el) return;
  const open = el.style.display !== 'none';
  el.style.display = open ? 'none' : '';
  if (tog) tog.textContent = open ? '▼' : '▲';
}

// Badge: cuenta empresas/recursos únicos afectados, no violaciones
async function actualizarBadgeVigencias() {
  const esSA    = currentUser?.rol === 'superadmin';
  const esAdmin = currentUser?.rol === 'admin';
  if (!esSA && !esAdmin) return;

  const hoy = new Date();
  hoy.setHours(0, 0, 0, 0);
  const limite = new Date(hoy);
  limite.setDate(limite.getDate() + DIAS_ALERTA);
  const limiStr = limite.toISOString().slice(0, 10);
  const uid = currentUser.id;

  // Cuenta IDs únicos de camiones con ALGÚN campo vencido/próximo
  const _qCamion = () => {
    let q = sb.from('camiones')
      .select('id')
      .or(`vigencia_caat.lte.${limiStr},fecha_vencimiento_tc.lte.${limiStr},fecha_vencimiento_seguro.lte.${limiStr},fecha_vencimiento_permiso_sct.lte.${limiStr}`)
      .not('id', 'is', null);
    if (!esSA) q = q.eq('propietario_id', uid);
    return q;
  };

  const _q = (tabla, campo) => {
    let q = sb.from(tabla).select('id', { count: 'exact', head: true })
      .lte(campo, limiStr).not(campo, 'is', null);
    if (!esSA && tabla !== 'perfiles') q = q.eq('propietario_id', uid);
    if (!esSA && tabla === 'perfiles')  q = q.eq('user_id', uid);
    return q;
  };

  try {
    const [{ data: camIds }, { count: cOp }, { count: cCus }, { count: cPat }] = await Promise.all([
      _qCamion(),
      _q('operadores', 'fecha_vencimiento'),
      _q('custodios',  'fecha_vencimiento_cert'),
      _q('patios',     'fecha_vencimiento_permiso'),
    ]);
    const camUniq = new Set((camIds || []).map(c => c.id)).size;
    const total   = camUniq + (cOp || 0) + (cCus || 0) + (cPat || 0);
    const badge   = document.getElementById('home-vig-badge');
    if (badge) badge.textContent = total > 0 ? total : '';
  } catch (_) {}
}

