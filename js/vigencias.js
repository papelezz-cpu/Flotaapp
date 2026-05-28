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
  const sinFecha = []; // recursos con fecha requerida pero no registrada

  const _add = (empId, empNombre, tipo, nombre, docLabel, fecha, requerido = false) => {
    if (!fecha) {
      if (requerido) sinFecha.push({ empId, empNombre, tipo, nombre, docLabel });
      return;
    }
    const d = new Date(fecha + 'T00:00:00');
    const dias = Math.ceil((d - hoy) / 86400000);
    const estado = dias < 0 ? 'vencido' : dias <= DIAS_ALERTA ? 'proximo' : 'vigente';
    if (estado === 'vigente') return;
    items.push({ empId, empNombre, tipo, nombre, docLabel, fecha, dias, estado });
  };

  (camiones || []).forEach(c => {
    const emp = c.propietario?.nombre || c.propietario_id;
    const nom = `${c.tipo} (${c.id})`;
    _add(c.propietario_id, emp, 'Camión', nom, 'Tarjeta de Circulación',  c.fecha_vencimiento_tc,            true);
    _add(c.propietario_id, emp, 'Camión', nom, 'Seguro',                  c.fecha_vencimiento_seguro,         true);
    _add(c.propietario_id, emp, 'Camión', nom, 'Permiso SCT',             c.fecha_vencimiento_permiso_sct,    true);
    _add(c.propietario_id, emp, 'Camión', nom, 'CAAT',                    c.vigencia_caat,                    false);
    _add(c.propietario_id, emp, 'Camión', nom, 'Verificación vehicular',  c.fecha_vencimiento_verificacion,   false);
  });

  (operadores || []).forEach(o => {
    const emp = o.propietario?.nombre || o.propietario_id;
    const nom = [o.nombre, o.primer_apellido].filter(Boolean).join(' ') || o.id;
    _add(o.propietario_id, emp, 'Operador', nom, 'Licencia de conducir', o.fecha_vencimiento, true);
    if (o.fecha_examen_medico) {
      const dEx = new Date(o.fecha_examen_medico + 'T00:00:00');
      dEx.setFullYear(dEx.getFullYear() + 1);
      _add(o.propietario_id, emp, 'Operador', nom, 'Examen médico (1 año)', dEx.toISOString().slice(0, 10));
    } else {
      sinFecha.push({ empId: o.propietario_id, empNombre: emp, tipo: 'Operador', nombre: nom, docLabel: 'Examen médico' });
    }
    if (o.fecha_examen_toxicologico) {
      const dTox = new Date(o.fecha_examen_toxicologico + 'T00:00:00');
      dTox.setFullYear(dTox.getFullYear() + 1);
      _add(o.propietario_id, emp, 'Operador', nom, 'Examen toxicológico (1 año)', dTox.toISOString().slice(0, 10));
    } else {
      sinFecha.push({ empId: o.propietario_id, empNombre: emp, tipo: 'Operador', nombre: nom, docLabel: 'Examen toxicológico' });
    }
    if (o.fecha_carta_antecedentes) {
      const dAnt = new Date(o.fecha_carta_antecedentes + 'T00:00:00');
      dAnt.setFullYear(dAnt.getFullYear() + 1);
      _add(o.propietario_id, emp, 'Operador', nom, 'Carta de no antecedentes (1 año)', dAnt.toISOString().slice(0, 10));
    } else {
      sinFecha.push({ empId: o.propietario_id, empNombre: emp, tipo: 'Operador', nombre: nom, docLabel: 'Carta de antecedentes' });
    }
  });

  (custodios || []).forEach(c => {
    const emp = c.propietario?.nombre || c.propietario_id;
    _add(c.propietario_id, emp, 'Custodio', esc(c.nombre || c.id), 'Certificación', c.fecha_vencimiento_cert, true);
    if (c.porta_arma) {
      _add(c.propietario_id, emp, 'Custodio', esc(c.nombre || c.id), 'Licencia SEDENA (portación de arma)', c.fecha_vencimiento_licencia_sedena, true);
    }
  });

  (patios || []).forEach(p => {
    const emp = p.propietario?.nombre || p.propietario_id;
    _add(p.propietario_id, emp, 'Patio', esc(p.nombre || p.id), 'Permiso operativo', p.fecha_vencimiento_permiso, true);
  });

  (perfiles || []).forEach(p => {
    _add(p.user_id, p.nombre, 'Empresa', p.nombre, 'Permiso SCT',      p.fecha_vencimiento_permiso_sct);
    _add(p.user_id, p.nombre, 'Empresa', p.nombre, 'Seguro RC',         p.fecha_vencimiento_seguro_rc);
    _add(p.user_id, p.nombre, 'Empresa', p.nombre, 'Seguro de carga',   p.fecha_vencimiento_seguro_carga);
  });

  if (!items.length && !sinFecha.length) {
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

  // ── Documentos sin fecha registrada ──────────────────
  if (sinFecha.length) {
    if (esSA) {
      const sinFechaPorEmp = {};
      sinFecha.forEach(sf => {
        if (!sinFechaPorEmp[sf.empId]) sinFechaPorEmp[sf.empId] = { nombre: sf.empNombre, items: [] };
        sinFechaPorEmp[sf.empId].items.push(sf);
      });
      html += `<div class="vig-seccion-title" style="margin-top:28px;color:var(--text-muted)">⚠ Documentos sin fecha — no pueden ser monitoreados (${sinFecha.length})</div>`;
      for (const [empId, grupo] of Object.entries(sinFechaPorEmp)) {
        const uid_safe = empId.replace(/[^a-z0-9]/gi, '');
        html += `
          <div class="vig-empresa-card" style="opacity:0.75">
            <div class="vig-empresa-header" onclick="toggleVigEmpresa('sf-${uid_safe}')">
              <div class="vig-empresa-name">🏢 ${esc(grupo.nombre)}</div>
              <div class="vig-empresa-badges"><span class="vig-badge" style="background:var(--bg-muted);color:var(--text-muted)">📋 ${grupo.items.length} sin fecha</span></div>
              <span class="apr-emp-toggle" id="vig-tog-sf-${uid_safe}">▼</span>
            </div>
            <div class="vig-empresa-items" id="vig-items-sf-${uid_safe}" style="display:none">
              ${grupo.items.map(sf => `
                <div class="vig-item" style="border-left:3px solid var(--text-muted)">
                  <div class="vig-item-left">
                    <div class="vig-item-nombre">${_VIG_EMOJI[sf.tipo] || '📄'} ${esc(sf.nombre)}</div>
                    <div class="vig-item-doc">${esc(sf.tipo)} · ${esc(sf.docLabel)}</div>
                  </div>
                  <div class="vig-item-right"><div class="vig-item-dias" style="color:var(--text-muted)">Sin fecha</div></div>
                </div>`).join('')}
            </div>
          </div>`;
      }
    } else {
      html += `<div class="vig-seccion-title" style="margin-top:${items.length ? '28px' : '0'};color:var(--text-muted)">⚠ Documentos sin fecha registrada (${sinFecha.length})</div>`;
      html += sinFecha.map(sf => `
        <div class="vig-item" style="border-left:3px solid var(--text-muted)">
          <div class="vig-item-left">
            <div class="vig-item-nombre">${_VIG_EMOJI[sf.tipo] || '📄'} ${esc(sf.nombre)}</div>
            <div class="vig-item-doc">${esc(sf.tipo)} · ${esc(sf.docLabel)}</div>
          </div>
          <div class="vig-item-right"><div class="vig-item-dias" style="color:var(--text-muted)">Sin fecha</div></div>
        </div>`).join('');
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

// Badge: cuenta recursos únicos afectados (vencidos o próximos a vencer)
async function actualizarBadgeVigencias() {
  const esSA    = currentUser?.rol === 'superadmin';
  const esAdmin = currentUser?.rol === 'admin';
  if (!esSA && !esAdmin) return;

  const hoy = new Date();
  hoy.setHours(0, 0, 0, 0);
  const limite = new Date(hoy);
  limite.setDate(limite.getDate() + DIAS_ALERTA);
  const limiStr = limite.toISOString().slice(0, 10);
  // Para docs con vigencia virtual de 1 año (examen médico, tox, antecedentes)
  // Expirado en 30 días si: exam_date + 365 <= hoy + 30 → exam_date <= hoy - 335
  const anioAtras = new Date(hoy);
  anioAtras.setDate(anioAtras.getDate() - (365 - DIAS_ALERTA));
  const anioAtrasStr = anioAtras.toISOString().slice(0, 10);
  const uid = currentUser.id;

  const _f = (q, tabla) => {
    if (esSA) return q;
    return tabla === 'perfiles' ? q.eq('user_id', uid) : q.eq('propietario_id', uid);
  };

  try {
    // Empresa query: admin ve sólo la suya; SA ve todas las empresas admin
  let empQ;
  if (esAdmin) {
    empQ = sb.from('perfiles').select('user_id', { count: 'exact', head: true })
      .eq('user_id', uid)
      .or(`fecha_vencimiento_permiso_sct.lte.${limiStr},fecha_vencimiento_seguro_rc.lte.${limiStr},fecha_vencimiento_seguro_carga.lte.${limiStr}`);
  } else if (esSA) {
    empQ = sb.from('perfiles').select('user_id', { count: 'exact', head: true })
      .eq('rol', 'admin')
      .or(`fecha_vencimiento_permiso_sct.lte.${limiStr},fecha_vencimiento_seguro_rc.lte.${limiStr},fecha_vencimiento_seguro_carga.lte.${limiStr}`);
  } else {
    empQ = Promise.resolve({ count: 0 });
  }

  const [camData, opData, cusData, { count: cPat }, empData] = await Promise.all([
      // Camiones: único por id con cualquier doc vencido/próximo (solo aprobados/pendientes)
      _f(sb.from('camiones').select('id')
        .in('aprobacion', ['aprobada', 'pendiente'])
        .or(`vigencia_caat.lte.${limiStr},fecha_vencimiento_tc.lte.${limiStr},fecha_vencimiento_seguro.lte.${limiStr},fecha_vencimiento_permiso_sct.lte.${limiStr},fecha_vencimiento_verificacion.lte.${limiStr}`)
        .not('id', 'is', null), 'camiones'),
      // Operadores: licencia, médico (1yr virtual), tox (1yr virtual), antecedentes (1yr virtual)
      _f(sb.from('operadores').select('id')
        .in('aprobacion', ['aprobada', 'pendiente'])
        .or(`fecha_vencimiento.lte.${limiStr},fecha_examen_medico.lte.${anioAtrasStr},fecha_examen_toxicologico.lte.${anioAtrasStr},fecha_carta_antecedentes.lte.${anioAtrasStr}`)
        .not('id', 'is', null), 'operadores'),
      // Custodios: único por id — certificación o licencia SEDENA
      _f(sb.from('custodios').select('id')
        .in('aprobacion', ['aprobada', 'pendiente'])
        .or(`fecha_vencimiento_cert.lte.${limiStr},fecha_vencimiento_licencia_sedena.lte.${limiStr}`)
        .not('id', 'is', null), 'custodios'),
      // Patios
      _f(sb.from('patios').select('id', { count: 'exact', head: true })
        .in('aprobacion', ['aprobada', 'pendiente'])
        .lte('fecha_vencimiento_permiso', limiStr).not('fecha_vencimiento_permiso', 'is', null), 'patios'),
      empQ,
    ]);

    const camUniq = new Set((camData.data || []).map(c => c.id)).size;
    const opUniq  = new Set((opData.data  || []).map(o => o.id)).size;
    const cusUniq = new Set((cusData.data || []).map(c => c.id)).size;
    const total   = camUniq + opUniq + cusUniq + (cPat || 0) + (empData.count || 0);

    const badge = document.getElementById('home-vig-badge');
    if (badge) badge.textContent = total > 0 ? total : '';
  } catch (_) {}
}

