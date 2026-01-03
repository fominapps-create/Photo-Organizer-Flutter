# Filtored Release & Publishing Guide

## Version Increment Rules

| Stage | Increment Version? | Increment Build #? | Increment Scan Logic? | Update Timestamp? |
|-------|-------------------|-------------------|----------------------|-------------------|
| **dev** | ❌ NO | ❌ NO | ❌ NO | ✅ YES (to APK upload time) |
| **alpha** | ✅ YES | ✅ YES | ✅ If logic changed | ✅ YES |
| **beta** | ✅ YES | ✅ YES | ✅ If logic changed | ✅ YES |
| **production** | ✅ YES | ✅ YES | ✅ If logic changed | ✅ YES |

**Dev builds** are for internal testing only - same version, just updated APK + timestamp.

**Alpha/Beta/Production** are official releases - increment versions appropriately.

---

## Related Files

| File | Purpose |
|------|---------|
| `docs/version.json` | **Source of truth** - edit this to change versions |
| `tools/sync_versions.dart` | Syncs version.json to other files |
| `lib/config/app_config.dart` | App-side version constants (auto-generated) |
| `lib/services/tag_store.dart` | Scan version logic + history |
| `lib/services/local_tagging_service.dart` | ML Kit classification logic |
| `pubspec.yaml` | Flutter version (auto-generated) |
| `docs/dev.html` | Dev download page (reads version.json) |

---

## Publishing Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            DEVELOPMENT CYCLE                                 │
└─────────────────────────────────────────────────────────────────────────────┘

    ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────────┐
    │  Code    │────▶│  Test    │────▶│  Build   │────▶│  Dev Build   │
    │  Change  │     │  Locally │     │  APK     │     │  (internal)  │
    └──────────┘     └──────────┘     └──────────┘     └──────────────┘
         │                                                    │
         │                                                    ▼
         │                                          ┌──────────────────┐
         │                                          │ Upload to GitHub │
         │                                          │ Releases (dev)   │
         │                                          └──────────────────┘
         │                                                    │
         ▼                                                    ▼
    ┌─────────────────────────────────────────────────────────────────┐
    │                     READY FOR ALPHA?                             │
    │  □ Major features complete    □ No crash bugs                   │
    │  □ Tested on physical device  □ Changes documented              │
    └─────────────────────────────────────────────────────────────────┘
                                    │
                          YES ──────┴────── NO → Continue dev
                                    │
                                    ▼
    ┌──────────────┐     ┌──────────────┐     ┌──────────────────────┐
    │ Bump version │────▶│ Sync files   │────▶│ Alpha Build          │
    │ x.x.x-alpha  │     │ (dart tools/)│     │ (testers: 5-10)      │
    └──────────────┘     └──────────────┘     └──────────────────────┘
                                                        │
                                                        ▼
                                              ┌──────────────────┐
                                              │ Collect Feedback │
                                              │ Fix Issues       │
                                              └──────────────────┘
                                                        │
                                    ┌───────────────────┴───────────────────┐
                                    ▼                                       ▼
                          ┌─────────────────┐                     ┌─────────────────┐
                          │ Minor fixes     │                     │ Major issues    │
                          │ → Stay in alpha │                     │ → Back to dev   │
                          └─────────────────┘                     └─────────────────┘
                                    │
                                    ▼
    ┌─────────────────────────────────────────────────────────────────┐
    │                     READY FOR PRODUCTION?                        │
    │  □ Stable for 1+ week        □ Tested on 3+ devices             │
    │  □ Performance acceptable    □ No privacy concerns              │
    │  □ Play Store listing ready  □ All feedback addressed           │
    └─────────────────────────────────────────────────────────────────┘
                                    │
                          YES ──────┴────── NO → Continue alpha
                                    │
                                    ▼
    ┌──────────────┐     ┌──────────────┐     ┌──────────────────────┐
    │ Bump version │────▶│ Build bundle │────▶│ Production Release   │
    │ x.x.x (final)│     │ (appbundle)  │     │ → Play Store         │
    └──────────────┘     └──────────────┘     └──────────────────────┘
```

---

## Scan Logic Version Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      CLASSIFICATION LOGIC CHANGE?                            │
└─────────────────────────────────────────────────────────────────────────────┘

    ┌───────────────────────────────────────────────────────────────────┐
    │                    WHAT DID YOU CHANGE?                           │
    └───────────────────────────────────────────────────────────────────┘
                                    │
           ┌────────────────────────┼────────────────────────┐
           ▼                        ▼                        ▼
    ┌──────────────┐      ┌──────────────────┐      ┌──────────────┐
    │ Confidence   │      │ Keywords added/  │      │ UI / perf /  │
    │ thresholds   │      │ removed from     │      │ unrelated    │
    │ changed      │      │ detection lists  │      │ bug fixes    │
    └──────────────┘      └──────────────────┘      └──────────────┘
           │                        │                        │
           ▼                        ▼                        ▼
    ┌──────────────┐      ┌──────────────────┐      ┌──────────────┐
    │ INCREMENT    │      │ INCREMENT        │      │ DO NOT       │
    │ scanLogic    │      │ scanLogic        │      │ INCREMENT    │
    │ Version      │      │ Version          │      │              │
    └──────────────┘      └──────────────────┘      └──────────────┘
           │                        │                        
           └────────────┬───────────┘                        
                        ▼
    ┌───────────────────────────────────────────────────────────────────┐
    │                    ON APP LAUNCH (user side)                      │
    └───────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
                    ┌───────────────────────────────┐
                    │ savedVersion < currentVersion │
                    │         ?                     │
                    └───────────────────────────────┘
                           │              │
                         YES              NO
                           │              │
                           ▼              ▼
              ┌────────────────────┐  ┌─────────────┐
              │ Show "Rescan All?" │  │ Normal      │
              │ dialog to user     │  │ startup     │
              └────────────────────┘  └─────────────┘
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
    ┌──────────────────┐      ┌──────────────────┐
    │ User says YES    │      │ User says LATER  │
    │ → Rescan photos  │      │ → Keep old tags  │
    │ → Update version │      │ → Ask again next │
    └──────────────────┘      └──────────────────┘
```

---

## Version Sync Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         VERSION MANAGEMENT                                   │
└─────────────────────────────────────────────────────────────────────────────┘

                    ┌─────────────────────────┐
                    │   docs/version.json     │  ◀── SINGLE SOURCE OF TRUTH
                    │   {                     │
                    │     "appVersion": "x",  │
                    │     "scanLogicVersion", │
                    │     "buildNumber",      │
                    │     "changes": [...]    │
                    │   }                     │
                    └─────────────────────────┘
                                │
                                │  dart tools/sync_versions.dart
                                │
                ┌───────────────┼───────────────┐
                ▼               ▼               ▼
    ┌───────────────────┐ ┌──────────────┐ ┌────────────────┐
    │ lib/config/       │ │ pubspec.yaml │ │ Website        │
    │ app_config.dart   │ │              │ │ (reads json    │
    │                   │ │ version:     │ │  directly)     │
    │ appVersion = "x"  │ │   "x+build"  │ │                │
    │ scanLogicVersion  │ │              │ │ dev.html       │
    └───────────────────┘ └──────────────┘ └────────────────┘
```

---

## Quick Decision Tree

```
                        ┌─────────────────────┐
                        │ What are you doing? │
                        └─────────────────────┘
                                   │
        ┌──────────────┬───────────┼───────────┬──────────────┐
        ▼              ▼           ▼           ▼              ▼
   ┌─────────┐   ┌──────────┐ ┌─────────┐ ┌─────────┐   ┌──────────┐
   │ Quick   │   │ Feature  │ │ ML Kit  │ │ Ready   │   │ Ready    │
   │ test    │   │ complete │ │ logic   │ │ for     │   │ for      │
   │ locally │   │ testing  │ │ changed │ │ testers │   │ public   │
   └─────────┘   └──────────┘ └─────────┘ └─────────┘   └──────────┘
        │              │           │           │              │
        ▼              ▼           ▼           ▼              ▼
   ┌─────────┐   ┌──────────┐ ┌─────────┐ ┌─────────┐   ┌──────────┐
   │ flutter │   │ Dev      │ │Increment│ │ Alpha   │   │ Prod     │
   │ run     │   │ build    │ │ scan    │ │ build   │   │ build    │
   │         │   │ → GitHub │ │ version │ │ x.x-α   │   │ x.x.x    │
   │ (no     │   │ release  │ │ in json │ │         │   │          │
   │ publish)│   │ -dev tag │ │         │ │ GitHub  │   │ Play     │
   └─────────┘   └──────────┘ └─────────┘ │ release │   │ Store    │
                                          └─────────┘   └──────────┘
```

---

## Version Format

```
MAJOR.MINOR.PATCH-STAGE
```

| Component | Meaning | Example |
|-----------|---------|---------|
| MAJOR | Breaking changes, major redesign | 1.0.0 |
| MINOR | New features, significant improvements | 0.5.0 |
| PATCH | Bug fixes, small tweaks | 0.4.1 |
| STAGE | Release stage suffix | -dev, -alpha, -beta, (none for production) |

### APK Naming Convention

```
filtored-{version}.apk
```

| Stage | APK Filename | Example |
|-------|--------------|---------|
| **dev** | `filtored-X.X.X-dev.apk` | `filtored-0.4.1-dev.apk` |
| **alpha** | `filtored-X.X.X-alpha.apk` | `filtored-0.5.0-alpha.apk` |
| **beta** | `filtored-X.X.X-beta.apk` | `filtored-0.5.0-beta.apk` |
| **production** | `filtored-X.X.X.apk` | `filtored-1.0.0.apk` |

**Important:** The APK filename must match the version in `version.json` exactly, including the stage suffix.

### Stage Progression

```
dev → alpha → beta → production
```

| Stage | Audience | Distribution | Purpose |
|-------|----------|--------------|---------|
| **dev** | Developer only | filtored.com/dev.html | Internal testing, experimental features |
| **alpha** | Close testers (5-10 people) | filtored.com/download.html | Feature testing, feedback gathering |
| **beta** | Wider testers (50-100) | Play Store closed beta | Stability testing, pre-launch polish |
| **production** | Public | Play Store | Official release |

---

## Version Files & Sync

All versions are managed from a single source of truth:

```
docs/version.json  ← EDIT THIS ONE
```

Then run:
```bash
dart tools/sync_versions.dart
```

This updates:
- `lib/config/app_config.dart` (appVersion, scanLogicVersion)
- `pubspec.yaml` (version string)

### version.json Structure

```json
{
  "appVersion": "0.4.1-dev",
  "buildNumber": 12,
  "scanLogicVersion": 17,
  "lastUpdated": "2026-01-03T14:45:00",
  "changes": [
    "Change 1",
    "Change 2"
  ]
}
```

---

## Scan Logic Version

A separate integer that tracks ML Kit classification logic changes.

### When to Increment

✅ **DO increment** when:
- Changed ML Kit confidence thresholds
- Added/removed keywords from detection lists
- Modified category logic (people/animals/food/scenery/document)
- Fixed significant classification bugs

❌ **DO NOT increment** when:
- UI changes only
- Performance optimizations (same results)
- Bug fixes unrelated to scanning
- New features that don't affect existing tags

### Version History

| Version | Changes |
|---------|---------|
| 1 | Initial ML Kit implementation |
| 2 | Tier-based people detection, animal deduplication |
| 3 | Fixed gallery loading on fresh install |
| 4 | Stricter tier2 logic, eyelash → ambiguous |
| 5 | Event/party/pattern exclusions, body part detection |
| 6 | Room/furniture not documents, baby in costume → people |
| 7 | Dog requires 85%+ confidence |
| 8 | Detections store confidence, search filters low-confidence |
| 9 | Pedestrian/walker/jogger → People, 2+ clothing → People |
| 10 | Objects need 86%+ confidence to be searchable |
| 11-15 | Threshold adjustments, hair/skin detection |
| 16 | Count-based detection, face detection fallback |
| 17 | Body parts at any confidence, any food label = food, priority system |

---

## Publishing Workflow

### Dev Build (Internal Testing)

```bash
# 1. Build APK
flutter build apk --release

# 2. Create/update GitHub release
gh release delete v0.4.1-dev -y  # if exists
gh release create v0.4.1-dev "build/app/outputs/flutter-apk/app-release.apk#filtored-0.4.1-dev.apk" \
  --title "v0.4.1-dev" \
  --notes "Dev build - [date] - [changes]" \
  --prerelease

# 3. Update docs/version.json
#    - Update lastUpdated to CURRENT TIME (match APK upload time)
#    - DO NOT change appVersion, buildNumber, or scanLogicVersion
#    - Optionally update changes list

# 4. Push to main
git add docs/version.json
git commit -m "Dev build - [date]"
git push
```

Download: https://filtored.com/dev.html

### Alpha Build (Testers)

```bash
# 1. Update version.json
#    - Change stage: "0.5.0-alpha"
#    - Update changes list
#    - Increment buildNumber

# 2. Run sync
dart tools/sync_versions.dart

# 3. Build & release
flutter build apk --release
gh release create v0.5.0-alpha "..." --title "v0.5.0-alpha" --prerelease

# 4. Commit all changes
git add .
git commit -m "Alpha release v0.5.0-alpha"
git push
```

Download: https://filtored.com/download.html

### Production Release

```bash
# 1. Update version.json
#    - Remove stage: "0.5.0" (no suffix)
#    - Final changes list

# 2. Run sync
dart tools/sync_versions.dart

# 3. Build release bundle for Play Store
flutter build appbundle --release

# 4. Upload to Play Console

# 5. Create GitHub release (not prerelease)
gh release create v0.5.0 "..." --title "v0.5.0" --notes "..."

# 6. Commit & tag
git add .
git commit -m "Release v0.5.0"
git tag v0.5.0
git push --tags
```

---

## APK Size Limit

GitHub has a **100MB file limit** for regular commits.

**Solution:** Always use GitHub Releases for APKs (allows up to 2GB).

```bash
# ❌ DON'T do this
git add docs/download/filtored.apk  # Will fail if >100MB

# ✅ DO this
gh release create v0.4.1-dev "path/to/app-release.apk#filtored-0.4.1-dev.apk" --prerelease
```

---

## Website Download Links

The dev.html page automatically builds download URLs from version.json:

```
https://github.com/fominapps-create/Photo-Organizer-Flutter/releases/download/v{version}/filtored-{version}.apk
```

So when you create a release, name the asset: `filtored-{version}.apk`

---

## Quick Reference

| Task | Command |
|------|---------|
| Build debug APK | `flutter build apk --debug` |
| Build release APK | `flutter build apk --release` |
| Build App Bundle | `flutter build appbundle --release` |
| Sync versions | `dart tools/sync_versions.dart` |
| Create release | `gh release create v{version} "apk#name.apk" --prerelease` |
| Delete release | `gh release delete v{version} -y` |
| List releases | `gh release list` |

---

## Checklist Before Release

### Dev Build
- [ ] Code compiles without errors
- [ ] Tested on emulator
- [ ] APK builds successfully

### Alpha Build
- [ ] All dev checklist items
- [ ] Tested on physical device
- [ ] Major features working
- [ ] No crash-inducing bugs
- [ ] Updated version.json changes list

### Production Build
- [ ] All alpha checklist items
- [ ] Tested on multiple devices
- [ ] Performance acceptable
- [ ] Battery usage reasonable
- [ ] Privacy policy updated (if needed)
- [ ] Play Store listing updated
- [ ] Screenshots updated (if UI changed)
