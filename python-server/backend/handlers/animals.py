from ..config import ANIMALS_FOLDER, CONFIDENCE_THRESHOLD
import os


def select(results, img=None):
    """
    Prefer model detections: if the YOLO results contain a high-confidence
    detection whose class name matches a known animal, return the animals
    folder. Otherwise fall back to filename heuristics.
    """
    # Try to read model detection info (ultralytics Results)
    try:
        names = getattr(results, 'names', None) or {}
        boxes = getattr(results, 'boxes', None)
        if boxes is not None:
            confs = list(getattr(boxes, 'conf', []))
            cls_idxs = list(getattr(boxes, 'cls', []))
            for conf, cls_idx in zip(confs, cls_idxs):
                try:
                    if float(conf) >= float(CONFIDENCE_THRESHOLD):
                        cls_name = names.get(int(cls_idx), str(cls_idx)).lower()
                        if cls_name in ('dog', 'cat', 'horse', 'cow', 'sheep', 'bird', 'animal', 'pet'):
                            return ANIMALS_FOLDER
                except Exception:
                    continue
    except Exception:
        # If results don't match expected structure, we'll fall back below
        pass

    # Filename fallback
    try:
        src = getattr(results, 'orig_img_path', None) or getattr(results, 'path', None)
    except Exception:
        src = None

    if not src and isinstance(results, str):
        src = results

    if src:
        name = os.path.basename(src).lower()
        for kw in ('dog', 'cat', 'pet', 'animal'):
            if kw in name:
                return ANIMALS_FOLDER

    return None
