#!/usr/bin/env python3
"""Render the published 1024 px Game Center achievement badges."""

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
CATALOG = json.loads((ROOT / "docs/game-center-catalog.json").read_text())
DEST = ROOT / "docs/app-store/game-center"
SIZE = 1024
SCALE = 2
FONT = Path("/System/Library/Fonts/Supplemental/Arial Bold.ttf")


def regular_polygon(cx, cy, radius, sides, start=-math.pi / 2):
    return [
        (cx + radius * math.cos(start + n * 2 * math.pi / sides),
         cy + radius * math.sin(start + n * 2 * math.pi / sides))
        for n in range(sides)
    ]


def render(local_id, index):
    s = SCALE
    image = Image.new("RGB", (SIZE * s, SIZE * s), "#071523")
    d = ImageDraw.Draw(image)
    palette = ["#FF654F", "#F7C44B", "#60D7AB", "#38C6D6", "#EE5B98",
               "#A788F1", "#F09747", "#F4D85A", "#5BC9FF", "#70DEBE"]
    accent = palette[index % len(palette)]
    d.rounded_rectangle((72*s, 72*s, 952*s, 952*s), radius=180*s,
                        fill="#10283A", outline="#294355", width=10*s)
    d.ellipse((155*s, 155*s, 869*s, 869*s), outline=accent, width=22*s)
    d.ellipse((205*s, 205*s, 819*s, 819*s), outline="#315366", width=5*s)

    def line(points, width=42, color=accent):
        d.line([(int(x*s), int(y*s)) for x, y in points], fill=color,
               width=width*s, joint="curve")

    def circle(x, y, radius, fill=accent):
        d.ellipse(((x-radius)*s, (y-radius)*s,
                   (x+radius)*s, (y+radius)*s), fill=fill)

    def label(value, size=260):
        font = ImageFont.truetype(str(FONT), size*s)
        box = d.textbbox((0, 0), value, font=font)
        x = (SIZE*s - (box[2]-box[0])) / 2 - box[0]
        y = (SIZE*s - (box[3]-box[1])) / 2 - box[1] - 22*s
        d.text((x, y), value, fill=accent, font=font)

    if local_id.startswith("family."):
        initials = "".join(part[0] for part in local_id[7:].split("-") if part)[:3].upper()
        label(initials, 200 if len(initials) > 2 else 270)
        small = ImageFont.truetype(str(FONT), 58*s)
        d.text((512*s, 745*s), "I · II · III · IV · V", fill=accent,
               anchor="mm", font=small)
    elif local_id == "builds.0":
        d.rounded_rectangle((340*s, 335*s, 685*s, 690*s), radius=65*s,
                            outline=accent, width=38*s)
        d.polygon([(450*s, 418*s), (450*s, 610*s), (605*s, 512*s)], fill=accent)
    elif local_id == "builds.2":
        label("50", 280)
    elif local_id == "lessons.0":
        line([(512, 385), (512, 675)], 24)
        line([(512, 410), (405, 360), (330, 372), (330, 640), (420, 640), (512, 675)], 24)
        line([(512, 410), (619, 360), (694, 372), (694, 640), (604, 640), (512, 675)], 24)
    elif local_id == "lessons.2":
        label("25", 280)
    elif local_id == "practice.0":
        d.polygon([(512*s, 315*s), (690*s, 390*s), (665*s, 630*s),
                   (512*s, 720*s), (359*s, 630*s), (334*s, 390*s)],
                  outline=accent)
        line([(408, 510), (480, 585), (620, 438)], 44)
    elif local_id == "crates.0":
        d.polygon([(512*s, 325*s), (690*s, 415*s), (512*s, 505*s),
                   (334*s, 415*s)], outline=accent, width=24*s)
        line([(334, 415), (334, 610), (512, 700), (690, 610), (690, 415)], 24)
        line([(512, 505), (512, 700)], 24)
    elif local_id == "rating.0":
        line([(340, 650), (450, 390), (510, 505), (585, 340), (690, 650)], 32)
        line([(330, 680), (700, 680)], 32)
        circle(450, 390, 20)
        circle(585, 340, 20)
    elif local_id == "rating.4":
        d.polygon([(330*s, 625*s), (355*s, 390*s), (460*s, 520*s),
                   (512*s, 320*s), (565*s, 520*s), (670*s, 390*s),
                   (694*s, 625*s)], fill=accent)
        line([(325, 665), (699, 665)], 22)
    elif local_id == "algorithm-atlas.0":
        line([(365, 600), (512, 360), (665, 600), (365, 600)], 22)
        for x, y in [(365, 600), (512, 360), (665, 600)]:
            circle(x, y, 38)
    else:
        for n in range(8):
            angle = -math.pi / 2 + n * math.pi / 4
            x, y = 512 + 205*math.cos(angle), 512 + 205*math.sin(angle)
            line([(512, 512), (x, y)], 13, "#557687")
            circle(x, y, 24)
        d.polygon([(int(x*s), int(y*s)) for x, y in
                   regular_polygon(512, 512, 100, 8)], fill=accent)

    image.resize((SIZE, SIZE), Image.Resampling.LANCZOS).save(
        DEST / f"{local_id}.png", format="PNG", dpi=(72, 72), optimize=True
    )


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    for index, achievement in enumerate(CATALOG["achievements"]):
        identifier = achievement.get("localID") or "family." + achievement["familyID"]
        render(identifier, index)


if __name__ == "__main__":
    main()
