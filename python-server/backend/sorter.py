import shutil
import os
import cv2
from categories import ANIMAL_CLASSES, DOCUMENT_CLASSES
from config import CONFIDENCE_THRESHOLD, PERSON_FOLDER, ANIMALS_FOLDER, JUNK_FOLDER, DOCUMENTS_FOLDER

MIN_BOX_PERCENT = 0.3  # 30% of image area

def is_document(img_path):
    """
    Simple heuristic to detect document-like images:
    looks for large rectangular bright areas.
    """
    img = cv2.imread(img_path)
    if img is None:
        return False
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    _, thresh = cv2.threshold(gray, 200, 255, cv2.THRESH_BINARY)
    contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    for cnt in contours:
        x, y, w, h = cv2.boundingRect(cnt)
        aspect_ratio = w / h
        if 0.5 < aspect_ratio < 2.0 and w * h > 10000:
            return True
    return False

def select_folder(results, img_path):
    """
    Decide which folder an image should go to based on the largest detected object.
    Two-pass logic: prefer objects >= MIN_BOX_PERCENT, else pick the largest object.
    """
    img_height, img_width = results.orig_shape[:2]
    image_area = img_width * img_height

    largest_area = 0
    largest_cls = None
    big_enough_cls = None

    for cls_id, conf, box in zip(results.boxes.cls, results.boxes.conf, results.boxes.xyxy):
        if conf < CONFIDENCE_THRESHOLD:
            continue

        width = box[2] - box[0]
        height = box[3] - box[1]
        area = width * height

        cls_name = results.names[int(cls_id)]

        # Track largest overall object
        if area > largest_area:
            largest_area = area
            largest_cls = cls_name

        # Track first object meeting MIN_BOX_PERCENT
        if area / image_area >= MIN_BOX_PERCENT and big_enough_cls is None:
            big_enough_cls = cls_name

    # Pick object: prefer big enough, else largest
    final_cls = big_enough_cls or largest_cls

    # Decide folder
    if final_cls == "person":
        return PERSON_FOLDER
    elif final_cls in ANIMAL_CLASSES:
        return ANIMALS_FOLDER
    elif final_cls in DOCUMENT_CLASSES or is_document(img_path):
        return DOCUMENTS_FOLDER
    else:
        return JUNK_FOLDER

def move_to_folder(img_path, dest_folder):
    """
    Move the image to the selected folder.
    Prints messages if the destination folder is empty or missing.
    """
    if not os.path.exists(dest_folder):
        print(f"Destination folder '{dest_folder}' does not exist. Skipping '{os.path.basename(img_path)}'.")
        return

    if len(os.listdir(dest_folder)) == 0:
        print(f"Destination folder '{os.path.basename(dest_folder)}' is empty, moving '{os.path.basename(img_path)}'.")

    shutil.move(img_path, dest_folder)
