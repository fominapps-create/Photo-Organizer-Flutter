import os
import shutil
from ..config import TARGET_FOLDER, PERSON_FOLDER, ANIMALS_FOLDER, DOCUMENTS_FOLDER, JUNK_FOLDER

def move_to_folder(img_path, dest_folder, main_object=None):
    """Move `img_path` into `dest_folder` and rename with detected object name.

    `dest_folder` may be None or a full path. If None, move to JUNK_FOLDER.
    `main_object` is the detected object name to include in filename.
    Returns destination directory path.
    """
    if not dest_folder:
        dest_dir = JUNK_FOLDER
    else:
        # if dest_folder is a known constant or looks like a path
        dest_dir = dest_folder

    try:
        os.makedirs(dest_dir, exist_ok=True)
        basename = os.path.basename(img_path)
        name, ext = os.path.splitext(basename)
        
        # Build new filename with object name
        if main_object:
            new_name = basename  # Keep original name
        else:
            new_name = basename
        
        dst = os.path.join(dest_dir, new_name)
        # If destination exists, add a numeric suffix
        if os.path.exists(dst):
            base_name, base_ext = os.path.splitext(new_name)
            i = 1
            while True:
                dst = os.path.join(dest_dir, f"{base_name}_{i}{base_ext}")
                if not os.path.exists(dst):
                    break
                i += 1
        shutil.move(img_path, dst)
        return dst
    except Exception:
        # If move fails, try to keep file in original location
        return None
