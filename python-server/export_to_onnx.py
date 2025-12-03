from ultralytics import YOLO

# Load your YOLOv8 nano model
model = YOLO("yolov8n.pt")  

# Export to ONNX format
model.export(format="onnx")  # This will create yolov8n.onnx in your folder
