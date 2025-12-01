"""
Simple PNG -> ICO converter using Pillow.
Usage: python scripts/png2ico.py path/to/input.png path/to/output.ico
Installs Pillow if needed with: pip install pillow
"""
import sys
import os

try:
    from PIL import Image
except ImportError as e:
    print("Pillow is required. Installing now...")
    os.system(f"{sys.executable} -m pip install --upgrade pip")
    os.system(f"{sys.executable} -m pip install pillow")
    from PIL import Image


def main():
    if len(sys.argv) < 3:
        print("Usage: python png2ico.py input.png output.ico")
        sys.exit(1)
    input_path = sys.argv[1]
    output_path = sys.argv[2]

    sizes = [(256,256), (128,128), (64,64), (48,48), (32,32), (16,16)]

    if not os.path.exists(input_path):
        print(f"Input file not found: {input_path}")
        sys.exit(2)

    img = Image.open(input_path)
    # Convert to RGBA if not
    img = img.convert('RGBA')

    # If the input image is smaller than target sizes, we will not upscale them to avoid blurring.
    # Instead we'll resize if larger; if smaller, Pillow will upscale by default (blended).

    # Save ICO with multiple sizes
    try:
        img.save(output_path, format='ICO', sizes=sizes)
        print(f"Wrote {output_path}")
    except Exception as e:
        print(f"Failed to save ICO: {e}")
        sys.exit(3)

if __name__ == '__main__':
    main()
