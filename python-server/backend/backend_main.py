# backend_main.py
import os
import time
import cv2
from .model import load_model
from .handlers import person, animals, documents, junk, utils
from . import tags_db
from .config import SOURCE_FOLDER, CONFIDENCE_THRESHOLD, AUTO_TAG_MAX, PERSIST_UPLOADS
from .config import PERSIST_UPLOADS as _PERSIST_UPLOADS
from .config import ALLOW_REMOTE
from .config import RELOAD
from .config import UPLOAD_TOKEN
from .config import TEMP_FOLDER
from .config import TARGET_FOLDER
from .config import ALLOW_ORIGINS
from .config import SOURCE_FOLDER
from .config import CONFIDENCE_THRESHOLD
from .config import AUTO_TAG_MAX
from . import config as _cfg

# --- Load YOLO model once ---
model = None

def get_model():
    """Load YOLO model (singleton)."""
    global model
    if model is None:
        model = load_model()
    return model


def process_single_image(img_path: str, results=None, tags=None) -> str:
    """
    Process a single image and move it to the appropriate folder.
    Returns the destination folder.
    """
    filename = os.path.basename(img_path)
    img = cv2.imread(img_path)
    if img is None:
        print(f"Skipping '{filename}' — cannot read image")
        return "skipped"

    try:
        # Allow caller to pass precomputed results to avoid running inference twice
        if results is None:
            results = get_model()(img_path)[0]
    except Exception as e:
        print(f"Skipping '{filename}' (YOLO error): {e}")
        return "skipped"

    # Extract main detected object name (highest confidence)
    main_object = None
    if results.boxes and len(results.boxes) > 0:
        max_conf_idx = results.boxes.conf.argmax()
        class_id = int(results.boxes.cls[max_conf_idx])
        main_object = results.names[class_id]

    # Decide destination folder by priority
    dest = (
        person.select(results) or
        animals.select(results) or
        documents.select(results, img) or
        junk.select(results, img)
    )

    # If tags were not provided to this function, compute them from results
    computed_tags = tags
    if computed_tags is None:
        computed_tags = []
        if results.boxes is not None and len(results.boxes) > 0:
            detections = []
            for conf, cls_idx in zip(results.boxes.conf, results.boxes.cls):
                class_id = int(cls_idx)
                class_name = results.names[class_id]
                if float(conf) >= CONFIDENCE_THRESHOLD:
                    detections.append((class_name, float(conf)))
            detections.sort(key=lambda x: x[1], reverse=True)
            names = [d[0] for d in detections]
            computed_tags = list(dict.fromkeys(names))
            if AUTO_TAG_MAX is not None and isinstance(AUTO_TAG_MAX, int):
                computed_tags = computed_tags[:AUTO_TAG_MAX]

    # If moving/organizing is disabled in config, skip physical organization.
    if getattr(_cfg, 'ENABLE_MOVING', False) is False:
        print(f"Skipping file move (ENABLE_MOVING=False). Computed tags: {computed_tags}")
        # Do not persist tags here — API layer should persist tags by photoID when available.
        return "skipped"

    # Move file with object name (legacy behavior)
    final_dst = utils.move_to_folder(img_path, dest, main_object)
    if final_dst:
        final_name = os.path.basename(final_dst)
        print(f"Moved '{filename}' → {final_name}")
        # If tags were provided, persist them under the final filename
        try:
            if computed_tags is not None:
                tags_db.set_tags(final_name, computed_tags)
        except Exception:
            pass
        return final_dst
    else:
        print(f"Failed to move '{filename}'")
        return "skipped"


def run_backend(folder: str = SOURCE_FOLDER):
    """Run the full photo organizer process on all images in the folder."""
    start_time = time.time()
    image_files = [
        os.path.join(root, f)
        for root, _, files in os.walk(folder)
        for f in files
        if f.lower().endswith((".jpg", ".jpeg", ".png"))
    ]

    if not image_files:
        print(f"No images found in source folder: {folder}")
        return

    for idx, img_path in enumerate(image_files, 1):
        dest = process_single_image(img_path)
        print(f"{idx}/{len(image_files)} → {os.path.basename(dest)}")

    end_time = time.time()
    minutes, seconds = divmod(end_time - start_time, 60)
    print(f"\n✅ Processing completed in {int(minutes)} min {int(seconds)} sec")
