exec(open('gen.py').read().split('# ───────── Set completo')[0])

def rosa_sola(col, conFlecha, L=118, Ld=72):
    o=[]
    for t in (270,0,90,180): o.append(f'<polygon points="{pts(espiga(t,L,30))}" fill="{col}"/>')
    diag = (45,135,225) if conFlecha else (315,45,135,225)
    for t in diag: o.append(f'<polygon points="{pts(espiga(t,Ld,22))}" fill="{col}"/>')
    if conFlecha: o.append(flecha(col, rShaft=150, rPunta=196, sw=26, anc=36))
    o.append(f'<circle cx="256" cy="256" r="29" fill="none" stroke="{col}" stroke-width="19"/>')
    return '\n    '.join(o)

def tile(fondo, col, conFlecha, escala, dx, dy):
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" role="img" aria-label="PortGo">\n'
            '  <title>PortGo</title>\n'
            f'  <rect width="512" height="512" rx="116" fill="{fondo}"/>\n'
            f'  <g transform="translate({dx},{dy}) scale({escala})" transform-origin="256 256">\n    '
            + rosa_sola(col, conFlecha) + '\n  </g>\n</svg>\n')

# A: rosa con flecha corta, recentrada (bbox 144..431 x, 80..368 y -> centro 287,224)
open('ico-a.svg','w').write(tile('#0f2a26', '#2dd4bf', True,  1.18, -22, 22))
# B: rosa simétrica sin flecha
open('ico-b.svg','w').write(tile('#0f2a26', '#2dd4bf', False, 1.30, 0, 0))
# versiones claras
open('ico-a-claro.svg','w').write(tile('#0d9488', '#ffffff', True,  1.18, -22, 22))
open('ico-b-claro.svg','w').write(tile('#0d9488', '#ffffff', False, 1.30, 0, 0))
print('ok')
