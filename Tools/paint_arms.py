"""Paint per-Delta first-person arm textures from Boss's HudArms.

Usage: python paint_arms.py <HudArms.tga> <CloneTextures export dir> <out dir>
Only Boss (38) has first-person arms in the game. This keeps his texture and remaps the
orange trim to each commando's trim colour, measured from their body texture.
"""
import colorsys
import sys
from pathlib import Path

from PIL import Image

# Trim hue windows (degrees) for picking the measured colour out of each body texture.
TRIM_HUES = {"38": (0, 40), "07": (330, 360), "40": (70, 170), "62": (35, 60)}


def is_trim(h, s, v, lo, hi, min_s=0.3):
    deg = h * 360
    return s > min_s and v > 0.2 and lo <= deg <= hi


def mean_trim(path, lo, hi, min_s):
    im = Image.open(path).convert("RGB").resize((512, 512))
    hs, ss, vs = [], [], []
    for r, g, b in im.getdata():
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if is_trim(h, s, v, lo, hi, min_s):
            hs.append(h)
            ss.append(s)
            vs.append(v)
    return sum(hs) / len(hs), sum(ss) / len(ss), sum(vs) / len(vs)


def paint(arms, src, dst):
    lo, hi = TRIM_HUES["38"]
    out = arms.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if not is_trim(h, s, v, lo, hi):
                continue
            nh = dst[0]
            ns = min(1.0, s * dst[1] / src[1])
            nv = min(1.0, v * dst[2] / src[2])
            nr, ng, nb = colorsys.hsv_to_rgb(nh, ns, nv)
            px[x, y] = (int(nr * 255), int(ng * 255), int(nb * 255), a)
    return out


def main():
    arms_path, body_dir, out_dir = map(Path, sys.argv[1:4])
    out_dir.mkdir(parents=True, exist_ok=True)
    arms = Image.open(arms_path).convert("RGBA")
    src = mean_trim(body_dir / "CloneCommando38.tga", *TRIM_HUES["38"], 0.45)

    for delta in ("07", "40", "62"):
        # Fixer's green is muted, so accept lower saturation when measuring it.
        dst = mean_trim(body_dir / f"CloneCommando{delta}.tga", *TRIM_HUES[delta], 0.15 if delta == "40" else 0.45)
        paint(arms, src, dst).save(out_dir / f"HudArms{delta}.tga")
        print(delta, "trim hsv", tuple(round(c, 3) for c in dst))

    # Self-check: the recolour must actually change trim pixels and leave the gloves alone.
    painted = Image.open(out_dir / "HudArms07.tga").convert("RGBA")
    assert painted.getpixel((140, 330)) == arms.getpixel((140, 330)), "glove pixel changed"
    assert painted.tobytes() != arms.tobytes(), "nothing was recoloured"


if __name__ == "__main__":
    main()
