#!/usr/bin/env python3
"""Generate five review-only label arrangements in four printable heights."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

from generate_format_previews import EAN, FONT_BOLD, FONT_REGULAR, FORMATS, WIDTH, ean_modules, text

OUT = Path(__file__).resolve().parents[1] / "docs" / "dispositions"
OUT.mkdir(parents=True, exist_ok=True)

LAYOUTS = [
    ("prix_en_tete", "Prix en tête"),
    ("deux_colonnes", "Deux colonnes"),
    ("code_en_tete", "Code en tête"),
    ("composition_centree", "Composition centrée"),
    ("code_en_bas", "Code en bas"),
]


def render(slug: str, height: int) -> Image.Image:
    image = Image.new("L", (WIDTH, height), 255)
    draw = ImageDraw.Draw(image)
    factor = height / 208
    font_factor = min(1.0 + (height - 208) / 600, 1.35)

    def y(value):
        return round(value * factor)

    def label(value, x, top, width, band, size, *, bold=True, align="left"):
        text(draw, value, (x, y(top), width, y(band)), round(size * font_factor),
             bold=bold, align=align, min_size=8)

    def barcode(top, bottom, digits_top):
        # 95 EAN-13 modules at exactly three printer dots each, with 49-dot
        # quiet zones on either side of the bars.
        start = (WIDTH - 95 * 3) // 2
        for index, bit in enumerate(ean_modules(EAN)):
            if bit == "1":
                x = start + index * 3
                draw.rectangle((x, y(top), x + 2, y(bottom) - 1), fill=0)
        label(EAN[:1], 18, digits_top, 30, 18, 12, align="center")
        label(EAN[1:7], 55, digits_top, 140, 18, 12, align="center")
        label(EAN[7:], 205, digits_top, 140, 18, 12, align="center")

    if slug == "prix_en_tete":
        label("Peinture / Aérosols", 12, 7, 205, 16, 12)
        label("RÉF RAYON : 12-04-08", 12, 24, 210, 16, 11)
        label("5,95 €", 225, 7, 147, 40, 34, align="right")
        label("Prix de vente TTC", 221, 49, 151, 18, 13, align="right")
        label("Spray Acrylique", 12, 69, 360, 29, 26)
        barcode(104, 153, 155)
        label("Réf. 4523187", 12, 182, 360, 19, 14, align="center")
    elif slug == "deux_colonnes":
        label("Peinture / Aérosols", 12, 7, 360, 17, 12)
        label("RÉF RAYON : 12-04-08", 12, 25, 360, 17, 11)
        label("Spray Acrylique", 12, 54, 195, 42, 23)
        label("5,95 €", 220, 48, 152, 40, 34, align="right")
        label("Prix de vente TTC", 215, 89, 157, 17, 12, align="right")
        barcode(111, 160, 162)
        label("Réf. 4523187", 12, 187, 360, 18, 14, align="center")
    elif slug == "code_en_tete":
        label("Peinture / Aérosols", 12, 6, 360, 16, 12)
        label("RÉF RAYON : 12-04-08", 12, 23, 360, 16, 11)
        barcode(48, 105, 107)
        label("Spray Acrylique", 12, 135, 360, 30, 26)
        label("Réf. 4523187", 12, 167, 205, 17, 13)
        label("Prix de vente TTC", 12, 187, 205, 17, 13)
        label("5,95 €", 225, 173, 147, 33, 31, align="right")
    elif slug == "composition_centree":
        label("Peinture / Aérosols", 12, 6, 360, 17, 12, align="center")
        label("RÉF RAYON : 12-04-08", 12, 25, 360, 16, 11, align="center")
        label("Spray Acrylique", 12, 48, 360, 29, 27, align="center")
        barcode(81, 127, 129)
        label("Réf. 4523187", 12, 149, 360, 17, 13, align="center")
        label("Prix de vente TTC", 12, 166, 360, 17, 13, align="center")
        label("5,95 €", 12, 183, 360, 24, 26, align="center")
    elif slug == "code_en_bas":
        label("Peinture / Aérosols", 12, 7, 360, 17, 12)
        label("Spray Acrylique", 12, 26, 360, 30, 27)
        label("RÉF RAYON : 12-04-08", 12, 60, 360, 17, 11)
        label("Prix de vente TTC", 12, 84, 205, 17, 14)
        label("5,95 €", 221, 75, 151, 41, 35, align="right")
        label("Réf. 4523187", 12, 111, 360, 18, 13, align="center")
        barcode(137, 183, 186)
    else:
        raise ValueError(slug)

    return image.point(lambda value: 255 if value >= 160 else 0, mode="1")


def board(items, output, columns=2):
    scale = 2
    margin = 24
    cell_width = WIDTH * scale + 48
    rows = (len(items) + columns - 1) // columns
    cell_height = max(height for _, height, _ in items) * scale + 108
    canvas = Image.new("RGB", (columns * cell_width + 2 * margin,
                               rows * cell_height + 2 * margin), "#eeeeee")
    draw = ImageDraw.Draw(canvas)
    heading = ImageFont.truetype(FONT_BOLD, 27)
    detail = ImageFont.truetype(FONT_REGULAR, 18)
    for index, (title, height, label_image) in enumerate(items):
        col, row = index % columns, index // columns
        left = margin + col * cell_width + 20
        top = margin + row * cell_height
        draw.text((left, top), title, font=heading, fill="black")
        draw.text((left, top + 35), f"48 × {height // 8} mm de zone imprimée", font=detail, fill="black")
        canvas.paste(label_image.convert("RGB").resize((WIDTH * scale, height * scale),
                                                       Image.Resampling.NEAREST), (left, top + 68))
    canvas.save(output)


if __name__ == "__main__":
    summary = []
    for slug, title in LAYOUTS:
        variants = []
        for format_slug, format_title, height, _ in FORMATS:
            result = render(slug, height)
            assert result.mode == "1" and result.size == (WIDTH, height)
            result.save(OUT / f"{slug}_{format_slug}.png")
            variants.append((format_title, height, result))
            if format_slug == "standard":
                summary.append((title, height, result))
        board(variants, OUT / f"{slug}_quatre_formats.png")
    board(summary, OUT / "comparaison_dispositions.png")
    print(OUT / "comparaison_dispositions.png")
