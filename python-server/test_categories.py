"""
Test the expanded CLIP categories with sample images or text descriptions.
"""
import sys
import os
sys.path.insert(0, os.path.dirname(__file__))

from backend.clip_model import get_clip_model, classify_image, PHOTO_CATEGORIES

def test_categories():
    """Display all available categories."""
    print("=" * 60)
    print("CLIP PHOTO CATEGORIES")
    print("=" * 60)
    
    for i, category in enumerate(PHOTO_CATEGORIES, 1):
        print(f"\n{i}. {category}")
    
    print("\n" + "=" * 60)
    print(f"Total Categories: {len(PHOTO_CATEGORIES)}")
    print("=" * 60)

def test_classification(image_path: str):
    """Test classification on a specific image."""
    if not os.path.exists(image_path):
        print(f"Error: Image not found at {image_path}")
        return
    
    print(f"\nTesting classification on: {image_path}")
    print("-" * 60)
    
    try:
        tags = classify_image(image_path, confidence_threshold=0.15, max_tags=3)
        print(f"Detected tags: {tags}")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    test_categories()
    
    # Test with image if provided
    if len(sys.argv) > 1:
        image_path = sys.argv[1]
        test_classification(image_path)
    else:
        print("\nUsage: python test_categories.py <image_path>")
        print("Example: python test_categories.py temp/screenshot.png")
