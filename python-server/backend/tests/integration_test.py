import json
import base64
import io
import sys

try:
    import requests
except Exception:
    requests = None

SERVER = 'http://127.0.0.1:8000'

# A tiny 1x1 PNG (transparent)
PNG_BASE64 = (
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMA' \
    'ASsJTYQAAAAASUVORK5CYII='
)


def make_png_bytes():
    return base64.b64decode(PNG_BASE64)


def post_single(photo_id: str):
    url = f"{SERVER}/process-image/"
    files = {
        'file': ('tiny.png', make_png_bytes(), 'image/png')
    }
    data = {
        'photoID': photo_id
    }
    if requests is None:
        print('`requests` not installed. Install it with `pip install requests` and re-run this test.')
        return False
    try:
        r = requests.post(url, files=files, data=data, timeout=10)
        print('POST response:', r.status_code, r.text)
        return r
    except Exception as e:
        print('POST request failed:', e)
        return False


def get_tags(photo_id: str):
    # Use query parameter to support photoIDs that contain slashes
    url = f"{SERVER}/tags/"
    params = { 'photoID': photo_id }
    if requests is None:
        print('`requests` not installed. Install it with `pip install requests` and re-run this test.')
        return False
    try:
        r = requests.get(url, params=params, timeout=5)
        print('GET tags response:', r.status_code, r.text)
        return r
    except Exception as e:
        print('GET request failed:', e)
        return False


def post_batch(photo_ids):
    url = f"{SERVER}/process-images-batch/"
    files = []
    for i in range(len(photo_ids)):
        files.append(('files', ('tiny.png', make_png_bytes(), 'image/png')))
    data = {
        'photoIDs': json.dumps(photo_ids)
    }
    if requests is None:
        print('`requests` not installed. Install it with `pip install requests` and re-run this test.')
        return False
    try:
        r = requests.post(url, files=files, data=data, timeout=20)
        print('BATCH POST response:', r.status_code, r.text)
        return r
    except Exception as e:
        print('BATCH POST failed:', e)
        return False


def run_all():
    print('Integration test: POST single image with photoID → GET tags')
    pid = 'test://device/1'
    r = post_single(pid)
    if not r:
        return 2
    if r.status_code != 200:
        print('Single POST failed')
        return 3

    g = get_tags(pid)
    if not g:
        return 4
    if g.status_code != 200:
        print('GET tags failed')
        return 5

    print('\nIntegration test: batch POST with photoIDs')
    pids = ['test://device/2', 'test://device/3']
    rb = post_batch(pids)
    if not rb:
        return 6
    if rb.status_code != 200:
        print('Batch POST failed')
        return 7

    print('\nAll integration steps completed. Check the server logs and responses above.')
    return 0


if __name__ == '__main__':
    sys.exit(run_all())
