"""
generate_web_icons.py

Create web icons (favicon and icons) from a source PNG using Pillow.
Usage: python scripts/generate_web_icons.py path/to/source.png
Writes to `web/favicon.png` and `web/icons/Icon-192.png`, `web/icons/Icon-512.png`,
`web/icons/Icon-maskable-192.png`, `web/icons/Icon-maskable-512.png`.
"""
import os
import sys
from PIL import Image, ImageDraw


def ensure_dir(path):
    os.makedirs(path, exist_ok=True)


def crop_center(img, crop_percent=10):
    """Crop edges by a percentage to zoom in on the center."""
    width, height = img.size
    crop_pixels = int(min(width, height) * crop_percent / 100)
    
    return img.crop((
        crop_pixels,
        crop_pixels,
        width - crop_pixels,
        height - crop_pixels
    ))


def add_rounded_corners(img, radius):
    """Add rounded corners to an image."""
    # Create a mask for rounded corners
    mask = Image.new('L', img.size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([(0, 0), img.size], radius=radius, fill=255)
    
    # Apply the mask to the image
    output = Image.new('RGBA', img.size, (0, 0, 0, 0))
    output.paste(img, (0, 0))
    output.putalpha(mask)
    
    return output


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
        
        # Process favicon differently
        if name == 'favicon.png':
            # Crop 12% from edges to make fox face bigger
            cropped = crop_center(img, crop_percent=12)
            resized = cropped.resize(size, Image.LANCZOS)
            # Use 20% radius for nice rounded corners
            radius = int(min(size) * 0.20)
            resized = add_rounded_corners(resized, radius)
        else:
            resized = img.resize(size, Image.LANCZOS)
        
        resized.save(out_path)
        print(f"Wrote {out_path}")


if __name__ == '__main__':
    main()
