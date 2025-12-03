import json
import os
from typing import Dict, List

TAGS_DB_PATH = os.path.join(os.path.dirname(__file__), 'tags_db.json')


def _load_tags_db() -> Dict[str, List[str]]:
    try:
        if os.path.exists(TAGS_DB_PATH):
            with open(TAGS_DB_PATH, 'r', encoding='utf-8') as f:
                return json.load(f)
    except Exception:
        pass
    return {}


def _save_tags_db(db: Dict[str, List[str]]) -> None:
    try:
        with open(TAGS_DB_PATH, 'w', encoding='utf-8') as f:
            json.dump(db, f, ensure_ascii=False, indent=2)
    except Exception:
        # Best-effort only; don't crash
        pass


def get_tags(filename: str):
    db = _load_tags_db()
    return db.get(filename, [])


def set_tags(filename: str, tags: List[str]):
    db = _load_tags_db()
    db[filename] = tags
    _save_tags_db(db)


def move_tags(old_filename: str, new_filename: str):
    db = _load_tags_db()
    if old_filename in db:
        db[new_filename] = db.pop(old_filename)
        _save_tags_db(db)
