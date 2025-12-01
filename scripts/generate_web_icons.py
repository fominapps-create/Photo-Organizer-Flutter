"""
generate_web_icons.py

Create web icons (favicon and icons) from a source PNG using Pillow.
Usage: python scripts/generate_web_icons.py path/to/source.png
Writes to `web/favicon.png` and `web/icons/Icon-192.png`, `web/icons/Icon-512.png`,
`web/icons/Icon-maskable-192.png`, `web/icons/Icon-maskable-512.png`.
"""
import os
import sys
from PIL import Image


def ensure_dir(path):
    os.makedirs(path, exist_ok=True)


def main():
    if len(sys.argv) < 2:
        print("Usage: python scripts/generate_web_icons.py input.png [workspaceRoot]")
        sys.exit(1)

    input_path = sys.argv[1]
    workspace_root = sys.argv[2] if len(sys.argv) >= 3 else os.getcwd()

    if not os.path.exists(input_path):
        print(f"Input not found: {input_path}")
        sys.exit(2)

    web_root = os.path.join(workspace_root, 'web')
    icons_dir = os.path.join(web_root, 'icons')
    ensure_dir(icons_dir)

    sizes = {
        'Icon-192.png': (192, 192),
        'Icon-512.png': (512, 512),
        'Icon-maskable-192.png': (192, 192),
        'Icon-maskable-512.png': (512, 512),
        'favicon.png': (48, 48),
    }

    img = Image.open(input_path).convert('RGBA')

    for name, size in sizes.items():
        out_path = os.path.join(icons_dir if 'Icon' in name or 'maskable' in name else web_root, name)
        resized = img.resize(size, Image.LANCZOS)
        resized.save(out_path)
        print(f"Wrote {out_path}")


if __name__ == '__main__':
    main()
