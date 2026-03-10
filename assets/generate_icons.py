"""
VibeScribe icon generator using Pillow only.
Produces:
  - AppIcon_new.png (1024x1024, premium gradient + microphone)
  - menubar_icon_new.png (44x44, black template silhouette)
  - menubar_icon_new@2x.png (44x44, black template silhouette)
  - menubar_icon_new_1x.png (22x22, black template silhouette)
"""

import math
from PIL import Image, ImageDraw, ImageFilter, ImageChops
import os

OUTPUT_DIR = os.path.dirname(os.path.abspath(__file__))


# ─────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────

def make_rounded_rect_mask(size, radius):
    """Return an L-channel image usable as a mask for rounded corners."""
    mask = Image.new("L", size, 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return mask


def lerp_color(c1, c2, t):
    """Linearly interpolate between two RGB tuples."""
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


def gradient_diagonal(size, stops):
    """
    Create a diagonal (top-left → bottom-right) gradient image.
    stops: list of (t, (r,g,b)) where t ∈ [0,1]
    """
    w, h = size
    img = Image.new("RGB", size)
    pixels = img.load()
    for y in range(h):
        for x in range(w):
            # Normalised position along the diagonal
            t = (x / (w - 1) + y / (h - 1)) / 2
            # Find bracket in stops
            color = stops[0][1]
            for i in range(len(stops) - 1):
                t0, c0 = stops[i]
                t1, c1 = stops[i + 1]
                if t0 <= t <= t1:
                    local_t = (t - t0) / (t1 - t0) if t1 != t0 else 0
                    color = lerp_color(c0, c1, local_t)
                    break
                color = stops[-1][1]
            pixels[x, y] = color
    return img


def radial_glow(size, center, radius, color_rgb, max_alpha=200):
    """Return an RGBA image with a soft radial glow."""
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    pixels = img.load()
    cx, cy = center
    for y in range(size[1]):
        for x in range(size[0]):
            dist = math.sqrt((x - cx) ** 2 + (y - cy) ** 2)
            if dist < radius:
                # Smooth falloff: cosine curve
                t = dist / radius
                alpha = int(max_alpha * (0.5 + 0.5 * math.cos(math.pi * t)))
                pixels[x, y] = (*color_rgb, alpha)
    return img


# ─────────────────────────────────────────────────
# APP ICON  1024 × 1024
# ─────────────────────────────────────────────────

def draw_arc_pair(draw, cx, cy, radius, thickness, alpha_factor, arc_spread_deg=50):
    """
    Draw a symmetric pair of curved arcs around center (cx,cy).
    Renders as semi-transparent white lines on an RGBA canvas.
    """
    half = arc_spread_deg / 2
    # Left arc  (pointing left)
    l_start = 180 - half
    l_end = 180 + half
    # Right arc (pointing right)
    r_start = 360 - half
    r_end = 360 + half  # same as 0 + half

    alpha = int(255 * alpha_factor)
    bbox = [cx - radius, cy - radius, cx + radius, cy + radius]

    # Pillow arc uses degrees measured clockwise from 3 o'clock
    # We want arcs opening left and right, centred on the mic
    # Left-side arcs: centred around 9 o'clock (180°)
    draw.arc(bbox, start=l_start, end=l_end, fill=(255, 255, 255, alpha), width=thickness)
    # Right-side arcs: centred around 3 o'clock (360°/0°)
    draw.arc(bbox, start=r_start - 360, end=r_end - 360, fill=(255, 255, 255, alpha), width=thickness)


def build_app_icon():
    SIZE = 1024
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    # ── 1. Background gradient ─────────────────────────────
    gradient_stops = [
        (0.0,  (26,  5,  51)),   # deep violet  #1a0533
        (0.45, (107, 33, 168)),  # electric purple #6b21a8
        (1.0,  (192, 38, 211)),  # vibrant magenta #c026d3
    ]
    bg = gradient_diagonal((SIZE, SIZE), gradient_stops)
    bg = bg.convert("RGBA")

    # Apply macOS rounded-square mask (radius ~230/1024)
    rr_mask = make_rounded_rect_mask((SIZE, SIZE), radius=230)
    bg.putalpha(rr_mask)
    img = Image.alpha_composite(img, bg)

    # ── 2. Subtle vignette/depth layer ────────────────────
    # Dark corners via radial overlay, center is brighter
    vignette = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    vdraw = ImageDraw.Draw(vignette)
    # We paint a large semi-transparent dark ellipse at edges
    for i in range(8):
        shrink = i * 40
        alpha_v = int(18 * (8 - i) / 8)
        vdraw.ellipse(
            [shrink, shrink, SIZE - shrink, SIZE - shrink],
            fill=(10, 0, 25, alpha_v),
        )
    img = Image.alpha_composite(img, vignette)

    # ── 3. Microphone body ────────────────────────────────
    # Centered at (512, 460), 120px wide, 210px tall
    cx, cy = SIZE // 2, 460
    mic_w, mic_h = 120, 210
    mic_r = mic_w // 2  # corner radius for mic capsule

    mic_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    md = ImageDraw.Draw(mic_layer)

    mic_x0 = cx - mic_w // 2
    mic_y0 = cy - mic_h // 2
    mic_x1 = cx + mic_w // 2
    mic_y1 = cy + mic_h // 2

    # Main body fill — white with slight transparency
    md.rounded_rectangle([mic_x0, mic_y0, mic_x1, mic_y1],
                         radius=mic_r, fill=(255, 255, 255, 230))

    # Inner highlight strip (left side)
    highlight_x0 = mic_x0 + 12
    highlight_y0 = mic_y0 + 20
    highlight_x1 = mic_x0 + 30
    highlight_y1 = mic_y1 - 20
    md.rounded_rectangle([highlight_x0, highlight_y0, highlight_x1, highlight_y1],
                         radius=8, fill=(255, 255, 255, 80))

    # Fine grid lines across the mic (horizontal ridges, subtle)
    for i in range(1, 8):
        line_y = mic_y0 + int(i * mic_h / 8)
        if line_y > mic_y0 + mic_r and line_y < mic_y1 - mic_r:
            md.line([(mic_x0 + 8, line_y), (mic_x1 - 8, line_y)],
                    fill=(180, 180, 220, 60), width=1)

    img = Image.alpha_composite(img, mic_layer)

    # ── 4. Soft bloom/glow behind mic ─────────────────────
    # Rendered BEFORE the mic so it glows behind + around it
    glow_layer = radial_glow(
        (SIZE, SIZE),
        center=(cx, cy),
        radius=230,
        color_rgb=(220, 180, 255),
        max_alpha=70,
    )
    # Insert glow below the mic by compositing before the mic
    # (We already composited mic, so we add a second lighter glow on top)
    glow_top = radial_glow(
        (SIZE, SIZE),
        center=(cx, cy),
        radius=130,
        color_rgb=(255, 255, 255),
        max_alpha=35,
    )
    img = Image.alpha_composite(img, glow_layer)
    img = Image.alpha_composite(img, glow_top)

    # ── 5. Stand and base ─────────────────────────────────
    stand_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sd = ImageDraw.Draw(stand_layer)

    stand_top_y = mic_y1          # bottom of mic body
    stand_bot_y = stand_top_y + 80
    base_w = 110

    # Vertical stem
    sd.rounded_rectangle(
        [cx - 3, stand_top_y, cx + 3, stand_bot_y],
        radius=3,
        fill=(255, 255, 255, 220),
    )

    # Horizontal base bar — slightly rounded
    base_x0 = cx - base_w // 2
    base_x1 = cx + base_w // 2
    base_y0 = stand_bot_y - 4
    base_y1 = stand_bot_y + 4
    sd.rounded_rectangle([base_x0, base_y0, base_x1, base_y1],
                         radius=4, fill=(255, 255, 255, 220))

    # Small feet at ends of base
    foot_h = 10
    sd.rounded_rectangle([base_x0, base_y1, base_x0 + 16, base_y1 + foot_h],
                         radius=3, fill=(255, 255, 255, 190))
    sd.rounded_rectangle([base_x1 - 16, base_y1, base_x1, base_y1 + foot_h],
                         radius=3, fill=(255, 255, 255, 190))

    img = Image.alpha_composite(img, stand_layer)

    # ── 6. Sound-wave arcs ────────────────────────────────
    arc_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ad = ImageDraw.Draw(arc_layer)

    # 3 pairs of arcs, increasing radius, decreasing opacity
    arc_params = [
        (140, 4, 0.55, 45),   # innermost
        (195, 3, 0.38, 48),
        (255, 2, 0.22, 50),   # outermost
    ]
    for radius, thickness, alpha_f, spread in arc_params:
        draw_arc_pair(ad, cx, cy, radius, thickness, alpha_f, arc_spread_deg=spread)

    # Soften arcs slightly
    arc_layer = arc_layer.filter(ImageFilter.GaussianBlur(radius=0.8))
    img = Image.alpha_composite(img, arc_layer)

    # ── 7. Subtle noise/texture overlay ──────────────────
    # A very faint noise pattern adds premium texture
    import random
    noise_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    noise_pixels = noise_layer.load()
    rng = random.Random(42)
    for y in range(0, SIZE, 2):
        for x in range(0, SIZE, 2):
            if rng.random() < 0.25:
                v = rng.randint(200, 255)
                noise_pixels[x, y] = (v, v, v, rng.randint(3, 9))
    img = Image.alpha_composite(img, noise_layer)

    # ── 8. Final rounded-square crop ─────────────────────
    final_mask = make_rounded_rect_mask((SIZE, SIZE), radius=230)
    r, g, b, a = img.split()
    # AND the alpha with the rounded mask
    new_alpha = ImageChops.multiply(a, final_mask)
    img = Image.merge("RGBA", (r, g, b, new_alpha))

    return img


# ─────────────────────────────────────────────────
# MENU BAR TEMPLATE ICON
# ─────────────────────────────────────────────────

def draw_menubar_mic(size_px):
    """
    Draw a clean black-on-transparent microphone template icon.
    size_px: final canvas size in pixels (22 or 44).
    Internally we draw at 2× for AA then resize down for the 22px version.
    """
    DRAW_SIZE = max(size_px * 2, 44)  # always draw at ≥44 for AA
    img = Image.new("RGBA", (DRAW_SIZE, DRAW_SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    cx = DRAW_SIZE // 2
    cy = DRAW_SIZE // 2

    # Scale factor relative to a 44-pixel canvas
    scale = DRAW_SIZE / 44.0

    # ── Mic body ──────────────────────────────────────────
    # At 44px: 10px wide, 17px tall, centred slightly above centre
    body_w = round(10 * scale)
    body_h = round(17 * scale)
    body_r = round(body_w / 2)
    body_cy = round(cy - 2 * scale)    # slightly above centre

    bx0 = cx - body_w // 2
    by0 = body_cy - body_h // 2
    bx1 = cx + body_w // 2
    by1 = body_cy + body_h // 2

    d.rounded_rectangle([bx0, by0, bx1, by1], radius=body_r,
                        fill=(0, 0, 0, 255))

    # ── Neck arc / collar ─────────────────────────────────
    # A C-shaped collar arc around the bottom half of the mic body
    collar_r = round(13 * scale)
    collar_cx = cx
    collar_cy = by1  # start at bottom of mic body

    # We approximate the collar as a thick arc (210° wide, opening upward)
    collar_bbox = [
        collar_cx - collar_r,
        collar_cy - collar_r,
        collar_cx + collar_r,
        collar_cy + collar_r,
    ]
    collar_thick = max(round(2.2 * scale), 2)
    # Arc from ~210° to ~330° (bottom opening, going around the mic)
    d.arc(collar_bbox, start=210, end=330, fill=(0, 0, 0, 255), width=collar_thick)

    # ── Stem (vertical line below collar) ─────────────────
    stem_top_y = collar_cy + collar_r - collar_thick  # approximately where arc ends
    stem_bot_y = collar_cy + collar_r + round(4 * scale)
    stem_w = max(round(2.2 * scale), 2)
    d.rounded_rectangle(
        [cx - stem_w // 2, stem_top_y,
         cx + stem_w // 2, stem_bot_y],
        radius=round(stem_w / 2),
        fill=(0, 0, 0, 255),
    )

    # ── Base bar ──────────────────────────────────────────
    base_w = round(14 * scale)
    base_h = max(round(2.2 * scale), 2)
    base_y = stem_bot_y
    d.rounded_rectangle(
        [cx - base_w // 2, base_y,
         cx + base_w // 2, base_y + base_h],
        radius=round(base_h / 2),
        fill=(0, 0, 0, 255),
    )

    # ── Sound-wave arcs (2 pairs, symmetric) ──────────────
    arc_params = [
        # (radius, half-spread-deg, line_width)
        (round(16 * scale), 40, max(round(1.6 * scale), 1)),
        (round(20 * scale), 38, max(round(1.4 * scale), 1)),
    ]
    arc_cy = body_cy  # arcs centre on the mic capsule centre

    for arc_r, half_spread, lw in arc_params:
        arc_bbox = [
            cx - arc_r, arc_cy - arc_r,
            cx + arc_r, arc_cy + arc_r,
        ]
        # Left arc: centred on 180°
        d.arc(arc_bbox,
              start=180 - half_spread, end=180 + half_spread,
              fill=(0, 0, 0, 255), width=lw)
        # Right arc: centred on 0°
        d.arc(arc_bbox,
              start=360 - half_spread, end=360 + half_spread,
              fill=(0, 0, 0, 255), width=lw)

    # Resize to target size with LANCZOS for clean antialiasing
    if DRAW_SIZE != size_px:
        img = img.resize((size_px, size_px), Image.LANCZOS)

    return img


# ─────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────

def main():
    # App Icon
    print("Generating AppIcon_new.png …")
    app_icon = build_app_icon()
    app_icon_path = os.path.join(OUTPUT_DIR, "AppIcon_new.png")
    app_icon.save(app_icon_path, "PNG", optimize=False)
    print(f"  Saved: {app_icon_path}  size={app_icon.size}")

    # Menu bar icons
    for filename, size in [
        ("menubar_icon_new.png",    44),
        ("menubar_icon_new@2x.png", 44),
        ("menubar_icon_new_1x.png", 22),
    ]:
        print(f"Generating {filename} …")
        icon = draw_menubar_mic(size)
        path = os.path.join(OUTPUT_DIR, filename)
        icon.save(path, "PNG", optimize=False)
        print(f"  Saved: {path}  size={icon.size}")

    print("\nAll icons generated successfully.")


if __name__ == "__main__":
    main()
