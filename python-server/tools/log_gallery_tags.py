import requests
import sys

try:
    url = 'http://127.0.0.1:8000/all-organized-images-with-tags/'
    res = requests.get(url, timeout=5)
    res.raise_for_status()
    data = res.json()
    images = data.get('images', [])

    tags_map = {}
    for item in images:
        img_url = item.get('url')
        tags = item.get('tags', [])
        tags_map[img_url] = tags

    print('Images and tags (count: {}):'.format(len(tags_map)))
    for k, v in tags_map.items():
        print(f'{k}: {v}')

    unique_tags = set()
    for tags in tags_map.values():
        for t in tags:
            unique_tags.add(t)

    print('\nUnique tags ({}):'.format(len(unique_tags)))
    if unique_tags:
        for t in sorted(unique_tags):
            print('-', t)
    else:
        print('(none)')

except Exception as e:
    print('Error: ', e, file=sys.stderr)
    sys.exit(1)
