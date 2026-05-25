#!/usr/bin/env python3
"""Generates a cute keyboard-mascot app icon for KleanKeyboard.

Renders a master PNG and a full macOS AppIcon.iconset/ (all required sizes).
On a Mac, build_app.sh turns the iconset into AppIcon.icns via `iconutil`.

Run:  python3 icon/make_icon.py
"""

import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
SS = 2          # supersample factor for smooth edges
BASE = 1024     # master logical size
S = BASE * SS

# ---- palette (soft pastels) -------------------------------------------------
GRAD_TOP = (255, 205, 221)      # pink
GRAD_BOTTOM = (184, 197, 255)   # periwinkle
BODY = (255, 253, 249)          # cream keyboard body
BODY_EDGE = (224, 220, 235)
KEY = (233, 236, 245)
KEY_EDGE = (210, 214, 228)
FACE = (60, 54, 78)             # soft near-black for eyes/mouth
BLUSH = (255, 160, 178)
SPARKLE = (255, 255, 255)
SHADOW = (90, 80, 120, 60)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return m


def sparkle(draw, cx, cy, r, fill=SPARKLE):
    w = r * 0.16
    pts = [
        (cx, cy - r), (cx + w, cy - w), (cx + r, cy), (cx + w, cy + w),
        (cx, cy + r), (cx - w, cy + w), (cx - r, cy), (cx - w, cy - w),
    ]
    draw.polygon(pts, fill=fill)


def render():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # diagonal-ish gradient background
    grad = Image.new("RGBA", (S, S))
    gp = grad.load()
    for y in range(S):
        for_row = lerp(GRAD_TOP, GRAD_BOTTOM, y / (S - 1))
        for x in range(S):
            gp[x, y] = for_row + (255,)
    # blend a touch of horizontal shift for warmth
    img.paste(grad, (0, 0))

    # clip to rounded square (macOS-style)
    mask = rounded_mask(S, int(S * 0.225))
    img.putalpha(mask)

    draw = ImageDraw.Draw(img)

    def u(v):  # scale a 1024-space value into supersampled space
        return v * SS

    # ---- soft drop shadow for the keyboard body ----
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(shadow)
    sdraw.rounded_rectangle(
        [u(205), u(330), u(820), u(770)], radius=u(70), fill=SHADOW
    )
    img.alpha_composite(shadow)

    # ---- keyboard body ----
    draw.rounded_rectangle(
        [u(195), u(305), u(829), u(745)], radius=u(70),
        fill=BODY, outline=BODY_EDGE, width=u(4)
    )

    # ---- top rows of keys ----
    key_w, key_h, gap = 78, 66, 18
    start_x = 250
    for row, ry in enumerate((345, 345 + key_h + gap)):
        cols = 6 if row == 0 else 6
        for c in range(cols):
            kx = start_x + c * (key_w + gap)
            draw.rounded_rectangle(
                [u(kx), u(ry), u(kx + key_w), u(ry + key_h)],
                radius=u(14), fill=KEY, outline=KEY_EDGE, width=u(3)
            )
    # a wide space bar
    draw.rounded_rectangle(
        [u(330), u(345 + 2 * (key_h + gap)), u(694), u(345 + 2 * (key_h + gap) + key_h)],
        radius=u(14), fill=KEY, outline=KEY_EDGE, width=u(3)
    )

    # ---- kawaii face on the lower body ----
    eye_y = 645
    for ex in (430, 594):
        draw.ellipse([u(ex - 26), u(eye_y - 34), u(ex + 26), u(eye_y + 34)], fill=FACE)
        # little highlight
        draw.ellipse([u(ex + 2), u(eye_y - 26), u(ex + 16), u(eye_y - 12)], fill=(255, 255, 255))

    # blush
    for bx in (372, 652):
        draw.ellipse([u(bx - 26), u(eye_y + 22), u(bx + 26), u(eye_y + 52)], fill=BLUSH)

    # smile (arc)
    draw.arc(
        [u(470), u(640), u(554), u(715)], start=20, end=160,
        fill=FACE, width=u(11)
    )

    # ---- sparkles for that just-cleaned shine ----
    sparkle(draw, u(250), u(235), u(58))
    sparkle(draw, u(805), u(250), u(40))
    sparkle(draw, u(840), u(560), u(30))
    sparkle(draw, u(190), u(640), u(34))

    # downscale master to logical size
    master = img.resize((BASE, BASE), Image.LANCZOS)
    return master


def main():
    master = render()
    master_path = os.path.join(HERE, "icon_master_1024.png")
    master.save(master_path)
    print("wrote", master_path)

    iconset = os.path.join(HERE, "AppIcon.iconset")
    os.makedirs(iconset, exist_ok=True)
    specs = [
        (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
    ]
    for size, name in specs:
        master.resize((size, size), Image.LANCZOS).save(os.path.join(iconset, name))
        print("wrote", os.path.join("AppIcon.iconset", name))


if __name__ == "__main__":
    main()
