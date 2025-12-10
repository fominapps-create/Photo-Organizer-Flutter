from __future__ import annotations

import os
from . import config as srv_cfg
from typing import Any, TYPE_CHECKING
from fastapi import BackgroundTasks, Header

# Disable missing-imports for this file in editors (works for pyright/Pylance)
# We keep a runtime fallback below so the code still runs if FastAPI is installed
# in a virtual environment that isn't active in the editor.
# pyright: reportMissingImports=false

# FastAPI may be installed in the project's virtual environment. Editors without
# the correct interpreter selected can show "Import could not be resolved".
# Add a safe import fallback so the file remains lint-clean when FastAPI isn't
# available in the global environment (this keeps the file runnable in editors
# without changing runtime behavior when FastAPI *is* installed).
try:
    from fastapi import FastAPI, UploadFile, HTTPException, Header, File, Form
    from fastapi.middleware.cors import CORSMiddleware
    from fastapi.staticfiles import StaticFiles
except Exception:  # pragma: no cover - editor fallback
    FastAPI = Any
    HTTPException = Exception
    CORSMiddleware = Any
    StaticFiles = Any

if TYPE_CHECKING:
    # Import types for static type checking (won't run at runtime in editors)
    from fastapi import UploadFile

from .backend_main import process_single_image, get_model
from .clip_model import get_clip_model, classify_image
from .ocr_enhancement import enhance_screenshot_tag, is_ocr_available
from . import tags_db as _tags_db
from pydantic import BaseModel
from .config import TEMP_FOLDER, TARGET_FOLDER, CONFIDENCE_THRESHOLD, CLIP_CONFIDENCE_THRESHOLD
from .model import load_model  # kept for legacy usage elsewhere
import time
import json
from typing import Dict, List

# File to persist tags server-side so tags survive app reinstall
TAGS_DB_PATH = os.path.join(os.path.dirname(__file__), 'tags_db.json')


def _load_tags_db() -> Dict[str, List[str]]:
    # Deprecated: use `tags_db` module helpers. Kept for backward compatibility in this file.
    try:
        if os.path.exists(TAGS_DB_PATH):
            with open(TAGS_DB_PATH, 'r', encoding='utf-8') as f:
                return json.load(f)
    except Exception:
        pass
    return {}


def _save_tags_db(db: Dict[str, List[str]]) -> None:
    # Deprecated wrapper; prefer `tags_db.set_tags` and `tags_db.get_tags`.
    try:
        with open(TAGS_DB_PATH, 'w', encoding='utf-8') as f:
            json.dump(db, f, ensure_ascii=False, indent=2)
    except Exception:
        logging.warning('Failed to save tags DB')
import logging

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')

# --- Setup ---
app = FastAPI(title="Photo Organizer API")  # type: ignore[arg-type]
os.makedirs(TEMP_FOLDER, exist_ok=True)  # ensure temp folder exists
# Serve organized files (so the Flutter app can download thumbnails/full images)
if os.path.exists(TARGET_FOLDER):
    app.mount("/organized", StaticFiles(directory=TARGET_FOLDER), name="organized")
else:
    os.makedirs(TARGET_FOLDER, exist_ok=True)
    app.mount("/organized", StaticFiles(directory=TARGET_FOLDER), name="organized")
# The model is loaded/managed by backend_main.get_model() when needed.

# Allow all origins (for testing), you can restrict later
# Restrict CORS to local host by default for safety. Use `--allow-remote` or
# set `ALLOW_ORIGINS` to a comma-separated list to loosen restrictions.
default_origins = ["http://localhost:8000", "http://127.0.0.1:8000", "http://10.0.2.2:8000"]
# Use configured ALLOW_ORIGINS from server config (comma-separated), if set
if getattr(srv_cfg, 'ALLOW_ORIGINS', None):
    try:
        default_origins = [o.strip() for o in srv_cfg.ALLOW_ORIGINS.split(",") if o.strip()]
    except Exception:
        pass
app.add_middleware(
    CORSMiddleware,
    allow_origins=default_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Upload authorization token (if set, requires X-Upload-Token header to match)
UPLOAD_TOKEN = srv_cfg.UPLOAD_TOKEN

# Persist uploads (default: False for ephemeral testing) - set PERSIST_UPLOADS=1 to keep files
PERSIST_UPLOADS = bool(srv_cfg.PERSIST_UPLOADS)


def _require_token(x_upload_token: str | None):
    """Require an upload token when UPLOAD_TOKEN is set.

    This helper raises a HTTPException(403) if the header doesn't match the
    configured token. If no token is configured, it is a no-op.
    """
    if UPLOAD_TOKEN and x_upload_token != UPLOAD_TOKEN:
        raise HTTPException(status_code=403, detail='Forbidden')

# Optional Pillow import for EXIF stripping
try:
    from PIL import Image
    from io import BytesIO
except Exception:
    Image = None
    def _require_token(x_upload_token: str | None):
        """Require an upload token when UPLOAD_TOKEN is set.

        This helper raises a HTTPException(403) if the header doesn't match the
        configured token. If no token is configured, it is a no-op.
        """
        if UPLOAD_TOKEN and x_upload_token != UPLOAD_TOKEN:
            raise HTTPException(status_code=403, detail='Forbidden')

    BytesIO = None

# --- Routes ---
@app.post("/process-image/")
async def detect_tags(file: "UploadFile" = File(...), photoID: str = Form(...), x_upload_token: str | None = Header(None)):
    """
    Upload an image and return all detected object tags (YOLO classes above threshold).
    """
    # Check valid image type
    if not file.filename.lower().endswith((".jpg", ".jpeg", ".png")):
        raise HTTPException(status_code=400, detail="Invalid file type")

    # Ensure upload is allowed (token check)
    _require_token(x_upload_token)

    # Save uploaded file temporarily and measure read time
    temp_path = os.path.join(TEMP_FOLDER, file.filename)
    # If an upload token exists, require it in the header
    try:
        from fastapi import Request
    except Exception:
        Request = None
    # FastAPI Header injection is not possible without function signature; we'll
    # read `X-Upload-Token` from request.headers if present (and required)
    # Note: This is a simple check — extend if more complex auth required.
    # We will try to inspect the header via BackgroundTasks request context if present.
    # (Workaround: the tests here do not force header usage.)

    # Validate header-based upload token if set; fall back to allowing when not set.
    # If request header isn't available here, the upload token check may be enforced
    # at a proxy / API gateway in production; for now this is a best-effort guard.
    try:
        # FastAPI makes header available with Header, but to avoid changing signature,
        # we do this check if UploadFile upload token is present in the headers of the request.
        pass
    except Exception:
        pass

    try:
        t_read0 = time.time()
        data = await file.read()
        # Strip EXIF if PIL available
        try:
            if Image is not None and BytesIO is not None:
                img_buf = BytesIO(data)
                img = Image.open(img_buf)
                out = BytesIO()
                # Save without EXIF by not passing exif info; preserve PNG/JPEG format
                img.save(out, format=img.format or "PNG")
                data = out.getvalue()
        except Exception:
            logging.warning("Failed to strip EXIF / image metadata; continuing with original image")
        t_read1 = time.time()
        with open(temp_path, "wb") as f:
            f.write(data)
        logging.info(f"Reading upload for {file.filename} took {round((t_read1 - t_read0) * 1000)}ms")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to save file: {e}")

    # Run CLIP classification
    try:
        logging.info(f"Starting CLIP classification for {file.filename}")
        t0 = time.time()
        # Use CLIP for better quality tagging
        from .config import AUTO_TAG_MAX
        max_tags = AUTO_TAG_MAX if AUTO_TAG_MAX is not None else 5
        # Use a CLIP-specific threshold for image-level classification so
        # categories like `food` are less likely to be filtered out by a
        # box-based confidence threshold (YOLO uses CONFIDENCE_THRESHOLD).
        clip_threshold = CLIP_CONFIDENCE_THRESHOLD if 'CLIP_CONFIDENCE_THRESHOLD' in globals() else CONFIDENCE_THRESHOLD
        tags = classify_image(temp_path, confidence_threshold=clip_threshold, max_tags=max_tags)
        t1 = time.time()
        logging.info(f"CLIP classification for {file.filename} took {round((t1 - t0) * 1000)}ms")
        logging.info(f"Detected tags for {file.filename}: {tags}")
        
        # Enhance screenshot tags with OCR if available
        if tags and is_ocr_available():
            enhanced_tags = []
            for tag in tags:
                enhanced_tag, specific = enhance_screenshot_tag(temp_path, tag)
                enhanced_tags.append(enhanced_tag)
                if specific:
                    logging.info(f"Enhanced {tag} → {enhanced_tag} (detected: {specific})")
            tags = enhanced_tags
        
        # For compatibility with old backend_main, we need results object
        # Since we're not using YOLO anymore, we'll pass None and tags directly
        results = None
    except Exception as e:
        if os.path.exists(temp_path):
            os.remove(temp_path)
        raise HTTPException(status_code=500, detail=f"Classification error: {e}")

    # Schedule organization as a background task (do not block API response)
    try:
        # Organize the file synchronously so the API can return the final URL/name
        final_dst = process_single_image(temp_path, results, tags)
        if final_dst and isinstance(final_dst, str) and final_dst != 'skipped':
            rel_path = os.path.relpath(final_dst, TARGET_FOLDER)
            final_url = f"/organized/{rel_path.replace(os.sep, '/')}"
            logging.info(f"Organized {file.filename} → {final_url}")
        else:
            final_url = None
    except Exception as e:
        logging.warning(f"Failed to schedule background organization for {file.filename}: {e}")

    # Non-persistent by default: if persistence is not enabled, remove final file and temp files
    try:
        if not PERSIST_UPLOADS:
            # if final_dst exists, attempt to remove it
            if final_dst and isinstance(final_dst, str):
                try:
                    if os.path.exists(final_dst):
                        os.remove(final_dst)
                except Exception:
                    logging.warning('Failed to delete final file for non-persistent mode')
            if os.path.exists(temp_path):
                os.remove(temp_path)
    except Exception:
        logging.exception('Error cleaning up files in non-persistent mode')

    # Persist tags under provided `photoID` (tag-only mode required by architecture).
    try:
        try:
            _tags_db.set_tags(photoID, tags)
        except Exception:
            logging.exception('Failed to persist tags under photoID')
    except Exception:
        pass

    return {"filename": file.filename, "photoID": photoID, "tags": tags, "url": final_url}


@app.post("/process-images-batch/")
async def detect_tags_batch(files: List["UploadFile"] = File(...), photoIDs: str = Form(...), x_upload_token: str | None = Header(None)):
    """
    Upload multiple images and return detected tags for all (faster batch processing).
    """
    _require_token(x_upload_token)
    
    # Save all uploaded files
    temp_paths = []
    filenames = []
    
    for file in files:
        if not file.filename.lower().endswith((".jpg", ".jpeg", ".png")):
            continue
            
        try:
            temp_path = os.path.join(TEMP_FOLDER, file.filename)
            data = await file.read()
            
            # Write directly without EXIF processing for speed
            # (EXIF data doesn't affect CLIP classification)
            with open(temp_path, "wb") as f:
                f.write(data)
            
            temp_paths.append(temp_path)
            filenames.append(file.filename)
        except Exception as e:
            logging.warning(f"Failed to save {file.filename}: {e}")
    
    if not temp_paths:
        raise HTTPException(status_code=400, detail="No valid images uploaded")
    
    # Batch classify with YOLO+CLIP hybrid or CLIP-only based on config
    try:
        from .config import AUTO_TAG_MAX, USE_HYBRID_CLASSIFICATION
        from .clip_model import classify_batch as clip_classify_batch
        
        max_tags = AUTO_TAG_MAX if AUTO_TAG_MAX is not None else 5
        # Use CLIP-specific threshold for batch classification as well
        clip_threshold = CLIP_CONFIDENCE_THRESHOLD if 'CLIP_CONFIDENCE_THRESHOLD' in globals() else CONFIDENCE_THRESHOLD
        
        if USE_HYBRID_CLASSIFICATION:
            # Use hybrid approach: YOLO first (fast), CLIP fallback (slow but accurate)
            logging.info(f"Starting hybrid YOLO+CLIP classification for {len(temp_paths)} images")
            from .yolo_clip_hybrid import classify_batch_hybrid
            
            t0 = time.time()
            batch_tags, stats = classify_batch_hybrid(
                temp_paths,
                yolo_model=None,  # Will auto-load fast nano model
                clip_batch_func=clip_classify_batch,
                yolo_confidence=0.60,  # Lower for nano model
                clip_threshold=clip_threshold,
                max_tags=max_tags
            )
            t1 = time.time()
            
            total_ms = round((t1 - t0) * 1000)
            avg_ms = round(total_ms / len(temp_paths), 1)
            yolo_pct = round(100 * stats["yolo_success"] / stats["total_images"], 1)
            
            logging.info(f"Hybrid batch completed: {total_ms}ms total, {avg_ms}ms/image")
            logging.info(f"  YOLO: {stats['yolo_success']}/{stats['total_images']} images ({yolo_pct}%) in {stats['yolo_time_ms']}ms")
            logging.info(f"  CLIP: {stats['clip_fallback']} images in {stats['clip_time_ms']}ms")
        else:
            # Use CLIP-only (slower but more accurate on CPU)
            logging.info(f"Starting CLIP-only classification for {len(temp_paths)} images")
            t0 = time.time()
            batch_tags = clip_classify_batch(temp_paths, confidence_threshold=clip_threshold, max_tags=max_tags)
            t1 = time.time()
            logging.info(f"CLIP batch took {round((t1 - t0) * 1000)}ms for {len(temp_paths)} images ({round((t1-t0)*1000/len(temp_paths))}ms per image)")
        
    except Exception as e:
        # Cleanup on error
        for temp_path in temp_paths:
            if os.path.exists(temp_path):
                os.remove(temp_path)
        raise HTTPException(status_code=500, detail=f"Batch classification error: {e}")
    
    # Build response — map results to provided photoIDs when supplied
    # photoIDs is required and must be a JSON array string matching the uploaded files order
    ids_list = None
    try:
        import json as _json
        ids_list = _json.loads(photoIDs)
        if not isinstance(ids_list, list):
            raise ValueError('photoIDs must be a JSON array')
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid photoIDs: {e}")

    results = []
    for idx, (filename, tags, temp_path) in enumerate(zip(filenames, batch_tags, temp_paths)):
        photo_id = None
        if ids_list and idx < len(ids_list):
            photo_id = ids_list[idx]
            try:
                _tags_db.set_tags(photo_id, tags)
            except Exception:
                logging.exception('Failed to persist tags for photoID in batch')

        results.append({
            "filename": filename,
            "photoID": photo_id,
            "tags": tags,
            "url": None  # Not organizing in batch mode for speed
        })

        # Cleanup temp files
        try:
            if not PERSIST_UPLOADS and os.path.exists(temp_path):
                os.remove(temp_path)
        except Exception:
            pass

    return {"results": results, "count": len(results)}


@app.get("/")
def root():
    return {"status": "Photo Organizer API running (CLIP-powered)"}


@app.get("/folders/")
def list_folders(x_upload_token: str | None = Header(None)):
    _require_token(x_upload_token)
    """Return a list of subfolder names under TARGET_FOLDER."""
    try:
        subs = [name for name in os.listdir(TARGET_FOLDER) if os.path.isdir(os.path.join(TARGET_FOLDER, name))]
        return subs
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/folders/{folder_name}/")
def list_folder_files(folder_name: str, x_upload_token: str | None = Header(None)):
    _require_token(x_upload_token)
    """Return a list of file URLs for the requested subfolder."""
    folder_path = os.path.join(TARGET_FOLDER, folder_name)
    if not os.path.exists(folder_path) or not os.path.isdir(folder_path):
        raise HTTPException(status_code=404, detail="Folder not found")
    files = []
    for fname in sorted(os.listdir(folder_path)):
        fpath = os.path.join(folder_path, fname)
        if os.path.isfile(fpath) and fname.lower().endswith(('.jpg', '.jpeg', '.png')):
            # Build a URL to the mounted static files
            files.append(f"/organized/{folder_name}/{fname}")
    return files


@app.get("/all-organized-images/")
def list_all_organized_images(x_upload_token: str | None = Header(None)):
    _require_token(x_upload_token)
    """Return a list of all organized image URLs recursively."""
    images = []
    for root, dirs, files in os.walk(TARGET_FOLDER):
        for file in files:
            if file.lower().endswith(('.jpg', '.jpeg', '.png')):
                # Get relative path from TARGET_FOLDER
                rel_path = os.path.relpath(os.path.join(root, file), TARGET_FOLDER)
                images.append(f"/organized/{rel_path.replace(os.sep, '/')}")
    return {"images": images}


@app.get('/tags/{photo_id}/')
def get_tags_for_file(photo_id: str, x_upload_token: str | None = Header(None)):
    _require_token(x_upload_token)
    """Return tags for a specific photoID if present in DB."""
    try:
        tags = _tags_db.get_tags(photo_id)
    except Exception:
        logging.exception('Failed to read tags for photoID')
        raise HTTPException(status_code=500, detail='Failed to read tags')
    return {"photoID": photo_id, "tags": tags}


@app.get('/tags/')
def get_tags_query(photoID: str | None = None, x_upload_token: str | None = Header(None)):
    """Return tags for a photoID supplied as a query parameter (supports URIs with slashes)."""
    _require_token(x_upload_token)
    if not photoID:
        raise HTTPException(status_code=400, detail='photoID query parameter required')
    try:
        tags = _tags_db.get_tags(photoID)
    except Exception:
        logging.exception('Failed to read tags for photoID')
        raise HTTPException(status_code=500, detail='Failed to read tags')
    return {"photoID": photoID, "tags": tags}


class _TagsPayload(BaseModel):
    tags: List[str]


@app.post('/tags/{photo_id}/')
def set_tags_for_file(photo_id: str, payload: _TagsPayload, x_upload_token: str | None = Header(None)):
    _require_token(x_upload_token)
    """Set tags for a photoID (dev/test helper)."""
    try:
        _tags_db.set_tags(photo_id, payload.tags)
    except Exception:
        logging.exception('Failed to set tags')
        raise HTTPException(status_code=500, detail="Failed to set tags")
    return {"photoID": photo_id, "tags": payload.tags}


@app.get('/all-organized-images-with-tags/')
def list_all_organized_images_with_tags(x_upload_token: str | None = Header(None)):
    _require_token(x_upload_token)
    """Return a list of images and tags (uses server-side tag DB)."""
    try:
        images = []
        db = _load_tags_db()
        for root, dirs, files in os.walk(TARGET_FOLDER):
            for file in files:
                if file.lower().endswith(('.jpg', '.jpeg', '.png')):
                    rel_path = os.path.relpath(os.path.join(root, file), TARGET_FOLDER)
                    url = f"/organized/{rel_path.replace(os.sep, '/')}"
                    images.append({"url": url, "tags": db.get(file, [])})
        return {"images": images}
    except Exception as e:
        # Log detailed exception and return an empty list to avoid 500 errors
        logging.exception('Failed to list organized images with tags')
        return {"images": []}


@app.get('/tags-db/')
def dump_tags_db(x_upload_token: str | None = Header(None)):
    _require_token(x_upload_token)
    db = _load_tags_db()
    return db


@app.get('/all-tags/')
def get_all_unique_tags():
    """
    Get all unique tags that exist across all images.
    Used for search autocomplete suggestions.
    
    Returns:
        {"tags": ["people", "animals", "food", ...]}
    """
    try:
        db = _load_tags_db()
        all_tags = set()
        for filename, tags in db.items():
            if isinstance(tags, list):
                all_tags.update(tags)
        
        # Sort alphabetically for consistent UI
        sorted_tags = sorted(list(all_tags))
        return {"tags": sorted_tags}
    except Exception as e:
        logging.error(f"Failed to get all tags: {e}")
        return {"tags": []}
