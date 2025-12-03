from backend.backend_main import process_single_image
import os

path = os.path.abspath('temp_test.png')
print('Processing:', path)
try:
    dest = process_single_image(path)
    print('Result dest:', dest)
except Exception as e:
    print('Error during processing:', e)
