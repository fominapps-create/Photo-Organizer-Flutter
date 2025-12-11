"""
CLIP-based image classification for photo organization.
Provides better quality and more intuitive tagging than YOLO for general photos.
"""
import torch
from PIL import Image
from transformers import CLIPProcessor, CLIPModel
import logging

logger = logging.getLogger(__name__)

# Simplified categories for speed - short prompts process much faster
# Document: text pages, forms, receipts, printed text
PHOTO_CATEGORIES = [
    "people",
    "animals",
    "food",
    "scenery",
    "text document with visible writing",
]


class CLIPPhotoClassifier:
    """CLIP-based photo classifier for intelligent tagging."""
    
    def __init__(self, model_name="openai/clip-vit-base-patch32"):
        """
        Initialize CLIP model.
        
        Args:
            model_name: Hugging Face model identifier. Default uses base model for speed.
                       Use "openai/clip-vit-large-patch14" for better accuracy (slower).
        """
        logger.info(f"Loading CLIP model: {model_name}")
        self.model = CLIPModel.from_pretrained(model_name)
        self.processor = CLIPProcessor.from_pretrained(model_name)
        self.categories = PHOTO_CATEGORIES
        
        # Move to GPU if available
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        self.model.to(self.device)
        logger.info(f"CLIP model loaded on {self.device}")
    
    def classify_image(self, image_path: str, confidence_threshold: float = 0.15, max_tags: int = 5, 
                      expected_tags: list = None):
        """
        Classify image and return relevant tags.
        
        Args:
            image_path: Path to image file
            confidence_threshold: Minimum confidence score (0-1) to include tag
            max_tags: Maximum number of tags to return
            expected_tags: If provided, will try progressively lower thresholds to find these tags
            
        Returns:
            List of tuples: [(tag, confidence), ...]
        """
        try:
            # Load and process image
            image = Image.open(image_path).convert("RGB")
            
            # Prepare inputs for CLIP
            inputs = self.processor(
                text=self.categories,
                images=image,
                return_tensors="pt",
                padding=True
            )
            
            # Move to device
            inputs = {k: v.to(self.device) for k, v in inputs.items()}
            
            # Get predictions
            with torch.no_grad():
                outputs = self.model(**inputs)
                logits_per_image = outputs.logits_per_image
                probs = logits_per_image.softmax(dim=1)[0]
            
            # Map category indices to clean names
            category_names = [
                "people", "animals", "food", "scenery",
                "document"
            ]
            
            # Build all scores for dynamic threshold adjustment
            all_scores = []
            for idx, prob in enumerate(probs):
                tag_name = category_names[idx] if idx < len(category_names) else "other"
                if tag_name != "other":
                    all_scores.append((tag_name, float(prob)))
            
            # Sort by confidence
            all_scores.sort(key=lambda x: x[1], reverse=True)
            
            # If expected_tags provided, try to find them with dynamic thresholds
            if expected_tags:
                # Try progressively lower thresholds: 0.80 -> 0.70 -> 0.60 -> 0.50 -> 0.40 -> 0.30 -> 0.20
                for threshold_attempt in [0.80, 0.70, 0.60, 0.50, 0.40, 0.30, 0.20]:
                    found_tags = [
                        (tag, score) for tag, score in all_scores 
                        if score >= threshold_attempt and tag in expected_tags
                    ]
                    if found_tags:
                        logger.info(f"Found expected tags {expected_tags} at threshold {threshold_attempt}: {found_tags}")
                        return found_tags[:max_tags]
                
                # If expected tags not found even at 0.20, log it and continue with normal logic
                logger.warning(f"Expected tags {expected_tags} not found even at threshold 0.20. Top scores: {all_scores[:3]}")
            
            # Normal classification with category-specific thresholds
            category_thresholds = {
                "food": 0.80,
                "document": 0.70,
                "animals": 0.70,
                "people": 0.80,
                "scenery": 0.70,
            }
            
            results = []
            for tag_name, prob in all_scores:
                required_threshold = category_thresholds.get(tag_name, confidence_threshold)
                if prob >= required_threshold:
                    results.append((tag_name, prob))
            
            # If no categories matched, tag as 'unknown' and log why
            if not results:
                logger.warning(f"No categories matched for {image_path}. Top scores: {all_scores[:3]}")
                results.append(("unknown", 0.0))
            
            # Sort by confidence and limit
            results.sort(key=lambda x: x[1], reverse=True)
            results = results[:max_tags]
            
            logger.info(f"Classified {image_path}: {[tag for tag, _ in results]}")
            return results
            
        except Exception as e:
            logger.error(f"Error classifying {image_path}: {e}")
            return []
    
    def classify_batch(self, image_paths: list, confidence_threshold: float = 0.15, max_tags: int = 5):
        """
        Classify multiple images in batch for better performance.
        
        Args:
            image_paths: List of image file paths
            confidence_threshold: Minimum confidence score
            max_tags: Maximum tags per image
            
        Returns:
            List of results, one per image: [[(tag, conf), ...], ...]
        """
        try:
            # Load all images
            images = []
            valid_paths = []
            for path in image_paths:
                try:
                    img = Image.open(path).convert("RGB")
                    images.append(img)
                    valid_paths.append(path)
                except Exception as e:
                    logger.warning(f"Failed to load {path}: {e}")
            
            if not images:
                return [[] for _ in image_paths]
            
            # Process batch
            inputs = self.processor(
                text=self.categories,
                images=images,
                return_tensors="pt",
                padding=True
            )
            
            inputs = {k: v.to(self.device) for k, v in inputs.items()}
            
            # Get predictions for all images
            with torch.no_grad():
                outputs = self.model(**inputs)
                logits_per_image = outputs.logits_per_image
                probs = logits_per_image.softmax(dim=1)
            
            # Map category indices to clean names
            category_names = [
                "people", "animals", "food", "scenery",
                "document"
            ]
            
            # Strict thresholds to minimize false positives
            # Higher for food and people (80%) to avoid misclassification
            category_thresholds = {
                "food": 0.80,
                "document": 0.70,
                "animals": 0.70,
                "people": 0.80,
                "scenery": 0.70,
            }
            
            # Process results for each image
            batch_results = []
            for img_idx, image_probs in enumerate(probs):
                results = []
                for idx, prob in enumerate(image_probs):
                    tag_name = category_names[idx] if idx < len(category_names) else "other"
                    
                    # Skip 'other' tag
                    if tag_name == "other":
                        continue
                    
                    # Apply category-specific threshold
                    required_threshold = category_thresholds.get(tag_name, confidence_threshold)
                    
                    if prob >= required_threshold:
                        results.append((tag_name, float(prob)))
                
                # If no categories matched, tag as 'unknown'
                if not results:
                    results.append(("unknown", 0.0))
                
                results.sort(key=lambda x: x[1], reverse=True)
                results = results[:max_tags]
                batch_results.append(results)
                
                if img_idx < len(valid_paths):
                    logger.info(f"Batch classified {valid_paths[img_idx]}: {[tag for tag, _ in results]}")
            
            return batch_results
            
        except Exception as e:
            logger.error(f"Error in batch classification: {e}")
            return [[] for _ in image_paths]
    
    def get_tags_only(self, image_path: str, confidence_threshold: float = 0.15, max_tags: int = 5):
        """
        Get just the tag names without confidence scores.
        
        Returns:
            List of strings: ["tag1", "tag2", ...]
        """
        results = self.classify_image(image_path, confidence_threshold, max_tags)
        return [tag for tag, _ in results]


# Singleton instance
_clip_classifier = None


def get_clip_model():
    """Get or create CLIP classifier singleton."""
    global _clip_classifier
    if _clip_classifier is None:
        _clip_classifier = CLIPPhotoClassifier()
    return _clip_classifier


def classify_image(image_path: str, confidence_threshold: float = 0.15, max_tags: int = 1, 
                   expected_tags: list = None):
    """
    Convenience function to classify a single image.
    Returns only the most confident category.
    Lower default threshold (0.15) to reduce None results, but strict categories
    like messaging (0.35) and social-media (0.30) still require high confidence.
    
    Args:
        image_path: Path to image
        confidence_threshold: Minimum confidence (ignored if expected_tags provided)
        max_tags: Maximum number of tags
        expected_tags: If provided, will try progressively lower thresholds to find these
    
    Returns:
        List of tag strings (typically just 1 tag)
    """
    classifier = get_clip_model()
    results = classifier.classify_image(image_path, confidence_threshold, max_tags, expected_tags)
    tags = [tag for tag, _ in results]
    # Filter out "other" unless it's the only option
    if len(tags) > 1 and "other" in tags:
        tags = [t for t in tags if t != "other"]
    return tags


def classify_batch(image_paths: list, confidence_threshold: float = 0.15, max_tags: int = 1):
    """
    Convenience function to classify multiple images.
    Returns only the most confident category per image.
    Lower default threshold to reduce None results.
    
    Returns:
        List of tag lists: [["people"], ["scenery"], ["food"], ...]
    """
    classifier = get_clip_model()
    results = classifier.classify_batch(image_paths, confidence_threshold, max_tags)
    cleaned_results = []
    for img_results in results:
        tags = [tag for tag, _ in img_results]
        # Filter out "other" unless it's the only option
        if len(tags) > 1 and "other" in tags:
            tags = [t for t in tags if t != "other"]
        cleaned_results.append(tags)
    return cleaned_results
