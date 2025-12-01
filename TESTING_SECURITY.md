# Photo Organizer — Safe Testing Guide

This guide describes the minimal steps required to safely share the app with testers while ensuring their photos are not leaked or persistently stored.

## Summary of safety defaults (applied by default)
- The app will default to a sensible server base URL on emulators (Android emulators: `http://10.0.2.2:8000`). Uploads are available by default for development testing; on physical devices, set the Server base URL to `http://<your-PC-IP>:8000` if needed.
- The server listen defaults to `127.0.0.1` (local-only). Use the CLI flag `--allow-remote` to bind to 0.0.0.0 and allow LAN access.
- The API server will strip EXIF (location) metadata from uploaded images before saving/processing where possible (requires Pillow).
- Server uploads are non-persistent by default. Use `--persist-uploads` to keep uploaded files in `TARGET_FOLDER` for debugging; otherwise files are removed after processing.
- Uploads can require an `X-Upload-Token` header if `--upload-token <token>` is passed to `run_server.py`.
- CORS is restricted to local host by default.

## How to run the server safely (developer)
1. Install dependencies for backend (make sure to do this inside your virtual environment):

```powershell
cd python-server/backend
python -m pip install -r requirements.txt
```

2. Run with default safe config (localhost-only; no persistence):

```powershell
python run_server.py --no-reload --port 8000
```

3. OPTIONAL: If you need to test across a physical device on the same LAN, pass the following flags to enable remote access, require an upload token and optionally persist uploads:

```powershell
python run_server.py --allow-remote --upload-token "some-secret-token"
# or to persist uploads for debugging:
python run_server.py --allow-remote --upload-token "some-secret-token" --persist-uploads
```

Ask testers to set the app Server URL to `http://<your-Pc-IP>:8000` when testing from a real device, and set the Upload Token if the server requires one.

## How to prepare a safe release build (developer)
1. Ensure the release build does not automatically discover or use a remote server. For safe releases, keep autodiscovery disabled and document any intended server endpoints for testers.
2. Build using release mode and sign the APK:

```powershell
# From workspace root
flutter build appbundle --release
# Or for a side-loaded APK
flutter build apk --release
```

3. Distribute via Play internal testing or a verified link.

## Instructions for testers
1. Install release-signed app (internal test link recommended).
2. Open App → Settings:
   - On emulators no changes are needed — the app defaults a local server URL. On physical devices set the Server Base URL to your host IP if needed.
   - Optionally set an Upload Token if the server requires authorization.
3. Select only sample/test photos to upload first (avoid sensitive photos).
4. Confirm the upload with the dialog shown at upload time.
5. Verify that your photo still exists in the phone gallery after upload.
6. When you finish testing, uninstall the test app if desired.

## Developer options & controls
- `--allow-remote` CLI flag: pass to `run_server.py` to bind the server to `0.0.0.0` (LAN accessible). Do not use in production.
- `--upload-token <token>` CLI flag: when passed, the server will require `X-Upload-Token` on uploads.
- `--persist-uploads` CLI flag: when passed, the uploaded files will be kept instead of being deleted after processing (for debugging).

## Final Notes
- For production: add HTTPS and authentication at the server front-end (caddy/nginx/Let's Encrypt) instead of relying on HTTP.
- Strip EXIF client-side too if needed for double safety.
- The app does not request camera/mic/location permissions by default; testers can grant limited photo access on Android 13+ to avoid exposing the full device album.

If you'd like, I can apply more hardening steps (e.g., swapping the server to require strong authentication, adding TLS via a reverse proxy or making a custom verification endpoint).