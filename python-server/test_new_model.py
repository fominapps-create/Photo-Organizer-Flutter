"""Test new 256x256 model with correct preprocessing"""
import onnxruntime as ort
import numpy as np
from PIL import Image
import urllib.request
import io
import json

# Load new model
sess = ort.InferenceSession('onnx_models/mobileclip_256.onnx')
print(f'Input shape: {sess.get_inputs()[0].shape}')

# Load text embeddings
text_emb = np.load('../assets/models/semantic_embeddings.npy')
with open('../assets/models/semantic_metadata.json') as f:
    meta = json.load(f)

def test_image(url, label):
    print(f"\n=== {label} ===")
    with urllib.request.urlopen(url, timeout=10) as response:
        img = Image.open(io.BytesIO(response.read())).convert('RGB')
    
    # MobileCLIP preprocessing: resize to 256, just /255 (no mean/std!)
    img = img.resize((256, 256))
    img_np = np.array(img).astype(np.float32) / 255.0
    img_chw = img_np.transpose(2, 0, 1)
    img_batch = np.expand_dims(img_chw, 0).astype(np.float32)
    
    result = sess.run(None, {'image': img_batch})
    img_emb = result[0][0]
    
    sims = np.dot(text_emb, img_emb)
    indices = np.argsort(sims)[::-1][:5]
    for i in indices:
        print(f"  {meta['descriptions'][i]}: {sims[i]:.4f}")

test_image("https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=300", "Portrait")
test_image("https://images.unsplash.com/photo-1587300003388-59208cc962cb?w=300", "Dog")
test_image("https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=300", "Food")
test_image("https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=300", "Mountains")
