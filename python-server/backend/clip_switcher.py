"""
CLIP Model Switcher

Single configuration point to switch between full CLIP and MobileCLIP.
Change USE_MOBILE_CLIP to switch models without touching other code.

Usage in other files:
    from .clip_switcher import classify_image, classify_batch
"""

# ============================================================================
# CONFIGURATION - Change this to switch models
# ============================================================================
# PRIORITY: ACCURACY FIRST (customer satisfaction)
# - Full CLIP: 600MB, ~170ms/image, best accuracy
# - MobileCLIP-S2: 70MB, ~80ms/image, ~95% of CLIP accuracy
#
# Only switch to MobileCLIP after testing confirms acceptable accuracy.
# ============================================================================
USE_MOBILE_CLIP = True  # TESTING: MobileCLIP-S2 (70MB, ~95% accuracy)

MOBILE_CLIP_SIZE = "s2"  # If enabled: "s0" (fastest), "s1", "s2" (best accuracy)
# ============================================================================

import logging
logger = logging.getLogger(__name__)

if USE_MOBILE_CLIP:
    logger.info(f"Using MobileCLIP ({MOBILE_CLIP_SIZE}) - lightweight model for free tier")
    from .mobile_clip_model import (
        classify_image,
        classify_batch,
        get_mobile_clip_model as get_clip_model,
        MobileCLIPPhotoClassifier as CLIPPhotoClassifier,
    )
else:
    logger.info("Using full CLIP (openai/clip-vit-base-patch32) - premium model")
    from .clip_model import (
        classify_image,
        classify_batch,
        get_clip_model,
        CLIPPhotoClassifier,
    )

# Re-export everything with consistent names
__all__ = [
    'classify_image',
    'classify_batch', 
    'get_clip_model',
    'CLIPPhotoClassifier',
    'USE_MOBILE_CLIP',
    'MOBILE_CLIP_SIZE',
]
