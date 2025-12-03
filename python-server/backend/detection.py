from ultralytics import YOLO
from config import CONFIDENCE_THRESHOLD

model = YOLO("yolov8n.pt")

def detect(img_path):
    result = model(img_path)[0]
    return result.boxes
