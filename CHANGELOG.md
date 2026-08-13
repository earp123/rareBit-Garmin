# Changelog

All notable changes to rareBit Official are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased] — 2026-08-13

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
