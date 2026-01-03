"""
Test MobileCLIP with semantic descriptions - shows what the model "sees" in each image.
This helps validate the model's understanding beyond just category classification.
"""
import onnxruntime as ort  # type: ignore
import numpy as np
from PIL import Image
import os

# Semantic descriptions to test against - these are more descriptive than categories
SEMANTIC_DESCRIPTIONS = [
    # People descriptions
    "a photo of a person's face",
    "a group of people together",
    "a selfie photo",
    "a portrait of someone",
    "people at a party or event",
    "a baby or young child",
    "a family photo",
    
    # Animal descriptions
    "a photo of a dog",
    "a photo of a cat",
    "a bird or flying animal",
    "a wild animal in nature",
    "a pet animal indoors",
    
    # Food descriptions
    "a plate of cooked food",
    "a dessert or sweet treat",
    "fruits or vegetables",
    "a drink or beverage",
    "a restaurant meal",
    "homemade cooking",
    
    # Scenery descriptions  
    "a beautiful landscape or nature view",
    "a sunset or sunrise",
    "mountains or hills",
    "a beach or ocean",
    "a city skyline",
    "trees and forest",
    
    # Document descriptions
    "a text document or paper",
    "a screenshot of a phone or computer",
    "handwritten notes",
    "a receipt or bill",
    "a book or printed text",
    
    # Object descriptions
    "a car or vehicle",
    "furniture or home interior",
    "electronics or gadgets",
    "clothing or fashion items",
    "art or decorative items",
    
    # Scene context
    "an indoor photo",
    "an outdoor photo",
    "a photo taken at night",
    "a blurry or low quality photo",
    "a professional photograph",
]

def load_model_and_embeddings():
    """Load ONNX model and compute embeddings for semantic descriptions"""
    print("Loading ONNX model...")
    session = ort.InferenceSession("onnx_models/mobileclip_image_encoder.onnx")
    
    # We need to compute text embeddings for the semantic descriptions
    # Since we exported only the image encoder, we'll use the Python model for text
    print("Loading MobileCLIP for text encoding...")
    import torch
    import mobileclip  # type: ignore
    
    checkpoint_path = "checkpoints/mobileclip_s0.pt"
    model, _, _ = mobileclip.create_model_and_transforms(
        'mobileclip_s0',
        pretrained=checkpoint_path
    )
    model.eval()
    
    tokenizer = mobileclip.get_tokenizer('mobileclip_s0')
    
    print(f"Computing embeddings for {len(SEMANTIC_DESCRIPTIONS)} descriptions...")
    text_tokens = tokenizer(SEMANTIC_DESCRIPTIONS)
    with torch.no_grad():
        text_features = model.encode_text(text_tokens)
        text_features = text_features / text_features.norm(dim=-1, keepdim=True)
    
    semantic_embeddings = text_features.numpy()
    print(f"✓ Semantic embeddings shape: {semantic_embeddings.shape}")
    
    return session, semantic_embeddings

def preprocess_image(img_path):
    """Preprocess image for MobileCLIP"""
    image = Image.open(img_path).convert("RGB")
    image = image.resize((224, 224))
    
    img_array = np.array(image).astype(np.float32)
    
    # Normalize with CLIP stats
    mean = np.array([0.48145466, 0.4578275, 0.40821073], dtype=np.float32)
    std = np.array([0.26862954, 0.26130258, 0.27577711], dtype=np.float32)
    img_array = (img_array / 255.0 - mean) / std
    
    # Transpose to NCHW format
    img_array = img_array.transpose(2, 0, 1)
    img_array = np.expand_dims(img_array, axis=0)
    
    return img_array

def analyze_image(session, semantic_embeddings, img_path):
    """Analyze an image and return top semantic descriptions"""
    
    # Preprocess and run inference
    img_array = preprocess_image(img_path)
    outputs = session.run(None, {"image": img_array})
    embedding = outputs[0][0]  # Remove batch dim
    
    # Calculate similarities
    similarities = embedding @ semantic_embeddings.T
    
    # Get top matches
    top_indices = np.argsort(similarities)[::-1][:10]
    
    results = []
    for idx in top_indices:
        score = similarities[idx]
        desc = SEMANTIC_DESCRIPTIONS[idx]
        results.append((desc, score))
    
    return results

def main():
    session, semantic_embeddings = load_model_and_embeddings()
    
    # Test on sample images
    test_images = [
        "../temp_emulator_photos/img1.png",
        "../temp_emulator_photos/img10.png", 
        "../temp_emulator_photos/img20.png",
        "../temp_emulator_photos/img50.png",
        "../temp_emulator_photos/img100.png",
        "../temp_emulator_photos/img150.png",
        "../temp_emulator_photos/img200.png",
        "../temp_emulator_photos/img250.png",
    ]
    
    print("\n" + "="*70)
    print("SEMANTIC IMAGE ANALYSIS")
    print("="*70)
    
    for img_path in test_images:
        if not os.path.exists(img_path):
            print(f"\n⚠ Skipping {img_path} (not found)")
            continue
        
        print(f"\n{'─'*70}")
        print(f"📷 {os.path.basename(img_path)}")
        print(f"{'─'*70}")
        
        results = analyze_image(session, semantic_embeddings, img_path)
        
        print("\nWhat MobileCLIP sees in this image:")
        for i, (desc, score) in enumerate(results[:7], 1):
            bar = "█" * int(score * 40)
            confidence = "high" if score > 0.25 else "medium" if score > 0.20 else "low"
            print(f"  {i}. {desc}")
            print(f"     Score: {score:.3f} ({confidence}) {bar}")
        
        # Summarize
        top_desc = results[0][0]
        print(f"\n  → Best match: \"{top_desc}\"")

if __name__ == "__main__":
    main()
