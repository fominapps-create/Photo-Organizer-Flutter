# Server Connection & Safety Guide
 The server will log the effective host and will only accept remote connections if started with the `--allow-remote` CLI flag.
 Uploads are ephemeral by default; pass `--persist-uploads` to keep files on disk after processing for debugging.
 An optional upload token may be required by the server if `--upload-token <token>` is passed; the client will then send `X-Upload-Token` when configured in settings.
- CORS is restricted by default; use the CLI flag `--allow-origins "https://example.com,https://localhost:8000"` to whitelist other origins.
- Uploads are ephemeral by default. Use the `--persist-uploads` flag to keep processed images on disk.
- An optional upload token may be required by the server if the `--upload-token` CLI flag is used. The client will send `X-Upload-Token` when configured in settings.

---

## Quick start (safe-by-default)
1. Start the server (default safe configuration):
```powershell
cd python-server
python run_server.py
```
This will start the server bound to `127.0.0.1:8000` by default. The server prints the effective host to stdout.

2. Run the Flutter app on your phone or emulator:
```powershell
flutter run
```
- The app will default to a platform-friendly server base URL for local testing. On Android emulators the app will use `http://10.0.2.2:8000` by default, so you can start the server locally and run the app without additional configuration.

---

## What to do to test on a different device (e.g., physical phone on same LAN)
 Allow remote access (server binds to 0.0.0.0):
If you want to expose the server to other devices for testing (less safe), do the following on the host machine running the server:

1. Allow remote access (server binds to 0.0.0.0):
```powershell
cd python-server
 python run_server.py --allow-remote
```
2. Allow persistent uploads (optional):
```powershell
 python run_server.py --persist-uploads
```
3. Optionally set a token so devices must provide the `X-Upload-Token` header to upload:
```powershell
 python run_server.py --upload-token "your-secret-token"
```
4. In the Flutter app, the Server Base URL is now defaulted for you on emulators. If testing from a physical device, set the server URL to `http://<your-host-ip>:8000` and (optionally) set an upload token in Settings.

> ⚠️ Note: When exposing the server, you must make sure your firewall rules on Windows allow inbound connections to port 8000 and your phone/device is on the same WiFi network.
Tip: There are helper scripts under `scripts/`:
- `scripts/start_server_safe.ps1` — start server in safe local-only ephemeral mode (default)
 `--allow-remote` (unsafe = binds `0.0.0.0`)
- `scripts/start_server_remote.ps1` — start server bound to 0.0.0.0, set token and optional persistence for LAN testing
---

## Server-side security & behavior
 `bind` host & `--allow-remote`:
    - Default: `127.0.0.1` (local-only)
    - `--allow-remote` (unsafe = binds `0.0.0.0`)

 `allow_origins` & `--allow-origins`:
    - Default: CORS only for local origins.
    - `--allow-origins` can be used to whitelist allowed Origins for CORS as a comma-separated list.
- `UPLOAD_TOKEN` header check:
   - Default: Not required.
 - `--persist-uploads`:
    - Default: not set (ephemeral). Processed images will be deleted.
    - When passed, the server keeps processed images on disk (less safe for testers).

- EXIF stripping:
   - Server attempts to remove EXIF metadata (best-effort) using Pillow when available. If Pillow is not installed, server logs a warning and continues.

---

## Client-side notes (Flutter app)
- The client defaults the server URL to a platform-friendly value (e.g., `http://10.0.2.2:8000` for Android emulator) and uploads are enabled by default for local development.
Open the Settings screen to:
   - Configure the upload token (optional)
   - The app will use the emulator-friendly default base URL automatically; for physical devices, set the server URL in Settings if needed
   - Use logs and server output for diagnostics (device logs and server stdout)
- The client will prompt for user confirmation before uploading any image.

---

## Running the server in an "open for testing" mode (example)
```powershell
# Example: open for remote devices and require token with persistence on
$ python run_server.py --allow-remote --upload-token 'testtoken' --persist-uploads
```

---

## Troubleshooting
- If the client cannot connect:
   - Confirm the server was started with `--allow-remote` if you are testing across devices
   - Confirm host IP and firewall rules in Windows
   - Check the device logs or server logs to see detailed connection logs
- If uploads are getting blocked by the server because of missing token:
   - Ensure the server was started with `--upload-token <token>` if a token is required
   - Set the same token in app Settings if required by the server

---

## Security checklist before sharing with testers (Minimal steps)
By default, the app auto-uses a platform-friendly base URL on emulators; uploads are available for local development testing. Exercise caution if you enable persistence or expose the server to LAN devices. 
- If you want testers to exercise the detection pipeline, do this:
   1. Start the server with `--allow-remote` (if testing LAN), optionally with `--upload-token` and `--persist-uploads`.
   2. Share the server IP and token (if set) with testers.
   3. Ask them to confirm the target server base URL (if testing on a physical device) and optional token.

> ✅ Tip: If you want to avoid any risk to testers’ photos, do not pass `--persist-uploads` (default). Also consider enabling token-based authorization for an additional layer of safety.

---

## Files of interest
- Server: `python-server/run_server.py`, `python-server/backend/backend_api.py`
- Client: `lib/services/api_service.dart`, `lib/screens/settings_screen.dart`, `lib/screens/explorer_screen.dart`, `lib/main.dart`

---

If anything is unclear or you'd like a single-command script to start the server for local testing, I can add a convenient powershell script or desktop shortcut to automate the safe mode start.
