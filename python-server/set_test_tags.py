from backend.tags_db import set_tags, _load_tags_db

# Set a simple tag for favicon.png
set_tags('favicon.png', ['test_icon'])

print('Updated tags DB:')
print(_load_tags_db())
