# Python Server (Photo Organizer)

This folder contains the backend FastAPI server used by the Photo Organizer app.

What to back up
- All `.py` files in this folder and `backend/` (these are the server source files).
- `backend/requirements.txt` — lists required Python packages.

What NOT to commit to Git
- Python virtual environments (e.g., `yolovenv/`, `venv/`, `.venv/`)
- Large binary model files (e.g., `yolov8n.pt`, `yolov8m.pt`, `*.onnx`) — instead store them externally and re-download when restoring.

Restore / Run steps (Windows PowerShell)
1. Clone the repo:
```powershell
git clone https://github.com/<your-username>/Photo-Organizer-Flutter.git
cd Photo-Organizer-Flutter\python-server
```

2. Create and activate a virtual environment:
```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
```

3. Install dependencies:
```powershell
pip install -r backend/requirements.txt
# If your project uses torch/ultralytics, install those packages as well per their instructions
```

4. Place model files in this folder (or in `python-server/models/`). Required example filenames:
- `yolov8n.pt` (small)
- `yolov8m.pt` (medium) — optional
- `yolov8x.pt` (large) — optional

You can download official YOLOv8 models from the Ultralytics releases or your preferred source. If you have your own model files, copy them here.

5. Configure runtime settings: copy `.env.example` to `.env` and edit values (e.g., `TARGET_FOLDER`, `UPLOAD_TOKEN`).

6. Start the server (example):
```powershell
python run_server.py --persist-uploads --upload-token mytoken
```

Notes
- The server will serve persisted organized images from `TARGET_FOLDER` when `--persist-uploads` is set; keep that folder outside the repository to avoid accidental commits.
- If you need a script to download model files from a URL, use `scripts/download_models.ps1` (edit it to add real model URLs).
