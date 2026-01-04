"""Test MobileCLIP accuracy with real images"""
import onnxruntime as ort
import numpy as np
from PIL import Image
import json
import urllib.request
import io

def test_image(url, description):
    print(f"\n=== Testing: {description} ===")
    
    try:
        with urllib.request.urlopen(url, timeout=10) as response:
            img_data = response.read()
        img = Image.open(io.BytesIO(img_data)).convert('RGB').resize((224, 224))
    except Exception as e:
        print(f"Failed to load: {e}")
        return
    
    img_np = np.array(img).astype(np.float32) / 255.0
    
    # CLIP preprocessing
    mean = np.array([0.48145466, 0.4578275, 0.40821073])
    std = np.array([0.26862954, 0.26130258, 0.27577711])
    img_norm = (img_np - mean) / std
    img_chw = img_norm.transpose(2, 0, 1)
    img_batch = np.expand_dims(img_chw, 0).astype(np.float32)
    
    # Run inference
    result = sess.run(None, {'image': img_batch})
    img_emb = result[0][0]
    
    # Calculate similarities
    similarities = np.dot(text_emb, img_emb)
    
    # Top 5 matches
    indices = np.argsort(similarities)[::-1][:5]
    print("Top 5 matches:")
    for i in indices:
        print(f"  {meta['descriptions'][i]}: {similarities[i]:.4f}")

# Load model and embeddings
print("Loading model and embeddings...")
sess = ort.InferenceSession('../assets/models/mobileclip_image_encoder.onnx')
text_emb = np.load('../assets/models/semantic_embeddings.npy')
with open('../assets/models/semantic_metadata.json') as f:
    meta = json.load(f)

# Check norms
print(f"Text embedding norm (first): {np.linalg.norm(text_emb[0]):.4f}")

# Test with different images
test_image(
    "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=300",
    "Portrait of a man"
)
test_image(
    "https://images.unsplash.com/photo-1587300003388-59208cc962cb?w=300",
    "Dog"
)
test_image(
    "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=300",
    "Food plate"
)
test_image(
    "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=300",
    "Mountain landscape"
)
