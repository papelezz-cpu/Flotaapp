// ── Acumulador de hallazgos ───────────────────────────────────────────────
// Tres niveles: FALLA (error real), AVISO (funciona pero es inconsistente o
// poco práctico) y OK. INFO es contexto para leer el resto.
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { RAIZ } from './api.mjs';

const ICONO = { FALLA: '❌', AVISO: '⚠️ ', OK: '✅', INFO: 'ℹ️ ' };

export class Reporte {
  constructor(titulo) {
    this.titulo = titulo;
    this.inicio = new Date();
    this.hallazgos = [];
    this.seccionActual = 'General';
  }

  seccion(nombre) {
    this.seccionActual = nombre;
    console.log(`\n\x1b[1m── ${nombre} ${'─'.repeat(Math.max(0, 62 - nombre.length))}\x1b[0m`);
  }

  _add(nivel, mensaje, detalle) {
    const h = { nivel, seccion: this.seccionActual, mensaje, detalle: detalle ?? null };
    this.hallazgos.push(h);
    const color = nivel === 'FALLA' ? '\x1b[31m' : nivel === 'AVISO' ? '\x1b[33m' : nivel === 'OK' ? '\x1b[32m' : '\x1b[36m';
    console.log(`  ${ICONO[nivel]} ${color}${mensaje}\x1b[0m`);
    if (detalle) {
      const txt = typeof detalle === 'string' ? detalle : JSON.stringify(detalle, null, 2);
      console.log(txt.split('\n').map(l => '       ' + l).join('\n'));
    }
    return h;
  }

  ok(m, d)    { return this._add('OK', m, d); }
  aviso(m, d) { return this._add('AVISO', m, d); }
  falla(m, d) { return this._add('FALLA', m, d); }
  info(m, d)  { return this._add('INFO', m, d); }

  get conteo() {
    return this.hallazgos.reduce((a, h) => (a[h.nivel] = (a[h.nivel] || 0) + 1, a), {});
  }

  resumen() {
    const c = this.conteo;
    console.log(`\n\x1b[1m${'═'.repeat(66)}\x1b[0m`);
    console.log(`\x1b[1mRESUMEN\x1b[0m  ❌ ${c.FALLA || 0} fallas   ⚠️  ${c.AVISO || 0} avisos   ✅ ${c.OK || 0} ok`);
    const graves = this.hallazgos.filter(h => h.nivel === 'FALLA');
    if (graves.length) {
      console.log('\n\x1b[31m\x1b[1mFallas:\x1b[0m');
      graves.forEach((h, i) => console.log(`  ${i + 1}. [${h.seccion}] ${h.mensaje}`));
    }
    console.log(`\x1b[1m${'═'.repeat(66)}\x1b[0m`);
  }

  guardar(nombreArchivo) {
    const dir = join(RAIZ, 'pruebas', 'salida');
    const c = this.conteo;
    let md = `# ${this.titulo}\n\n`;
    md += `**Corrida:** ${this.inicio.toLocaleString('es-MX')}  \n`;
    md += `**Resultado:** ${c.FALLA || 0} fallas · ${c.AVISO || 0} avisos · ${c.OK || 0} ok\n\n`;
    let sec = null;
    for (const h of this.hallazgos) {
      if (h.seccion !== sec) { sec = h.seccion; md += `\n## ${sec}\n\n`; }
      md += `- ${ICONO[h.nivel].trim()} **${h.nivel}** — ${h.mensaje}\n`;
      if (h.detalle) {
        const txt = typeof h.detalle === 'string' ? h.detalle : JSON.stringify(h.detalle, null, 2);
        md += '\n  ```\n' + txt.split('\n').map(l => '  ' + l).join('\n') + '\n  ```\n\n';
      }
    }
    writeFileSync(join(dir, nombreArchivo + '.md'), md, 'utf8');
    writeFileSync(join(dir, nombreArchivo + '.json'), JSON.stringify(this.hallazgos, null, 2), 'utf8');
    console.log(`\nReporte guardado en pruebas/salida/${nombreArchivo}.md`);
  }
}

export const hoyISO = () => new Date().toISOString().slice(0, 10);
export const diasDesde = (fecha) => Math.floor((Date.now() - new Date(fecha)) / 86400000);
