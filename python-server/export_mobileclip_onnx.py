"""
Convert MobileCLIP to ONNX format for Flutter
Uses TorchScript tracing with fixed input sizes to avoid dynamic shape issues
"""
import torch
import mobileclip
import os

class ImageEncoderWrapper(torch.nn.Module):
    """Wrapper that normalizes the output embedding"""
    def __init__(self, image_encoder):
        super().__init__()
        self.encoder = image_encoder
        
    def forward(self, x):
        features = self.encoder(x)
        # L2 normalize the output
        return features / features.norm(dim=-1, keepdim=True)

def export_to_onnx():
    print("Loading MobileCLIP model...")
    
    checkpoint_path = "checkpoints/mobileclip_s0.pt"
    model, _, preprocess = mobileclip.create_model_and_transforms(
        'mobileclip_s0',
        pretrained=checkpoint_path
    )
    model.eval()
    print("✓ Model loaded")
    
    # Wrap image encoder to include normalization
    wrapped_encoder = ImageEncoderWrapper(model.image_encoder)
    wrapped_encoder.eval()
    
    # Export image encoder only (that's what we need for classification)
    print("\nExporting image encoder to ONNX...")
    
    # Create dummy input (224x224 RGB image) - fixed size, no dynamic axes
    dummy_image = torch.randn(1, 3, 224, 224)
    
    # Export image encoder
    os.makedirs("onnx_models", exist_ok=True)
    onnx_path = "onnx_models/mobileclip_image_encoder.onnx"
    
    # Use trace-based export with fixed shapes (no dynamic axes)
    torch.onnx.export(
        wrapped_encoder,
        dummy_image,
        onnx_path,
        export_params=True,
        opset_version=12,  # Use older opset for better compatibility
        do_constant_folding=True,
        input_names=['image'],
        output_names=['embedding'],
        # No dynamic_axes - fixed batch size of 1
        dynamo=False  # Use legacy tracer
    )
    
    # Check file size
    size_mb = os.path.getsize(onnx_path) / (1024 * 1024)
    print(f"✓ Exported to {onnx_path} ({size_mb:.1f} MB)")
    
    # Now export text embeddings for our 6 categories (pre-computed)
    print("\nPre-computing category embeddings...")
    tokenizer = mobileclip.get_tokenizer('mobileclip_s0')
    
    categories = [
        "a photo of a person or people",
        "a photo of an animal or pet", 
        "a photo of food or a meal",
        "a photo of scenery or landscape",
        "a photo of a document or text",
        "a photo of an object or thing",
    ]
    
    text_tokens = tokenizer(categories)
    with torch.no_grad():
        text_features = model.encode_text(text_tokens)
        text_features = text_features / text_features.norm(dim=-1, keepdim=True)
    
    # Save as numpy for easy loading
    import numpy as np
    np.save("onnx_models/category_embeddings.npy", text_features.numpy())
    print(f"✓ Saved category embeddings ({text_features.shape})")
    
    print("\n✅ Done! Files ready for Flutter:")
    print(f"   - {onnx_path}")
    print("   - onnx_models/category_embeddings.npy")

if __name__ == "__main__":
    export_to_onnx()
