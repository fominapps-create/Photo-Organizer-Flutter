"""
Test MobileCLIP for image classification
"""
import torch
import mobileclip
from PIL import Image
import os
import sys
import urllib.request

def download_checkpoint():
    """Download MobileCLIP checkpoint if not exists"""
    checkpoint_dir = "checkpoints"
    checkpoint_path = os.path.join(checkpoint_dir, "mobileclip_s0.pt")
    
    if os.path.exists(checkpoint_path):
        return checkpoint_path
    
    os.makedirs(checkpoint_dir, exist_ok=True)
    
    url = "https://docs-assets.developer.apple.com/ml-research/datasets/mobileclip/mobileclip_s0.pt"
    print(f"Downloading MobileCLIP checkpoint (~20MB)...")
    urllib.request.urlretrieve(url, checkpoint_path)
    print("✓ Downloaded")
    
    return checkpoint_path

def test_mobileclip():
    print("Setting up MobileCLIP...\n")
    
    # Download checkpoint if needed
    checkpoint_path = download_checkpoint()
    
    print("Loading model...")
    
    # Use S0 for fastest, S1 for balance, S2 for best quality
    model, _, preprocess = mobileclip.create_model_and_transforms(
        'mobileclip_s0',  # Smallest/fastest model
        pretrained=checkpoint_path
    )
    tokenizer = mobileclip.get_tokenizer('mobileclip_s0')
    
    model.eval()
    print("✓ Model loaded")
    
    # Our 6 categories as text prompts
    categories = [
        "a photo of a person or people",
        "a photo of an animal or pet",
        "a photo of food or a meal",
        "a photo of scenery or landscape",
        "a photo of a document or text",
        "a photo of an object or thing",
    ]
    
    category_names = ["People", "Animals", "Food", "Scenery", "Document", "Other"]
    
    # Tokenize category descriptions
    text = tokenizer(categories)
    
    # Test with sample images if available
    test_images = []
    test_dir = "../temp_emulator_photos"
    if os.path.exists(test_dir):
        # Get a mix of images from different parts of the folder
        all_files = [f for f in os.listdir(test_dir) if f.lower().endswith(('.jpg', '.jpeg', '.png'))]
        # Take images from different ranges
        indices = [0, 50, 100, 150, 200, 250, 300, 350, 400, 450]
        for idx in indices:
            if idx < len(all_files):
                test_images.append(os.path.join(test_dir, all_files[idx]))
    
    if not test_images:
        print("No test images found in temp_emulator_photos/")
        print("Please add some test images and run again.")
        return
    
    print(f"\nTesting {len(test_images)} images...\n")
    
    with torch.no_grad():
        # Encode text categories once
        text_features = model.encode_text(text)
        text_features /= text_features.norm(dim=-1, keepdim=True)
        
        for img_path in test_images:
            try:
                # Load and preprocess image
                image = preprocess(Image.open(img_path).convert("RGB")).unsqueeze(0)
                
                # Encode image
                image_features = model.encode_image(image)
                image_features /= image_features.norm(dim=-1, keepdim=True)
                
                # Calculate similarity
                similarity = (100.0 * image_features @ text_features.T).softmax(dim=-1)
                values, indices = similarity[0].topk(3)
                
                print(f"📷 {os.path.basename(img_path)}")
                for i, (value, index) in enumerate(zip(values, indices)):
                    print(f"   {i+1}. {category_names[index]}: {value.item()*100:.1f}%")
                print()
                
            except Exception as e:
                print(f"Error processing {img_path}: {e}")

if __name__ == "__main__":
    test_mobileclip()
