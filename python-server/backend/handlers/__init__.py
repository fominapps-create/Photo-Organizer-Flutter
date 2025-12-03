"""Handlers package (stubs for testing).

These lightweight handlers use filename heuristics to assign categories
so the API can run without the full production logic.
"""

from .person import select as select_person
from .animals import select as select_animals
from .documents import select as select_documents
from .junk import select as select_junk
from .utils import move_to_folder

__all__ = [
    "select_person",
    "select_animals",
    "select_documents",
    "select_junk",
    "move_to_folder",
]
