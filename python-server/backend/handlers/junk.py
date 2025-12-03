from ..config import JUNK_FOLDER

def select(results, img=None):
    """Fallback selector: treat as Junk if nothing else matched."""
    return JUNK_FOLDER
