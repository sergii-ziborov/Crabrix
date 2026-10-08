#!/usr/bin/env python3
"""Draw original Crabrix App Store creative assets at Apple's exact sizes.

These are purpose-built illustrations of the real Learn and Code workflow.
They contain no fabricated performance claims or altered app screenshots.
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs/app-store/creative"
FONT = "/System/Library/Fonts/SFNS.ttf"
MONO = "/System/Library/Fonts/SFNSMono.ttf"

INK = (8, 14, 22)
PANEL = (19, 29, 40)
WHITE = (247, 250, 252)
MUTED = (153, 174, 189)
ORANGE = (255, 101, 70)
MINT = (96, 212, 174)
BLUE = (91, 174, 248)


def font(size, mono=False):
    return ImageFont.truetype(MONO if mono else FONT, size=size)


def gradient(width, height):
    image = Image.new("RGB", (width, height))
    pix = image.load()
    for y in range(height):
        yy = y / max(1, height - 1)
        for x in range(width):
            xx = x / max(1, width - 1)
            glow = max(0, 1 - ((xx - 0.78) ** 2 / 0.34 + (yy - 0.47) ** 2 / 0.31))
            pix[x, y] = (
                int(8 + 13 * yy + 16 * glow),
                int(14 + 18 * yy + 18 * glow),
                int(22 + 27 * yy + 21 * glow),
            )
    return image


def text(draw, xy, value, size, color=WHITE, mono=False, spacing=0):
    draw.multiline_text(xy, value, font=font(size, mono), fill=color, spacing=spacing)


def pill(draw, box, label, fill, fg=WHITE, size=37):
    draw.rounded_rectangle(box, radius=(box[3] - box[1]) // 2, fill=fill)
    bounds = draw.textbbox((0, 0), label, font=font(size))
    tw, th = bounds[2] - bounds[0], bounds[3] - bounds[1]
    x = box[0] + ((box[2] - box[0]) - tw) / 2
    y = box[1] + ((box[3] - box[1]) - th) / 2 - bounds[1]
    draw.text((x, y), label, font=font(size), fill=fg)


def code_panel(canvas, box, scale=1.0):
    x0, y0, x1, y1 = box
    d = ImageDraw.Draw(canvas)
    # The visual mirrors the native editor's actual file, Check, Run, and
    # Output concepts without pretending to be a captured app screenshot.
    d.rounded_rectangle(box, radius=int(52 * scale), fill=PANEL, outline=(57, 76, 90), width=max(2, int(3 * scale)))
    d.rounded_rectangle((x0 + 3, y0 + 3, x1 - 3, y0 + 115 * scale), radius=int(50 * scale), fill=(28, 43, 56))
    d.rectangle((x0 + 3, y0 + 80 * scale, x1 - 3, y0 + 115 * scale), fill=(28, 43, 56))
    d.ellipse((x0 + 48 * scale, y0 + 42 * scale, x0 + 68 * scale, y0 + 62 * scale), fill=ORANGE)
    d.ellipse((x0 + 82 * scale, y0 + 42 * scale, x0 + 102 * scale, y0 + 62 * scale), fill=MINT)
    d.ellipse((x0 + 116 * scale, y0 + 42 * scale, x0 + 136 * scale, y0 + 62 * scale), fill=BLUE)
    text(d, (x0 + 185 * scale, y0 + 31 * scale), "src/main.rs", int(47 * scale), WHITE, True)
    badge = (x1 - 258 * scale, y0 + 22 * scale, x1 - 38 * scale, y0 + 90 * scale)
    pill(d, badge, "▶ Run", (91, 48, 43), ORANGE, int(34 * scale))

    left = x0 + 74 * scale
    line_y = y0 + 171 * scale
    rows = [
        [("fn", ORANGE), (" main() {", WHITE)],
        [("    let", ORANGE), (" ferris = ", WHITE), ("\"crab\"", MINT), (";", WHITE)],
        [("    println!", (184, 132, 242)), ("(\"{ferris}\");", WHITE)],
        [("}", WHITE)],
    ]
    mono_font = font(int(54 * scale), True)
    for row_index, row in enumerate(rows):
        current = left
        for segment, color in row:
            d.text((current, line_y + row_index * 90 * scale), segment, font=mono_font, fill=color)
            current += d.textlength(segment, font=mono_font)

    oy = y1 - 176 * scale
    d.rounded_rectangle((x0 + 45 * scale, oy, x1 - 45 * scale, y1 - 40 * scale), radius=int(25 * scale), fill=(12, 39, 38))
    text(d, (x0 + 78 * scale, oy + 24 * scale), "OUTPUT", int(30 * scale), MINT, True)
    text(d, (x0 + 78 * scale, oy + 69 * scale), "crab", int(45 * scale), WHITE, True)


def accents(draw, width, height):
    draw.line((0, 0, width, 0), fill=(29, 60, 69), width=8)
    draw.ellipse((int(width * .81), -int(height * .30), int(width * 1.08), int(height * .48)), outline=(30, 80, 80), width=4)
    draw.ellipse((int(width * .78), -int(height * .36), int(width * 1.12), int(height * .55)), outline=(26, 58, 68), width=3)


def header():
    w, h = 3840, 1646
    im = gradient(w, h)
    d = ImageDraw.Draw(im)
    accents(d, w, h)
    d.rounded_rectangle((250, 190, 305, 245), radius=12, fill=ORANGE)
    text(d, (333, 184), "CRABRIX", 70, WHITE)
    text(d, (250, 370), "Learn Rust.\nBuild for real.", 215, WHITE, spacing=19)
    d.rounded_rectangle((250, 955, 635, 968), radius=7, fill=ORANGE)
    text(d, (250, 1030), "Courses, Cargo projects, and local compilation", 61, MUTED)
    text(d, (250, 1110), "on iPhone and iPad.", 61, MUTED)
    pill(d, (250, 1300, 705, 1392), "LEARN RUST", (29, 67, 62), MINT, 38)
    pill(d, (735, 1300, 1185, 1392), "RUN LOCALLY", (76, 41, 39), ORANGE, 38)
    code_panel(im, (2170, 170, 3695, 1480), 0.90)
    path = OUT / "crabrix-header-3840x1646.png"
    im.save(path, optimize=True)
    return path


def search():
    w, h = 1920, 1280
    im = gradient(w, h)
    d = ImageDraw.Draw(im)
    accents(d, w, h)
    d.rounded_rectangle((105, 95, 145, 135), radius=10, fill=ORANGE)
    text(d, (165, 94), "CRABRIX", 51)
    text(d, (105, 267), "Rust on\nyour iPhone.", 132, WHITE, spacing=20)
    d.rounded_rectangle((108, 658, 340, 668), radius=6, fill=ORANGE)
    text(d, (105, 714), "Learn. Code. Run locally.", 46, MUTED)
    pill(d, (105, 1000, 530, 1080), "7 RUST COURSES", (29, 67, 62), MINT, 30)
    pill(d, (105, 1095, 530, 1175), "46 EXAMPLES", (76, 41, 39), ORANGE, 30)
    code_panel(im, (825, 130, 1855, 1160), 0.64)
    path = OUT / "crabrix-search-1920x1280.png"
    im.save(path, optimize=True)
    return path


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for generated in (header(), search()):
        with Image.open(generated) as image:
            assert image.mode == "RGB"
            print(generated, image.size, generated.stat().st_size)
