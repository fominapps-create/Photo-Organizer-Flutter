#!/usr/bin/env python3
"""
Generate Android mipmap launcher icons from assets/Icon4.png.
Writes `ic_launcher.png` into each mipmap-* directory under android/app/src/main/res/.

Usage: python scripts/generate_mipmap_icons.py
"""
import os
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SRC = os.path.join(ROOT, 'assets', 'Icon4.png')
RES_DIR = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')

sizes = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
    'mipmap-anydpi-v26': 108,  # used for adaptive icons; we'll write a 108px image
}

if not os.path.exists(SRC):
    print('Source icon not found:', SRC)
    raise SystemExit(1)

img = Image.open(SRC).convert('RGBA')
for folder, size in sizes.items():
    dest_dir = os.path.join(RES_DIR, folder)
    if not os.path.exists(dest_dir):
        print('Skipping missing res dir', dest_dir)
        continue
    out = img.resize((size, size), Image.LANCZOS)
    out_path = os.path.join(dest_dir, 'ic_launcher.png')
    out.save(out_path)
    print('Wrote', out_path)

print('Done')
