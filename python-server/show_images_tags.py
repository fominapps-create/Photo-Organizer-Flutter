from backend import backend_api

# Call functions directly to see returned structure
print('All images with tags:')
print(backend_api.list_all_organized_images_with_tags())

# Check tags endpoint
print('\nTags for folder.png:')
print(backend_api.get_tags_for_file('folder.png'))
