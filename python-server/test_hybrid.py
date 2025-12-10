"""
Test the YOLO+CLIP hybrid classification system.

This script tests:
1. YOLO class mapping correctness
2. Single image hybrid classification
3. Batch hybrid classification performance
4. Speed improvements vs CLIP-only
"""

import sys
import os
import time

# Add backend to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from backend.yolo_clip_hybrid import (
    classify_batch_hybrid,
    YOLO_TO_CATEGORY,
    YOLO_MIN_CONFIDENCE,
    get_fast_yolo_model
)
from backend.clip_model import classify_batch as clip_classify_batch

def print_mapping_summary():
    """Print summary of YOLO class mappings."""
    print("\n" + "="*60)
    print("YOLO TO CATEGORY MAPPING SUMMARY")
    print("="*60)
    
    categories = {}
    for class_id, category in YOLO_TO_CATEGORY.items():
        if category not in categories:
            categories[category] = []
        categories[category].append(class_id)
    
    for category, class_ids in sorted(categories.items()):
        print(f"\n{category.upper()}: {len(class_ids)} YOLO classes")
        print(f"  Class IDs: {sorted(class_ids)}")
    
    print(f"\nTotal mapped classes: {len(YOLO_TO_CATEGORY)}")
    print(f"Unmapped classes: {80 - len(YOLO_TO_CATEGORY)} (will use CLIP fallback)")
    print(f"YOLO confidence threshold: {YOLO_MIN_CONFIDENCE} (lower for nano model)")
    print("="*60)


def test_hybrid_vs_clip_only(test_images_folder: str = "temp"):
    """
    Test hybrid approach vs CLIP-only on sample images.
    
    Args:
        test_images_folder: Folder containing test images
    """
    print("\n" + "="*60)
    print("PERFORMANCE TEST: YOLO+CLIP Hybrid vs CLIP-Only")
    print("="*60)
    
    # Find test images
    test_dir = os.path.join(os.path.dirname(__file__), test_images_folder)
    if not os.path.exists(test_dir):
        print(f"\n⚠️  Test folder not found: {test_dir}")
        print("Please place some test images in the 'temp' folder.")
        return
    
    image_files = [
        os.path.join(test_dir, f) 
        for f in os.listdir(test_dir) 
        if f.lower().endswith(('.jpg', '.jpeg', '.png'))
    ]
    
    if not image_files:
        print(f"\n⚠️  No images found in {test_dir}")
        return
    
    print(f"\nFound {len(image_files)} test images")
    
    # Load models
    print("\nLoading models...")
    yolo_model = get_fast_yolo_model()
    print("  ✓ YOLO nano model loaded")
    
    # Test 1: CLIP-only (baseline)
    print("\n" + "-"*60)
    print("TEST 1: CLIP-Only Classification (baseline)")
    print("-"*60)
    
    t0 = time.time()
    clip_results = clip_classify_batch(image_files, confidence_threshold=0.70, max_tags=5)
    t1 = time.time()
    
    clip_time_ms = round((t1 - t0) * 1000, 1)
    clip_avg_ms = round(clip_time_ms / len(image_files), 1)
    
    print(f"CLIP-only results:")
    for img, tags in zip(image_files, clip_results):
        print(f"  {os.path.basename(img)}: {tags}")
    
    print(f"\nCLIP-only timing:")
    print(f"  Total: {clip_time_ms}ms")
    print(f"  Average: {clip_avg_ms}ms per image")
    print(f"  Speed: {round(1000 / clip_avg_ms, 1)} images/second")
    
    # Test 2: YOLO+CLIP Hybrid
    print("\n" + "-"*60)
    print("TEST 2: YOLO+CLIP Hybrid Classification")
    print("-"*60)
    
    t2 = time.time()
    hybrid_results, stats = classify_batch_hybrid(
        image_files,
        yolo_model=yolo_model,
        clip_batch_func=clip_classify_batch,
        yolo_confidence=0.60,  # Lower for nano model
        clip_threshold=0.70,
        max_tags=5
    )
    t3 = time.time()
    
    hybrid_time_ms = round((t3 - t2) * 1000, 1)
    hybrid_avg_ms = round(hybrid_time_ms / len(image_files), 1)
    
    print(f"Hybrid results:")
    for img, tags in zip(image_files, hybrid_results):
        print(f"  {os.path.basename(img)}: {tags}")
    
    print(f"\nHybrid timing:")
    print(f"  Total: {hybrid_time_ms}ms")
    print(f"  Average: {hybrid_avg_ms}ms per image")
    print(f"  Speed: {round(1000 / hybrid_avg_ms, 1)} images/second")
    print(f"\nHybrid breakdown:")
    print(f"  YOLO success: {stats['yolo_success']}/{stats['total_images']} ({round(100*stats['yolo_success']/stats['total_images'], 1)}%)")
    print(f"  YOLO time: {stats['yolo_time_ms']}ms")
    print(f"  CLIP fallback: {stats['clip_fallback']} images")
    print(f"  CLIP time: {stats['clip_time_ms']}ms")
    
    # Performance comparison
    print("\n" + "="*60)
    print("PERFORMANCE COMPARISON")
    print("="*60)
    
    speedup = round(clip_time_ms / hybrid_time_ms, 2)
    time_saved_ms = clip_time_ms - hybrid_time_ms
    time_saved_pct = round(100 * time_saved_ms / clip_time_ms, 1)
    
    print(f"CLIP-only:  {clip_time_ms}ms ({clip_avg_ms}ms/img) = {round(1000/clip_avg_ms, 1)} img/s")
    print(f"Hybrid:     {hybrid_time_ms}ms ({hybrid_avg_ms}ms/img) = {round(1000/hybrid_avg_ms, 1)} img/s")
    print(f"\nSpeedup: {speedup}x faster")
    print(f"Time saved: {time_saved_ms}ms ({time_saved_pct}%)")
    
    # Tag comparison
    print("\n" + "-"*60)
    print("TAG COMPARISON")
    print("-"*60)
    
    matches = 0
    differences = 0
    
    for img, clip_tags, hybrid_tags in zip(image_files, clip_results, hybrid_results):
        clip_set = set(clip_tags)
        hybrid_set = set(hybrid_tags)
        
        if clip_set == hybrid_set:
            matches += 1
            print(f"✓ {os.path.basename(img)}: Identical ({clip_tags})")
        else:
            differences += 1
            print(f"✗ {os.path.basename(img)}:")
            print(f"    CLIP:   {clip_tags}")
            print(f"    Hybrid: {hybrid_tags}")
            print(f"    Only in CLIP: {list(clip_set - hybrid_set)}")
            print(f"    Only in Hybrid: {list(hybrid_set - clip_set)}")
    
    print(f"\nTag accuracy:")
    print(f"  Identical: {matches}/{len(image_files)} ({round(100*matches/len(image_files), 1)}%)")
    print(f"  Different: {differences}/{len(image_files)}")
    
    print("\n" + "="*60)
    print("TEST COMPLETE")
    print("="*60)
    
    # Projected performance at scale
    print(f"\nProjected performance for 5711 photos:")
    print(f"  CLIP-only: {round(5711 * clip_avg_ms / 1000, 1)} seconds ({round(5711 * clip_avg_ms / 60000, 1)} minutes)")
    print(f"  Hybrid:    {round(5711 * hybrid_avg_ms / 1000, 1)} seconds ({round(5711 * hybrid_avg_ms / 60000, 1)} minutes)")
    print(f"  Time saved: {round(5711 * (clip_avg_ms - hybrid_avg_ms) / 60000, 1)} minutes")


if __name__ == "__main__":
    print("\n" + "="*60)
    print("YOLO+CLIP HYBRID CLASSIFICATION TEST")
    print("="*60)
    
    # Show mapping summary
    print_mapping_summary()
    
    # Test performance
    test_hybrid_vs_clip_only()
