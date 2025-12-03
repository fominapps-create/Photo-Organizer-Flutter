import onnx
from onnx_tf.backend import prepare

# Load your ONNX model
onnx_model_path = "G:/Python Projects/Photo Organizer/yolov8n.onnx"
onnx_model = onnx.load(onnx_model_path)

# Prepare TensorFlow representation
tf_rep = prepare(onnx_model)

# Export as TensorFlow SavedModel
tf_model_path = "G:/Python Projects/Photo Organizer/yolov8n_tf"
tf_rep.export_graph(tf_model_path)

print(f"TensorFlow SavedModel exported to: {tf_model_path}")
