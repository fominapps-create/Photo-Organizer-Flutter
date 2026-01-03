"""
Export semantic embeddings for Flutter - richer descriptions than just 6 categories.
This creates a more detailed understanding of image contents.
"""
import numpy as np
import torch
import mobileclip  # type: ignore

# Semantic descriptions grouped by category
SEMANTIC_TAGS = {
    "people": [
        "a photo of a person's face",
        "a group of people together", 
        "a selfie photo",
        "a portrait of someone",
        "people at a party or event",
        "a baby or young child",
        "a family photo",
        "a person smiling",
        "a person outdoors",
    ],
    "animals": [
        "a photo of a dog",
        "a photo of a cat", 
        "a bird or flying animal",
        "a wild animal in nature",
        "a pet animal indoors",
        "a cute animal",
    ],
    "food": [
        "a plate of cooked food",
        "a dessert or sweet treat",
        "fruits or vegetables",
        "a drink or beverage",
        "a restaurant meal",
        "homemade cooking",
        "breakfast food",
        "dinner or lunch",
    ],
    "scenery": [
        "a beautiful landscape or nature view",
        "a sunset or sunrise",
        "mountains or hills",
        "a beach or ocean",
        "a city skyline",
        "trees and forest",
        "a garden with flowers",
        "a lake or river",
    ],
    "documents": [
        "a text document or paper",
        "a screenshot of a phone or computer",
        "handwritten notes",
        "a receipt or bill",
        "a book or printed text",
        "a diagram or chart",
    ],
    "other": [
        "a car or vehicle",
        "furniture or home interior",
        "electronics or gadgets",
        "clothing or fashion items",
        "art or decorative items",
        "a building or architecture",
    ],
}

def export_semantic_embeddings():
    print("Loading MobileCLIP...")
    
    checkpoint_path = "checkpoints/mobileclip_s0.pt"
    model, _, _ = mobileclip.create_model_and_transforms(
        'mobileclip_s0',
        pretrained=checkpoint_path
    )
    model.eval()
    tokenizer = mobileclip.get_tokenizer('mobileclip_s0')
    
    # Flatten all descriptions with their category
    all_descriptions = []
    category_for_desc = []
    
    for category, descriptions in SEMANTIC_TAGS.items():
        for desc in descriptions:
            all_descriptions.append(desc)
            category_for_desc.append(category)
    
    print(f"Computing embeddings for {len(all_descriptions)} semantic descriptions...")
    
    text_tokens = tokenizer(all_descriptions)
    with torch.no_grad():
        text_features = model.encode_text(text_tokens)
        text_features = text_features / text_features.norm(dim=-1, keepdim=True)
    
    embeddings = text_features.numpy()
    
    # Save embeddings
    np.save("onnx_models/semantic_embeddings.npy", embeddings)
    print(f"✓ Saved semantic embeddings: {embeddings.shape}")
    
    # Save metadata (descriptions and categories)
    import json
    metadata = {
        "descriptions": all_descriptions,
        "categories": category_for_desc,
    }
    with open("onnx_models/semantic_metadata.json", "w") as f:
        json.dump(metadata, f, indent=2)
    print(f"✓ Saved metadata for {len(all_descriptions)} descriptions")
    
    # Print summary
    print("\nSemantic tags by category:")
    for cat, descs in SEMANTIC_TAGS.items():
        print(f"  {cat}: {len(descs)} descriptions")

if __name__ == "__main__":
    export_semantic_embeddings()
