#!/usr/bin/env python3
"""Generate review-only 1-bit shelf label proposals at the 5890's native width."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "formats"
OUT.mkdir(parents=True, exist_ok=True)
WIDTH = 384
EAN = "4006381333931"
FONT_REGULAR = "/System/Library/Fonts/Supplemental/Arial.ttf"
FONT_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"

LEFT_ODD = ["0001101", "0011001", "0010011", "0111101", "0100011", "0110001", "0101111", "0111011", "0110111", "0001011"]
LEFT_EVEN = ["0100111", "0110011", "0011011", "0100001", "0011101", "0110001", "0000101", "0010001", "0001001", "0010111"]
# Keep the right-hand patterns identical to LabelCore/EAN13.swift.
RIGHT = ["1110010", "1100110", "1101100", "1000010", "1011100", "1001110", "1010000", "1000100", "1001000", "1110100"]
PARITY = ["OOOOOO", "OOEOEE", "OOEEOE", "OOEEEO", "OEOOEE", "OEEOOE", "OEEEOO", "OEOEOE", "OEOEEO", "OEEOEO"]


def ean_modules(ean: str) -> str:
    assert len(ean) == 13 and ean.isascii() and ean.isdigit()
    digits = [int(c) for c in ean]
    checksum = (10 - sum(value * (1 if i % 2 == 0 else 3) for i, value in enumerate(digits[:12])) % 10) % 10
    assert checksum == digits[-1]
    bits = "101"
    for index in range(1, 7):
        bits += (LEFT_ODD if PARITY[digits[0]][index - 1] == "O" else LEFT_EVEN)[digits[index]]
    bits += "01010"
    for index in range(7, 13):
        bits += RIGHT[digits[index]]
    bits += "101"
    assert len(bits) == 95
    return bits


def text(draw, value, box, size, *, bold=False, align="left", min_size=10):
    x, y, w, h = box
    font_path = FONT_BOLD if bold else FONT_REGULAR
    while size >= min_size:
        font = ImageFont.truetype(font_path, size)
        bounds = draw.textbbox((0, 0), value, font=font)
        tw, th = bounds[2] - bounds[0], bounds[3] - bounds[1]
        if tw <= w and th <= h:
            break
        size -= 1
    if align == "center":
        x += (w - tw) // 2
    elif align == "right":
        x += w - tw
    draw.text((x - bounds[0], y - bounds[1]), value, fill=0, font=font)


def render(height, layout):
    image = Image.new("L", (WIDTH, height), 255)
    draw = ImageDraw.Draw(image)
    text(draw, "Peinture / Aérosols", (12, layout["category"], 360, 20), layout["category_size"], bold=True)
    text(draw, "RÉF RAYON : 12-04-08", (12, layout["shelf"], 360, 20), layout["shelf_size"], bold=True)
    text(draw, "Spray Acrylique", (12, layout["name"], 360, 42), layout["name_size"], bold=True)

    start = (WIDTH - 95 * 3) // 2
    y0, y1 = layout["bars"]
    for index, bit in enumerate(ean_modules(EAN)):
        if bit == "1":
            x = start + index * 3
            draw.rectangle((x, y0, x + 2, y1 - 1), fill=0)
    y = layout["digits"]
    size = layout["digits_size"]
    text(draw, EAN[:1], (22, y, 27, 20), size, bold=True, align="center")
    text(draw, EAN[1:7], (58, y, 135, 20), size, bold=True, align="center")
    text(draw, EAN[7:], (208, y, 135, 20), size, bold=True, align="center")
    text(draw, "Réf. 4523187", (12, layout["reference"], 360, 24), layout["reference_size"], bold=True, align="center")
    text(draw, "Prix de vente TTC", (12, layout["caption"], 215, 26), layout["caption_size"], bold=True)
    text(draw, "5,95 €", (223, layout["price"], 149, 48), layout["price_size"], bold=True, align="right")
    # Threshold text once; the bars were placed at exact integer dots.
    return image.point(lambda value: 255 if value >= 160 else 0, mode="1")


FORMATS = [
    ("compact", "Compact rayon", 208, dict(category=6, category_size=12, shelf=22, shelf_size=11,
        name=39, name_size=25, bars=(70, 120), digits=123, digits_size=13, reference=145,
        reference_size=12, caption=178, caption_size=15, price=166, price_size=31)),
    ("standard", "Standard actuel", 240, dict(category=7, category_size=13, shelf=26, shelf_size=12,
        name=44, name_size=28, bars=(84, 154), digits=156, digits_size=16, reference=178,
        reference_size=14, caption=208, caption_size=19, price=194, price_size=37)),
    ("rayon_aere", "Rayon aéré", 312, dict(category=10, category_size=16, shelf=34, shelf_size=14,
        name=58, name_size=32, bars=(103, 195), digits=199, digits_size=17, reference=228,
        reference_size=17, caption=274, caption_size=21, price=257, price_size=43)),
    ("grand", "Grand", 416, dict(category=14, category_size=18, shelf=43, shelf_size=16,
        name=75, name_size=38, bars=(139, 267), digits=274, digits_size=18, reference=310,
        reference_size=19, caption=369, caption_size=22, price=346, price_size=47)),
]

labels = []
for slug, title, height, layout in FORMATS:
    label = render(height, layout)
    label.save(OUT / f"{slug}.png")
    assert label.mode == "1" and label.size == (WIDTH, height)
    labels.append((title, height, label))

# Side-by-side review board. Every label uses the same display scale (2 screen
# pixels per printer dot), so differences in height remain visually honest.
scale = 2
cell_w = WIDTH * scale + 52
first_row_height = 240 * scale + 116
second_row_height = 416 * scale + 116
board = Image.new("RGB", (cell_w * 2 + 40, first_row_height + second_row_height + 40), "#eeeeee")
draw = ImageDraw.Draw(board)
heading_font = ImageFont.truetype(FONT_BOLD, 29)
small_font = ImageFont.truetype(FONT_REGULAR, 19)
for index, (title, height, label) in enumerate(labels):
    col, row = index % 2, index // 2
    left = 20 + col * cell_w
    top = 20 if row == 0 else 20 + first_row_height
    draw.text((left + 26, top + 4), title, font=heading_font, fill="black")
    draw.text((left + 26, top + 42), f"Zone imprimee : 48 x {height // 8} mm  |  384 x {height} points", font=small_font, fill="#333333")
    board.paste(label.convert("RGB").resize((WIDTH * scale, height * scale), Image.Resampling.NEAREST), (left + 26, top + 76))
board.save(OUT / "comparaison.png")
print(OUT / "comparaison.png")
