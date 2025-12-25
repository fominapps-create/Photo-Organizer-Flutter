"""
YOLO+CLIP Hybrid Classification System

This module provides a fast hybrid approach that uses YOLO as a first-pass filter
before falling back to the slower CLIP model.

IMPORTANT: For hybrid mode to be faster than CLIP-only, YOLO must run quickly.
On CPU, use yolov8n.pt (nano model) which runs at 15-30ms per image.
On GPU, any YOLO model will be fast enough (5-10ms).

Current performance on CPU:
- yolov8n.pt (nano): ~20-30ms per image - GOOD for hybrid
- yolov8x.pt (xlarge): ~250-330ms per image - TOO SLOW, hybrid will be slower than CLIP

Strategy:
1. Run fast YOLO (nano model on CPU or any model on GPU)
2. Map YOLO detections to our 5 categories (people, animals, food, scenery, document)
3. If YOLO succeeds -> return tags immediately
4. If YOLO fails -> fallback to CLIP for conceptual understanding

Expected performance (with yolov8n.pt on CPU):
- YOLO success rate: 40-60% of photos
- Average time per image: ~100ms (vs 170ms CLIP-only)
- Target speed: 10 img/s (vs 5-6 img/s currently)
"""

import logging
import time
from typing import List, Tuple, Set
from ultralytics import YOLO
from .config import MIN_BOX_PERCENT, MIN_PERSON_PERCENT

logger = logging.getLogger(__name__)

# Fast YOLO model for hybrid classification
_hybrid_yolo_model = None

def get_fast_yolo_model():
    """
    Get or load the fast YOLO model (nano) for hybrid classification.
    This is separate from the main YOLO model to ensure we use the fastest version.
    """
    global _hybrid_yolo_model
    if _hybrid_yolo_model is None:
        logger.info("Loading yolov8n.pt (nano model) for hybrid classification...")
        _hybrid_yolo_model = YOLO("yolov8n.pt")
        logger.info("Fast YOLO model loaded successfully")
    return _hybrid_yolo_model

# YOLO class ID to category mapping
# Based on COCO dataset 80 classes
YOLO_TO_CATEGORY = {
    # PEOPLE (class 0)
    0: "people",  # person
    
    # ANIMALS (classes 14-23)
    14: "animals",  # bird
    15: "animals",  # cat
    16: "animals",  # dog
    17: "animals",  # horse
    18: "animals",  # sheep
    19: "animals",  # cow
    20: "animals",  # elephant
    21: "animals",  # bear
    22: "animals",  # zebra
    23: "animals",  # giraffe
    
    # FOOD (classes 46-60) - Only ACTUAL food items, not accessories
    # This prevents a bowl or cup from overriding a cat photo!
    46: "food",  # banana
    47: "food",  # apple
    48: "food",  # sandwich
    49: "food",  # orange
    50: "food",  # broccoli
    51: "food",  # carrot
    52: "food",  # hot dog
    53: "food",  # pizza
    54: "food",  # donut
    55: "food",  # cake
    
    # NOTE: Food accessories (bowl, cup, fork, etc.) are NOT mapped to "food"
    # because they often appear in pet photos and would incorrectly override
    # the animal category. These are still captured in all_detections for search.
    
    # DOCUMENT-like objects (but keep confidence low - let CLIP handle most documents)
    # We'll be conservative here since YOLO can't detect "text document with visible writing"
    73: "document",  # book (only if high confidence)
}

# Minimum confidence for YOLO detections
# Lower threshold since we're using nano model which may have lower confidence
YOLO_MIN_CONFIDENCE = 0.60  # Default for most categories

# Category-specific confidence thresholds
ANIMAL_MIN_CONFIDENCE = 0.45  # Lower for animals (cats/dogs often have lower confidence)
FOOD_RELATED_MIN_CONFIDENCE = 0.80  # Higher to reduce false positives (e.g., fox mascots tagged as food!)
PEOPLE_MIN_CONFIDENCE = 0.50  # Moderate for people detection


def map_yolo_detections_to_categories(yolo_results, confidence_threshold: float = YOLO_MIN_CONFIDENCE) -> Tuple[List[str], dict]:
    """
    Map YOLO detection results to our 5 categories.
    Returns only the DOMINANT category based on weighted score (confidence * area).
    
    Args:
        yolo_results: YOLO model inference results
        confidence_threshold: Minimum confidence for accepting detections
        
    Returns:
        Tuple of (category_list, debug_info_dict)
        - category_list: List with single dominant category (or empty if nothing found)
        - debug_info: Dict with detection details for logging
    """
    all_objects = set()  # All detected objects regardless of size
    debug_info = {
        "detections": [],
        "mapped_categories": [],
        "all_objects": [],
        "max_confidence": 0.0,
    }
    
    # Track category with highest weighted score (confidence * area)
    category_scores = {}  # category -> weighted_score
    
    if not yolo_results or not hasattr(yolo_results, 'boxes') or yolo_results.boxes is None:
        return [], debug_info
    
    boxes = yolo_results.boxes
    if len(boxes) == 0:
        return [], debug_info
    
    # Get image dimensions for size filtering
    img_height, img_width = yolo_results.orig_shape if hasattr(yolo_results, 'orig_shape') else (1, 1)
    image_area = img_width * img_height
    
    # Process each detection
    for box in boxes:
        class_id = int(box.cls[0])
        confidence = float(box.conf[0])
        class_name = yolo_results.names[class_id] if hasattr(yolo_results, 'names') else f"class_{class_id}"
        
        # Calculate bounding box area to filter out tiny objects
        xyxy = box.xyxy[0]  # [x1, y1, x2, y2]
        box_width = float(xyxy[2] - xyxy[0])
        box_height = float(xyxy[3] - xyxy[1])
        box_area = box_width * box_height
        box_percent = box_area / image_area if image_area > 0 else 0
        
        debug_info["detections"].append({
            "class": class_name,
            "class_id": class_id,
            "confidence": confidence,
            "box_percent": round(box_percent * 100, 1)
        })
        
        debug_info["max_confidence"] = max(debug_info["max_confidence"], confidence)
        
        # Capture ALL detected objects for search (chairs, tables, etc.) with basic threshold
        # This allows searching for any YOLO-detected object, not just our main categories
        if confidence >= confidence_threshold and box_percent >= MIN_BOX_PERCENT:
            all_objects.add(class_name.lower())
        
        # Check if this class maps to a main category (people, animals, food, document)
        if class_id in YOLO_TO_CATEGORY:
            category = YOLO_TO_CATEGORY[class_id]
            
            # Use appropriate confidence threshold based on category
            min_conf = confidence_threshold
            
            # Animals (cats, dogs, etc.) - lower threshold as they often have lower confidence
            if class_id in [14, 15, 16, 17, 18, 19, 20, 21, 22, 23]:  # Animal classes
                min_conf = ANIMAL_MIN_CONFIDENCE
            # Food and food-related items (all food classes need higher threshold)
            elif class_id in [39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55]:
                min_conf = FOOD_RELATED_MIN_CONFIDENCE
            # People
            elif class_id == 0:  # Person
                min_conf = PEOPLE_MIN_CONFIDENCE
            
            if confidence >= min_conf:
                # Also add to all_objects if it passes stricter category threshold
                all_objects.add(class_name.lower())
                
                # Filter out objects that are too small for main tags
                min_size = MIN_PERSON_PERCENT if class_id == 0 else MIN_BOX_PERCENT
                if box_percent < min_size:
                    logger.debug(f"Including {class_name} in all_objects but not main tags - too small ({round(box_percent*100, 1)}% < {round(min_size*100, 1)}%)")
                    debug_info["all_objects"].append(class_name.lower())
                    continue
                
                # Weighted score = confidence * box_percent (both 0-1 range)
                weighted_score = confidence * box_percent
                if category not in category_scores:
                    category_scores[category] = 0.0
                category_scores[category] += weighted_score
                
                debug_info["mapped_categories"].append({
                    "category": category,
                    "from_class": class_name,
                    "confidence": confidence,
                    "box_percent": round(box_percent * 100, 1),
                    "weighted_score": round(weighted_score * 100, 2)
                })
                debug_info["all_objects"].append(class_name.lower())
    
    # Return only the dominant category with priority consideration
    # Priority: people > animals > food > document > other
    # This ensures a cat isn't tagged as "food" just because there's a bowl nearby
    CATEGORY_PRIORITY = {
        "people": 4,
        "animals": 3,
        "food": 2,
        "document": 1,
    }
    
    if category_scores:
        # Sort by priority first, then by weighted score
        def sort_key(cat):
            priority = CATEGORY_PRIORITY.get(cat, 0)
            score = category_scores[cat]
            return (priority, score)
        
        dominant_category = max(category_scores.keys(), key=sort_key)
        result = [dominant_category]
        logger.debug(f"Category scores: {category_scores} -> Dominant: {dominant_category} (priority-based)")
    else:
        result = []
    
    debug_info["all_objects_list"] = list(all_objects)
    debug_info["category_scores"] = {k: round(v * 100, 2) for k, v in category_scores.items()}
    return result, debug_info


def classify_image_hybrid(image_path: str, yolo_model, clip_classifier_func, 
                         yolo_confidence: float = YOLO_MIN_CONFIDENCE,
                         clip_threshold: float = 0.70) -> Tuple[List[str], dict]:
    """
    Classify a single image using YOLO+CLIP hybrid approach.
    
    Args:
        image_path: Path to image file
        yolo_model: Loaded YOLO model
        clip_classifier_func: Function to call CLIP (signature: func(image_path, threshold) -> List[str])
        yolo_confidence: Minimum confidence for YOLO detections
        clip_threshold: Confidence threshold for CLIP fallback
        
    Returns:
        Tuple of (tags_list, timing_info_dict)
    """
    timing = {
        "yolo_ms": 0,
        "clip_ms": 0,
        "total_ms": 0,
        "method": "unknown"
    }
    
    t_start = time.time()
    
    # Step 1: Try YOLO (fast)
    t0 = time.time()
    try:
        yolo_results = yolo_model(image_path)[0]
        t1 = time.time()
        timing["yolo_ms"] = round((t1 - t0) * 1000, 1)
        
        # Map YOLO detections to categories
        tags, debug_info = map_yolo_detections_to_categories(yolo_results, yolo_confidence)
        
        if tags:
            # YOLO succeeded - return immediately
            timing["method"] = "yolo"
            timing["total_ms"] = timing["yolo_ms"]
            
            logger.debug(f"YOLO success for {image_path}: {tags} ({timing['yolo_ms']}ms)")
            logger.debug(f"  Detections: {debug_info['mapped_categories']}")
            
            return tags, timing
        else:
            # YOLO found objects but none mapped to our categories
            logger.debug(f"YOLO found objects but no category match: {debug_info['detections']}")
            
    except Exception as e:
        t1 = time.time()
        timing["yolo_ms"] = round((t1 - t0) * 1000, 1)
        logger.warning(f"YOLO error for {image_path}: {e}")
    
    # Step 2: YOLO failed - fallback to CLIP (slow but accurate)
    t2 = time.time()
    try:
        tags = clip_classifier_func(image_path, clip_threshold)
        t3 = time.time()
        timing["clip_ms"] = round((t3 - t2) * 1000, 1)
        timing["method"] = "clip_fallback"
        timing["total_ms"] = round((t3 - t_start) * 1000, 1)
        
        logger.debug(f"CLIP fallback for {image_path}: {tags} ({timing['clip_ms']}ms, total {timing['total_ms']}ms)")
        
        return tags, timing
        
    except Exception as e:
        t3 = time.time()
        timing["clip_ms"] = round((t3 - t2) * 1000, 1)
        timing["total_ms"] = round((t3 - t_start) * 1000, 1)
        logger.error(f"CLIP error for {image_path}: {e}")
        # Return "Other" instead of empty list - ensures every photo has at least one tag
        return ["Other"], timing


def classify_batch_hybrid(image_paths: List[str], yolo_model=None, clip_batch_func=None,
                         yolo_confidence: float = YOLO_MIN_CONFIDENCE,
                         clip_threshold: float = 0.70,
                         max_tags: int = 5) -> Tuple[List[List[str]], List[List[str]], dict]:
    """
    Classify a batch of images using YOLO+CLIP hybrid approach.
    
    This is more efficient than processing sequentially because:
    1. YOLO can be called individually (very fast anyway at 15-30ms with nano model)
    2. Only images that failed YOLO are batched for CLIP (much faster than sequential CLIP)
    
    Args:
        image_paths: List of image file paths
        yolo_model: YOLO model to use (if None, will load fast nano model automatically)
        clip_batch_func: Function to batch process with CLIP 
                        (signature: func(image_paths, threshold, max_tags) -> List[List[str]])
        yolo_confidence: Minimum confidence for YOLO detections
        clip_threshold: Confidence threshold for CLIP
        max_tags: Maximum tags per image
        
    Returns:
        Tuple of (results_list, all_detections_list, stats_dict)
        - results_list: List of tag lists (one per input image, in same order)
        - all_detections_list: List of all object detections including small ones
        - stats: Performance statistics
    """
    t_start = time.time()
    
    # Use fast nano model if no model provided
    if yolo_model is None:
        yolo_model = get_fast_yolo_model()
    
    results = [None] * len(image_paths)  # Preserve order
    all_detections = [None] * len(image_paths)  # All detected objects
    clip_needed_indices = []  # Track which images need CLIP
    clip_needed_paths = []
    
    stats = {
        "total_images": len(image_paths),
        "yolo_success": 0,
        "clip_fallback": 0,
        "yolo_time_ms": 0,
        "clip_time_ms": 0,
        "total_time_ms": 0,
        "avg_time_per_image_ms": 0,
    }
    
    # Phase 1: Try YOLO for all images (fast, sequential is fine)
    t0 = time.time()
    for idx, image_path in enumerate(image_paths):
        try:
            yolo_results = yolo_model(image_path)[0]
            tags, debug_info = map_yolo_detections_to_categories(yolo_results, yolo_confidence)
            
            if tags:
                # YOLO succeeded
                results[idx] = tags[:max_tags]
                # Store all detections for search
                all_detections[idx] = debug_info.get("all_objects_list", tags[:max_tags])
                stats["yolo_success"] += 1
            else:
                # Need CLIP fallback but still store any all_objects detected
                all_detections[idx] = debug_info.get("all_objects_list", [])
                clip_needed_indices.append(idx)
                clip_needed_paths.append(image_path)
                
        except Exception as e:
            logger.warning(f"YOLO error for {image_path}: {e}")
            all_detections[idx] = []
            clip_needed_indices.append(idx)
            clip_needed_paths.append(image_path)
    
    t1 = time.time()
    stats["yolo_time_ms"] = round((t1 - t0) * 1000, 1)
    
    # Phase 2: Batch process remaining images with CLIP
    if clip_needed_paths:
        t2 = time.time()
        try:
            clip_results = clip_batch_func(clip_needed_paths, clip_threshold, max_tags)
            
            # Map CLIP results back to original indices
            for clip_idx, original_idx in enumerate(clip_needed_indices):
                results[original_idx] = clip_results[clip_idx]
                # For CLIP-only results, all_detections same as tags
                if not all_detections[original_idx]:
                    all_detections[original_idx] = clip_results[clip_idx]
                stats["clip_fallback"] += 1
                
        except Exception as e:
            logger.error(f"CLIP batch error: {e}")
            # Fill failed images with "Other" tag instead of empty
            for original_idx in clip_needed_indices:
                if results[original_idx] is None:
                    results[original_idx] = ["Other"]
                if all_detections[original_idx] is None:
                    all_detections[original_idx] = ["Other"]
        
        t3 = time.time()
        stats["clip_time_ms"] = round((t3 - t2) * 1000, 1)
    
    # Ensure no None values in results - use "Other" for failed classifications
    for idx in range(len(results)):
        if results[idx] is None or results[idx] == []:
            results[idx] = ["Other"]
        if all_detections[idx] is None or all_detections[idx] == []:
            all_detections[idx] = ["Other"]
    
    # Calculate final stats
    t_end = time.time()
    stats["total_time_ms"] = round((t_end - t_start) * 1000, 1)
    stats["avg_time_per_image_ms"] = round(stats["total_time_ms"] / len(image_paths), 1)
    
    # Log performance summary
    yolo_pct = round(100 * stats["yolo_success"] / stats["total_images"], 1)
    logger.info(f"Hybrid batch: {stats['total_images']} images in {stats['total_time_ms']}ms "
               f"({stats['avg_time_per_image_ms']}ms/img)")
    logger.info(f"  YOLO: {stats['yolo_success']} success ({yolo_pct}%) in {stats['yolo_time_ms']}ms")
    logger.info(f"  CLIP: {stats['clip_fallback']} fallback in {stats['clip_time_ms']}ms")
    
    return results, all_detections, stats


def validate_yolo_with_clip(image_path: str, yolo_tags: List[str], 
                            clip_classifier_func, clip_threshold: float = 0.70,
                            confidence_diff_threshold: float = 0.20) -> dict:
    """
    Validate YOLO classification by running CLIP and comparing results.
    
    This helps identify cases where:
    - YOLO correctly detected objects but missed semantic context
    - YOLO confidence was borderline and CLIP has higher confidence in different category
    - YOLO false positives
    
    Args:
        image_path: Path to image file
        yolo_tags: Tags returned by YOLO
        clip_classifier_func: Function to call CLIP (signature: func(image_path, threshold) -> List[str])
        clip_threshold: Base threshold for CLIP (we'll use a lower threshold for validation)
        confidence_diff_threshold: Minimum confidence difference to override YOLO (default 20%)
        
    Returns:
        Dict with validation results:
        {
            "agreement": bool,  # Do YOLO and CLIP agree?
            "clip_tags": List[str],  # Tags from CLIP
            "should_override": bool,  # Should we override YOLO with CLIP?
            "override_tags": List[str],  # Recommended tags if override
            "clip_time_ms": float,
            "reason": str  # Explanation of decision
        }
    """
    t0 = time.time()
    
    result = {
        "agreement": False,
        "clip_tags": [],
        "should_override": False,
        "override_tags": [],
        "clip_time_ms": 0,
        "reason": ""
    }
    
    try:
        # Run CLIP with LOWER threshold for validation (more permissive to catch disagreements)
        validation_threshold = max(0.40, clip_threshold - 0.20)  # 20% lower, but minimum 40%
        clip_tags = clip_classifier_func(image_path, validation_threshold)
        
        t1 = time.time()
        result["clip_time_ms"] = round((t1 - t0) * 1000, 1)
        result["clip_tags"] = clip_tags
        
        # Check for agreement
        yolo_set = set(yolo_tags)
        clip_set = set(clip_tags)
        
        if yolo_set == clip_set:
            result["agreement"] = True
            result["reason"] = "Perfect agreement"
            return result
        
        # Check for overlap
        overlap = yolo_set & clip_set
        if overlap and len(overlap) >= len(yolo_set) * 0.5:
            result["agreement"] = True
            result["reason"] = f"Partial agreement: {overlap}"
            return result
        
        # Disagreement detected
        result["agreement"] = False
        
        # YOLO is better at object detection (people, animals, food)
        # CLIP is better at scene/context classification (scenery, document)
        # NEVER let CLIP remove YOLO's object detections
        # CLIP can only ADD complementary tags
        
        yolo_object_categories = {'people', 'animals', 'food'}
        has_yolo_objects = yolo_set & yolo_object_categories
        
        if clip_tags:
            # Re-run CLIP with NORMAL threshold to check if it's confident
            # Pass yolo_tags as expected_tags to enable dynamic threshold search
            clip_confident_tags = clip_classifier_func(image_path, clip_threshold, expected_tags=yolo_tags)
            
            logger.info(f"🔍 Validation check: YOLO={yolo_tags}, CLIP_low={clip_tags}, CLIP_high={clip_confident_tags}")
            
            # CRITICAL: Never override with empty or None
            if not clip_confident_tags or len(clip_confident_tags) == 0:
                # CLIP couldn't find anything confident - keep YOLO's detection
                result["should_override"] = False
                result["override_tags"] = []
                result["reason"] = f"CLIP found nothing confident. Keeping YOLO tags: {yolo_tags}"
                logger.info(f"✅ Keeping YOLO tags (CLIP empty): {yolo_tags}")
            elif has_yolo_objects:
                # YOLO detected objects (people/animals/food)
                # NEVER remove these - YOLO is authoritative for objects
                # CLIP can only add scene/context tags (NOT unknown)
                clip_set_confident = set(clip_confident_tags)
                clip_scene_tags = clip_set_confident - yolo_object_categories
                
                # Remove "other" from scene tags - if YOLO detected something, it's not other
                clip_scene_tags.discard('other')
                
                if clip_scene_tags:
                    # CLIP found complementary scene tags - COMBINE with YOLO
                    combined_tags = list(yolo_set | clip_scene_tags)
                    result["should_override"] = True
                    result["override_tags"] = combined_tags
                    result["reason"] = f"Adding CLIP scene tags to YOLO objects: {yolo_tags} + {list(clip_scene_tags)}"
                    logger.info(f"➕ Validation enhancement: {yolo_tags} + {list(clip_scene_tags)} = {combined_tags}")
                else:
                    # CLIP only found object tags - trust YOLO for objects
                    result["should_override"] = False
                    result["override_tags"] = []
                    result["reason"] = f"YOLO objects are authoritative. Keeping: {yolo_tags}"
                    logger.info(f"✅ Keeping YOLO objects (authoritative): {yolo_tags}")
            else:
                # No YOLO objects detected - CLIP can replace freely
                result["should_override"] = True
                result["override_tags"] = clip_confident_tags
                result["reason"] = f"No YOLO objects. Using CLIP: {clip_confident_tags}"
                logger.info(f"🔄 Validation override (no YOLO objects): {yolo_tags} -> {clip_confident_tags}")
        else:
            # CLIP found nothing even at low threshold
            # Keep YOLO tags - YOLO is better at object detection
            result["should_override"] = False
            result["override_tags"] = []  # Explicitly empty
            result["reason"] = f"CLIP found nothing, keeping YOLO tags: {yolo_tags}"
            logger.info(f"✅ Keeping YOLO tags (CLIP found nothing): {yolo_tags}")
        
        return result
        
    except Exception as e:
        t1 = time.time()
        result["clip_time_ms"] = round((t1 - t0) * 1000, 1)
        result["reason"] = f"Validation error: {e}"
        logger.error(f"Validation error for {image_path}: {e}")
        return result


def validate_batch_with_clip(image_paths: List[str], yolo_tags_list: List[List[str]],
                             clip_batch_func, clip_threshold: float = 0.70) -> List[dict]:
    """
    Validate a batch of YOLO classifications with CLIP.
    
    Args:
        image_paths: List of image paths
        yolo_tags_list: List of YOLO tags for each image (parallel to image_paths)
        clip_batch_func: Function to batch process with CLIP
        clip_threshold: Confidence threshold for CLIP
        
    Returns:
        List of validation results (one per image)
    """
    # For now, validate sequentially (could optimize with true batching later)
    from .clip_switcher import classify_image as clip_classify_single
    
    results = []
    for image_path, yolo_tags in zip(image_paths, yolo_tags_list):
        validation = validate_yolo_with_clip(
            image_path, 
            yolo_tags,
            clip_classify_single,
            clip_threshold
        )
        results.append(validation)
    
    return results
