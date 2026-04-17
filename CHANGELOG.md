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

#### Haptic Crash — `Too Many Timers Error` (resolved)
- **Root cause:** CIQ 6.x enforces a hard limit of 3 concurrent `Timer.Timer` objects (instantiation consumes a slot, not just `.start()`). The app had 3 permanent timer objects (view spinner + `BleManager._notifTimer` + countdown), leaving no slot for `Attention.vibrate()`'s internal timer — crash on every AR2 alert
- **Fix:** Replaced `_notifTimer` (`Timer.Timer`) with a `System.getTimer()` timestamp comparison — identical 5 s debounce behavior, zero timer slots consumed. Permanent timer count drops from 3 → 2, freeing one slot for haptics
- **Also fixed:** An earlier incorrect workaround had added a parameter to `onTick` and `_unlockNotif` callbacks. "Too Many Arguments Error" in CIQ means the function declares *more* parameters than the caller provides (not fewer) — zero-arg signatures are correct for `Timer.Timer` callbacks and have been restored
- **AR2 pattern:** Tuned to four 500 ms pulses with 200 ms gaps (~2.8 s total), clearly distinct from AR1's single long buzz
- **Status: resolved** — both alerts confirmed working on device while countdown timer is running

---

### Known Issues

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
| `source/BleManager.mc` | Multi-device scan accumulation; `connectToResult()`; pre-allocated vibe sequences; `_notifTimer` replaced with timestamp debounce; haptic crash resolved |
| `source/DeviceMenuDelegate.mc` | **New** — handles device picker selection and back |
| `.vscode/tasks.json` | **New** — direct monkeyc build task for venu2plus |
| `.claude/settings.json` | **New** — PostToolUse hook: auto-builds on every `.mc` file edit |
