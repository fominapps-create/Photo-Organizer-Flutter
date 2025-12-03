from ..config import PERSON_FOLDER
import os

def select(results):
    """Simple heuristic: if filename contains 'person' or 'face', classify as Person.
    `results` may be a model result object; we accept either a string/filepath or an object.
    """
    # try to handle when results contains a source/filepath attribute
    try:
        src = getattr(results, 'orig_img_path', None) or getattr(results, 'path', None)
    except Exception:
        src = None

    if not src and isinstance(results, str):
        src = results

    if src:
        name = os.path.basename(src).lower()
        if 'person' in name or 'face' in name:
            return PERSON_FOLDER

    # Fallback: no decision
    return None
