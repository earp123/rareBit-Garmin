# Changelog

## [Unreleased] — branch: `timer_feature`

### Overview
This branch overhauls the main UI from a BLE scanner card view into a sports match timer view. The BLE scanner is now the entry point; on successful subscription the app navigates automatically to the timer view.

---

### New Features

#### Timer View (`TimerView.mc`)
- **Count-up timer** (blue, `FONT_NUMBER_MILD`) sits above the main timer
- **Countdown timer** (white, `FONT_NUMBER_HOT`) centered on screen — this is the primary match period timer
- **Time of day** (green, `FONT_NUMBER_MILD`, 12h format, no leading zero) sits below the main timer
- **AR1 / AR2 link indicators** below the clock — filled green dot when linked, outline grey dot when unlinked; sourced live from BleManager
- Duration picker accessible via menu (15–45 min options)
- Layout uses a 0.55× font height scalar to compensate for Garmin number font metric padding (~40–50% larger than actual glyph height)

#### App Flow
- App launches → BLE scan starts automatically (no tap required)
- Found devices are accumulated and deduplicated; a **device picker menu** is shown when the first match is found
- User selects a device → connects → subscribes → slides up to Timer View
- Back from Timer View returns to the BLE scanner view

#### Build System
- Added `.vscode/tasks.json` with a direct `monkeyc` build task (Ctrl+Shift+B)
- Target: `venu2plus`
- Output: `bin/rareBitGarmin.prg` — ready to sideload via USB drag to `GARMIN/APPS/`

---

### Bug Fixes

#### Haptic Crash — `Too Many Arguments Error` (partially resolved)
- **Root cause identified:** CIQ 6.x runtime on physical hardware passes an unexpected argument to `Timer.Timer` callbacks, causing "Too Many Arguments Error — Failed invoking <symbol>"
- **What was fixed:** Removed `_buzzTimer` and `_buzzTimer2` entirely; `_buzzAlert2` now encodes all three staccato bursts as a single `Attention.vibrate()` call using gap `VibeProfile` entries — no timer callbacks used for haptics
- **Vibe sequences pre-allocated** in `initialize()` to avoid repeated object allocation during BLE notification callbacks
- All `Attention.vibrate()` calls wrapped in `try/catch`
- **Status: crash persists** — further investigation needed; likely unrelated second crash site or the same CIQ runtime quirk manifesting elsewhere

---

### Known Issues

- **App crash on AR2 alert haptic sequence** — crash source not yet pinned to a specific line in the new build; next step is to retrieve the updated crash log after deploying the current `.prg`
- Launcher icon is 24×24 (original placeholder); device expects 70×70 — upscaled at runtime, no functional impact
- No supported languages defined in manifest — cosmetic warning only

---

### Files Changed (vs `main`)
| File | Change |
|------|--------|
| `source/myGarminAppApp.mc` | BleManager lifted to app level; `getInitialView()` launches BLE scan view |
| `source/myGarminAppView.mc` | Auto-starts scan on show; pushes device picker on `BLE_FOUND`; pushes TimerView on `BLE_SUBSCRIBED` |
| `source/myGarminAppDelegate.mc` | No changes |
| `source/TimerView.mc` | New timer UI with count-up, countdown, clock, and AR1/AR2 indicators |
| `source/TimerDelegate.mc` | No changes |
| `source/BleManager.mc` | Multi-device scan accumulation; `connectToResult()`; pre-allocated vibe sequences; haptic crash fix |
| `source/DeviceMenuDelegate.mc` | **New** — handles device picker selection and back |
| `.vscode/tasks.json` | **New** — direct monkeyc build task for venu2plus |
