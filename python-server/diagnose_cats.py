"""
Quick diagnostic to understand why cats are tagged as unknown.
Shows YOLO detection confidence scores and CLIP fallback behavior.
"""
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from backend.yolo_clip_hybrid import get_fast_yolo_model, map_yolo_detections_to_categories
from backend.clip_model import classify_image

def diagnose_cat_photos():
    """Check cat photo detections and understand unknown tags."""
    
    test_dir = os.path.join(os.path.dirname(__file__), "temp")
    if not os.path.exists(test_dir):
        print("No temp directory found")
        return
    
    # Find images
    image_files = [
        os.path.join(test_dir, f) 
        for f in os.listdir(test_dir) 
        if f.lower().endswith(('.jpg', '.jpeg', '.png'))
    ][:10]  # First 10 images
    
    print("\n" + "="*70)
    print("CAT PHOTO DIAGNOSTIC - Why are cats tagged as 'unknown'?")
    print("="*70)
    
    # Load YOLO
    yolo_model = get_fast_yolo_model()
    
    for img_path in image_files:
        filename = os.path.basename(img_path)
        print(f"\n{filename}")
        print("-" * 70)
        
        # Run YOLO
        yolo_results = yolo_model(img_path)[0]
        
        # Check raw detections
        if yolo_results.boxes and len(yolo_results.boxes) > 0:
            print("YOLO Raw Detections:")
            for box in yolo_results.boxes:
                class_id = int(box.cls[0])
                confidence = float(box.conf[0])
                class_name = yolo_results.names[class_id]
                print(f"  - {class_name} (class {class_id}): {confidence:.2%} confidence")
        else:
            print("YOLO: No detections")
        
        # Check mapped categories
        tags, debug_info = map_yolo_detections_to_categories(yolo_results, confidence_threshold=0.60)
        
        if tags:
            print(f"\nYOLO Mapped Tags: {tags}")
            print(f"  (Max confidence: {debug_info['max_confidence']:.2%})")
        else:
            print(f"\nYOLO: No tags (confidence too low)")
            if debug_info['detections']:
                print(f"  Detections found but below threshold:")
                for det in debug_info['detections']:
                    print(f"    - {det['class']}: {det['confidence']:.2%}")
            
            # Fallback to CLIP
            print("\nCLIP Fallback:")
            clip_results = classify_image(img_path, confidence_threshold=0.70, max_tags=5)
            if clip_results:
                print(f"  Tags: {clip_results}")
            else:
                print(f"  Tags: ['unknown'] (no category above 70% threshold)")
    
    print("\n" + "="*70)
    print("DIAGNOSIS COMPLETE")
    print("="*70)
    print("\nCommon reasons cats are 'unknown':")
    print("1. YOLO detects cat with 40-59% confidence → below 60% threshold → falls to CLIP")
    print("2. CLIP analyzes cat photo but gets 60-69% for 'animals' → below 70% threshold → 'unknown'")
    print("\nSOLUTION:")
    print("- Lower YOLO animal threshold to 45% (catches more cats)")
    print("- Cats detected by YOLO at 45%+ will skip CLIP entirely")
    print("- Result: More cats properly tagged as 'animals'")

if __name__ == "__main__":
    diagnose_cat_photos()
