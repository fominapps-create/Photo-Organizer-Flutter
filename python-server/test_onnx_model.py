"""
Test the exported ONNX model to verify it works correctly
"""
import onnxruntime as ort
import numpy as np
from PIL import Image
import os

def test_onnx_model():
    print("Loading ONNX model...")
    
    # Load ONNX model
    session = ort.InferenceSession("onnx_models/mobileclip_image_encoder.onnx")
    
    # Load pre-computed category embeddings
    category_embeddings = np.load("onnx_models/category_embeddings.npy")
    
    categories = [
        "people",
        "animals", 
        "food",
        "scenery",
        "documents",
        "other"
    ]
    
    print(f"✓ Model loaded")
    print(f"✓ Category embeddings: {category_embeddings.shape}")
    
    # Test on sample images (various expected categories)
    test_images = [
        "../temp_emulator_photos/img1.png",    # Unknown
        "../temp_emulator_photos/img10.png",   # Unknown
        "../temp_emulator_photos/img20.png",   # Unknown
        "../temp_emulator_photos/img50.png",   # Unknown
        "../temp_emulator_photos/img100.png",  # Unknown
        "../temp_emulator_photos/img150.png",  # Unknown
    ]
    
    for img_path in test_images:
        if not os.path.exists(img_path):
            print(f"⚠ Skipping {img_path} (not found)")
            continue
            
        print(f"\n--- Testing: {os.path.basename(img_path)} ---")
        
        # Load and preprocess image
        image = Image.open(img_path).convert("RGB")
        image = image.resize((224, 224))
        
        # Convert to tensor format: (1, 3, 224, 224) normalized to [-1, 1]
        img_array = np.array(image).astype(np.float32)
        
        # Normalize: ImageNet stats (approximate for CLIP)
        mean = np.array([0.48145466, 0.4578275, 0.40821073], dtype=np.float32)
        std = np.array([0.26862954, 0.26130258, 0.27577711], dtype=np.float32)
        img_array = (img_array / 255.0 - mean) / std
        
        # Transpose to NCHW format
        img_array = img_array.transpose(2, 0, 1)
        img_array = np.expand_dims(img_array, axis=0)
        
        # Run inference
        outputs = session.run(None, {"image": img_array})
        embedding = outputs[0]
        
        # Calculate cosine similarities (embeddings are already normalized)
        similarities = embedding @ category_embeddings.T
        similarities = similarities[0]  # Remove batch dim
        
        # Apply softmax to get probabilities
        exp_sim = np.exp(similarities * 100)  # Temperature scaling
        probs = exp_sim / exp_sim.sum()
        
        # Show results
        for i, (cat, prob) in enumerate(zip(categories, probs)):
            bar = "█" * int(prob * 30)
            print(f"  {cat:12} {prob*100:5.1f}% {bar}")
        
        winner = categories[np.argmax(probs)]
        print(f"  → Predicted: {winner}")

if __name__ == "__main__":
    # Install onnxruntime if needed
    try:
        import onnxruntime
    except ImportError:
        print("Installing onnxruntime...")
        import subprocess
        subprocess.run(["pip", "install", "--user", "onnxruntime"])
        import onnxruntime
    
    test_onnx_model()
