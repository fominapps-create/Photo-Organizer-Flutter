# Filtored

AI-powered photo organization app.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Dev Quick Start (Windows)

To quickly start the backend server, configure the emulator and run the Flutter app on an Android emulator all in one step, use the helper script:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev_start_all.ps1

To start only the emulator and run the Flutter app (skip starting the Python server), use the -NoServer flag:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev_start_all.ps1 -NoServer
```
```

This script:
- Starts the `python-server` in safe mode (localhost-only)
- Waits for the server to accept requests
- Starts an emulator if none are running and sets `adb reverse` so the emulator can reach the host server
- Runs the Flutter app on the first available emulator/device

Quick single-line emulator run (no checks)
----------------------------------------

If you just want to launch the emulator and run the app (no server, minimal checks), run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_app_on_emulator_simple.ps1
```

This script launches the first configured emulator using `flutter emulators --launch` and then runs `flutter run` to install and start the app. If you want a more robust flow (adb selection, fallbacks, etc.), use `dev_start_all.ps1`.

If you prefer to run tasks individually, see the `scripts/` folder for `start_server_safe.ps1`, `start_server_remote.ps1`, and `run_app_on_emulator.ps1`.

Troubleshooting tips:
- Make sure `flutter` is installed and on your PATH. See https://flutter.dev/docs/get-started/install
- Make sure Android `adb` (platform-tools) is installed and on your PATH. You can install it via Android Studio SDK Manager.
- If the scripts fail to find commands, try restarting your shell/IDE so PATH changes take effect.
