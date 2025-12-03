"""
CLIP-based image classification for photo organization.
Provides better quality and more intuitive tagging than YOLO for general photos.
"""
import torch
from PIL import Image
from transformers import CLIPProcessor, CLIPModel
import logging

logger = logging.getLogger(__name__)

# Expanded categories for impressive accuracy
# Using very specific descriptions to improve CLIP accuracy
PHOTO_CATEGORIES = [
    # People - be very specific about human faces and bodies
    "photograph of people, humans, faces, persons, man, woman, human beings, crowd, selfie, portrait",
    
    # Animals - specific animal features
    "photograph of animals, pets, dogs, cats, birds, wildlife, creatures with fur or feathers",
    
    # Food - specific food characteristics
    "photograph of food, meals, dishes, plates of food, cooked food, fruits, vegetables, beverages, dining",
    
    # Scenery - natural outdoor environments
    "photograph of natural scenery, landscapes, mountains, forests, beaches, oceans, nature, outdoor views, sky",
    
    # Gaming screenshots - video game interfaces
    "screenshot of a video game, gaming interface, game graphics, 3D game, game menu, video game screen",
    
    # Social media screenshots - app interfaces with specific UI elements
    "screenshot of social media feed with visible likes, comments, profile pictures, Instagram interface, Twitter timeline, Facebook posts, TikTok videos, social network UI",
    
    # Messaging screenshots - chat interfaces with conversation bubbles
    "screenshot of messaging app with visible chat bubbles, conversation threads, WhatsApp green interface, Telegram blue interface, Discord server chat, text message conversation, message timestamps",
    
    # Documents (SCREENSHOT) - digital document screenshots
    "screenshot of digital document, PDF viewer, document reader, text file, spreadsheet, presentation slide, digital form, scanned document on screen",
    
    # General screenshots - other digital content
    "screenshot of website, web page, browser, app interface, digital screen, phone screen, statistics dashboard, graphs on screen",
    
    # Other - catch-all for things that don't fit (will be filtered out)
    "photograph of objects, items, products, buildings, vehicles, indoor spaces, abstract images",
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
    
    def classify_image(self, image_path: str, confidence_threshold: float = 0.15, max_tags: int = 5):
        """
        Classify image and return relevant tags.
        
        Args:
            image_path: Path to image file
            confidence_threshold: Minimum confidence score (0-1) to include tag
            max_tags: Maximum number of tags to return
            
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
                "gaming", "social-media", "messaging", 
                "Document Screenshot", "screenshots", "other"
            ]
            
            # Stricter thresholds for specific categories to reduce false positives
            category_thresholds = {
                "messaging": 0.60,  # Extremely strict - only when absolutely sure
                "social-media": 0.55,  # Extremely strict - needs clear social UI elements
                "Document Screenshot": 0.25,  # Moderate - distinguish from general screenshots
            }
            
            # Get top matching categories
            results = []
            for idx, prob in enumerate(probs):
                tag_name = category_names[idx] if idx < len(category_names) else "other"
                
                # Skip 'other' entirely - it means we don't know
                if tag_name == "other":
                    continue
                
                # Apply category-specific threshold
                required_threshold = category_thresholds.get(tag_name, confidence_threshold)
                
                if prob >= required_threshold:
                    results.append((tag_name, float(prob)))
            
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
                "gaming", "social-media", "messaging", 
                "Document Screenshot", "screenshots", "other"
            ]
            
            # Stricter thresholds for specific categories
            category_thresholds = {
                "messaging": 0.60,  # Extremely strict
                "social-media": 0.55,  # Extremely strict
                "Document Screenshot": 0.25,  # Moderate
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


def classify_image(image_path: str, confidence_threshold: float = 0.15, max_tags: int = 1):
    """
    Convenience function to classify a single image.
    Returns only the most confident category.
    Lower default threshold (0.15) to reduce None results, but strict categories
    like messaging (0.35) and social-media (0.30) still require high confidence.
    
    Returns:
        List of tag strings (typically just 1 tag)
    """
    classifier = get_clip_model()
    tags = classifier.get_tags_only(image_path, confidence_threshold, max_tags)
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
