"""Draws assets/images/logo_gear.png — the outline gear that turns behind each O of the
main-menu wordmark (scripts/menu.gd). Blue line art with a white halo baked in, to match
the wordmark's own outline. Rerun after changing any number below, then update
GEAR_RING in menu.gd from the value this prints."""
import math
from PIL import Image, ImageDraw

SIZE = 1024
SS = 4               # supersampling factor for smooth lines
TEETH = 20
R_TIP = 0.94         # tooth tips, as a fraction of the half-size
R_ROOT = 0.82        # valleys between teeth
R_RING = 0.70        # the inner circle
TIP_FRAC = 0.46      # share of each tooth's pitch taken by its flat tip...
ROOT_FRAC = 0.56     # ...and by its base, so the teeth taper slightly
STROKE = 0.05        # blue line width (fraction of half-size)
HALO = 0.02          # white halo on each side of the line
BLUE = (61, 140, 224, 255)
WHITE = (255, 255, 255, 255)

big = SIZE * SS
half = big / 2.0

def pt(r, a):
    return (half + math.cos(a) * r * half, half + math.sin(a) * r * half)

outline = []
pitch = math.tau / TEETH
for i in range(TEETH):
    c = i * pitch - math.pi / 2
    outline += [pt(R_ROOT, c - pitch * ROOT_FRAC / 2), pt(R_TIP, c - pitch * TIP_FRAC / 2),
                pt(R_TIP, c + pitch * TIP_FRAC / 2), pt(R_ROOT, c + pitch * ROOT_FRAC / 2)]
outline += outline[:2]   # overlap the start so the closing corner joins cleanly

def draw(img, width, colour):
    d = ImageDraw.Draw(img)
    w = max(1, round(width * half))
    d.line(outline, fill=colour, width=w, joint="curve")
    r = R_RING * half
    d.ellipse([half - r - w / 2, half - r - w / 2, half + r + w / 2, half + r + w / 2], outline=colour, width=w)

img = Image.new("RGBA", (big, big), (255, 255, 255, 0))
draw(img, STROKE + 2 * HALO, WHITE)
draw(img, STROKE, BLUE)
img = img.resize((SIZE, SIZE), Image.LANCZOS)
out = __file__.replace("\\", "/").rsplit("/src/", 1)[0] + "/logo_gear.png"
img.save(out)
print("wrote", out)
print("GEAR_RING =", round(R_RING - STROKE / 2, 3))
