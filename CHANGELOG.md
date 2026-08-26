# Changelog

All notable changes to rareBit Official are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased] — 2026-08-25

Field-test-ready overhaul: zero-touch connect flow with a timer-only
fallback, maximized and centered countdown, settings menu on BACK (MM:SS
interval picker, half submenu, exit), AR icon alert flash with real art
assets, a simulator test build, and fixes for the AR2 haptic crash and the
Venu Sq 2 launch crash.

### Added

- **Settings menu on BACK** — BACK (or MENU) on the live screen now opens a
  Menu2 settings menu: Interval, Half, Reset Timer, Disconnect. BACK no longer
  disconnects from the live screen; Disconnect moved into the menu.
- **Exit App menu item** — with the live screen latched and BACK owning the
  settings menu, the menu's last entry is the app's exit path
  (`System.exit()`, which still runs the BLE teardown via `onStop`).
  Deliberately two presses so a stray BACK can never kill the app mid-match.
- **MM:SS interval picker** — replaces the 5-minute preset list and the
  minutes-only custom picker. Up/down arrows over each field; tap above /
  below the digit row to adjust (left half = minutes, right half = seconds,
  15 s steps), tap the digits or press SELECT to set, BACK to cancel. Swipes
  are deliberately inert. Intervals may now include seconds (e.g. 12:30);
  00:00 is disallowed. The picker's delegate is a raw `InputDelegate` —
  a `BehaviorDelegate` converts touchscreen taps into the select behavior
  before `onTap` ever runs, which made every arrow tap confirm instead.
- **Half submenu** — explicit "1st" / "2nd" choice (focus starts on the
  current setting). 2nd bases the count-up at the interval, so with the
  default 45:00 interval the count-up starts at 45:00 and climbs from there;
  1st counts up from 00:00. Same behavior as the old toggle, clearer UI.
- **Real art assets** — app logo and AR paging icon. Full-resolution masters
  live in `/assets` (`launcher_icon_master.png` 3100², `ar_icon_master.png`
  320×377); watch-sized PNGs are generated from them into
  `resources/drawables` (launcher 70×70 — resolves the long-standing
  launcher-icon size warning — and AR icon 48×56). Regenerate from the
  masters when the art changes.

- **Simulator UI-test flavor** — `monkey-sim.jungle` + `SimMode.mc` build a
  variant (`SIM_TIMER_TEST = true`) that boots straight into the live match
  timer with both ARs linked, no BLE hardware needed. Build with
  `monkeyc -f monkey-sim.jungle ...`, run with `monkeydo`. The normal
  `monkey.jungle` build is unaffected. Note: `(:release)`/`(:debug)` are
  reserved annotations tied to `-r` — the flavors use `(:simTest)`/
  `(:noSimTest)` instead.
- **Vector-font countdown** on devices with scalable faces — the layout
  binary-searches the largest vector font ("RobotoCondensedBold" →
  "RobotoRegular" fallbacks) that fits, and adopts it only when it beats the
  best system font. Venu 3 gains ~10%, CIQ-6 devices (Venu 4 / Venu X1 /
  vivoactive 6) ~50%+ from the Condensed faces.

### Changed

- **Zero-touch connect flow** — the app starts scanning the moment it opens
  and pairs with the first advertisement matching the relay service UUID.
  No confirmation card, no device picker (more than one rareBit relay in
  range is not a real-world concern). The `BLE_FOUND` state is retired.
- **Timer-only fallback** — if the scan finds no relay within 15 seconds the
  app gives up on BLE (`BLE_OFFLINE`) and opens the match timer anyway: the
  app is fully usable as a timer without the Bluetooth extras. BACK during
  the scan/connect phase skips straight to the timer without waiting.
- **The live screen is latched** — once the timer screen is up it never gets
  replaced by BLE screens. A dropped connection triggers a quiet background
  rescan (auto-reconnect when the relay reappears), still subject to the
  15 s deadline; three consecutive pairing failures also fall back to
  timer-only rather than looping. The settings menu shows Disconnect while
  subscribed and Rescan otherwise.
- **AR shape glyphs replaced by an icon alert flash** — the circle/triangle
  symbols and linked-state indicators are gone. Idle live screen shows only
  the timers; during an AR's 3-second alert window the AR icon
  (`resources/drawables/ar_icon.png`, generated from the master in
  `/assets`) flashes in 300 ms phases above the digits with the AR number
  ("1", "2", or "1 2") beside it in amber. Link-status double-tap haptics are unchanged; there is
  just no persistent visual for link state anymore.
- **Sim build: Test Alert menu items** — the SIM_TIMER_TEST settings menu
  gains "Test Alert 1/2" entries (via `BleManager.simulateAlert`) to preview
  the flash without BLE traffic. Absent from device builds.
- **Countdown digits maximized on every screen** — seeing the timer at a
  glance is the app's top priority. The live screen now sizes the countdown
  per device at `onLayout()`: largest system number font (usually
  `FONT_NUMBER_THAI_HOT`) or vector font that fits, with a round-screen chord
  check so digits never clip the bezel. Visible digit height roughly doubles
  on venu2-gen (99 px on venu2plus) and better than doubles on venu3+.
- **Countdown dead-centered on the screen** — the digits' midpoint sits at
  exactly h/2 on every device (sim-verified on venu2s / venusq2m / venu3 /
  venuX1 / venu2plus). The live screen's bottom hint line was removed to make
  room; its guidance now lives in the settings flow. On venu3 the reclaimed
  space grew the vector countdown from 119 to 137 px.
- **AR symbols no longer constrain the timer size** — the state dot is gone
  from the live screen and the AR row floats in the gap above the digits
  (clamped to the screen edge) instead of reserving stack space.

### Fixed

- **AR2 alert crash while the match timer runs** — the AR2 haptic chained
  its bursts through two one-shot `Timer.Timer`s; with the view's tick timer
  and the match timer's expiry one-shot already holding slots, the chain
  blew the CIQ concurrent-timer limit ("Too Many Timers") — which is why it
  only crashed with the timer running. The pattern is now four 500 ms buzzes
  with 150 ms gaps (~2.5 s) encoded in a single `Attention.vibrate()` call,
  zero timers — same class of fix the old timer branch used for its haptic
  crash. `_buzzTimer` / `_buzzTimer2` are gone entirely.
  **Confirmed fixed on-watch 2026-08-25** — AR2 page alert (flash + haptic)
  works with the match timer running.
- **Venu Sq 2 (non-Music) removed from the manifest** — the base model has no
  `Toybox.BluetoothLowEnergy` module (only Venu Sq 2 Music does, per Garmin's
  API docs), so the app crashed at launch ("Symbol Not Found" instantiating
  `BleManager`). Pre-existing on main; venusq2m remains supported and runs.

### TODO

- [ ] venu2plus verdict: acceptable but could stand to be bigger. The
      2021-gen Venu devices cap out at `FONT_NUMBER_THAI_HOT` (no vector
      fonts on CIQ 5.0). Next lever: bundle a custom digits-only bitmap font
      (0–9 + colon); width headroom suggests roughly +15–20% before the round
      chord binds.
- [ ] On-device check of the 0.55 visual-height scalar and 0.70 vector
      cap-height estimate on venu2plus and a venu3-gen watch, plus the
      alert-flash icon size (48×56 — regenerable from the master at any size).

## 2026-08-14

Match timer feature, AR alert UI, and BLE robustness work ([#1](https://github.com/earp123/rareBit-Garmin/pull/1)).

### Added

- **Match timer** (`MatchTimer.mc`) — countdown-primary timer for match periods,
  defaulting to 45 minutes. Elapsed time is derived from `System.getTimer()`
  deltas, so timekeeping is exact regardless of redraw rate. Owned by the app
  rather than the BLE layer, so match time survives a relay disconnect and
  reconnect.
- **Synchronized count-up timer** — runs off the same elapsed clock as the
  countdown, so the two cannot drift. Its base follows the half setting: 00:00
  for the 1st half, or the selected interval for the 2nd half (e.g. counts up
  from 45:00 with 45-minute intervals).
- **Interval expiry haptic** — a distinct vibration pattern (two long pulses
  plus a longer closer) fires exactly when the countdown reaches 00:00,
  scheduled by a one-shot timer on start and canceled on pause/reset.
- **Stoppage time** — after expiry the countdown holds at 00:00 and turns amber
  while the count-up keeps running.
- **Match settings menu** (`MatchMenu.mc`) — opened with MENU from the live
  screen:
  - Reset Timer
  - Half toggle (1st / 2nd), with a sublabel showing the resulting count-up base
  - Interval selection: 5–45 minute presets in 5-minute steps, plus a Custom
    picker for any value from 1–99 minutes (swipe or page buttons to adjust,
    tap or SELECT to set)
- **AR alert blink** — when an alert notification arrives, that AR's symbol
  blinks between its default shape and a contrasting filled amber diamond for
  3 seconds, giving a visual indication alongside the existing haptics.
- **`BleManager.teardown()`** — stops any scan, unpairs any live GATT
  connection, and clears all session state. Safe to call from any state.

### Changed

- **App renamed to "rareBit Official"** (was the placeholder "BLE Scanner").
- **AR1 / AR2 naming** replaces D1 / D2 throughout the UI and source comments.
- **Live screen redesigned** as a symbol-forward layout: AR symbols in a row
  above, countdown in large digits at center (white running, gray paused, amber
  in stoppage), and the secondary count-up below in smaller soft-blue digits.
  Spacing is computed from per-device font metrics and centered on the vertical
  column so the layout stays within the usable area of round screens.
- **AR symbols follow link state** — an unlinked AR draws nothing; its symbol
  appears when the AR links. AR1 renders as a circle outline and AR2 as a
  triangle outline, both placeholders for custom icons.
- **Reset moved into the settings menu**, removing the accidental one-press
  reset of a running match.
- **App exit now tears down BLE** — `AppBase.onStop()` calls `teardown()`
  instead of `stopScan()`, so exiting while connected no longer leaves the
  peripheral paired.
- **View tick source** now runs at two speeds — 150 ms for spinner and alert
  blink animation, 500 ms to refresh the timer digits — and stops entirely when
  nothing is animating.

### Fixed

- **Notification gate dropped real alerts.** The gate re-armed a 5-second lock
  after every processed notification, so an alert arriving within 5 seconds of a
  previous one was discarded entirely — no buzz, no display update, and its link
  status bits were lost. The gate now closes only for 3 seconds after
  subscribing (its original intent of absorbing stale stacked packets), and
  link-status bits are still parsed while gated so the AR indicators never go
  stale.
- **Stale connection state.** The `ScanResult` reference is now released once a
  connection is established, rather than being held for the life of the session.
- Gate duration comments corrected to match the actual timer value.

### Notes

- The notification byte layout is unchanged: bit 7 is AR1 linked, bit 6 is AR2
  linked, bits 5–2 are reserved and unread, and bits 1–0 carry the notification
  type. Bytes past the first are not parsed.
- The match timer is currently reachable only from the subscribed (live) screen.
