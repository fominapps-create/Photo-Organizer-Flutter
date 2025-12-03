"""
Test CLIP model to verify it's working correctly.
"""
import sys
import os

# Add backend to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'backend'))

from backend.clip_model import classify_image, get_clip_model

def test_clip():
    print("=" * 60)
    print("CLIP Model Test")
    print("=" * 60)
    
    print("\n1. Loading CLIP model...")
    try:
        model = get_clip_model()
        print("✓ CLIP model loaded successfully!")
        print(f"  Device: {model.device}")
        print(f"  Categories: {len(model.categories)} predefined categories")
    except Exception as e:
        print(f"✗ Failed to load CLIP model: {e}")
        return False
    
    print("\n2. Testing with sample image...")
    # Test with a sample image if available
    test_image_paths = [
        "temp/test.jpg",
        "temp/test.png",
        "../test_image.jpg",
        "test.jpg"
    ]
    
    test_image = None
    for path in test_image_paths:
        full_path = os.path.join(os.path.dirname(__file__), path)
        if os.path.exists(full_path):
            test_image = full_path
            break
    
    if test_image:
        print(f"  Testing with: {test_image}")
        try:
            tags = classify_image(test_image, confidence_threshold=0.10, max_tags=8)
            print(f"✓ Classification successful!")
            print(f"  Detected tags: {tags}")
        except Exception as e:
            print(f"✗ Classification failed: {e}")
            return False
    else:
        print("  No test image found (this is OK)")
        print("  Model is ready to classify images!")
    
    print("\n" + "=" * 60)
    print("CLIP Model Ready! 🎉")
    print("=" * 60)
    print("\nNext steps:")
    print("1. Start the server: python run_server.py")
    print("2. Test with your Flutter app")
    print("3. Enjoy better quality photo tagging!")
    print("\nNote: First run will download model (~600MB)")
    return True

if __name__ == "__main__":
    success = test_clip()
    sys.exit(0 if success else 1)
