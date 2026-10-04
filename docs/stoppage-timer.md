# Stoppage Timer — tap tracks stoppages without stopping the match clock

Part of `docs/tester-build.md`. Revised 3 Oct 2026: the stoppage total now
shows on the live screen, matching the iOS watch app's stoppage line.

**Name: Stoppage, not Delay** (Sam, 3 Oct; first set 8 Sep). Every
user-facing string and identifier says Stoppage. Start from commit `d550d45`
on `feature/delay-timer` — the first implementation (menu, submenu, tap
handler, `getTimer()` state, tick) — and adapt it to the revised behaviour
below. The codebase also says "stoppage time" for the countdown holding at
00:00 past expiry; `MatchTimer.mc`'s header keeps the two apart.

## Goal

An **optional setting** (default OFF) that turns a screen tap on the live
timer into a stopwatch for interruptions — injury, VAR, substitution —
**without touching the countdown or the count-up**. The count-up is the
running match clock; the Stoppage Timer is separate and the two never share
state. SELECT keeps start/pause as today, so nothing moves to long-press
(unlike iOS, where tap had been the pause control).

## Behaviour

Setting: `Stoppage Timer` — `Off` (default) / `On`, its own item in
`MatchMenu.mc`, two-entry submenu like Half, session-only.

With the setting **On**, live screen only (`_ble.isLive()`):

| Input | Countdown / count-up | Stoppage |
|---|---|---|
| Tap, no segment open | untouched | open a segment |
| Tap, segment open | untouched | close it; add to `_stoppageTotalMs`, `_stoppageCount++` |
| SELECT | start / pause as today | untouched |
| Expiry (00:00) with a segment open | as today | close it into the total |
| Reset Timer / interval change | reset as today | clear segment, total, count |
| Half change | base change only | untouched |

Setting **Off**: tap stays inert (stray-touch guard unchanged). Pre-live
tap keeps its current meaning.

## Display

- **Stoppage line** replaces the time-of-day line (same slot `_todY`, same
  `FONT_MEDIUM`) whenever the setting is On and `total + open > 0`:
  `+MM:SS` in `C_STOPPAGE` (orange) where the value is
  `_stoppageTotalMs + openSegmentMs`. While a segment is open prefix a
  `●` glyph — if the system font lacks it, use a 4 px filled circle
  drawn left of the text. Time-of-day returns after Reset.
- AR alert flash still owns the slot during its 3 s window; the stoppage
  keeps counting underneath.
- Menu sublabel on the `Stoppage Timer` item: `On — 03:40 total (3)` /
  `Off`.
- No haptic on open/close.

## Implementation

- `MatchTimer.mc`: `_stoppageEnabled`, `_stoppageOpen`, `_stoppageTick`,
  `_stoppageTotalMs`, `_stoppageCount`; `toggleStoppage()`,
  `getStoppageMs()` (total + open), `isStoppageOpen()`, `formatStoppage()`,
  `set/isStoppageEnabled()`. `reset()` and `setInterval()` clear stoppage
  state; `onExpiry()` closes an
  open segment before buzzing. All `System.getTimer()` deltas.
- `myGarminAppDelegate.mc` `onTap()`: `if live && enabled → toggleStoppage();
  requestUpdate(); return true;` else current behaviour.
- `myGarminAppView.mc` `_drawLiveScreen()`: stoppage line vs time-of-day
  selection as above. `_syncTimer()`: an open segment counts as `slow`
  (500 ms) so the line ticks even if both clocks are paused.
- `MatchMenu.mc`: item + `StoppageMenuDelegate` (copy `HalfMenuDelegate`).

## Test (Sam, on-watch)

1. Setting Off: tap does nothing. Time-of-day shows as before.
2. Setting On, 2:00 interval running: tap ~0:30, tap ~0:45, tap ~1:10,
   let it expire with the segment open. Expect clock never paused,
   orange `+00:15` after the 2nd tap, `≈ +01:05` at expiry, `●` only
   while open, expiry buzz unchanged.
3. Reset Timer → line gone, time-of-day back, sublabel `Off`/`On — 00:00`.
4. Page an AR mid-stoppage: flash shows, stoppage correct afterwards.
5. Sleeve/raindrop with setting On opens a segment but never touches
   the clock — accepted trade-off of the setting.

## Decisions (flagged)

- Tap toggles open/close and banks a total (iOS parity). Count shown in
  the sublabel only.
- Stoppage line replaces time-of-day rather than adding a line, so the
  countdown keeps its size. Sam chose this over sublabel-only (3 Oct).

## CHANGELOG note

**Stoppage Timer** — optional tap-to-start stopwatch for interruptions;
orange `+MM:SS` running total in the time-of-day slot; separate from the
count-up; cleared by Reset. Setting in the menu, default Off.
