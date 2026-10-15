exec(open('gen.py').read().split('# ───────── Set completo')[0])

# Tonos muestreados del archivo original, con los brillos abiertos para que
# el degradado tenga vida sin recurrir a biselado falso.
DEFS = '''  <defs>
    <linearGradient id="oro" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0"   stop-color="#F0D49B"/>
      <stop offset=".42" stop-color="#C9A571"/>
      <stop offset="1"   stop-color="#6B4F2E"/>
    </linearGradient>
    <linearGradient id="oroClaro" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0"   stop-color="#FBE9C4"/>
      <stop offset=".5"  stop-color="#D9B87E"/>
      <stop offset="1"   stop-color="#8A6D4E"/>
    </linearGradient>
    <linearGradient id="acero" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0"   stop-color="#E4E7E8"/>
      <stop offset=".5"  stop-color="#A8ACAE"/>
      <stop offset="1"   stop-color="#5E6061"/>
    </linearGradient>
  </defs>
'''
FONDO = '#0F1113'

def marca_oro(anillo=True, arcos=True):
    o=[]
    if anillo:
        o.append('<circle cx="256" cy="256" r="206" fill="none" stroke="url(#oro)" stroke-width="7"/>')
        for t in (270,0,90,180):
            x,y = P(t,206); o.append(f'<circle cx="{x}" cy="{y}" r="14" fill="url(#oroClaro)"/>')
    if arcos:
        # Un arco en acero y el otro en oro, como en la imagen original.
        o.append(arco(340, 110, 158, 28, 'url(#acero)'))
        o.append(arco(160, 290, 158, 28, 'url(#oro)'))
    for t in (270,0,90,180): o.append(f'<polygon points="{pts(espiga(t,112,29))}" fill="url(#acero)"/>')
    for t in (45,135,225):   o.append(f'<polygon points="{pts(espiga(t,68,21))}" fill="url(#oro)"/>')
    o.append(flecha('url(#oroClaro)'))
    o.append('<circle cx="256" cy="256" r="28" fill="none" stroke="url(#oroClaro)" stroke-width="18"/>')
    return '\n  '.join(o)

def svg_oro(cuerpo, fondo=None, vb='0 0 512 512'):
    r = f'  <rect width="512" height="512" rx="116" fill="{fondo}"/>\n' if fondo else ''
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb}" role="img" aria-label="PortGo">\n'
            f'  <title>PortGo</title>\n{DEFS}{r}  {cuerpo}\n</svg>\n')

open('oro-icono.svg','w').write(svg_oro(marca_oro(), FONDO))
open('oro-isotipo.svg','w').write(svg_oro(marca_oro()))
# favicon: sin anillo ni arcos, recentrado como el de teal
def rosa_oro():
    o=[]
    for t in (270,0,90,180): o.append(f'<polygon points="{pts(espiga(t,118,30))}" fill="url(#acero)"/>')
    for t in (45,135,225):   o.append(f'<polygon points="{pts(espiga(t,72,22))}" fill="url(#oro)"/>')
    o.append(flecha('url(#oroClaro)', rShaft=150, rPunta=196, sw=26, anc=36))
    o.append('<circle cx="256" cy="256" r="29" fill="none" stroke="url(#oroClaro)" stroke-width="19"/>')
    return '\n  '.join(o)
open('oro-favicon.svg','w').write(svg_oro(
    f'<g transform="translate(-22,22) scale(1.18)" transform-origin="256 256">\n  {rosa_oro()}\n  </g>', FONDO))
print('ok')
