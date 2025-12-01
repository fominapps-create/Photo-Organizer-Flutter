# Photo Organizer - Architecture Overview

This document summarizes the components and dataflow for the Photo Organizer project.

## Components

- Flutter Mobile/Desktop/Web app (lib/)
  - `main.dart` — app bootstrap; initializes `ApiService` which tries candidate local URLs to find the backend.
  - `ApiService` — handles HTTP endpoints: `/process-image/`, `/all-organized-images/`, `/tags/{}`.
  - Explorer UI — selects and uploads photos in batches; saves returned tags in SharedPreferences under the filename key.
  - Gallery UI — fetches `/all-organized-images/` and displays thumbnails; loads tags from SharedPreferences and shows them as chips.
  - Albums — create tag-based albums using stored SharedPreferences tags.

- Python backend (python-server/backend/)
  - `backend_api.py` — FastAPI app. Key endpoints:
    - `POST /process-image/` — accepts multipart image upload, returns `{ "filename": ..., "tags": [...] }`.
    - `GET /` — status.
    - `GET /all-organized-images/` — list of image URLs.
    - `GET /all-organized-images-with-tags/` — list of images with server-side tags (optional).
    - `GET /tags/{filename}/` — lookup tags for a specific filename from server-side JSON DB.
  - `backend_main.py` — organizes files using YOLO output (moves file into `TARGET_FOLDER/<category>`)
  - `model.py` — loads Ultralytics YOLO weights; returns a model callable.
  - `sorter.py` — heuristics for deciding target folder (Person/Animals/Documents/Junk).
  - `config.py` — file paths and thresholds.

## Dataflow

1. App boot: For development, the app defaults to a platform-friendly server base URL (Android emulator: `http://10.0.2.2:8000`) and upload features are enabled by default for local testing. For release builds, keep `ApiService.initialize()` disabled or not invoked to avoid accidental uploads; developers can call `ApiService.initialize()` during local dev/testing to auto-discover servers.
2. User selects images.
3. App uploads images to `POST /process-image/` via `ApiService.uploadImage`. Backend saves the file to `TEMP_FOLDER` and runs YOLO detection.
4. Backend responds with `{"filename": "uploaded.png", "tags": ["cat", "dog"]}`. Backend also persists the tags in `tags_db.json` and organizes the file on disk.
5. App saves these tags in `SharedPreferences` (client-side) keyed by filename.
6. Gallery fetches `GET /all-organized-images/` (or `GET /all-organized-images-with-tags/` to include server tags) and displays thumbnails; loads tags from SharedPreferences and shows tag chips.

## Notes

- Tags are saved both locally (SharedPreferences) and server-side (`tags_db.json`), allowing recovery if the app is reinstalled or moved.
- `tags_db.json` is a small, file-based mapping for simplicity; for production, migrate to a small SQLite DB or a proper storage backend.

## Quick suggestions for improvement
- Add a `GET /images/with-tags` endpoint that returns images and tags directly (already implemented as `all-organized-images-with-tags/`).
- Store tags as metadata (EXIF) on files or in a small DB instead of a flat JSON file for resilience.
- Add upload deduplication and filename disambiguation.

---
Generated summary by Copilot-based assistant.