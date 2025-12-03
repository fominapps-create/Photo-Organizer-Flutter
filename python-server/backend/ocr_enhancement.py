"""
OCR-based screenshot enhancement for detecting specific games and apps.
Uses EasyOCR (free) for high accuracy text detection.
"""
import logging
from typing import List, Tuple, Optional
import numpy as np
from PIL import Image

logger = logging.getLogger(__name__)

# Lazy load EasyOCR (only when needed)
_ocr_reader = None

def get_ocr_reader():
    """Get or initialize EasyOCR reader (singleton)."""
    global _ocr_reader
    if _ocr_reader is None:
        try:
            import easyocr
            logger.info("Initializing EasyOCR (this may take a moment on first run)...")
            # Use English only for speed, add more languages if needed
            _ocr_reader = easyocr.Reader(['en'], gpu=False)
            logger.info("EasyOCR initialized successfully")
        except ImportError:
            logger.warning("EasyOCR not installed. Install with: pip install easyocr")
            return None
        except Exception as e:
            logger.error(f"Failed to initialize EasyOCR: {e}")
            return None
    return _ocr_reader


# Game and app detection patterns
GAME_PATTERNS = {
    # Popular games
    'minecraft': ['minecraft', 'creeper', 'steve', 'mojang'],
    'roblox': ['roblox', 'robux'],
    'fortnite': ['fortnite', 'epic games', 'battle royale'],
    'gta': ['grand theft auto', 'gta', 'rockstar'],
    'league-of-legends': ['league of legends', 'lol', 'riot games'],
    'valorant': ['valorant', 'spike', 'riot games'],
    'call-of-duty': ['call of duty', 'cod', 'warzone', 'activision'],
    'apex-legends': ['apex legends', 'respawn'],
    'counter-strike': ['counter-strike', 'cs:go', 'csgo', 'valve'],
    'dota': ['dota', 'dota 2'],
    'overwatch': ['overwatch', 'blizzard'],
    'pubg': ['pubg', "playerunknown's"],
    'among-us': ['among us', 'impostor', 'crewmate'],
    'fall-guys': ['fall guys'],
    'rocket-league': ['rocket league', 'psyonix'],
    'genshin': ['genshin impact', 'genshin', 'mihoyo'],
}

APP_PATTERNS = {
    # Social media
    'instagram': ['instagram', 'insta', '@', '#'],
    'twitter': ['twitter', 'tweet', 'retweet', '@'],
    'facebook': ['facebook', 'fb.com'],
    'tiktok': ['tiktok', 'for you'],
    'snapchat': ['snapchat', 'snap'],
    'reddit': ['reddit', 'upvote', 'r/'],
    'youtube': ['youtube', 'subscribe'],
    
    # Messaging
    'whatsapp': ['whatsapp', 'online', 'typing...'],
    'telegram': ['telegram', 'forwarded'],
    'discord': ['discord', 'online', 'server'],
    'messenger': ['messenger', 'facebook messenger'],
    'signal': ['signal', 'disappearing messages'],
    'slack': ['slack', 'workspace'],
    
    # Other
    'maps': ['google maps', 'directions', 'eta'],
    'email': ['gmail', 'inbox', 'sent', 'draft'],
    'browser': ['google.com', 'search', 'chrome', 'firefox'],
}


def extract_text_from_image(image_path: str) -> List[str]:
    """
    Extract text from image using OCR.
    
    Args:
        image_path: Path to image file
        
    Returns:
        List of detected text strings (lowercase)
    """
    reader = get_ocr_reader()
    if reader is None:
        return []
    
    try:
        # Run OCR
        results = reader.readtext(image_path)
        
        # Extract text and convert to lowercase
        detected_texts = [text.lower() for (bbox, text, conf) in results if conf > 0.3]
        
        return detected_texts
        
    except Exception as e:
        logger.error(f"OCR failed for {image_path}: {e}")
        return []


def detect_game_or_app(detected_texts: List[str]) -> Optional[str]:
    """
    Detect specific game or app from extracted text.
    
    Args:
        detected_texts: List of text strings from OCR
        
    Returns:
        Game/app identifier or None
    """
    if not detected_texts:
        return None
    
    # Combine all text for easier matching
    combined_text = ' '.join(detected_texts)
    
    # Check games first
    for game_id, patterns in GAME_PATTERNS.items():
        for pattern in patterns:
            if pattern.lower() in combined_text:
                logger.info(f"Detected game: {game_id} (matched: {pattern})")
                return game_id
    
    # Check apps
    for app_id, patterns in APP_PATTERNS.items():
        for pattern in patterns:
            if pattern.lower() in combined_text:
                logger.info(f"Detected app: {app_id} (matched: {pattern})")
                return app_id
    
    return None


def enhance_screenshot_tag(image_path: str, base_tag: str) -> Tuple[str, Optional[str]]:
    """
    Enhance screenshot classification with OCR detection.
    
    Args:
        image_path: Path to image
        base_tag: Base tag from CLIP (e.g., "gaming", "social-media")
        
    Returns:
        Tuple of (enhanced_tag, specific_identifier)
        Example: ("gaming", "minecraft") or ("social-media", "instagram")
    """
    # Only run OCR for screenshot-related tags
    screenshot_tags = ['gaming', 'social-media', 'messaging', 'screenshots']
    if base_tag not in screenshot_tags:
        return (base_tag, None)
    
    try:
        # Extract text from screenshot
        detected_texts = extract_text_from_image(image_path)
        
        if not detected_texts:
            return (base_tag, None)
        
        # Detect specific game/app
        specific = detect_game_or_app(detected_texts)
        
        if specific:
            # Return enhanced tag like "gaming-minecraft"
            return (f"{base_tag}-{specific}", specific)
        
        return (base_tag, None)
        
    except Exception as e:
        logger.error(f"Screenshot enhancement failed for {image_path}: {e}")
        return (base_tag, None)


def is_ocr_available() -> bool:
    """Check if EasyOCR is available."""
    try:
        import easyocr
        return True
    except ImportError:
        return False
