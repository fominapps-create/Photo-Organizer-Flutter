from .tags_db import _load_tags_db, _save_tags_db
from .config import TARGET_FOLDER
import os


def find_file_by_basename(basename):
    for root, dirs, files in os.walk(TARGET_FOLDER):
        for f in files:
            if f == basename:
                return os.path.join(root, f)
    return None


def migrate():
    db = _load_tags_db()
    updated = False
    new_db = dict(db)
    for key in list(db.keys()):
        # If file exists under TARGET_FOLDER, nothing to do
        file_path = find_file_by_basename(key)
        if file_path:
            continue
        # Otherwise, check candidate matching baseline without suffix
        if '_1' in key:
            base = key.split('_')[0] + os.path.splitext(key)[1]
            candidate = find_file_by_basename(base)
            if candidate:
                # Move tag mapping
                new_basename = os.path.basename(candidate)
                new_db[new_basename] = new_db.pop(key)
                updated = True
                print(f"Migrated tags from {key} to {new_basename}")

    if updated:
        _save_tags_db(new_db)
        print('Migration complete. Tags DB updated.')
    else:
        print('No updates required.')


if __name__ == '__main__':
    migrate()
