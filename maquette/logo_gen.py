"""Génère le logo GSB en SVG : ellipse bleue, capybara réaliste, lettres GSB.

La fourrure est faite de poils tracés un à un, tirés au hasard (graine fixe,
le résultat est reproductible) et découpés sur la silhouette.

Usage, depuis la racine du dépôt :
    python maquette/logo_gen.py legacy/app/src/Pg/GsbFraisBundle/Resources/public/images/logo.svg
"""
import math
import random
import sys

random.seed(2013)

# Silhouette du capybara, vue de profil, tournée vers la droite.
# Croupe plus haute que le garrot, ventre qui s'affaisse entre les pattes.
CORPS = ("M126 252 C100 200 116 146 172 130 C226 116 302 128 362 141 "
         "C388 147 401 159 408 175 L420 252 C414 280 392 296 354 300 "
         "C304 307 242 307 198 301 C160 296 139 281 126 252 Z")
TETE = ("M356 152 C378 121 420 106 462 110 C498 114 522 129 532 157 "
        "C540 181 538 205 530 222 C520 241 499 250 474 250 "
        "C440 252 409 245 391 236 C373 227 364 205 360 186 Z")
PATTE_AV = "M360 270 C368 292 368 316 364 330 C378 336 400 336 406 330 C404 312 402 292 408 264 Z"
PATTE_AR = "M150 272 C140 296 150 318 144 330 C160 337 184 337 192 331 C192 314 196 296 208 280 Z"
PATTE_AV2 = "M334 272 C338 296 336 318 334 328 C344 332 360 332 364 327 C362 310 362 292 366 268 Z"
PATTE_AR2 = "M196 272 C194 296 198 318 196 328 C206 332 222 332 226 327 C226 310 228 292 234 274 Z"


def dans_silhouette(x, y):
    """Approximation de la silhouette par deux ellipses, pour placer les poils."""
    corps = ((x - 268) / 150) ** 2 + ((y - 218) / 84) ** 2 <= 1
    tete = ((x - 448) / 86) ** 2 + ((y - 180) / 68) ** 2 <= 1
    return corps or tete


def poils(n, couleur, opacite, largeur, zone_y=None):
    traits = []
    while len(traits) < n:
        x = random.uniform(110, 540)
        y = random.uniform(105, 305)
        if not dans_silhouette(x, y):
            continue
        if zone_y and not (zone_y[0] <= y <= zone_y[1]):
            continue
        # Sens du poil : vers l'arrière et un peu vers le bas, plus penché
        # sur la croupe et sur les joues.
        angle = math.radians(random.gauss(200 if x < 400 else 190, 12) + (y - 200) * 0.08)
        long = random.uniform(4, 9)
        x2 = x + long * math.cos(angle)
        y2 = y + long * math.sin(angle) * 0.6 + random.uniform(1, 3)
        cx = (x + x2) / 2 + random.uniform(-2, 2)
        cy = (y + y2) / 2 - random.uniform(0.5, 2.5)
        traits.append(f'<path d="M{x:.1f} {y:.1f} Q{cx:.1f} {cy:.1f} {x2:.1f} {y2:.1f}"/>')
    return (f'<g stroke="{couleur}" stroke-opacity="{opacite}" stroke-width="{largeur}" '
            f'stroke-linecap="round" fill="none">' + "".join(traits) + "</g>")


fourrure = "\n".join([
    poils(700, "#3B2410", 0.30, 0.8, (105, 205)),   # dos, plus sombre
    poils(900, "#4A2E15", 0.20, 0.7),               # partout
    poils(650, "#D9A66D", 0.22, 0.7, (170, 300)),   # reflets clairs des flancs
    poils(200, "#F0C58E", 0.22, 0.6, (245, 305)),   # ventre
])

moustaches = "".join(
    f'<path d="M{516 + i * 3} {196 + i * 4} q{18 + i * 4} {-4 + i * 3} {34 + i * 5} {-2 + i * 6}"/>'
    for i in range(4))

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 400" role="img" aria-labelledby="titreLogo">
<title id="titreLogo">Laboratoire Galaxy-Swiss Bourdin</title>
<defs>
  <linearGradient id="fond" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#9DB6DC"/><stop offset=".45" stop-color="#5B84BF"/><stop offset="1" stop-color="#8FAAD4"/>
  </linearGradient>
  <radialGradient id="pelage" cx="0.45" cy="0.38" r="0.7">
    <stop offset="0" stop-color="#B07A45"/><stop offset=".55" stop-color="#8A5A2E"/><stop offset="1" stop-color="#5A3719"/>
  </radialGradient>
  <radialGradient id="pelageTete" cx="0.45" cy="0.35" r="0.75">
    <stop offset="0" stop-color="#A9743F"/><stop offset=".6" stop-color="#83532A"/><stop offset="1" stop-color="#553315"/>
  </radialGradient>
  <linearGradient id="dos" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#2E1B0B" stop-opacity=".55"/><stop offset=".35" stop-color="#2E1B0B" stop-opacity="0"/>
    <stop offset=".8" stop-color="#E7B77E" stop-opacity="0"/><stop offset="1" stop-color="#E7B77E" stop-opacity=".35"/>
  </linearGradient>
  <radialGradient id="museau" cx="0.85" cy="0.5" r="0.5">
    <stop offset="0" stop-color="#3A2413" stop-opacity=".85"/><stop offset="1" stop-color="#3A2413" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="oeil" cx="0.4" cy="0.35" r="0.7">
    <stop offset="0" stop-color="#3B2A1E"/><stop offset=".7" stop-color="#120B06"/><stop offset="1" stop-color="#000"/>
  </radialGradient>
  <radialGradient id="ombreSol" cx=".5" cy=".5" r=".5">
    <stop offset="0" stop-color="#1F355C" stop-opacity=".45"/><stop offset="1" stop-color="#1F355C" stop-opacity="0"/>
  </radialGradient>
  <!-- Grain de poil : un bruit étiré dans le sens du pelage, qui assombrit par endroits,
       et un léger flou des bords pour une silhouette duveteuse. -->
  <filter id="fourrure" x="-5%" y="-5%" width="110%" height="115%">
    <feTurbulence type="fractalNoise" baseFrequency="0.06 0.7" numOctaves="3" seed="7" result="bruit"/>
    <feDisplacementMap in="SourceGraphic" in2="bruit" scale="2.5" xChannelSelector="R" yChannelSelector="G" result="bords"/>
    <feColorMatrix in="bruit" type="matrix" values="0 0 0 0 0.12  0 0 0 0 0.07  0 0 0 0 0.02  0 0 0 -1.6 0.95" result="grain"/>
    <feComposite in="grain" in2="bords" operator="in" result="grainDecoupe"/>
    <feMerge><feMergeNode in="bords"/><feMergeNode in="grainDecoupe"/></feMerge>
  </filter>
  <filter id="ombrePortee" x="-10%" y="-10%" width="130%" height="140%">
    <feGaussianBlur in="SourceAlpha" stdDeviation="3"/>
    <feOffset dx="4" dy="5"/>
    <feComponentTransfer><feFuncA type="linear" slope=".35"/></feComponentTransfer>
    <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
  </filter>
  <filter id="flou" x="-20%" y="-50%" width="140%" height="200%"><feGaussianBlur stdDeviation="4"/></filter>
  <linearGradient id="patte" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#6B4320"/><stop offset=".6" stop-color="#5A381A"/><stop offset="1" stop-color="#2E1B0C"/>
  </linearGradient>
  <linearGradient id="patteLoin" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#4A2D14"/><stop offset="1" stop-color="#22140A"/>
  </linearGradient>
  <clipPath id="silhouette"><path d="{CORPS}"/><path d="{TETE}"/></clipPath>
</defs>

<!-- ellipse de fond, comme le logo d'origine -->
<ellipse cx="300" cy="200" rx="292" ry="188" fill="#3F5F8F"/>
<ellipse cx="300" cy="196" rx="286" ry="182" fill="url(#fond)"/>
<ellipse cx="300" cy="120" rx="230" ry="80" fill="#FFFFFF" opacity=".10"/>

<!-- ombre au sol -->
<ellipse cx="300" cy="244" rx="190" ry="14" fill="url(#ombreSol)"/>

<!-- capybara : réduit et posé sur les lettres -->
<g transform="translate(22 -46) scale(.86)" filter="url(#ombrePortee)">
  <g filter="url(#fourrure)">
    <!-- pattes du côté éloigné, plus sombres -->
    <path d="{PATTE_AR2}" fill="url(#patteLoin)"/>
    <path d="{PATTE_AV2}" fill="url(#patteLoin)"/>
    <path d="{CORPS}" fill="url(#pelage)"/>
    <path d="{TETE}" fill="url(#pelageTete)"/>
    <path d="{PATTE_AR}" fill="url(#patte)"/>
    <path d="{PATTE_AV}" fill="url(#patte)"/>
  </g>
  <!-- volumes : dos plus sombre, ventre plus clair, cuisse arrière marquée -->
  <g clip-path="url(#silhouette)">
    <rect x="100" y="100" width="450" height="210" fill="url(#dos)"/>
    <ellipse cx="185" cy="232" rx="66" ry="62" fill="#3A2411" opacity=".12"/>
    <!-- lumière rasante sur le dos -->
    <path d="M150 140 C220 120 300 130 360 144" stroke="#F3CF9C" stroke-opacity=".45" stroke-width="10" fill="none" stroke-linecap="round" filter="url(#flou)"/>
    <!-- ombre sous le ventre -->
    <path d="M200 300 C250 308 300 306 350 298" stroke="#2A170A" stroke-opacity=".45" stroke-width="16" fill="none" filter="url(#flou)"/>
    <ellipse cx="505" cy="185" rx="40" ry="48" fill="url(#museau)"/>
    <path d="M392 236 C402 214 400 180 382 150" stroke="#2E1B0B" stroke-opacity=".14" stroke-width="10" fill="none"/>
    {fourrure}
  </g>
  <!-- griffes -->
  <g stroke="#1E120A" stroke-width="2" stroke-linecap="round">
    <path d="M150 331 v4 M160 332 v4 M172 332 v4 M182 331 v4"/>
    <path d="M372 330 v4 M382 331 v4 M392 331 v4 M401 330 v4"/>
  </g>
  <!-- oreille -->
  <path d="M414 122 C410 104 424 94 438 99 C448 103 448 116 440 126 C432 132 420 131 414 122 Z" fill="#5E3A1B"/>
  <path d="M420 119 C418 108 427 102 435 105 C441 108 440 116 435 121 C430 125 423 124 420 119 Z" fill="#2E1B0C"/>
  <!-- œil, avec paupière et reflet -->
  <path d="M458 146 C464 138 480 138 486 146" stroke="#2E1B0B" stroke-width="3" fill="none" stroke-linecap="round"/>
  <ellipse cx="472" cy="151" rx="9" ry="7.5" fill="url(#oeil)"/>
  <circle cx="469" cy="148" r="2.4" fill="#FFFFFF" opacity=".9"/>
  <circle cx="476" cy="154" r="1" fill="#FFFFFF" opacity=".5"/>
  <!-- narine et bouche -->
  <path d="M522 166 C528 162 534 166 533 173 C531 178 525 176 523 172" fill="#1A0F08"/>
  <path d="M531 222 C522 228 510 229 500 225" stroke="#2A180B" stroke-width="2.5" fill="none" stroke-linecap="round"/>
  <path d="M530 196 C534 206 534 214 531 222" stroke="#2A180B" stroke-opacity=".6" stroke-width="2" fill="none"/>
  <!-- moustaches -->
  <g stroke="#1E120A" stroke-opacity=".55" stroke-width="1" fill="none" stroke-linecap="round">{moustaches}</g>
</g>

<!-- lettres GSB : ombre bleue décalée, puis lettres blanches cernées -->
<g font-family="'Arial Black', 'Segoe UI Black', 'Helvetica Neue', Arial, sans-serif" font-weight="900"
   font-style="italic" font-size="150" text-anchor="middle" letter-spacing="6">
  <text x="310" y="358" fill="#34558A">GSB</text>
  <text x="300" y="348" fill="#FFFFFF" stroke="#2D4E7E" stroke-width="7" paint-order="stroke" stroke-linejoin="round">GSB</text>
</g>
</svg>
'''

sortie = sys.argv[1]
with open(sortie, "w", encoding="utf-8") as f:
    f.write(svg)
print(sortie, len(svg), "octets")
