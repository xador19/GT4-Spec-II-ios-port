#!/usr/bin/env python3
"""Makes the iOS home screen icon.

usage: python3 ports/ios/make_icon.py [--picture FILE]

Without --picture it draws this project's own plain icon (a racing stripe and a chequered band, no game art or logo).
With --picture it uses the player's own square picture instead. Writes ports/ios/local-res (git-ignored): the iPhone
icons Info.plist names (CFBundleIconFiles AppIcon60x60), opaque squares that iOS rounds itself. CMakeLists.txt bundles
them when they exist. Needs Pillow (make_ipa.sh installs it in its Python environment).
"""
import argparse
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "local-res")
SIZES = (("AppIcon60x60@2x.png", 120), ("AppIcon60x60@3x.png", 180))


def plain_icon(size):
    """A dark blue square with a red-white racing stripe and a chequered band, drawn at 1024 and scaled down."""
    big = 1024
    image = Image.new("RGB", (big, big), (14, 28, 64))
    draw = ImageDraw.Draw(image)
    # Diagonal stripe: red, a thin white line, red.
    for offset, width, colour in ((0, 300, (214, 32, 44)), (300, 40, (245, 245, 245)), (340, 90, (214, 32, 44))):
        draw.polygon([(-200 + offset, big), (-200 + offset + width, big), (big + offset + width - 820, 0),
                      (big + offset - 820, 0)], fill=colour)
    # Chequered band along the bottom.
    cell = 64
    for row in range(2):
        for column in range(big // cell):
            if (row + column) % 2 == 0:
                y = big - (row + 1) * cell
                draw.rectangle([column * cell, y, (column + 1) * cell - 1, y + cell - 1], fill=(245, 245, 245))
    return image.resize((size, size), Image.LANCZOS)


def picture_icon(path, size):
    art = Image.open(path).convert("RGBA")
    side = min(art.size)
    left, top = (art.width - side) // 2, (art.height - side) // 2
    art = art.crop((left, top, left + side, top + side))
    # iOS refuses icons with transparency: flatten onto black.
    flat = Image.new("RGB", art.size, (0, 0, 0))
    flat.paste(art, mask=art.getchannel("A"))
    return flat.resize((size, size), Image.LANCZOS)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--picture", help="your own square picture (PNG or JPEG)")
    args = parser.parse_args()
    os.makedirs(OUT, exist_ok=True)
    for name, size in SIZES:
        icon = picture_icon(args.picture, size) if args.picture else plain_icon(size)
        icon.save(os.path.join(OUT, name))
        print("wrote", os.path.relpath(os.path.join(OUT, name), os.path.join(HERE, "..", "..")))


if __name__ == "__main__":
    main()
