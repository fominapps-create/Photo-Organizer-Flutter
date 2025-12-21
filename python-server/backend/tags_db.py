import json
import os
from typing import Dict, List, Any
from datetime import datetime

TAGS_DB_PATH = os.path.join(os.path.dirname(__file__), 'tags_db.json')


def _now_iso() -> str:
    return datetime.utcnow().isoformat() + 'Z'


def _load_tags_db() -> Dict[str, Any]:
    """Load tags DB. Supports legacy format (photoID -> [tags]) and new format
    (photoID -> {tags, last_updated, source}). If legacy format is detected,
    perform an in-place upgrade with a backup file.
    """
    try:
        if os.path.exists(TAGS_DB_PATH):
            with open(TAGS_DB_PATH, 'r', encoding='utf-8') as f:
                raw = json.load(f)
            # Detect legacy format: values are lists of strings
            needs_migrate = False
            for v in raw.values():
                if isinstance(v, list):
                    needs_migrate = True
                    break
            if needs_migrate:
                # Backup current file
                backup_path = TAGS_DB_PATH + '.bak'
                try:
                    with open(backup_path, 'w', encoding='utf-8') as bf:
                        json.dump(raw, bf, ensure_ascii=False, indent=2)
                except Exception:
                    # best-effort backup
                    pass
                # Convert to new format
                new = {}
                for k, v in raw.items():
                    if isinstance(v, list):
                        new[k] = {
                            'tags': v,
                            'last_updated': _now_iso(),
                            'source': 'migrated'
                        }
                    else:
                        new[k] = v
                _save_tags_db(new)
                return new
            return raw
    except Exception:
        pass
    return {}


def _save_tags_db(db: Dict[str, Any]) -> None:
    try:
        with open(TAGS_DB_PATH, 'w', encoding='utf-8') as f:
            json.dump(db, f, ensure_ascii=False, indent=2)
    except Exception:
        # Best-effort only; don't crash
        pass


def get_tags(photo_id: str) -> List[str]:
    db = _load_tags_db()
    entry = db.get(photo_id)
    if not entry:
        return []
    if isinstance(entry, list):
        # legacy
        return entry
    return entry.get('tags', [])


def set_tags(photo_id: str, tags: List[str], source: str = 'classifier', all_detections: List[str] = None) -> None:
    db = _load_tags_db()
    entry = {
        'tags': tags,
        'last_updated': _now_iso(),
        'source': source,
    }
    if all_detections:
        entry['all_detections'] = all_detections
    db[photo_id] = entry
    _save_tags_db(db)


def get_all_detections(photo_id: str) -> List[str]:
    """Get all detections for a photo (detailed objects for search)."""
    db = _load_tags_db()
    entry = db.get(photo_id)
    if not entry:
        return []
    if isinstance(entry, dict):
        return entry.get('all_detections', entry.get('tags', []))
    return []


def move_tags(old_photo_id: str, new_photo_id: str) -> None:
    db = _load_tags_db()
    if old_photo_id in db:
        db[new_photo_id] = db.pop(old_photo_id)
        # update last_updated when moved
        entry = db.get(new_photo_id)
        if isinstance(entry, dict):
            entry['last_updated'] = _now_iso()
        _save_tags_db(db)
