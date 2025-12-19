from PIL import Image
import os

# Paths
workspace_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
input_path = os.path.join(workspace_root, 'assets', 'Fox face abstract 1024x1024.png')
output_path = os.path.join(workspace_root, 'assets', 'Fox face abstract 1024x1024 padded.png')

# Load the original image
img = Image.open(input_path)

# Create a new transparent canvas
canvas_size = 1024
new_img = Image.new('RGBA', (canvas_size, canvas_size), (0, 0, 0, 0))

# Scale down the fox to 66% (safe zone for adaptive icons)
scale_factor = 0.66
new_size = int(canvas_size * scale_factor)

# Resize the fox image
fox_resized = img.resize((new_size, new_size), Image.Resampling.LANCZOS)

# Calculate position to center the fox
offset = (canvas_size - new_size) // 2

# Paste the resized fox onto the transparent canvas
new_img.paste(fox_resized, (offset, offset), fox_resized if fox_resized.mode == 'RGBA' else None)

# Save the padded version
new_img.save(output_path, 'PNG')

print(f"✓ Created padded icon at: {output_path}")
print(f"  Original size: {img.size}")
print(f"  Scaled size: {new_size}x{new_size} ({scale_factor*100:.0f}%)")
print(f"  Final canvas: {canvas_size}x{canvas_size} with transparent padding")
