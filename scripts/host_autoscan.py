#!/usr/bin/env python3
"""
Pull a few images from the Android emulator and POST them to the local server
`/process-image/` endpoint with `module=preview` to simulate the app's autoscan.

Usage: python host_autoscan.py [--count N]

This script finds `adb`, lists files in `/sdcard/DCIM/Camera`, pulls the first N
images into a temp folder, then uploads each file and prints the server JSON.
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def find_adb():
    candidates = [
        os.environ.get('ANDROID_SDK_ROOT', ''),
        os.path.join(os.environ.get('LOCALAPPDATA', ''), 'Android', 'Sdk'),
        os.path.join(os.environ.get('USERPROFILE', ''), 'AppData', 'Local', 'Android', 'Sdk'),
    ]
    for base in candidates:
        if not base:
            continue
        adb = Path(base) / 'platform-tools' / ('adb.exe' if os.name == 'nt' else 'adb')
        if adb.exists():
            return str(adb)
    # fallback to PATH
    return 'adb'


def run(cmd):
    return subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT, text=True)


def list_emulator_files(adb):
    try:
        out = run(f'"{adb}" shell ls -1 /sdcard/DCIM/Camera')
        lines = [l.strip() for l in out.splitlines() if l.strip()]
        # Keep only typical image extensions
        imgs = [l for l in lines if l.lower().endswith(('.png', '.jpg', '.jpeg'))]
        return imgs
    except Exception as e:
        print('Failed to list emulator files:', e)
        return []


def pull_files(adb, files, dest_dir):
    pulled = []
    for f in files:
        src = f'/sdcard/DCIM/Camera/{f}'
        dest = os.path.join(dest_dir, f)
        try:
            print(f'Pulling {src} -> {dest}')
            run(f'"{adb}" pull "{src}" "{dest}"')
            if os.path.exists(dest):
                pulled.append(dest)
        except Exception as e:
            print('  pull failed for', f, e)
    return pulled


def ensure_requests():
    try:
        import requests  # noqa: F401
        return True
    except Exception:
        print('`requests` not found, attempting `pip install requests`...')
        try:
            subprocess.check_call([sys.executable, '-m', 'pip', 'install', 'requests'])
            return True
        except Exception as e:
            print('Failed to install requests:', e)
            return False


def upload_files(files, server_url='http://127.0.0.1:8000/process-image/'):
    import requests
    for f in files:
        name = os.path.basename(f)
        print('\nUploading', name)
        try:
            with open(f, 'rb') as fh:
                resp = requests.post(server_url, files={'file': (name, fh)}, data={'module': 'preview'}, timeout=60)
            print('Status:', resp.status_code)
            try:
                print('JSON:', resp.json())
            except Exception:
                print('Body:', resp.text[:1000])
        except Exception as e:
            print('Upload failed:', e)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--count', type=int, default=20, help='Number of images to pull/upload')
    parser.add_argument('--server', type=str, default='http://127.0.0.1:8000/process-image/', help='Server upload endpoint')
    args = parser.parse_args()

    adb = find_adb()
    print('Using adb:', adb)

    imgs = list_emulator_files(adb)
    if not imgs:
        print('No images found on emulator path /sdcard/DCIM/Camera')
        sys.exit(1)

    to_take = imgs[:args.count]
    tmpdir = tempfile.mkdtemp(prefix='host_autoscan_')
    print('Using temp dir:', tmpdir)
    pulled = pull_files(adb, to_take, tmpdir)
    if not pulled:
        print('No files pulled; exiting')
        shutil.rmtree(tmpdir, ignore_errors=True)
        sys.exit(1)

    ok = ensure_requests()
    if not ok:
        print('requests unavailable; cannot upload files')
        shutil.rmtree(tmpdir, ignore_errors=True)
        sys.exit(1)

    upload_files(pulled, server_url=args.server)

    print('\nDone. Cleaning up temp files...')
    shutil.rmtree(tmpdir, ignore_errors=True)
