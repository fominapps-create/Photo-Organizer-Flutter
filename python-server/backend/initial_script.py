import os
import shutil
import logging
from ultralytics import YOLO

logger = logging.getLogger(__name__)

# --- CONFIG ---
SOURCE_FOLDER = r"C:\Users\MIKE\Pictures\Screenshots"  # your main folder
TARGET_FOLDER = r"C:\Users\MIKE\Pictures\Screenshots\Organized"    # where sorted images go
CONFIDENCE_THRESHOLD = 0.3  # minimum confidence to count detection

os.makedirs(TARGET_FOLDER, exist_ok=True)
PERSON_FOLDER = os.path.join(TARGET_FOLDER, "Person")
ANIMALS_FOLDER = os.path.join(TARGET_FOLDER, "Animals")
JUNK_FOLDER = os.path.join(TARGET_FOLDER, "Junk")

os.makedirs(PERSON_FOLDER, exist_ok=True)
os.makedirs(ANIMALS_FOLDER, exist_ok=True)
os.makedirs(JUNK_FOLDER, exist_ok=True)

# --- Load YOLOv8 model ---
model = YOLO("yolov8n.pt")  # small, fast model

# COCO classes considered as animals
ANIMAL_CLASSES = {
    "bird", "cat", "dog", "horse", "sheep", "cow", "elephant", "bear",
    "zebra", "giraffe", "panda", "lion", "tiger", "rabbit", "mouse"
}

# --- Process images recursively ---
for root, _, files in os.walk(SOURCE_FOLDER):
    for filename in files:
        if not filename.lower().endswith((".jpg", ".jpeg", ".png")):
            continue

        img_path = os.path.join(root, filename)
        try:
            results = model(img_path)[0]  # first result for image
        except Exception as e:
            logger.error(f"Skipping '{filename}' (error): {e}")
            continue

        folder_name = "Junk"

        for cls_id, conf in zip(results.boxes.cls, results.boxes.conf):
            if conf < CONFIDENCE_THRESHOLD:
                continue
            cls_name = results.names[int(cls_id)]
            if cls_name == "person":
                folder_name = "Person"
                break  # person takes priority
            elif cls_name in ANIMAL_CLASSES:
                folder_name = "Animals"
                # don't break, in case person is also detected

        if folder_name == "Person":
            dest_folder = PERSON_FOLDER
        elif folder_name == "Animals":
            dest_folder = ANIMALS_FOLDER
        else:
            dest_folder = JUNK_FOLDER

        shutil.move(img_path, os.path.join(dest_folder, filename))
        logger.info(f"Moved '{filename}' → '{folder_name}'")
