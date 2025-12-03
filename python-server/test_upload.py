from fastapi.testclient import TestClient
from backend import backend_api
import json

client = TestClient(backend_api.app)

with open('temp_test.png', 'rb') as f:
    files = {'file': ('temp_test.png', f, 'image/png')}
    resp = client.post('/process-image/', files=files)
    print('Status:', resp.status_code)
    print('Response body:', resp.text)

# Read tags DB
try:
    with open('backend/tags_db.json', 'r', encoding='utf-8') as f:
        db = json.load(f)
    print('\nStored tags DB (sample):')
    print(json.dumps(db, indent=2))
except Exception as e:
    print('\nCould not read tags DB:', e)
