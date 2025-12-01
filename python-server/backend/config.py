"""
Config file to hold runtime options for the FastAPI backend.
This avoids relying on environment variables at runtime; flags passed to `run_server.py`
will set these values before the app starts.
"""
import os

# Runtime-configurable options; prefer environment variables for portability.
UPLOAD_TOKEN = os.getenv("UPLOAD_TOKEN")
PERSIST_UPLOADS = os.getenv("PERSIST_UPLOADS", "False").lower() in ("1", "true", "yes")
ALLOW_REMOTE = os.getenv("ALLOW_REMOTE", "False").lower() in ("1", "true", "yes")
RELOAD = os.getenv("RELOAD", "True").lower() in ("1", "true", "yes")
ALLOW_ORIGINS = os.getenv("ALLOW_ORIGINS")  # comma-separated list or None to keep defaults

TEMP_FOLDER = os.getenv("TEMP_FOLDER", "temp")
# Machine-specific defaults preserved but better set via environment or .env
SOURCE_FOLDER = os.getenv("SOURCE_FOLDER", r"C:\Users\MIKE\Pictures\Screenshots")
TARGET_FOLDER = os.getenv("TARGET_FOLDER", r"C:\Users\MIKE\Pictures\Organized")

CONFIDENCE_THRESHOLD = 0.3  
MIN_BOX_PERCENT = 0.2       # 30% for objects
MIN_PERSON_PERCENT = 0.1    # 10% for persons

# How many tags to return per image. Set to None for no limit (return all tags above
# confidence threshold). Useful to avoid noisy long tag lists.
AUTO_TAG_MAX = 10

PERSON_FOLDER = os.path.join(TARGET_FOLDER, "Person")
ANIMALS_FOLDER = os.path.join(TARGET_FOLDER, "Animals")
DOCUMENTS_FOLDER = os.path.join(TARGET_FOLDER, "Documents")
JUNK_FOLDER = os.path.join(TARGET_FOLDER, "Junk")

os.makedirs(TEMP_FOLDER, exist_ok=True)
# Only create target subfolders when TARGET_FOLDER is set
if TARGET_FOLDER:
	os.makedirs(PERSON_FOLDER, exist_ok=True)
	os.makedirs(ANIMALS_FOLDER, exist_ok=True)
	os.makedirs(DOCUMENTS_FOLDER, exist_ok=True)
	os.makedirs(JUNK_FOLDER, exist_ok=True)
