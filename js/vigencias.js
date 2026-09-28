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

  // H-04: las cinco tablas se siguen consultando, pero SIN columnas de fecha.
  // Siguen haciendo falta por dos motivos que `vigencias` no puede cubrir:
  //   · los nombres que pinta el panel («Torton (T-001)», el nombre del chofer,
  //     la empresa dueña) — `vigencias` solo guarda entidad_tipo + entidad_id;
  //   · el universo de entidades, que es lo que permite decir «a este camión le
  //     falta la tarjeta». Un documento que nunca se subió NO tiene fila (el
  //     CHECK de la tabla exige archivo o fecha), así que una ausencia no se
  //     puede consultar: hay que saber qué entidades existen y cuáles de sus
  //     documentos son obligatorios, y eso último no está en el catálogo.
  // `tipo_carga` viene solo para decidir si el permiso de materiales peligrosos
  // es obligatorio en esa unidad: en un camión que no mueve hazmat, no tenerlo
  // no es un hueco, y listarlo como «sin fecha» sería ruido en 10 de 13.
  let camQ  = sb.from('camiones').select('id, tipo, tipo_carga, propietario_id, propietario:perfiles(nombre)').in('aprobacion', ['aprobada', 'pendiente']);
  let opQ   = sb.from('operadores').select('id, nombre, primer_apellido, propietario_id, propietario:perfiles(nombre)').in('aprobacion', ['aprobada', 'pendiente']);
  let cusQ  = sb.from('custodios').select('id, nombre, propietario_id, propietario:perfiles(nombre), porta_arma').in('aprobacion', ['aprobada', 'pendiente']);
  let patQ  = sb.from('patios').select('id, nombre, propietario_id, propietario:perfiles(nombre)').in('aprobacion', ['aprobada', 'pendiente']);
  let perfQ = sb.from('perfiles').select('user_id, nombre').eq('rol', 'admin');

  if (!esSA) {
    camQ  = camQ.eq('propietario_id', uid);
    opQ   = opQ.eq('propietario_id', uid);
    cusQ  = cusQ.eq('propietario_id', uid);
    patQ  = patQ.eq('propietario_id', uid);
    perfQ = perfQ.eq('user_id', uid);
  }

  // Las fechas, todas de golpe. `vigencias_caducidad` trae `vence_el` ya
  // calculado con la regla del catálogo, así que aquí desaparece el «súmale un
  // año» que antes se hacía a mano para los tres exámenes. Solo `vigente`: una
  // propuesta pendiente no es un documento acreditado que vigilar.
  // La RLS de la vista es la de la tabla (security_invoker=true), así que una
  // empresa recibe lo suyo y el superadmin todo, sin filtrar aquí.
  const vigQ = sb.from('vigencias_caducidad')
    .select('entidad_tipo, entidad_id, tipo_documento, fecha_documento, vence_el')
    .eq('estado', 'vigente');
  // El catálogo, para la etiqueta: es quien sabe que un examen dura 12 meses.
  const catQ = sb.from('catalogos').select('valor, meta').eq('clave', 'vigencia_tipo');

  const [{ data: camiones }, { data: operadores }, { data: custodios }, { data: patios },
         { data: perfiles }, { data: vigs }, { data: cat }] =
    await Promise.all([camQ, opQ, cusQ, patQ, perfQ, vigQ, catQ]);

  const _mesesDe = new Map((cat || []).map(c => [c.valor, c.meta?.vigencia_meses ?? null]));
  // Sufijo de la etiqueta. Antes decía «(1 año)» fijo; ahora sale del catálogo,
  // así que subir un examen a 24 meses no deja la etiqueta mintiendo.
  const _sufijo = (tipoDoc) => {
    const m = _mesesDe.get(tipoDoc);
    if (!m) return '';
    if (m % 12 === 0) { const a = m / 12; return ` (${a} año${a !== 1 ? 's' : ''})`; }
    return ` (${m} meses)`;
  };

  const _vig = new Map();
  (vigs || []).forEach(v => _vig.set(`${v.entidad_tipo}|${v.entidad_id}|${v.tipo_documento}`, v));

  const hoy = new Date();
  hoy.setHours(0, 0, 0, 0);
  const items = [];
  const sinFecha = []; // recursos con fecha requerida pero no registrada

  // `entTipo`/`entId` localizan la fila en el espejo; `tipoDoc` es la clave del
  // catálogo. `docLabel` sigue siendo texto de interfaz y no se toca.
  const _add = (empId, empNombre, tipo, nombre, docLabel, entTipo, entId, tipoDoc, requerido = false) => {
    const fila  = _vig.get(`${entTipo}|${entId}|${tipoDoc}`);
    const fecha = fila?.vence_el || null;
    if (!fecha) {
      // Sin fila, o con fila que solo tiene archivo y ninguna fecha: en los dos
      // casos no hay nada que vigilar. Son los «14 documentos con archivo pero
      // sin vencimiento» que la Etapa 2 hizo visibles.
      if (requerido) sinFecha.push({ empId, empNombre, tipo, nombre, docLabel });
      return;
    }
    const d = new Date(fecha + 'T00:00:00');
    const dias = Math.ceil((d - hoy) / 86400000);
    const estado = dias < 0 ? 'vencido' : dias <= DIAS_ALERTA ? 'proximo' : 'vigente';
    if (estado === 'vigente') return;
    // El sufijo solo acompaña a la fila que SÍ tiene caducidad: en la lista de
    // «sin fecha» no hay periodo que anunciar, y así era antes.
    items.push({ empId, empNombre, tipo, nombre, docLabel: docLabel + _sufijo(tipoDoc), fecha, dias, estado });
  };

  (camiones || []).forEach(c => {
    const emp = c.propietario?.nombre || c.propietario_id;
    const nom = `${c.tipo} (${c.id})`;
    _add(c.propietario_id, emp, 'Camión', nom, 'Tarjeta de Circulación', 'camion', c.id, 'tarjeta_circulacion', true);
    _add(c.propietario_id, emp, 'Camión', nom, 'Seguro',                 'camion', c.id, 'seguro_unidad',       true);
    _add(c.propietario_id, emp, 'Camión', nom, 'Permiso SCT',            'camion', c.id, 'permiso_sct_unidad',  true);
    _add(c.propietario_id, emp, 'Camión', nom, 'CAAT',                   'camion', c.id, 'caat',                false);
    _add(c.propietario_id, emp, 'Camión', nom, 'Verificación vehicular', 'camion', c.id, 'verificacion',        false);
    // Desde el 2026-09-24 este permiso FRENA el trato de un pedido de carga
    // peligrosa (guard_oferta_update). Antes no lo listaba nadie: se exigía al
    // alta y después se ignoraba. Obligatorio solo en las unidades que declaran
    // mover carga peligrosa, que son las únicas donde el guard lo mira.
    const esHazmat = (c.tipo_carga || []).some(t => t === 'Peligroso' || t === 'HAZMAT');
    if (esHazmat) {
      _add(c.propietario_id, emp, 'Camión', nom, 'Permiso de materiales peligrosos', 'camion', c.id, 'permiso_peligrosa', true);
    }
  });

  (operadores || []).forEach(o => {
    const emp = o.propietario?.nombre || o.propietario_id;
    const nom = [o.nombre, o.primer_apellido].filter(Boolean).join(' ') || o.id;
    // Los tres exámenes ya no necesitan trato aparte: su caducidad la calcula
    // la vista con la regla del catálogo, no este fichero sumando un año.
    _add(o.propietario_id, emp, 'Operador', nom, 'Licencia de conducir',     'operador', o.id, 'licencia',            true);
    _add(o.propietario_id, emp, 'Operador', nom, 'Examen médico',            'operador', o.id, 'examen_medico',       true);
    _add(o.propietario_id, emp, 'Operador', nom, 'Examen toxicológico',      'operador', o.id, 'examen_toxicologico', true);
    _add(o.propietario_id, emp, 'Operador', nom, 'Carta de no antecedentes', 'operador', o.id, 'carta_antecedentes',  true);
  });

  (custodios || []).forEach(c => {
    const emp = c.propietario?.nombre || c.propietario_id;
    _add(c.propietario_id, emp, 'Custodio', esc(c.nombre || c.id), 'Certificación', 'custodio', c.id, 'certificacion', true);
    if (c.porta_arma) {
      _add(c.propietario_id, emp, 'Custodio', esc(c.nombre || c.id), 'Licencia SEDENA (portación de arma)', 'custodio', c.id, 'licencia_sedena', true);
    }
  });

  (patios || []).forEach(p => {
    const emp = p.propietario?.nombre || p.propietario_id;
    _add(p.propietario_id, emp, 'Patio', esc(p.nombre || p.id), 'Permiso operativo', 'patio', p.id, 'permiso_patio', true);
  });

  (perfiles || []).forEach(p => {
    _add(p.user_id, p.nombre, 'Empresa', p.nombre, 'Permiso SCT',     'perfil', p.user_id, 'permiso_sct');
    _add(p.user_id, p.nombre, 'Empresa', p.nombre, 'Seguro RC',       'perfil', p.user_id, 'seguro_rc');
    _add(p.user_id, p.nombre, 'Empresa', p.nombre, 'Seguro de carga', 'perfil', p.user_id, 'seguro_carga');
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
          <div class="vig-empresa-card">
            <div class="vig-empresa-header" onclick="toggleVigEmpresa('sf-${uid_safe}')">
              <div class="vig-empresa-name">🏢 ${esc(grupo.nombre)}</div>
              <div class="vig-empresa-badges"><span class="vig-badge" style="background:var(--bg-muted);color:var(--text-muted)">📋 ${grupo.items.length} sin fecha</span></div>
              <span class="apr-emp-toggle" id="vig-tog-sf-${uid_safe}">▼</span>
            </div>
            <div class="vig-empresa-items" id="vig-items-sf-${uid_safe}" style="display:none">
              ${grupo.items.map(sf => `
                <div class="vig-item vig-item--sinfecha">
                  <div class="vig-item-left">
                    <div class="vig-item-nombre">${_VIG_EMOJI[sf.tipo] || '📄'} ${esc(sf.nombre)}</div>
                    <div class="vig-item-doc">${esc(sf.tipo)} · ${esc(sf.docLabel)}</div>
                  </div>
                  <div class="vig-item-right"><div class="vig-item-dias vig-item-dias--sinfecha">Sin fecha</div></div>
                </div>`).join('')}
            </div>
          </div>`;
      }
    } else {
      html += `<div class="vig-seccion-title" style="margin-top:${items.length ? '28px' : '0'};color:var(--text-muted)">⚠ Documentos sin fecha registrada (${sinFecha.length})</div>`;
      html += sinFecha.map(sf => `
        <div class="vig-item vig-item--sinfecha">
          <div class="vig-item-left">
            <div class="vig-item-nombre">${_VIG_EMOJI[sf.tipo] || '📄'} ${esc(sf.nombre)}</div>
            <div class="vig-item-doc">${esc(sf.tipo)} · ${esc(sf.docLabel)}</div>
          </div>
          <div class="vig-item-right"><div class="vig-item-dias vig-item-dias--sinfecha">Sin fecha</div></div>
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
  const uid = currentUser.id;

  // H-04: aquí vivía la regla del catálogo copiada a mano —
  //   anioAtras = hoy - (365 - DIAS_ALERTA)
  // para simular que un examen vence al año. Con `vence_el` en la vista, el
  // filtro es uno solo y el «12 meses» lo sigue diciendo el catálogo: si un día
  // vale 24, esto no hay que tocarlo. Antes, con 365 escrito aquí, el badge
  // habría seguido contando mal sin que nada fallara.
  const _f = (q, tabla) => {
    if (esSA) return q;
    return tabla === 'perfiles' ? q.eq('user_id', uid) : q.eq('propietario_id', uid);
  };

  try {
    // Los documentos afectados, de una sola consulta. La vista ya aplica la RLS
    // por usuario, así que la empresa recibe los suyos y el superadmin todos.
    const vigQ = sb.from('vigencias_caducidad')
      .select('entidad_tipo, entidad_id')
      .eq('estado', 'vigente')
      .lte('vence_el', limiStr);

    // Y las entidades que cuentan. `vigencias` no sabe de `aprobacion`, y el
    // badge nunca ha contado los recursos rechazados: sin esta intersección,
    // los papeles de un camión rechazado empezarían a inflar el globo.
    const [{ data: vigs }, { data: cams }, { data: ops }, { data: cuss }, { data: pats }, { data: perfs }] =
      await Promise.all([
        vigQ,
        _f(sb.from('camiones').select('id').in('aprobacion', ['aprobada', 'pendiente']), 'camiones'),
        _f(sb.from('operadores').select('id').in('aprobacion', ['aprobada', 'pendiente']), 'operadores'),
        _f(sb.from('custodios').select('id').in('aprobacion', ['aprobada', 'pendiente']), 'custodios'),
        _f(sb.from('patios').select('id').in('aprobacion', ['aprobada', 'pendiente']), 'patios'),
        esAdmin || esSA
          ? _f(sb.from('perfiles').select('user_id').eq('rol', 'admin'), 'perfiles')
          : Promise.resolve({ data: [] }),
      ]);

    const vivas = {
      camion:   new Set((cams  || []).map(x => x.id)),
      operador: new Set((ops   || []).map(x => x.id)),
      custodio: new Set((cuss  || []).map(x => x.id)),
      patio:    new Set((pats  || []).map(x => x.id)),
      perfil:   new Set((perfs || []).map(x => x.user_id)),
    };

    // Se cuentan RECURSOS afectados, no documentos: un camión con tres papeles
    // vencidos es uno, como antes.
    const afectados = new Set();
    (vigs || []).forEach(v => {
      if (vivas[v.entidad_tipo]?.has(v.entidad_id)) afectados.add(`${v.entidad_tipo}|${v.entidad_id}`);
    });

    // `.hc-badge` nace con `display:none` en el CSS, así que escribir solo el
    // texto deja el número dentro y el globo invisible. Los otros cinco badges
    // de la portada sí tocan `display`; este no lo hacía desde que se creó el
    // panel, así que nunca se vio. Encontrado probando la Etapa 4 el 2026-09-23:
    // la consulta daba 3 y el elemento contenía "3".
    const badge = document.getElementById('home-vig-badge');
    if (badge) {
      badge.textContent = afectados.size > 0 ? afectados.size : '';
      badge.style.display = afectados.size > 0 ? 'inline-block' : 'none';
    }
  } catch (_) {}
}

