#!/usr/bin/env python3
"""Wrap a simulator screenshot in a device body for posters and slides.

The simulator already renders the exact screen corner radius, so the body is
built from that radius plus a bezel thickness instead of guessing a device.
"""
from PIL import Image, ImageDraw, ImageFilter
import sys, os

def radius_from_alpha(im):
    """First opaque x on the top row is the corner radius of a rounded rect."""
    a = im.split()[-1]
    w, _ = im.size
    for y in range(0, 8):
        for x in range(w):
            if a.getpixel((x, y)) > 128:
                return max(x, 18)
    return 40

def frame(path, out, bezel, pad=120, body=(22, 22, 24), rim=(70, 70, 74), radius_extra=0):
    screen = Image.open(path).convert("RGBA")
    w, h = screen.size
    r = radius_from_alpha(screen) + radius_extra

    W, H = w + 2 * (bezel + pad), h + 2 * (bezel + pad)
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))

    body_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(body_layer)
    box = [pad, pad, pad + w + 2 * bezel, pad + h + 2 * bezel]
    d.rounded_rectangle(box, radius=r + bezel, fill=body)

    shadow = body_layer.filter(ImageFilter.GaussianBlur(28))
    shadow_alpha = shadow.split()[-1].point(lambda v: int(v * 0.45))
    shadow.putalpha(shadow_alpha)
    canvas.alpha_composite(shadow)

    canvas.alpha_composite(body_layer)

    rim_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(rim_layer)
    dr.rounded_rectangle(box, radius=r + bezel, outline=rim, width=max(3, bezel // 6))
    canvas.alpha_composite(rim_layer)

    canvas.alpha_composite(screen, (pad + bezel, pad + bezel))

    os.makedirs(os.path.dirname(out), exist_ok=True)
    canvas.save(out)
    print(f"{os.path.basename(out)}  {canvas.size[0]}x{canvas.size[1]}")

if __name__ == "__main__":
    # Raw simulator shots come from /tmp by default; override with argv[1].
    base = sys.argv[1] if len(sys.argv) > 1 else "/tmp"
    dest = os.path.dirname(os.path.abspath(__file__))
    frame(f"{base}/shot-iphone-today.png", f"{dest}/iphone-today.png", bezel=34)
    frame(f"{base}/shot-iphone-browse.png", f"{dest}/iphone-browse.png", bezel=34)
    frame(f"{base}/shot-ipad.png", f"{dest}/ipad-today.png", bezel=46)
    frame(f"{base}/shot-watch.png", f"{dest}/watch-today.png", bezel=56, pad=110, body=(44, 44, 48), rim=(120, 120, 128))
