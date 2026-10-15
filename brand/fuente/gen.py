import math
C = 256
def P(t, r):
    a = math.radians(t); return (round(C + r*math.cos(a),1), round(C + r*math.sin(a),1))
def pts(ps): return ' '.join(f'{x},{y}' for x,y in ps)
def uv(t):
    a = math.radians(t); u=(math.cos(a), math.sin(a)); return u, (-u[1], u[0])

def espiga(t, L, w):
    u,p = uv(t)
    return [(round(C+u[0]*L,1), round(C+u[1]*L,1)),
            (round(C+p[0]*w,1), round(C+p[1]*w,1)),
            (round(C-p[0]*w,1), round(C-p[1]*w,1))]

def arco(ini, fin, R, sw, col, cab=44, anc=30):
    x0,y0 = P(ini,R); x1,y1 = P(fin,R)
    a = math.radians(fin); d = (-math.sin(a), math.cos(a)); p = (-d[1], d[0])
    b = (x1 - d[0]*3, y1 - d[1]*3)
    grande = 1 if (fin-ini) % 360 > 180 else 0
    return (f'<path d="M {x0} {y0} A {R} {R} 0 {grande} 1 {x1} {y1}" fill="none" stroke="{col}" stroke-width="{sw}"/>\n  '
            f'<polygon points="{pts([(round(b[0]+d[0]*cab,1), round(b[1]+d[1]*cab,1)),(round(b[0]+p[0]*anc,1), round(b[1]+p[1]*anc,1)),(round(b[0]-p[0]*anc,1), round(b[1]-p[1]*anc,1))])}" fill="{col}"/>')

ANG_FLECHA = 315   # noreste: sale por el hueco entre los dos arcos

def flecha(col, rShaft=196, rPunta=248, sw=30, anc=42):
    u,p = uv(ANG_FLECHA)
    fin = (round(C+u[0]*rShaft,1), round(C+u[1]*rShaft,1))
    tip = (round(C+u[0]*rPunta,1), round(C+u[1]*rPunta,1))
    b1  = (round(fin[0]+p[0]*anc,1), round(fin[1]+p[1]*anc,1))
    b2  = (round(fin[0]-p[0]*anc,1), round(fin[1]-p[1]*anc,1))
    return (f'<line x1="256" y1="256" x2="{fin[0]}" y2="{fin[1]}" stroke="{col}" stroke-width="{sw}" stroke-linecap="round"/>\n  '
            f'<polygon points="{pts([tip,b1,b2])}" fill="{col}"/>')

def marca(claro, fuerte, anillo=True, arcos=True):
    o = []
    if anillo:
        o.append(f'<circle cx="256" cy="256" r="206" fill="none" stroke="{claro}" stroke-width="7"/>')
        for t in (270, 0, 90, 180):
            x,y = P(t,206); o.append(f'<circle cx="{x}" cy="{y}" r="14" fill="{claro}"/>')
    if arcos:
        # Dos arcos en ciclo horario. Los huecos quedan en 110-160 y 290-340;
        # la flecha sale justo por el segundo, a 315.
        o.append(arco(340, 110, 158, 28, claro))
        o.append(arco(160, 290, 158, 28, claro))
    # Rosa: 4 puntas cardinales largas + 3 diagonales cortas. Falta la del
    # noreste a propósito: ahí va la flecha, así no se enciman.
    for t in (270, 0, 90, 180):
        o.append(f'<polygon points="{pts(espiga(t,112,29))}" fill="{fuerte}"/>')
    for t in (45, 135, 225):
        o.append(f'<polygon points="{pts(espiga(t,68,21))}" fill="{fuerte}"/>')
    o.append(flecha(fuerte))
    o.append(f'<circle cx="256" cy="256" r="28" fill="none" stroke="{fuerte}" stroke-width="18"/>')
    return '\n  '.join(o)

def svg(cuerpo):
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" role="img" aria-label="PortGo">\n'
            f'  <title>PortGo</title>\n  {cuerpo}\n</svg>\n')

open('v2-completo.svg','w').write(svg(marca('#2dd4bf', '#0d9488')))
open('v2-simple.svg','w').write(svg(marca('#2dd4bf', '#0d9488', anillo=False, arcos=False)))
open('v2-completo-inv.svg','w').write(svg(marca('#2dd4bf', '#5eead4')))
print('generado')

# ───────── Set completo para brand/ ─────────
FUENTE = "'Space Grotesk','Segoe UI',system-ui,-apple-system,sans-serif"
NOTA = ('  <!-- Rosa de los vientos de 8 puntas dentro de dos arcos en ciclo y un\n'
        '       anillo con nodos cardinales. La punta del noreste se alarga en\n'
        '       flecha y sale por el hueco entre los arcos: es la unica que falta\n'
        '       en la rosa, para que no se encimen. Plano, en la paleta Marea. -->\n')

def texto(x,y,s,w,col,ls=0):
    return f'  <text x="{x}" y="{y}" font-family="{FUENTE}" font-size="{s}" font-weight="{w}" fill="{col}" letter-spacing="{ls}">'

def doc(vb, al, cuerpo):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb}" role="img" aria-label="{al}">\n'
            f'  <title>PortGo</title>\n{cuerpo}\n</svg>\n')

import os
os.makedirs('set', exist_ok=True)
for suf, claro, fuerte, tinta, sec in [('', '#2dd4bf', '#0d9488', '#102a26', '#4f6661'),
                                       ('-inverso', '#2dd4bf', '#5eead4', '#ffffff', '#5eead4')]:
    m = marca(claro, fuerte)
    g = '  <g transform="translate(20,34) scale(0.527)">\n    ' + m.replace('\n  ', '\n    ') + '\n  </g>\n'

    open(f'set/portgo-logo{suf}.svg','w').write(doc(
        '0 0 880 340', 'PortGo — Plataforma digital que mueve al mundo',
        NOTA + g + texto(336,160,128,700,tinta,-2) + 'PortGo</text>\n'
              + texto(340,214,30,500,sec,3.5) + 'PLATAFORMA DIGITAL</text>\n'
              + texto(340,257,30,500,sec,3.5) + 'QUE MUEVE AL MUNDO</text>'))

    open(f'set/portgo-horizontal{suf}.svg','w').write(doc(
        '0 0 830 340', 'PortGo', NOTA + g + texto(336,210,128,700,tinta,-2) + 'PortGo</text>'))

    open(f'set/portgo-isotipo{suf}.svg','w').write(doc('0 0 512 512','PortGo', NOTA + '  ' + m))
    open(f'set/portgo-isotipo-simple{suf}.svg','w').write(doc('0 0 512 512','PortGo',
        '  ' + marca(claro, fuerte, anillo=False, arcos=False)))
print('\n'.join(sorted(os.listdir('set'))))
