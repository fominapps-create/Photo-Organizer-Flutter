# Updating Desktop App Icons (macOS / Windows)

This document explains how to update the macOS and Windows desktop icons for the Photo Organizer app using `assets/Icon4.png`.

⚠️ Note: For publishing or store distribution, you should use properly sized images (transparent PNGs or specifically formatted `.ico` files). This script is intended for development/testing workflows.

What we added
- `scripts/update_desktop_icons.ps1` — PowerShell script that:
  - Replaces macOS App Icon images in `macos/Runner/Assets.xcassets/AppIcon.appiconset` with `assets/Icon4.png` (copying it into every app_icon_*.png file).
  - Runs the helper `scripts/png2ico.py` to generate `windows/runner/resources/app_icon.ico` from `assets/Icon4.png` (requires Python & Pillow).
   - Runs the helper `scripts/png2ico.py` to generate `windows/runner/resources/app_icon.ico` from `assets/Icon4.png` (requires Python & Pillow).
   - Optionally update web icons using `scripts/update_web_icons.ps1` which calls `scripts/generate_web_icons.py`.
- `scripts/png2ico.py` — small Python script that generates a multi-size `.ico` (sizes: 256, 128, 64, 48, 32, 16) using Pillow (`PIL`), and writes to target path.

How to run (Windows developer/tester)

1) Ensure `python` is available in PATH (or `py` alias) and Pillow is installable via pip.
2) From the workspace root, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\update_desktop_icons.ps1
```

This will copy the `Icon4.png` into macOS app icons and generate `windows\runner\resources\app_icon.ico`.
If you also want to update web icons (favicon and PWA icons), run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\update_web_icons.ps1
```

3) Rebuild the app and run on Windows to see the changed icon:

```powershell
flutter pub get
flutter build windows
# or to run directly in debug
flutter run -d windows
```

MacOS notes
- You should open `macos/Runner` in Xcode and check the app icon set in `Assets.xcassets` before archiving to ensure appropriate sizes and retina optimizations.
 - This script only copies the `Icon4.png` in lieu of resizing; for store-ready assets, provide sizes appropriate for packaging (16,32,64,128,256,512,1024).

Windows notes
- The script uses Pillow to generate an `.ico` from `Icon4.png`. If Pillow is not available it will attempt to install it via `pip`.
- The generated `app_icon.ico` is saved to `windows/runner/resources/app_icon.ico`. Rebuilding the Windows runner will include the new icon in the exe.

If you want the app icon to be changed for Linux/macOS/iOS/Android, consider using `flutter_launcher_icons` which updates Android/iOS icons automatically, but for macOS/Windows a manual update (or `.ico` creation) is required.

If you have any CI/CD pipeline for packaging, update the pipeline to run the icon update script (or regenerate the icon assets using store-preferred tools) before building the app.

---

If you'd like, I can also add a small CI script to auto-run icon generation or wire this into a `make`/npm script. Let me know if you want that.