from backend import backend_api
from typing import get_type_hints

print('annotations:', backend_api.detect_tags.__annotations__)
print('type_hints:', get_type_hints(backend_api.detect_tags))
