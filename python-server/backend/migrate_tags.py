"""
Manual migration helper (DEPRECATED).

This repository now performs automatic, safe migration inside `tags_db.py`
when a legacy list-based format is detected. The manual script that used to
perform filename->photoID mapping has been removed to avoid accidental
double-migrations and maintenance burden.

If you truly have legacy filename-keyed data and require a custom mapping,
please restore a dedicated migration tool from version control history and
run it intentionally. Do NOT run any migration unless you understand your
data format and have backups.

This file is intentionally a no-op that only documents the recommended action.
"""

import sys

def main():
    print("migrate_tags.py is deprecated. Do not run this file.")
    print("If you need to migrate filename-keyed tags to photoIDs, create a mapping and use a controlled migration tool.")
    sys.exit(0)

if __name__ == '__main__':
    main()
