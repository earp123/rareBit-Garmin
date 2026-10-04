# UI Refresh — palette, live-screen extras, branded connect screen

Part of `docs/tester-build.md`. Scope: `myGarminAppView.mc` only, plus
one new drawable if the launcher PNG needs a larger copy.

## 1. Palette — align with the iOS / Android apps

Replace the colour block at the top of `myGarminAppView.mc`:

| Const | Was | Now | Meaning |
|---|---|---|---|
| `C_ACC_LIVE` | `0x00CC66` | `0x39FF14` | neon green — relay linked / live |
| `C_ACC_ACTIVE` | `0xFFAA00` | `0xFFC300` | amber — scanning, connecting, expiry |
| `C_ACC_ALERT` | `0xFFAA00` | `0xFFC300` | amber — AR flash label |
| `C_ACC_ERROR` | `0xCC2200` | `0xFF3B30` | red |
| `C_COUNTUP` | `0x55AAEE` | `0x00CFFF` | cyan — count-up |
| `C_TOD` | `0x66CC88` | `0x66CC88` | unchanged — time of day |
| `C_STOPPAGE` | — | `0xFF9500` | **new** orange — stoppage line (iOS parity) |
| `C_RING_TRACK` | — | `0x1C1C1C` | **new** — ring background |

Keep `C_BG`, `C_TEXT_PRI/SEC`, `C_HINT`, `C_CARD_*`. AMOLED note: pure
`0x39FF14` at thin stroke widths is fine; do not use it for large fills.

## 2. Live screen additions

All anchored in `onLayout()` next to the existing `_cdY/_cuY/_todY`.

**Progress ring** — thin arc hugging the bezel showing countdown
progress. Round screens: `r = h/2 - 4`, pen 3 px, track in
`C_RING_TRACK` drawn full, then `drawArc` clockwise from 90° through
`360 * elapsed / interval`. Colour `C_ACC_LIVE` while running, `C_TEXT_SEC`
paused, `C_ACC_ACTIVE` full ring once expired. Rectangular screens: a 3 px
bar along the top edge instead, same fill rule. Redraws on the existing
500 ms tick — no new timer. `fraction = getElapsedMs() / intervalMs`
clamped to 1.0; add `MatchTimer.getIntervalMs()` if not present.

**Link dot** — 3 px radius at 12 o'clock just inside the ring
(`y = 10` on round, `y = 8` rect). `C_ACC_LIVE` when `BLE_SUBSCRIBED`,
`C_ACC_IDLE` otherwise (timer-only / dropped). This restores a persistent
link visual at a size that can't be mistaken for a page.

**Half tag** — `"1st"` / `"2nd"` in `FONT_XTINY`, `C_HINT`, centred
below the count-up only if `_cuY + cuVis/2 + 4 + fhXtiny` still clears
the disc chord (same chord test as `_pickCountdownFont`). Skip silently
on screens where it doesn't fit — never shrink the countdown for it.

## 3. Connect screen (pre-live, replaces the SCAN / ERR cards + bare spinner)

One layout for `BLE_IDLE / SCANNING / CONNECTING / CONNECTED / ERROR`:

- Launcher icon (`Rez.Drawables.LauncherIcon`, 70 px) centred at
  `safeT + safeH * 0.42`, with the spinner arc (existing `_drawSpinner`,
  radius `iconHalf + 12`) wrapped around it. Arc colour from
  `_accentColor(state)`; in `BLE_IDLE` draw the track only; in
  `BLE_ERROR` draw a full red ring.
- `"rareBit"` in `FONT_SMALL`, `C_TEXT_PRI`, directly under the ring.
- Status line (`FONT_XTINY`, `C_TEXT_SEC`): `tap to scan` / `finding
  relay…` / `connecting…` / `enabling notify…` / `_ble.getStatus()`.
- Hint line (`FONT_XTINY`, `C_HINT`): `back = timer only` during
  scan/connect, `tap = retry` in error, blank otherwise.
- Drop the state dot (`dotY`) and `_drawCard()` — the ring carries state.

The spinner's `150 ms` tick is unchanged. If the launcher PNG looks soft
at 70 px on venu3+/X1 (416–454 px screens), generate `launcher_icon_96.png`
from `assets/launcher_icon_master.png` and pick by `dc.getWidth() > 400`.

## Test (sim first, then Sam on-watch)

1. Sim `monkey-sim.jungle`: live screen shows ring + dot + half tag with
   the countdown the same size as before (compare `View:` println
   `visH` against the previous build on venu2plus / venu3 / venux1).
2. Device build, cold start: branded connect screen → ring colour tracks
   scan → connect → live. BACK mid-scan → timer-only, dot grey.
3. Run a 1:00 interval: ring sweeps green, goes full amber at 00:00;
   pause → ring grey.
4. Menu Disconnect → dot grey, timer keeps running; Rescan → green.

## Assess

- Any device where the ring clips the countdown digits → shrink ring
  pen to 2 px before touching font selection.
- Half tag skipped on which devices (log it); acceptable.

## CHANGELOG note

**UI refresh** — palette aligned with the iOS/Android apps (neon green
link, cyan count-up, amber expiry, orange stoppage); countdown progress ring
on the bezel; persistent link dot; half tag; branded connect screen with
the app icon replacing the SCAN/ERR cards.
