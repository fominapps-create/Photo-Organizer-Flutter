# Scanning States Logic

This document describes the scanning state progression in the Filtored app.

## State Variables

| Variable | Description |
|----------|-------------|
| `_rescanPending` | Version upgrade detected, waiting for user approval |
| `_clearingTags` | User approved rescan, deleting old tags |
| `_scanPreparing` | ML Kit warmup before scanning starts |
| `_scanning` | Actively scanning photos |
| `_showFinalTouches` | 3 seconds after reaching 100% |
| `_validationComplete` | Scan finished, validation done |
| `_hasScannedAtLeastOneBatch` | At least one batch of photos has been scanned |

## Scanning State Progression Table

| Step | Condition | State | Badge | Tooltip | Dots | Text |
|------|-----------|-------|-------|---------|------|------|
| 0 | If version upgrade detected | `_rescanPending = true` | 🟠 Orange | "Update available - rescanning soon..." | ⭐ | "Rescan pending..." |
| 1 | If version upgrade approved | `_clearingTags = true` | 🟠 Orange | "Deleting tags..." | ⚫⚫⚫⚫ | "Deleting tags..." |
| 2 | After step 1, or fresh start | `_scanPreparing = true` | 🟠 Orange | "Preparing to scan..." | ⚫⚫⚫⚫ | "Preparing to scan..." |
| 3 | | `_scanning = true`, 0% | 🟠 Orange | "Scanning 0/N (0%)" | ⚫⚫⚫⚫ | "Preparing to scan..." |
| 4 | | `_scanning = true`, 1-99% | 🟠 Orange | "Scanning X/N (Y%)" | ⚫⚫⚫⚫ | "Y%" |
| 5 | | `_scanning = true`, 100% | 🟠 Orange | "Scanning..." | ⚫⚫⚫⚫ | Hidden |
| 6 | 3 seconds after 100% | `_showFinalTouches = true` | 🟠 Orange | "Scanning..." | Hidden | "Almost done ⭐" |
| 7 | Scan complete | `_validationComplete = true` | 🔵 Blue | "✓ All N photos scanned" | Hidden | Hidden |

## Two Paths Through the Flow

### Path A - Fresh Install / Normal Boot
```
→ Step 2 → 3 → 4 → 5 → 6 → 7 ✓
```

### Path B - Version Upgrade (has old tags)
```
→ Step 0 (dialog) → 1 (clearing) → 2 → 3 → 4 → 5 → 6 → 7 ✓
```

Steps 0 and 1 only happen when upgrading from an older scan version. Otherwise the app starts at Step 2.

## Badge Color Logic

| Condition | Color |
|-----------|-------|
| `_validationComplete && !_validating && !_scanning` | 🔵 Blue (solid badge) |
| All other states (scanning, preparing, validating) | 🟠 Orange (outlined badge) |

The final state is always **blue** - there is no intermediate green state.

## Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         SCANNING FLOW                                    │
└─────────────────────────────────────────────────────────────────────────┘

                    ┌───────────────────┐
                    │   App Launches    │
                    └─────────┬─────────┘
                              │
                              ▼
                    ┌───────────────────┐
                    │ _scanning = true  │
                    │ 🟠 Orange Badge   │
                    └─────────┬─────────┘
                              │
                              ▼
                    ┌───────────────────┐
                    │ Scanning photos   │
                    │ Progress: 0-99%   │
                    │ 🟠 Orange Badge   │
                    └─────────┬─────────┘
                              │
                              ▼
                    ┌───────────────────┐
                    │ 100% complete     │
                    │ 🟠 Orange Badge   │
                    │ "Almost done ⭐"  │
                    └─────────┬─────────┘
                              │
                              ▼
       ┌──────────────────────────────────────────────┐
       │  _validationComplete = true                  │
       │  🔵 BLUE BADGE (FINAL STATE)                 │
       │  "✓ All N photos scanned"                    │
       └──────────────────────────────────────────────┘
```

## "Preparing to scan..." Logic

Shows only when there are actually unscanned photos:
- ✅ App updated + tags removed → shows "Preparing to scan..."
- ✅ 0 unscanned photos → hides the text (no "Preparing to scan...")

## Notes

- Grey badge was removed - badge is always orange until scan complete
- Green badge was removed - final state is always blue
- Validation step removed for offline mode - `_validationComplete` is set immediately after scanning
- Pause functionality removed from display
- "Final touches" renamed to "Almost done"
